param project_name string
param environment string
param version string

param adminUsername string = 'azureuser'
@secure()
param adminPassword string
param adminPublicKey string

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: 'vm-${project_name}-${environment}-${version}'
  location: resourceGroup().location
  zones: ['1']
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    
    storageProfile: {
      imageReference: {
        publisher: 'Debian'
        offer: 'debian-13'
        sku: '13-gen2'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: 'osdisk-${project_name}-${environment}-${version}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
    //    dataDisk:[]
    //    diskController: 'SCSI'
      }
    }
    osProfile: {
      computerName: 'vm-${project_name}-${environment}-${version}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
      secrets: []
      allowExtensionOperations: true
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resourceId('rg-network-${environment}-${version}', 'Microsoft.Network/networkInterfaces', 'nic-${project_name}-${environment}-${version}')
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}
