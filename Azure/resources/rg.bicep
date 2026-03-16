targetScope = 'subscription'

param env string
param version string
param name string

resource create_rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${name}-${env}-${version}'
  location: 'canadaeast'
}

