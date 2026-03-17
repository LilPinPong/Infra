targetScope = 'subscription'

param env string
param version string
param name string
param location string = 'canadaeast'

resource create_rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${name}-${env}-${version}'
  location: location
}

