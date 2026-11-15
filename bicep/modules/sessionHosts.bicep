// Session hosts — Entra ID joined (optionally Intune enrolled), Trusted Launch,
// zone-spread, monitored by AMA, and made ready for users declaratively:
//   1. Configure-FSLogix run command (Entra Kerberos + profile container)
//   2. Register-AvdAgent run command (agent + boot loader + token)
// Both scripts live in scripts/sessionhost/ and are embedded at compile time.

@description('Cloud environment profile (commercial or usgov).')
@allowed([
  'commercial'
  'usgov'
])
param cloud string = 'commercial'

@description('Session and host hardening profile (itar-cui by default when cloud == usgov; standard otherwise).')
@allowed([
  'standard'
  'itar-cui'
])
param complianceProfile string = (cloud == 'usgov' ? 'itar-cui' : 'standard')

param location string
param tags object
param count int
@maxLength(11)
param namePrefix string
param vmSize string
param availabilityZones int[]
param imageReference object
param encryptionAtHost bool
param subnetResourceId string
param enrollInIntune bool
param localAdminUsername string

@secure()
param localAdminPassword string

@secure()
param hostPoolRegistrationToken string

param dataCollectionRuleResourceId string
param profileShareUncPath string
param fslogixProfileSizeMiB int
param usersGroupObjectId string
param adminsGroupObjectId string
param avdServicePrincipalObjectId string

@description('Daily shutdown time (HHmm, in autoShutdownTimeZone) for these hosts; empty = none. The demo sets it: the landing zone auto shutdown covers only its own host pool (avd-second-brain decision 0017).')
param autoShutdownTime string = ''
param autoShutdownTimeZone string = 'UTC'

@description('Create the resource-group role assignments for VM sign-in and power management. Set to false on additional pool modules targeting the same resource group.')
param deployRoleAssignments bool = true

@description('Resource ID of the parent AVD host pool. When set, applies cm-resource-parent on the VM, disk, NIC, schedule, extensions, and run commands so Azure Cost Management groups session-host spend under the host pool.')
param hostPoolResourceId string = ''

@description('Enable Accelerated Networking on session host NICs. Set to false for VM sizes that do not support it.')
param enableAcceleratedNetworking bool = true

@description('How Azure-distributed GPU drivers are installed on NV-series session hosts: auto deploys the VM extension on Standard_NV* SKUs; extension forces the extension; image assumes drivers are baked into the golden image; none skips driver and policy setup.')
@allowed([
  'auto'
  'extension'
  'image'
  'none'
])
param gpuDriverMode string = 'auto'

@description('Configure Terminal Services host policies for GPU rendering, H.264/AVC hardware encoding, and AVC 4:4:4 mode on GPU session hosts.')
param enableGpuGraphicsPolicy bool = true

var hostTags = empty(hostPoolResourceId) ? tags : union(tags, { 'cm-resource-parent': hostPoolResourceId })
var vmSizeLower = toLower(vmSize)
var isNvGpu = startsWith(vmSizeLower, 'standard_nv')
var isAmdGpu = isNvGpu && (contains(vmSizeLower, 'as_v4') || contains(vmSizeLower, 'v710'))
var deployGpuExtension = (gpuDriverMode == 'extension') || (gpuDriverMode == 'auto' && isNvGpu)
var applyGpuPolicy = enableGpuGraphicsPolicy && isNvGpu && (gpuDriverMode != 'none')

var roles = {
  vmUserLogin: 'fb879df8-f326-4884-b1cf-06f3ad86be52'
  vmAdminLogin: '1c0163c0-47e6-4577-8991-ea5c82e286e4'
  powerOnOffContributor: '40c5ff49-9181-41f8-ae61-143b0e78555e'
}

// 11-char prefix + '-' + 3-digit index = 15 chars, the Windows computer-name limit.
var vmNames = [for i in range(0, count): '${namePrefix}-${padLeft(i + 1, 3, '0')}']
var intuneMdmId = '0000000a-0000-0000-c000-000000000000'
var loginAuthority = az.environment().authentication.loginEndpoint

