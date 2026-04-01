param project_name string
param environment string
param version string
param assignBlobRole bool = false

var vnet_rg string = 'rg-network-${environment}-${version}'
var vnet_name string = 'vnet-${resourceGroup().location}-${environment}-${version}'
var snet_name string = 'snet-${project_name}-${environment}-${version}'
var privateDnsResourceGroupName = 'rg-privatedns-${environment}-${version}'


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

resource ra 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignBlobRole) {
  name: guid(resourceGroup().id, 'ra-${project_name}-${environment}-${version}')
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9d819e60-1b9f-4871-b492-4e6cdee0b50a')
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource pep 'Microsoft.Network/privateEndpoints@2025-05-01' = {
  name: 'stvm-pep-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: resourceId(vnet_rg, 'Microsoft.Network/virtualNetworks/subnets', vnet_name, snet_name)
    }
    customNetworkInterfaceName: 'stvm-nic-${project_name}-${environment}-${version}'
    privateLinkServiceConnections: [
      {
        name: 'file'
        properties: {
          privateLinkServiceId: stvm.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  scope: resourceGroup(privateDnsResourceGroupName)
}

resource blobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-05-01' = {
  name: 'default'
  parent: pep
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}
