param project_name string
param environment string
param version string
param allowedHttpSourcePrefix string = '184.160.139.84'

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: 'vnet-${resourceGroup().location}-${environment}-${version}'
  scope: resourceGroup('rg-network-${environment}-${version}')
}

resource snet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnet
  name: 'snet-${project_name}-${environment}-${version}'
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '184.160.139.84'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Allow SSH traffic from KshTech IP address to any destination on port 22'
        }
      }
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedHttpSourcePrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Allow HTTP traffic from trusted source on port 80'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          priority: 1002
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          description: 'Allow HTTPS traffic from any source to any destination on port 443'
        }
      }
      {
        name: 'Allow-445'
        properties: {
          priority: 1003
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: snet.properties.addressPrefixes[0]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '445'
          description: 'Allow SMB traffic from any source to any destination on port 445'
        }
      }
    ]
  }
}

output snet string = snet.properties.addressPrefixes[0]
