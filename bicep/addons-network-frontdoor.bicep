// addons-network-frontdoor.bicep (trimmed for brevity)
param location string
param namePrefix string = 'acalab'
resource afdProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: '${namePrefix}-afd'
  location: 'Global'
  sku: { name: 'Premium_AzureFrontDoor' }
}
resource wafPolicy 'Microsoft.Network/frontdoorwebapplicationfirewallpolicies@2024-02-01' = {
  name: '${namePrefix}-waf'
  location: 'Global'
  properties: { policySettings: { enabledState: 'Enabled', mode: 'Prevention' } }
}
