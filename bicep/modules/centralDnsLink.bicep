// Links an existing central Private DNS zone to the AVD spoke VNet (HubPeered same-permission path).
// Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer or with Microsoft.

param zoneName string
param linkName string
param vnetResourceId string
param tags object = {}

resource existingZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: zoneName
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: existingZone
  name: linkName
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetResourceId
    }
    registrationEnabled: false
  }
}
