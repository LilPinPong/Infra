

resource network_watcher 'Microsoft.Network/networkWatchers@2025-05-01' = {
  name: 'nw-${resourceGroup().location}'
  location: resourceGroup().location
  properties: {}
}
