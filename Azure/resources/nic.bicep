param project_name string
param environment string
param version string


resource vnet 'Microsoft.Network/virtualNetworks@2025-05-01' existing = {
  name: 'vnet-${resourceGroup().location}-${environment}-${version}'
  scope: resourceGroup('rg-network-${environment}-${version}')
}

resource snet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' existing = {
  parent: vnet
  name: 'snet-${project_name}-${environment}-${version}'
}



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
            id: resourceId('rg-${project_name}-${environment}-${version}', 'Microsoft.Network/publicIPAddresses', 'pip-${project_name}-${environment}-${version}')
            properties:{
              deleteOption: 'Delete'
            }
          }
          subnet: {
            id: snet.id
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
      id: resourceId('rg-${project_name}-${environment}-${version}', 'Microsoft.Network/networkSecurityGroups', 'nsg-${project_name}-${environment}-${version}')
    }
    nicType: 'Standard'
    auxiliaryMode: 'None'
    auxiliarySku: 'None'
  }
}
