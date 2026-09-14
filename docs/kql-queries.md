# AI Monitoring — KQL Query Library

Baseline monitoring queries for Azure OpenAI and Azure AI Foundry token/usage
attribution. Data source: Log Analytics workspace **`aoai-laws`** (Azure Gov).

## How to use these queries

Most queries work for **both** services. Only the target resource changes, so each
query starts with a single variable:

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
```

Change that one line to point a query at AOAI (`aoai-dev808`) or Foundry
(`foundry-dev`). Queries that intentionally span **both** services are called out
explicitly (see the union view at the end).

### Known assumptions / caveats
- **Token counts** come only from platform metrics (`AzureMetrics`). Diagnostic logs
  (`AzureDiagnostics` / `RequestResponse`) do **not** carry token counts.
- Per-principal token numbers are **estimates** — the metric token total is distributed
  across callers by their share of requests that day. Exact per-user tokens require
  APIM (`azure-openai-emit-token-metric`) or capturing the API `user` field.
- Identity column is assumed to be `identity_claim_oid_g`, with `CallerIPAddress` as a
  fallback. Confirm with Query 1 and adjust if the real column differs.
- **Every query below uses placeholder environment values** — workspace name
  (`aoai-laws`), resource names (`aoai-dev808`, `foundry-dev`), object IDs, resource
  group, and rates are all specific to this test sub. Swap them for your own
  environment's values before trusting results.

---

## 0. One-time setup — shared `PrincipalMap` function

Save this once as a Log Analytics **function** in `aoai-laws` so every query below can
call `PrincipalMap()` instead of duplicating the datatable.

```kql
datatable(ObjectId:string, FriendlyName:string, Team:string)
[
    "00000000-0000-0000-0000-000000000000", "example-app",   "Platform",
    "11111111-1111-1111-1111-111111111111", "data-pipeline", "Data Eng",
]
```

**How to save it:** Logs blade → paste the query above → run it → **Save** → **Save as
function** → Function name: `PrincipalMap`, Category: `AI Monitoring` → Save.

> TODO: replace the two placeholder rows with real object IDs. Run Query 1 or Query 4
> below to collect the GUIDs that show up, then edit the function (Functions pane in
> Logs → find `PrincipalMap` → Edit) and add a row per known caller.

---

## 1. Discovery — confirm data is flowing and find the identity field

> *Change `targetResource` to your AOAI/Foundry resource name.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where _ResourceId has targetResource
| where Category == "RequestResponse"
| take 50
| evaluate narrow()
| where Value != ""
| distinct Column, Value
| order by Column asc
```

Look for a column holding a GUID caller/object ID (expected `identity_claim_oid_g`).

---

## 2. List which token metrics exist

> *Change `targetResource` to your AOAI/Foundry resource name.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureMetrics
| where TimeGenerated > ago(24h)
| where _ResourceId has targetResource
| distinct MetricName
| order by MetricName asc
```

Expected: `TokenTransaction`, `ProcessedPromptTokens`, `GeneratedTokens`,
`ProcessedInferenceTokens`, `ActiveTokens`.

---

## 3. Total token consumption over time

> *Change `targetResource` to your AOAI/Foundry resource name.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureMetrics
| where TimeGenerated > ago(7d)
| where _ResourceId has targetResource
| where MetricName in ("TokenTransaction","ProcessedPromptTokens","GeneratedTokens")
| summarize Tokens = sum(Total) by MetricName, bin(TimeGenerated, 1h)
| render timechart
```

---

## 4. Requests per principal (who is calling)

> *Change `targetResource` to your AOAI/Foundry resource name to meet your env settings.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureDiagnostics
| where TimeGenerated > ago(7d)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where _ResourceId has targetResource
| where Category == "RequestResponse"
| extend Principal = coalesce(column_ifexists("identity_claim_oid_g", ""), CallerIPAddress)
| summarize Requests = count(),
            Failures = countif(toint(ResultSignature) >= 400)
        by Principal
