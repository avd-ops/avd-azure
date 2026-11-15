# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer or with Microsoft.

BeforeAll {
  $testDir = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '../bicep/main.bicep'))) {
    $PSScriptRoot
  } else {
    Join-Path (Get-Location).Path 'tests'
  }
  $script:RepoRoot = Split-Path -Parent $testDir
}

Describe 'C31 avd-networking-outputs/v1 wiring in avd-azure' {
  It 'wires HubPeered connectivity env vars in parameters/*.bicepparam' {
    foreach ($paramFile in @('parameters/dev.bicepparam', 'parameters/test.bicepparam', 'parameters/prod.bicepparam')) {
      $text = Get-Content -Path (Join-Path $script:RepoRoot $paramFile) -Raw
      $text | Should -Match "readEnvironmentVariable\('AVD_CONNECTIVITY_MODE'"
      $text | Should -Match "readEnvironmentVariable\('AVD_HUB_VNET_ID'"
      $text | Should -Match "readEnvironmentVariable\('AVD_CREATE_HUB_PEERING'"
      $text | Should -Match "readEnvironmentVariable\('AVD_HUB_FIREWALL_IP'"
      $text | Should -Match "readEnvironmentVariable\('AVD_DNS_SERVERS_JSON'"
      $text | Should -Match "readEnvironmentVariable\('AVD_CENTRAL_DNS_ZONES_JSON'"
    }
  }

  It 'accepts all four centralPrivateDnsZoneResourceIds keys in bicep/main.bicep' {
    $mainText = Get-Content -Path (Join-Path $script:RepoRoot 'bicep/main.bicep') -Raw
    $mainText | Should -Match 'centralPrivateDnsZoneResourceIds\.\?file'
    $mainText | Should -Match 'centralPrivateDnsZoneResourceIds\.\?keyVault'
    $mainText | Should -Match 'centralPrivateDnsZoneResourceIds\.\?avd'
    $mainText | Should -Match 'centralPrivateDnsZoneResourceIds\.\?avdGlobal'
  }

  It 'supports --networking-outputs in scripts/deploy/deploy.sh' {
    $deployText = Get-Content -Path (Join-Path $script:RepoRoot 'scripts/deploy/deploy.sh') -Raw
    $deployText | Should -Match '--networking-outputs'
    $deployText | Should -Match 'avd-networking-outputs/v1'
    $deployText | Should -Match 'AVD_CONNECTIVITY_MODE="HubPeered"'
  }
}
