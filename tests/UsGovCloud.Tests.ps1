# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer or with Microsoft.

BeforeAll {
  $testDir = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '../contracts/cloud-environments.json'))) {
    $PSScriptRoot
  } else {
    Join-Path (Get-Location).Path 'tests'
  }
  $script:RepoRoot = Split-Path -Parent $testDir
  $script:CloudContractPath = Join-Path $script:RepoRoot 'contracts/cloud-environments.json'
  $script:OutputsSchemaPath = Join-Path $script:RepoRoot 'contracts/azure-outputs.schema.json'
  $script:HostBaselinePath = Join-Path $script:RepoRoot 'scripts/security/host-baseline.json'
  $script:CloudContract = Get-Content -Path $script:CloudContractPath -Raw | ConvertFrom-Json
  $script:OutputsSchema = Get-Content -Path $script:OutputsSchemaPath -Raw | ConvertFrom-Json
  $script:HostBaseline = Get-Content -Path $script:HostBaselinePath -Raw | ConvertFrom-Json
}

Describe 'C26 cloud-environments.json contract and azure-outputs.schema.json' {
  It 'pins contracts/cloud-environments.json with commercial and usgov environments' {
    Test-Path $script:CloudContractPath | Should -BeTrue
    $script:CloudContract.schema | Should -Be 'avd-cloud-environments/v1'
    $script:CloudContract.clouds.commercial.azCloudName | Should -Be 'AzureCloud'
    $script:CloudContract.clouds.usgov.azCloudName | Should -Be 'AzureUSGovernment'
    $script:CloudContract.clouds.usgov.psEnvironmentName | Should -Be 'AzureUSGovernment'
    $script:CloudContract.clouds.usgov.armEndpoint | Should -Be 'https://management.usgovcloudapi.net'
    $script:CloudContract.clouds.usgov.graphEndpoint | Should -Be 'https://graph.microsoft.us'
    $script:CloudContract.clouds.usgov.storageEndpointSuffix | Should -Be 'core.usgovcloudapi.net'
    $script:CloudContract.clouds.usgov.keyVaultDnsSuffix | Should -Be 'vault.usgovcloudapi.net'
    $script:CloudContract.clouds.usgov.privateDnsZones.avdGlobal | Should -Be 'privatelink-global.wvd.azure.us'
    $script:CloudContract.clouds.usgov.privateDnsZones.azureFiles | Should -Be 'privatelink.file.core.usgovcloudapi.net'
    $script:CloudContract.clouds.usgov.privateDnsZones.keyVault | Should -Be 'privatelink.vaultcore.usgovcloudapi.net'
    $script:CloudContract.clouds.usgov.capabilities.bastionDeveloperSku | Should -BeFalse
    $script:CloudContract.clouds.usgov.allowedRegions | Should -Be @('usgovvirginia', 'usgovarizona', 'usgovtexas')
  }

  It 'matches avd-assess contracts/cloud-environments.json when present alongside this repo' {
    $assessContract = Join-Path $script:RepoRoot '../avd-assess/contracts/cloud-environments.json'
    if (Test-Path $assessContract) {
      $localHash = (Get-FileHash -Path $script:CloudContractPath -Algorithm SHA256).Hash
      $assessHash = (Get-FileHash -Path $assessContract -Algorithm SHA256).Hash
      $localHash | Should -Be $assessHash
    }
  }

  It 'declares cloud and complianceProfile in contracts/azure-outputs.schema.json' {
    $script:OutputsSchema.properties.cloud.enum | Should -Be @('commercial', 'usgov')
    $script:OutputsSchema.properties.complianceProfile.enum | Should -Be @('standard', 'itar-cui')
  }
}