| order by Requests desc
```

---

## 5. Estimated tokens per principal

Proportional estimate: daily metric token total distributed by each principal's share
of requests that day.

> *Change `targetResource` to your AOAI/Foundry resource name.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
let lookback = 7d;
let binSize  = 1d;
let tokens =
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where _ResourceId has targetResource
    | where MetricName == "TokenTransaction"
    | summarize DailyTokens = sum(Total) by Day = bin(TimeGenerated, binSize);
let reqs =
    AzureDiagnostics
    | where TimeGenerated > ago(lookback)
    | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
    | where _ResourceId has targetResource
    | where Category == "RequestResponse"
    | extend Principal = coalesce(column_ifexists("identity_claim_oid_g", ""), CallerIPAddress)
    | summarize Requests = count() by Day = bin(TimeGenerated, binSize), Principal;
reqs
| join kind=inner (reqs | summarize TotalReq = sum(Requests) by Day) on Day
| join kind=inner tokens on Day
| extend EstTokens = round(DailyTokens * (todouble(Requests) / TotalReq), 0)
| project Day, Principal, Requests,
          RequestShare = round(100.0 * Requests / TotalReq, 1),
          EstTokens
| order by Day desc, EstTokens desc
```

---

## 6. Daily Top 10 consumers — est. tokens, day-over-day change, friendly names

Primary baseline-report query. Fill in `PrincipalMap` with real object IDs from Query 1.

> *Change `targetResource` to your resource name, and replace the `PrincipalMap`
> object IDs/names/teams with your own (see Query 0).*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
let lookback = 14d;
let binSize  = 1d;
let topN     = 10;
// One-time setup: save the datatable below as a function named PrincipalMap (see
// Query 0). If you haven't saved it yet, replace this line with the inline datatable.
let PrincipalMap = PrincipalMap();
let tokens =
    AzureMetrics
    | where TimeGenerated > ago(lookback)
    | where _ResourceId has targetResource
    | where MetricName == "TokenTransaction"
    | summarize DailyTokens = sum(Total) by Day = bin(TimeGenerated, binSize);
let reqs =
    AzureDiagnostics
    | where TimeGenerated > ago(lookback)
    | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
    | where _ResourceId has targetResource
    | where Category == "RequestResponse"
    | extend Principal = coalesce(column_ifexists("identity_claim_oid_g", ""), CallerIPAddress)
    | summarize Requests = count() by Day = bin(TimeGenerated, binSize), Principal;
let est =
    reqs
    | join kind=inner (reqs | summarize TotalReq = sum(Requests) by Day) on Day
    | join kind=inner tokens on Day
    | extend EstTokens = round(DailyTokens * (todouble(Requests) / TotalReq), 0)
    | project Day, Principal, Requests, EstTokens;
est
| order by Principal asc, Day asc
| extend PrevTokens = iff(prev(Principal) == Principal, prev(EstTokens), real(null))
| extend DoD_Tokens = iff(isnull(PrevTokens), real(null), EstTokens - PrevTokens)
| extend DoD_Pct    = iff(isnull(PrevTokens) or PrevTokens == 0, real(null),
                          round(100.0 * (EstTokens - PrevTokens) / PrevTokens, 1))
| order by Day asc, EstTokens desc
| extend Rank = row_number(1, prev(Day) != Day)
| where Rank <= topN
| lookup kind=leftouter PrincipalMap on $left.Principal == $right.ObjectId
| extend Consumer = coalesce(FriendlyName, Principal),
         Team     = coalesce(Team, "unmapped")
| project Day, Rank, Consumer, Team, Principal, Requests, EstTokens, DoD_Tokens, DoD_Pct
| order by Day desc, Rank asc
```

---

## 7. Throttling / errors (capacity baseline)

> *Change `targetResource` to your AOAI/Foundry resource name.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where _ResourceId has targetResource
| extend StatusCode = toint(ResultSignature)
| summarize Requests = count() by StatusCode, OperationName, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

Watch `429` (rate-limited) — signals the deployment TPM is undersized.

---

## 8. Combined view — both services in one result (spans AOAI + Foundry)

This one intentionally queries **both** resources and labels each row by `Service`.

> *Replace the hardcoded `"aoai-dev808"` / `"foundry-dev"` strings (no `let` variable
> here) with your own resource names.*

```kql
AzureMetrics
| where TimeGenerated > ago(7d)
| where _ResourceId has "aoai-dev808" or _ResourceId has "foundry-dev"
| where MetricName in ("TokenTransaction","ProcessedPromptTokens","GeneratedTokens")
| extend Service = iff(_ResourceId has "aoai-dev808", "AOAI (aoai-dev808)", "Foundry (foundry-dev)")
| summarize Tokens = sum(Total) by Service, MetricName, bin(TimeGenerated, 1h)
| render timechart
```

---

## 9. Deployment / model breakdown (which model is consuming tokens)

Column name for the deployment/model varies by resource — confirm the real one via
Query 1's discovery output (look for `DeploymentName_s`, `modelDeploymentName_s`, or a
value buried in `properties_s`) and adjust the `column_ifexists` chain below.

> *Change `targetResource` to your resource name; confirm the real deployment column
> name for your environment via Query 1.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureDiagnostics
| where TimeGenerated > ago(7d)
| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
| where _ResourceId has targetResource
| where Category == "RequestResponse"
| extend Deployment = coalesce(column_ifexists("DeploymentName_s", ""),
                                column_ifexists("modelDeploymentName_s", ""),
                                "unknown")
| summarize Requests = count(),
            Failures = countif(toint(ResultSignature) >= 400)
        by Deployment, OperationName
| order by Requests desc
```

