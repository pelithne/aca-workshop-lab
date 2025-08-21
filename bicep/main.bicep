param location string
param namePrefix string = 'acalab'
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${namePrefix}-law'
  location: location
  properties: { retentionInDays: 30 }
}
resource env 'Microsoft.App/managedEnvironments@2024-02-02-preview' = {
  name: 'acaenv-weu'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: listKeys(law.id, law.apiVersion).primarySharedKey
      }
    }
  }
}
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-shopapi'
  location: location
}
resource kv 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: '${namePrefix}-kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { name: 'standard' family: 'A' }
    accessPolicies: []
    enabledForTemplateDeployment: true
  }
}
output logAnalyticsId string = law.id
output managedEnvName string = env.name
output identityId string = uami.id
output keyVaultName string = kv.name
