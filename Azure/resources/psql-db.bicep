param adminUsername string = 'psqladmin'

@secure()
param adminPassword string 
param location string = resourceGroup().location 
param project_name string
param environment string 
param version string
param serverEdition string = 'Burstable' 
param instanceType string = 'Standard_B2s'
param availableZone string = '1'
param psql_version string = '15'


var dbServerName string = 'psql-${project_name}-${environment}-${version}' 
var snet_name string = 'snet-psql-${environment}-${version}'
var vnet_name string = 'vnet-${resourceGroup().location}-${environment}-${version}'
var vnet_rg string = 'rg-network-${environment}-${version}'
var dns_rg string = 'rg-privatedns-${environment}-${version}'
var dns_zone_name string = 'privatelink.postgres.database.azure.com'

resource psql 'Microsoft.DBforPostgreSQL/flexibleServers@2025-08-01' = {
  name: dbServerName
  location: location
  sku: {
    name: instanceType
    tier: serverEdition
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    version: psql_version
    network: {
      delegatedSubnetResourceId: resourceId(vnet_rg, 'Microsoft.Network/virtualNetworks/subnets', vnet_name, snet_name)
      privateDnsZoneArmResourceId: resourceId(dns_rg, 'Microsoft.Network/privateDnsZones', dns_zone_name)
    }
    highAvailability: {
      mode: 'Disabled'
    }
    storage:{
      storageSizeGB: 128
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    availabilityZone: availableZone
  }
}
