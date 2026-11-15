<#
.SYNOPSIS
    Installs Azure-distributed NVIDIA GRID or AMD GPU drivers during golden image build.
.DESCRIPTION
    Use this script when baking a custom GPU golden image and deploying session
    hosts with gpuDriverMode = 'image'. For marketplace images, leave
    gpuDriverMode = 'auto' (or 'extension') so Bicep installs the Azure VM
    extension (NvidiaGpuDriverWindows / AmdGpuDriverWindows).
    Only Azure-distributed drivers are supported on AVD GPU VMs
    (avd-assess ref:avd-gpu-acceleration#grid-driver-only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('nvidia', 'amd')]
    [string]$Vendor,

    [string]$InstallerPath
)

$ErrorActionPreference = 'Stop'

$urls = @{
    nvidia = 'https://go.microsoft.com/fwlink/?linkid=874181'
    amd    = 'https://go.microsoft.com/fwlink/?linkid=2203667'
}

$downloadUrl = $urls[$Vendor]
$targetInstaller = if ($InstallerPath) { $InstallerPath } else { Join-Path $env:TEMP "avd-gpu-driver-$Vendor.exe" }

if (-not (Test-Path -LiteralPath $targetInstaller)) {
    Write-Output "Downloading Azure-distributed $Vendor GPU driver from $downloadUrl..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $downloadUrl -OutFile $targetInstaller -UseBasicParsing
}

$silentArgs = if ($Vendor -eq 'nvidia') { '-s -n' } else { '-install -log' }
Write-Output "Installing $Vendor GPU driver silently..."
$proc = Start-Process -FilePath $targetInstaller -ArgumentList $silentArgs -Wait -PassThru
if ($proc.ExitCode -notin @(0, 3010)) {
    throw "GPU driver installer exited with code $($proc.ExitCode)."
}

Write-Output "Installed Azure-distributed $Vendor GPU driver (exit code $($proc.ExitCode))."
