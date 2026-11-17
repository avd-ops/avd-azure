#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Azure Local session host placement (Decision 0023)' {
    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:moduleFile = Join-Path $script:repoRoot 'bicep/modules/azureLocalSessionHosts.bicep'
        $script:mainFile = Join-Path $script:repoRoot 'bicep/main.bicep'
        $script:moduleText = Get-Content -LiteralPath $script:moduleFile -Raw
        $script:mainText = Get-Content -LiteralPath $script:mainFile -Raw
    }

    It 'compiles azureLocalSessionHosts.bicep cleanly with bicep build' {
        $out = az bicep build --file $script:moduleFile --stdout
        $LASTEXITCODE | Should -Be 0
        $arm = $out | ConvertFrom-Json
        $resList = if ($arm.resources -is [System.Array]) { $arm.resources } else { @($arm.resources.PSObject.Properties.Value) }
        $types = @($resList | ForEach-Object { $_.type })
        $types | Should -Contain 'Microsoft.HybridCompute/machines'
        $types | Should -Contain 'Microsoft.AzureStackHCI/networkInterfaces'
        $types | Should -Contain 'Microsoft.AzureStackHCI/virtualMachineInstances'
        $types | Should -Contain 'Microsoft.HybridCompute/machines/extensions'
    }

    It 'enforces native Entra ID join only in v1 (AADLoginForWindows, no JsonADDomainExtension)' {
        $script:moduleText | Should -Match 'AADLoginForWindows'
        $script:moduleText | Should -Not -Match 'JsonADDomainExtension'
    }

    It 'wires hostPlacement and optional azureLocal output in main.bicep' {
        $script:mainText | Should -Match "param hostPlacement string = 'azure'"
        $script:mainText | Should -Match "module storage 'modules/storage\.bicep' = if \(hostPlacement == 'azure'\)"
        $script:mainText | Should -Match "module azureLocalSessionHosts 'modules/azureLocalSessionHosts\.bicep' = if \(hostPlacement == 'azure-local'\)"
        $script:mainText | Should -Match 'output azureLocal object'
    }

    It 'compiles main.bicep cleanly with az bicep build' {
        $null = az bicep build --file $script:mainFile --stdout
        $LASTEXITCODE | Should -Be 0
    }
}
