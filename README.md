# AI Monitoring

Azure Monitor assets and KQL queries for tracking Azure OpenAI and Azure AI Foundry
usage through a shared Log Analytics workspace.

The project provides a baseline for monitoring:

- Token consumption and trends
- Request volume and failures
- HTTP 429 throttling
- Caller and team attribution estimates
- Model or deployment usage
- Quota and PTU utilization discovery
- Estimated token cost

## How it works

Azure OpenAI and Foundry platform metrics and `RequestResponse` diagnostic logs are
routed to Log Analytics. The included KQL library supports investigation and
reporting, while the Bicep modules create an interactive Azure Monitor Workbook and a
scheduled query alert for throttling.

The current templates use sample Azure Government environment values:

- Log Analytics workspace: `aoai-laws`
- Azure OpenAI resource: `aoai-dev808`
- Azure AI Foundry resource: `foundry-dev`

Replace these placeholders with values from your environment before deployment or
query execution.

## Repository layout

```text
.
|-- docs/
|   |-- infra-setup.md
|   `-- kql-queries.md
`-- infra/
    |-- alert-throttling.bicep
    `-- workbook-token-usage.bicep
```

- [Azure monitoring infrastructure](docs/infra-setup.md) describes the resources,
  telemetry flow, responsibilities, prerequisites, and current limitations.
- [KQL query library](docs/kql-queries.md) contains discovery, usage, attribution,
  throttling, utilization, and cost queries.
- [Throttling alert](infra/alert-throttling.bicep) defines a scheduled query rule for
  HTTP 429 responses.
- [Token usage workbook](infra/workbook-token-usage.bicep) defines the shared Azure
  Monitor Workbook.

## Prerequisites

The current Bicep modules expect existing Azure resources and telemetry configuration:

1. An Azure OpenAI or Azure AI Foundry resource receiving traffic.
2. A Log Analytics workspace.
3. Diagnostic settings that route platform metrics and the `RequestResponse` category
   from each monitored resource to the workspace.
4. An optional Azure Monitor Action Group for alert notifications.
5. Appropriate Azure RBAC permissions to query the workspace and deploy monitoring
   resources.

## Current status

The repository contains the monitoring architecture, KQL query library, workbook, and
throttling alert definitions. Detailed Bicep deployment and manual Azure portal
configuration procedures will be added after the infrastructure design review.

Token attribution by principal and estimated costs are approximations. Review the
assumptions in the documentation before using those results for operational or
financial decisions.