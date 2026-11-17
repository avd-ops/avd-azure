// Azure Local session hosts — native Entra ID join only in v1 (Decision 0023),
// deployed as Arc-enabled virtual machine instances on an existing registered
// Azure Local 23H2+ instance with a Custom Location and Arc logical network.

@description('Azure region matching the Azure Local cluster registration.')
param location string

@description('Resource tags applied to Arc machine, NIC, and VM instance resources.')
param tags object

@description('Number of Azure Local session hosts to deploy.')
@minValue(0)
param count int

@description('Host name prefix (max 11 chars so <prefix>-NN fits NetBIOS 15-char limit).')
@maxLength(11)
param namePrefix string

@description('Resource ID of the target Custom Location (Microsoft.ExtendedLocation/customLocations).')
param customLocationId string

@description('Resource ID of the target Arc logical network (Microsoft.AzureStackHCI/logicalNetworks).')
param logicalNetworkId string

@description('Resource ID of the target Azure Local gallery or marketplace image.')
param imageId string

@description('vCPU count per Azure Local VM instance.')
@minValue(2)
param processors int = 4

@description('Memory in MB per Azure Local VM instance.')
@minValue(4096)
param memoryMB int = 16384

@description('Enroll native Entra-joined session hosts in Microsoft Intune.')
param enrollInIntune bool = true

@description('Local administrator username for VM provisioning.')
param localAdminUsername string

@secure()
@description('Local administrator password for VM provisioning.')
param localAdminPassword string

@secure()
@description('AVD host pool registration token.')
param hostPoolRegistrationToken string

@description('Bring-your-own on-premises SMB UNC path for FSLogix profile containers.')
param localSmbProfilePath string = ''

@description('FSLogix profile VHDX max size in MiB.')
param fslogixProfileSizeMiB int = 30720

@description('Resource ID of the parent AVD host pool (applied as cm-resource-parent tag).')
param hostPoolResourceId string = ''

var hostTags = !empty(hostPoolResourceId)
  ? union(tags, { 'cm-resource-parent': hostPoolResourceId })
  : tags

var hostIndices = range(0, count)

resource hybridMachine 'Microsoft.HybridCompute/machines@2024-07-10' = [
  for i in hostIndices: {
    name: '${namePrefix}-${padLeft(string(i), 2, '0')}'
    location: location
    tags: hostTags
    kind: 'HCI'
    identity: {
      type: 'SystemAssigned'
    }
  }
]

resource hciNic 'Microsoft.AzureStackHCI/networkInterfaces@2024-01-01' = [
  for i in hostIndices: {
    name: '${namePrefix}-${padLeft(string(i), 2, '0')}-nic'
    location: location
    tags: hostTags
    extendedLocation: {
      type: 'CustomLocation'
      name: customLocationId
    }
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: logicalNetworkId
            }
          }
        }
      ]
    }
  }
]

resource vmInstance 'Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01' = [
  for i in hostIndices: {
    name: 'default'
    scope: hybridMachine[i]
    extendedLocation: {
      type: 'CustomLocation'
      name: customLocationId
    }
    properties: {
      hardwareProfile: {
        vmSize: 'Custom'
        processors: processors
        memoryMB: memoryMB
      }
      osProfile: {
        computerName: '${namePrefix}-${padLeft(string(i), 2, '0')}'
        adminUsername: localAdminUsername
        adminPassword: localAdminPassword
        windowsConfiguration: {
          provisionVMAgent: true
          provisionVMConfigAgent: true
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: hciNic[i].id
          }
        ]
      }
      storageProfile: {
        imageReference: {
          id: imageId
        }
      }
    }
  }
]

resource aadLoginExtension 'Microsoft.HybridCompute/machines/extensions@2024-07-10' = [
  for i in hostIndices: {
    parent: hybridMachine[i]
    name: 'AADLoginForWindows'
    location: location
    tags: hostTags
    dependsOn: [
      vmInstance[i]
    ]
    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      type: 'AADLoginForWindows'
      autoUpgradeMinorVersion: true
      settings: enrollInIntune
        ? {
            mdmId: '0000000a-0000-0000-c000-000000000000'
          }
        : {}
    }
  }
]

var fslogixCmd = !empty(localSmbProfilePath)
  ? 'New-Item -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Force | Out-Null; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name Enabled -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name VHDLocations -Value \'${localSmbProfilePath}\' -Type MultiString; Set-ItemProperty -Path HKLM:\\SOFTWARE\\FSLogix\\Profiles -Name SizeInMBs -Value ${fslogixProfileSizeMiB} -Type DWord;'
  : ''

resource avdConfigExtension 'Microsoft.HybridCompute/machines/extensions@2024-07-10' = [
  for i in hostIndices: {
    parent: hybridMachine[i]
    name: 'ConfigureAvdAndFSLogix'
    location: location
    tags: hostTags
    dependsOn: [
      aadLoginExtension[i]
    ]
    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      autoUpgradeMinorVersion: true
      protectedSettings: {
        commandToExecute: 'powershell -ExecutionPolicy Bypass -Command "${fslogixCmd} New-Item -Path \'HKLM:\\SOFTWARE\\Microsoft\\RDInfraAgent\' -Force | Out-Null; Set-ItemProperty -Path \'HKLM:\\SOFTWARE\\Microsoft\\RDInfraAgent\' -Name RegistrationToken -Value \'${hostPoolRegistrationToken}\' -Type String"'
      }
    }
  }
]

output names string[] = [for i in hostIndices: '${namePrefix}-${padLeft(string(i), 2, '0')}']
output vmInstanceIds string[] = [for i in hostIndices: vmInstance[i].id]
output hybridComputeMachineIds string[] = [for i in hostIndices: hybridMachine[i].id]
