param environment string
param version string

var vnetResourceGroupName string = 'rg-network-${environment}-${version}'
var vnetName string = 'vnet-${resourceGroup().location}-${environment}-${version}'
var soaEmail string = 'LangisGabyhotmail.onmicrosoft.com'

var zone_links = [
  'privatelink.blob.${az.environment().suffixes.storage}'
  'privatelink.file.${az.environment().suffixes.storage}'
  'privatelink.queue.${az.environment().suffixes.storage}'
  'privatelink.table.${az.environment().suffixes.storage}'
  'privatelink.database.${az.environment().suffixes.storage}'
  'privatelink.mysql.database.azure.com'
  'privatelink.mariadb.database.azure.com'
  'privatelink.postgres.database.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.azurewebsites.net'
  'privatelink.azurecr.io'
]

var vnetId = resourceId(vnetResourceGroupName, 'Microsoft.Network/virtualNetworks', vnetName)

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for link in zone_links: {
  name: link
  location: 'global'
  properties: {}
}]

resource soaZones 'Microsoft.Network/privateDnsZones/SOA@2024-06-01' = [for (link, i) in zone_links: {
  parent: zones[i]
  name: '@'
  properties: {
    ttl: 3600
    soaRecord: {
      email: soaEmail
      serialNumber: 1
      refreshTime: 3600
      retryTime: 900
      expireTime: 1209600
      minimumTtl: 900
    }
  }
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (link, i) in zone_links: {
  parent: zones[i]
  name: 'pl-${uniqueString(link, vnetId)}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
    resolutionPolicy: 'NxDomainRedirect'
  }
}]
