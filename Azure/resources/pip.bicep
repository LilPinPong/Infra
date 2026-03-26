param project_name string
param environment string
param version string

resource pip 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: 'pip-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
    dnsSettings: {
      domainNameLabel: 'lilpinpong'
    }
  }
}
 