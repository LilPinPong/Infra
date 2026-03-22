param project_name string 
param environment string
param version string

@description('The location of the resources')
param location string = resourceGroup().location

@description('The SKU of the vault to be created.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('The object ID of a user, service principal, or security group for access policies.')
param objectId string

@description('Permissions for secrets in the vault.')
param secretsPermissions array = ['get', 'list', 'set', 'delete', 'backup', 'restore']

@description('Permissions for keys in the vault.')
param keysPermissions array = ['get','list', 'create', 'delete', 'backup','restore']

param createKv bool = true

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = if (createKv) {
  name: 'kv-${environment}-${version}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    publicNetworkAccess:'Disabled'
    tenantId: subscription().tenantId
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    accessPolicies: [
      {
        objectId: objectId
        tenantId: subscription().tenantId
        permissions: {
          secrets: secretsPermissions
          keys: keysPermissions
        }
      }
    ]
  }
}   


resource vnet 'Microsoft.Network/VirtualNetworks@2023-11-01' existing = {
  name: 'vnet-${resourceGroup().location}-${environment}-${version}'
  scope: resourceGroup('rg-network-${environment}-${version}')
}

resource snet 'Microsoft.Network/virtualNetworks/subnets@2025-05-01' existing = {
  parent: vnet
  name: 'snet-${project_name}-${environment}-${version}'
}

resource pep 'Microsoft.Network/privateEndpoints@2025-05-01' = {
  name: 'pep-kv-${environment}-${version}'
  location: location
  tags: {}
  properties: {
    subnet: {
      id: snet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'kv-privatelink-${environment}-${version}'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: ['vault']
          requestMessage: 'Please approve the private endpoint connection for Key Vault.'
        }
      }
    ]
    customNetworkInterfaceName: 'nic-pep-kv-${environment}-${version}'
  }
}
