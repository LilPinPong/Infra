targetScope = 'subscription'

resource create_rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: deployment().name
  location: deployment().location
}

