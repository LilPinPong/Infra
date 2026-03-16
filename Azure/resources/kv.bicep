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
param secretsPermissions array = ['get', 'set', 'list']

@description('Permissions for keys in the vault.')
param keysPermissions array = ['get','encrypt','list']

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${project_name}-${environment}-${version}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    enableSoftDelete: false
    softDeleteRetentionInDays: 90
    enabledForTemplateDeployment: true
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