module vm 'br/public:avm/res/compute/virtual-machine:0.22.3' = [
  for (vmName, i) in vmNames: {
    name: 'vm-${vmName}'
    params: {
      name: vmName
      location: location
      tags: hostTags
      vmSize: vmSize
      autoShutdownConfig: empty(autoShutdownTime) ? {} : { status: 'Enabled', dailyRecurrenceTime: autoShutdownTime, timeZone: autoShutdownTimeZone }
      osType: 'Windows'
      // AVD multi-session: Windows client licensing via the user's M365/Windows E3+ entitlement.
      licenseType: 'Windows_Client'
      availabilityZone: empty(availabilityZones) ? -1 : availabilityZones[i % length(availabilityZones)]
      imageReference: imageReference
      securityType: 'TrustedLaunch'
      secureBootEnabled: true
      vTpmEnabled: true
      encryptionAtHost: encryptionAtHost
      // Premium SSD for the OS disk: multi-session hosts page, log on and update many users at once.
      osDisk: {
        caching: 'ReadWrite'
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      adminUsername: localAdminUsername
      adminPassword: localAdminPassword
      nicConfigurations: [
        {
          nicSuffix: '-nic'
          deleteOption: 'Delete'
          enableAcceleratedNetworking: enableAcceleratedNetworking
          ipConfigurations: [
            {
              name: 'ipconfig1'
              subnetResourceId: subnetResourceId
            }
          ]
        }
      ]
      managedIdentities: {
        systemAssigned: true
      }
      bootDiagnostics: true
      extensionAadJoinConfig: {
        enabled: true
        settings: enrollInIntune
          ? {
              mdmId: intuneMdmId
            }
          : {}
      }
      extensionMonitoringAgentConfig: {
        enabled: true
        dataCollectionRuleAssociations: [
          {
            name: 'avd-insights'
            dataCollectionRuleResourceId: dataCollectionRuleResourceId
          }
        ]
      }
      extensionGuestConfigurationExtension: {
        enabled: true
      }
      // Windows 11 ships Microsoft Defender Antivirus; the IaaS antimalware
      // extension is for Windows Server only.
      extensionAntiMalwareConfig: {
        enabled: false
      }
    }
  }
]

resource sessionHost 'Microsoft.Compute/virtualMachines@2024-07-01' existing = [
  for vmName in vmNames: {
    name: vmName
  }
]

resource configureFslogix 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = [
  for (vmName, i) in vmNames: {
    parent: sessionHost[i]
    name: 'Configure-FSLogix'
    location: location
    tags: hostTags
    properties: {
      source: {
        script: loadTextContent('../../scripts/sessionhost/Set-FSLogixConfiguration.ps1')
      }
      parameters: [
        {
          name: 'ProfileShareUncPath'
          value: profileShareUncPath
        }
        {
          name: 'ProfileSizeMiB'
          value: string(fslogixProfileSizeMiB)
        }
        {
          name: 'LocalAdminUsername'
          value: localAdminUsername
        }
        {
          name: 'Cloud'
          value: cloud
        }
        {
          name: 'ComplianceProfile'
          value: complianceProfile
        }
      ]
      asyncExecution: false
      treatFailureAsDeploymentFailure: true
      timeoutInSeconds: 600
    }
    dependsOn: [
      vm[i]
    ]
  }
]

resource registerAgent 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = [
  for (vmName, i) in vmNames: {
    parent: sessionHost[i]
    name: 'Register-AvdAgent'
    location: location
    tags: hostTags
    properties: {
      source: {
        script: loadTextContent('../../scripts/sessionhost/Register-AvdAgent.ps1')
      }
      parameters: [
        {
          name: 'Cloud'
          value: cloud
        }
        {
          name: 'ComplianceProfile'
          value: complianceProfile
        }
      ]
      protectedParameters: [
        {
          name: 'RegistrationToken'
          value: hostPoolRegistrationToken
        }
      ]
      asyncExecution: false
      treatFailureAsDeploymentFailure: true
      timeoutInSeconds: 1800
    }
    // Run commands on one VM execute one at a time.
    dependsOn: [
      configureFslogix[i]
    ]
  }
]

resource gpuDriverExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [
  for (vmName, i) in vmNames: if (deployGpuExtension) {
    parent: sessionHost[i]
    name: isAmdGpu ? 'AmdGpuDriverWindows' : 'NvidiaGpuDriverWindows'
    location: location
    tags: hostTags
    properties: {
      publisher: 'Microsoft.HpcCompute'
      type: isAmdGpu ? 'AmdGpuDriverWindows' : 'NvidiaGpuDriverWindows'
      typeHandlerVersion: isAmdGpu ? '1.1' : '1.9'
      autoUpgradeMinorVersion: true
    }
    dependsOn: [
      vm[i]
    ]
  }
]

resource configureGpuGraphics 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = [
  for (vmName, i) in vmNames: if (applyGpuPolicy) {
    parent: sessionHost[i]
    name: 'Configure-GpuGraphics'
    location: location
    tags: hostTags
    properties: {
      source: {
        script: loadTextContent('../../scripts/sessionhost/Set-GpuGraphicsPolicy.ps1')
      }
      asyncExecution: false
      treatFailureAsDeploymentFailure: true
      timeoutInSeconds: 600
    }
    dependsOn: [
      registerAgent[i]
    ]
  }
]

// ---------- Access to the hosts ----------
// Entra ID sign-in to the VMs requires these, in addition to the app group assignment.
resource usersLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployRoleAssignments) {
  name: guid(resourceGroup().id, usersGroupObjectId, roles.vmUserLogin)
  properties: {
    principalId: usersGroupObjectId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.vmUserLogin)
  }
}

resource adminsLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployRoleAssignments) {
  name: guid(resourceGroup().id, adminsGroupObjectId, roles.vmAdminLogin)
  properties: {
    principalId: adminsGroupObjectId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.vmAdminLogin)
  }
}

// Autoscale and Start VM on Connect start/stop the VMs in this resource group.
resource powerOnOff 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployRoleAssignments) {
  name: guid(resourceGroup().id, avdServicePrincipalObjectId, roles.powerOnOffContributor)
  properties: {
    principalId: avdServicePrincipalObjectId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.powerOnOffContributor)
  }
}

output names string[] = vmNames
output loginAuthority string = loginAuthority
