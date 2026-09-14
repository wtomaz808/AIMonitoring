@description('Location for the workbook resource (should match the resource group region).')
param location string = resourceGroup().location

@description('Resource ID of the aoai-laws Log Analytics workspace (used as the workbook data source).')
param logAnalyticsWorkspaceResourceId string

@description('Display name shown in the Workbooks gallery.')
param displayName string = 'AI Monitoring - AOAI & Foundry Token Usage'

var workbookContent = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      name: 'title'
      content: {
        json: '## AOAI & Foundry Token Usage\nPick a resource and time range, then review token volume and throttling (429) trends.'
      }
    }
    {
      type: 9
      name: 'parameters'
      content: {
        version: 'KqlParameterItem/1.0'
        style: 'pills'
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        parameters: [
          {
            id: guid('timeRange-param')
            version: 'KqlParameterItem/1.0'
            name: 'TimeRange'
            type: 4
            isRequired: true
            value: {
              durationMs: 604800000
            }
            typeSettings: {
              selectableValues: []
            }
          }
          {
            id: guid('targetResource-param')
            version: 'KqlParameterItem/1.0'
            name: 'TargetResource'
            type: 2
            isRequired: true
            multiSelect: false
            query: 'datatable(value:string, label:string) ["aoai-dev808", "AOAI (aoai-dev808)", "foundry-dev", "Foundry (foundry-dev)"]'
            typeSettings: {
              additionalResourceOptions: []
              showDefault: false
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            value: 'aoai-dev808'
          }
        ]
      }
    }
    {
      type: 3
      name: 'token-usage'
      content: {
        version: 'KqlItem/1.0'
        size: 0
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        query: 'AzureMetrics\n| where TimeGenerated {TimeRange}\n| where _ResourceId has "{TargetResource}"\n| where MetricName in ("TokenTransaction","ProcessedPromptTokens","GeneratedTokens")\n| summarize Tokens = sum(Total) by MetricName, bin(TimeGenerated, 1h)\n| render timechart'
      }
    }
    {
      type: 3
      name: 'throttling'
      content: {
        version: 'KqlItem/1.0'
        size: 0
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
        query: 'AzureDiagnostics\n| where TimeGenerated {TimeRange}\n| where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"\n| where _ResourceId has "{TargetResource}"\n| extend StatusCode = toint(ResultSignature)\n| summarize Requests = count() by StatusCode, bin(TimeGenerated, 1h)\n| render columnchart'
      }
    }
  ]
  isLocked: false
  fallbackResourceIds: [
    logAnalyticsWorkspaceResourceId
  ]
}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, displayName)
  location: location
  kind: 'shared'
  properties: {
    displayName: displayName
    serializedData: string(workbookContent)
    category: 'workbook'
    sourceId: logAnalyticsWorkspaceResourceId
    version: 'Notebook/1.0'
  }
}

output workbookResourceId string = workbook.id