---

## 10. Quota / PTU utilization

Exact utilization metric names vary by deployment type (PAYG vs. PTU) and haven't been
confirmed for this tenant yet — run the discovery step first.

> *Change `targetResource` to your resource name; confirm `utilizationMetric` for your
> environment before using Step 2.*

```kql
// Step 1: discovery — find the real utilization/quota metric name
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
AzureMetrics
| where TimeGenerated > ago(24h)
| where _ResourceId has targetResource
| where MetricName has_any ("Utilization", "Quota", "PTU", "Capacity")
| distinct MetricName
```

```kql
// Step 2: once confirmed, swap utilizationMetric below and chart it
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
let utilizationMetric = "AzureOpenAIProvisionedManagedUtilizationV2"; // replace with confirmed name
AzureMetrics
| where TimeGenerated > ago(7d)
| where _ResourceId has targetResource
| where MetricName == utilizationMetric
| summarize AvgUtilizationPct = avg(Average) by bin(TimeGenerated, 1h)
| render timechart
```

---

## 11. Estimated cost (requires your real per-1K-token rate)

Placeholder rates — fill in your actual negotiated/contract price per 1K tokens before
trusting this number.

> *Change `targetResource` to your resource name, and `costPer1kPromptTokens` /
> `costPer1kCompletionTokens` to your actual contract rate.*

```kql
let targetResource = "aoai-dev808";   // swap to "foundry-dev" for Foundry
// --- Fill in your actual rate (USD per 1K tokens) ---
let costPer1kPromptTokens     = 0.0; // e.g. 0.003
let costPer1kCompletionTokens = 0.0; // e.g. 0.006
AzureMetrics
| where TimeGenerated > ago(30d)
| where _ResourceId has targetResource
| where MetricName in ("ProcessedPromptTokens", "GeneratedTokens")
| summarize Tokens = sum(Total) by MetricName, Day = bin(TimeGenerated, 1d)
| evaluate pivot(MetricName, sum(Tokens), Day)
| extend EstCost = (ProcessedPromptTokens / 1000.0 * costPer1kPromptTokens)
                  + (GeneratedTokens / 1000.0 * costPer1kCompletionTokens)
| project Day, ProcessedPromptTokens, GeneratedTokens, EstCost
| order by Day desc
```

---

## Automation — scheduled workbook & alert

Infrastructure lives in [infra/](../infra/) (not just docs — these deploy real Azure
resources):

- **[workbook-token-usage.bicep](../infra/workbook-token-usage.bicep)** — an Azure
  Monitor Workbook with a resource/time-range picker, a token-usage timechart, and a
  throttling (429) chart. Deploy it, then open it in the Workbook editor to fine-tune
  or add more steps (e.g. paste Query 6's Top 10 table in as an extra step).
- **[alert-throttling.bicep](../infra/alert-throttling.bicep)** — a scheduled query
  alert (`Microsoft.Insights/scheduledQueryRules`) that fires when 429s exceed a
  threshold in a 1-hour window, per Query 7.

```powershell
# Workbook
az deployment group create -g <resource-group> -f infra/workbook-token-usage.bicep `
  -p logAnalyticsWorkspaceResourceId=<aoai-laws-resource-id>

# Alert (repeat per resource: aoai-dev808, foundry-dev)
az deployment group create -g <resource-group> -f infra/alert-throttling.bicep `
  -p logAnalyticsWorkspaceResourceId=<aoai-laws-resource-id> `
     targetResource=aoai-dev808 targetResourceLabel="AOAI (aoai-dev808)" `
     actionGroupResourceId=<action-group-resource-id>
```

> *Change every `<...>` placeholder above (resource group, workspace resource ID,
> action group) and the `targetResource`/`targetResourceLabel` values to your env.*
