param project_name string
param environment string
param version string

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: resourceId('rg-network-${environment}-${version}', 'Microsoft.Network/publicIPAddresses', 'pip-${project_name}-${environment}-${version}')
            properties:{
              deleteOption: 'Delete'
            }
          }
          subnet: {
            id: resourceId('rg-network-${environment}-${version}', 'Microsoft.Network/virtualNetworks/subnets', 'vnet-${resourceGroup().location}-${environment}-${version}', 'snet-psql-${environment}-${version}')
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    dnsSettings:{
      dnsServers: []
    }
    enableAcceleratedNetworking:true
    enableIPForwarding:false
    disableTcpStateTracking:false
    networkSecurityGroup: {
      id: resourceId('rg-network-${environment}-${version}', 'Microsoft.Network/networkSecurityGroups', 'nsg-${project_name}-${environment}-${version}')
    }
    nicType: 'Standard'
    auxiliaryMode: 'None'
    auxiliarySku: 'None'
  }
}