Describe 'Bicep Azure US Government and ITAR/CUI support' {
  It 'declares cloud and complianceProfile parameters and outputs in bicep/main.bicep and bicep/demo/main.bicep' {
    foreach ($relPath in @('bicep/main.bicep', 'bicep/demo/main.bicep')) {
      $text = Get-Content -Path (Join-Path $script:RepoRoot $relPath) -Raw
      $text | Should -Match "param cloud string = 'commercial'"
      $text | Should -Match "param complianceProfile string = \(cloud == 'usgov' \? 'itar-cui' : 'standard'\)"
      $text | Should -Match 'output cloud string = cloud'
      $text | Should -Match 'output complianceProfile string = complianceProfile'
      $text | Should -Not -Match '\.file\.core\.windows\.net'
    }
  }

  It 'wires AVD_CLOUD, AVD_COMPLIANCE_PROFILE, and usgovvirginia default region in parameters/*.bicepparam' {
    foreach ($paramFile in @('parameters/dev.bicepparam', 'parameters/test.bicepparam', 'parameters/prod.bicepparam')) {
      $text = Get-Content -Path (Join-Path $script:RepoRoot $paramFile) -Raw
      $text | Should -Match "readEnvironmentVariable\('AVD_CLOUD'"
      $text | Should -Match "readEnvironmentVariable\('AVD_COMPLIANCE_PROFILE'"
      $text | Should -Match "'usgovvirginia'"
    }
  }

  It 'configures sovereign Private Link DNS zones and az.environment() suffixes in bicep/modules/privateDns.bicep' {
    $dnsText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/privateDns.bicep') -Raw
    $dnsText | Should -Match "param cloud string = 'commercial'"
    $dnsText | Should -Match 'az\.environment\(\)\.suffixes\.storage'
    $dnsText | Should -Match 'az\.environment\(\)\.suffixes\.keyvaultDns'
    $dnsText | Should -Match 'privatelink\.wvd\.azure\.us'
    $dnsText | Should -Match 'privatelink-global\.wvd\.azure\.us'
    $dnsText | Should -Not -Match "'privatelink\.file\.core\.windows\.net'"
    $dnsText | Should -Not -Match "'privatelink\.vaultcore\.azure\.net'"
  }

  It 'derives dynamic storage and Key Vault endpoints via az.environment() in storage.bicep and keyVault.bicep' {
    $storageText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/storage.bicep') -Raw
    $kvText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/keyVault.bicep') -Raw
    $storageText | Should -Match 'az\.environment\(\)\.suffixes\.storage'
    $storageText | Should -Not -Match '\.file\.core\.windows\.net'
    $kvText | Should -Match 'az\.environment\(\)\.suffixes\.keyvaultDns'
    $kvText | Should -Not -Match '\.vault\.azure\.net'
  }

  It 'scopes allowed-locations policy to usgovvirginia, usgovarizona, and usgovtexas when cloud == usgov' {
    $govText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/governance.bicep') -Raw
    $govText | Should -Match "param cloud string = 'commercial'"
    $govText | Should -Match "'usgovvirginia'"
    $govText | Should -Match "'usgovarizona'"
    $govText | Should -Match "'usgovtexas'"
  }

  It 'adapts Bastion SKU to Basic with AzureBastionSubnet when cloud == usgov (bastionDeveloperSku == false)' {
    $bastionText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/bastionDeveloper.bicep') -Raw
    $netText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/modules/network.bicep') -Raw
    $bastionText | Should -Match "param cloud string = 'commercial'"
    $bastionText | Should -Match "param bastionDeveloperSku bool = cloud != 'usgov'"
    $bastionText | Should -Match "var effectiveSku = bastionDeveloperSku \? 'Developer' : bastionFallbackSku"
    $bastionText | Should -Match 'Microsoft\.Network/publicIPAddresses'
    $netText | Should -Match "name: 'AzureBastionSubnet'"
    $netText | Should -Match 'output bastionSubnetResourceId string'
  }

  It 'enforces itar-cui RDP lockdown properties in controlPlane.bicep and additionalPool.bicep' {
    $expectedRdp = $script:HostBaseline.complianceProfiles.'itar-cui'.customRdpProperty
    foreach ($relPath in @('bicep/modules/controlPlane.bicep', 'bicep/modules/additionalPool.bicep')) {
      $text = Get-Content -Path (Join-Path $script:RepoRoot $relPath) -Raw
      $text | Should -Match "param cloud string = 'commercial'"
      $text | Should -Match 'param complianceProfile string'
      $text | Should -Match ([regex]::Escape($expectedRdp))
    }
  }
}

