@allowed(['test','dev','qa','prod'])
param environment string
param version string
param project_name string

@description('network address IPv4 (format 1.2.3.4) range for the vnet')
param vnet_address_range string = '172.18.0.0'
@minValue(2) 
@maxValue(30)
param vnet_address_range_suffix int = 16
var snet_psql string = 'snet-psql-${environment}-${version}'
var snet_name string = 'snet-${project_name}-${environment}-${version}'

var vnet_name = 'vnet-${resourceGroup().location}-${environment}-${version}'
var vnet_address_space = '${vnet_address_range}/${vnet_address_range_suffix}'
var octets = split(vnet_address_range, '.')
var vnet_address_range_base = '${octets[0]}.${octets[1]}'

var subnets = [
  {subnetName: 'Gateway' , addressPrefix: '${vnet_address_range_base}.0.0/26'}
  {subnetName: 'Bastion' , addressPrefix: '${vnet_address_range_base}.0.64/26'}
  {subnetName: 'Firewall' , addressPrefix: '${vnet_address_range_base}.0.128/26'}
  {subnetName: 'FirewallMgmt' , addressPrefix: '${vnet_address_range_base}.0.192/26'}
  {subnetName: 'AppGateway' , addressPrefix: '${vnet_address_range_base}.1.0/26'}
  {subnetName: 'RouteServer' , addressPrefix: '${vnet_address_range_base}.1.64/26'}
  {subnetName: 'DatabricksPrivate' , addressPrefix: '${vnet_address_range_base}.1.128/26'}
  {subnetName: 'DatabricksPublic' , addressPrefix: '${vnet_address_range_base}.1.192/26'}
  {subnetName: snet_name , addressPrefix: '${vnet_address_range_base}.2.0/26'}
  {subnetName: snet_psql , addressPrefix: '${vnet_address_range_base}.2.64/26'}
]

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnet_name
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnet_address_space
      ]
    }
    encryption: {
      enabled: true
    }
    subnets: [
      for subnet in subnets: {
        name: subnet.subnetName
        properties: subnet.subnetName == snet_psql ? {
          defaultOutboundAccess: false
          addressPrefixes: [subnet.addressPrefix]
          delegations: [
            {
              name: 'psql_delegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        } : {
          addressPrefixes: [subnet.addressPrefix]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}
