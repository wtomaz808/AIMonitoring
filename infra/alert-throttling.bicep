@description('Location for the alert rule resource (should match the resource group region).')
param location string = resourceGroup().location

@description('Resource ID of the aoai-laws Log Analytics workspace.')
param logAnalyticsWorkspaceResourceId string

@description('Resource ID of an existing Action Group to notify. Leave empty for no notifications.')
param actionGroupResourceId string = ''

@description('Substring used to match _ResourceId, e.g. "aoai-dev808" or "foundry-dev".')
param targetResource string = 'aoai-dev808'

@description('Friendly label used in the alert display name/description.')
param targetResourceLabel string = 'AOAI (aoai-dev808)'

@description('Number of 429s in the evaluation window that triggers the alert.')
param throttlingThreshold int = 5

var alertName = 'throttling-${targetResource}'
var throttlingQuery = 'AzureDiagnostics\n| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"\n| where _ResourceId has "${targetResource}"\n| where toint(ResultSignature) == 429'

resource throttlingAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: alertName
  location: location
  properties: {
    displayName: 'Throttling (429s) - ${targetResourceLabel}'
    description: 'Fires when ${targetResourceLabel} returns 429 (rate limited) responses, indicating the deployment TPM is undersized.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [
      logAnalyticsWorkspaceResourceId
    ]
    criteria: {
      allOf: [
        {
          query: throttlingQuery
          timeAggregation: 'Count'
          operator: 'GreaterThanOrEqual'
          threshold: throttlingThreshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: empty(actionGroupResourceId) ? [] : [
        actionGroupResourceId
      ]
    }
  }
}

output alertResourceId string = throttlingAlert.id
