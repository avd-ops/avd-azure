// Azure Bastion (build/decisions/0019-jumpbox-bastion-developer.md, avd-ops decision 0013):
//   - commercial (bastionDeveloperSku == true): Bastion Developer SKU (no AzureBastionSubnet, no public IP, no charge).
//   - usgov (bastionDeveloperSku == false): Bastion Basic/Standard SKU with AzureBastionSubnet (/26) and Standard Public IP.

@description('Cloud environment profile (commercial or usgov).')
@allowed([
  'commercial'
  'usgov'
])
param cloud string = 'commercial'
param location string
param tags object
param name string
param vnetResourceId string

@description('Whether the target cloud supports Azure Bastion Developer SKU (C26 capabilities.bastionDeveloperSku; false in usgov).')
param bastionDeveloperSku bool = cloud != 'usgov'

@description('Fallback Bastion SKU when Bastion Developer SKU is unavailable (usgov).')
@allowed([
  'Basic'
  'Standard'
])
param bastionFallbackSku string = 'Basic'

@description('Resource ID of AzureBastionSubnet (used when bastionDeveloperSku is false).')
param bastionSubnetResourceId string = ''

@description('Entra group of AVD operators: Reader on this Bastion, which a connection needs.')
param adminsGroupObjectId string

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var effectiveSku = bastionDeveloperSku ? 'Developer' : bastionFallbackSku
var effectiveBastionSubnetId = !empty(bastionSubnetResourceId)
  ? bastionSubnetResourceId
  : '${vnetResourceId}/subnets/AzureBastionSubnet'

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (!bastionDeveloperSku) {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-07-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: effectiveSku
  }
  properties: bastionDeveloperSku
    ? {
        virtualNetwork: {
          id: vnetResourceId
        }
      }
    : {
        ipConfigurations: [
          {
            name: 'IpConf'
            properties: {
              subnet: {
                id: effectiveBastionSubnetId
              }
              publicIPAddress: {
                id: bastionPublicIp.id
              }
            }
          }
        ]
      }
}

resource adminsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(bastion.id, adminsGroupObjectId, readerRoleId)
  scope: bastion
  properties: {
    principalId: adminsGroupObjectId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
  }
}

output resourceId string = bastion.id
output skuName string = effectiveSku
