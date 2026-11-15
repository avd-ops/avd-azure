#requires -Version 7.2
$ErrorActionPreference = 'Stop'

Describe 'Per-run NamePrefix support in avd-azure' {
  BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $script:DevParam = Get-Content (Join-Path $RepoRoot 'parameters/dev.bicepparam') -Raw
    $script:DeploySh = Get-Content (Join-Path $RepoRoot 'scripts/deploy/deploy.sh') -Raw
  }

  It 'wires AVD_NAME_PREFIX in parameters/dev.bicepparam with avdlz fallback' {
    $DevParam | Should -Match "param\s+namePrefix\s*=.*readEnvironmentVariable\('AVD_NAME_PREFIX',\s*''\).*'avdlz'"
  }

  It 'supports --name-prefix and AVD_NAME_PREFIX in scripts/deploy/deploy.sh' {
    $DeploySh | Should -Match 'NAME_PREFIX_ARG="\$\{AVD_NAME_PREFIX:-\}"'
    $DeploySh | Should -Match '--name-prefix\)\s*NAME_PREFIX_ARG="\$2"'
    $DeploySh | Should -Match 'export AVD_NAME_PREFIX="\$NAME_PREFIX_ARG"'
    $DeploySh | Should -Match 'NAME_PREFIX="\$\{NAME_PREFIX_ARG:-\$\(param_value namePrefix\)\}"'
  }

  It 'derives --output-manifest prefix and resource group names from deployed outputs' {
    $DeploySh | Should -Match 'OUT_PREFIX="\$\{BASE_NAME%-\*\}"'
    $DeploySh | Should -Match '"controlPlane":\s*\$\(json_str "rg-\$BASE_NAME-avd"\)'
  }
}
