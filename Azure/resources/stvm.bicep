param project_name string
param environment string
param version string

var vnet_rg string = 'rg-network-${environment}-${version}'
var vnet_name string = 'vnet-${resourceGroup().location}-${environment}-${version}'
var snet_name string = 'snet-psql-${environment}-${version}'


resource stvm 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: 'stvm${project_name}${environment}${version}'
  location: resourceGroup().location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: stvm
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blob
  name: 'share-${project_name}-${environment}-${version}'
  properties:{}
}

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: 'vm-${project_name}-${environment}-${version}'
}

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'ra-${project_name}-${environment}-${version}')
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'Storage Blob Data Owner')
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource pep 'Microsoft.Network/privateEndpoints@2025-05-01' = {
  name: 'pep-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: resourceId(vnet_rg, 'Microsoft.Network/virtualNetworks/subnets', vnet_name, snet_name)
    }
    customNetworkInterfaceName: 'nic-pep-${project_name}-${environment}-${version}'
    privateLinkServiceConnections: [
      {
        name: 'file'
        properties: {
          privateLinkServiceId: resourceId('rg-${project_name}-${environment}-${version}', 'Microsoft.Storage/storageAccounts', 'st${project_name}${environment}${version}')
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}