Describe 'PowerShell AST scan for hardcoded commercial endpoints and suffixes' {
  It 'contains zero hardcoded commercial cloud endpoints or .windows.net literals in scripts/**/*.ps1' {
    $psFiles = Get-ChildItem -Path (Join-Path $script:RepoRoot 'scripts') -Recurse -Include '*.ps1', '*.psm1'
    $forbiddenPatterns = @(
      'management\.azure\.com',
      'graph\.microsoft\.com',
      'login\.microsoftonline\.com',
      'api\.bap\.microsoft\.com',
      '\.windows\.net'
    )
    $violations = New-Object System.Collections.Generic.List[string]
    foreach ($file in $psFiles) {
      $tokens = $null
      $errors = $null
      $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
      $errors | Should -BeNullOrEmpty
      $stringAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
      foreach ($strNode in $stringAsts) {
        foreach ($pattern in $forbiddenPatterns) {
          if ($strNode.Value -match $pattern) {
            $violations.Add("$($file.Name):$($strNode.Extent.StartLineNumber) -> $($strNode.Value)")
          }
        }
      }
    }
    $violations | Should -BeNullOrEmpty
  }
}

Describe 'Session host security baseline and deploy.sh cloud boundary checks' {
  It 'reports every control observed in host-baseline.json from Get-SessionHostSecurity.ps1' {
    $secScript = Get-Content -Path (Join-Path $script:RepoRoot 'scripts/ops/host/Get-SessionHostSecurity.ps1') -Raw
    foreach ($ctrl in $script:HostBaseline.controls) {
      $ctrl.id | Should -Not -BeNullOrEmpty
      $ctrl.observed | Should -Not -BeNullOrEmpty
      if ($ctrl.setBy -eq 'organization') {
        $ctrl.departure | Should -Not -BeNullOrEmpty
      }
      $secScript | Should -Match ([regex]::Escape("`$r.$($ctrl.observed)"))
    }
  }

  It 'configures FIPS 140, TLS 1.2+, screen capture protection, watermarking, and redirection lockdown in Set-FSLogixConfiguration.ps1' {
    $fslScript = Get-Content -Path (Join-Path $script:RepoRoot 'scripts/sessionhost/Set-FSLogixConfiguration.ps1') -Raw
    $fslScript | Should -Match 'fEnableScreenCaptureProtect'
    $fslScript | Should -Match 'fEnableWatermarking'
    $fslScript | Should -Match 'fDisableClip'
    $fslScript | Should -Match 'FIPSAlgorithmPolicy'
    $fslScript | Should -Match 'SchUseStrongCrypto'
  }

  It 'enforces fail-closed az cloud boundary check and US Gov Graph endpoint in scripts/deploy/deploy.sh' {
    $deploySh = Get-Content -Path (Join-Path $script:RepoRoot 'scripts/deploy/deploy.sh') -Raw
    $deploySh | Should -Match '--cloud\)'
    $deploySh | Should -Match '--compliance-profile\)'
    $deploySh | Should -Match '--output-manifest\)'
    $deploySh | Should -Match 'avd-ops-azure-outputs/v1'
    $deploySh | Should -Match 'AzureUSGovernment'
    $deploySh | Should -Match 'Cloud boundary mismatch'
    $deploySh | Should -Match 'https://graph\.microsoft\.us'
  }
}
