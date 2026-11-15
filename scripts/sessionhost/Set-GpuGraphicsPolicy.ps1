<#
.SYNOPSIS
    Configures Windows Remote Desktop Services host policies for GPU rendering,
    hardware H.264/AVC encoding, and AVC 4:4:4 mode on AVD GPU session hosts.
.DESCRIPTION
    AVD defaults to CPU rendering and software encoding even on NV-series GPU VMs
    (avd-assess ref:avd-gpu-acceleration#cpu-by-default). This script sets the
    documented Terminal Services Policy registry values so sessions use the
    Azure-distributed GPU driver for rendering and hardware encoding.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$tsPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
if (-not (Test-Path -LiteralPath $tsPolicyPath)) {
    New-Item -Path $tsPolicyPath -Force | Out-Null
}

$settings = [ordered]@{
    # Use hardware graphics adapters for all Remote Desktop Services sessions
    bEnumerateHWBeforeSW       = 1
    # Configure H.264/AVC hardware encoding for Remote Desktop Connections
    AVCHardwareEncodePreferred = 1
    # Prioritize H.264/AVC 444 Graphics mode for Remote Desktop Connections
    AVC444ModePreferred        = 1
}

foreach ($name in $settings.Keys) {
    New-ItemProperty -LiteralPath $tsPolicyPath -Name $name -Value $settings[$name] -PropertyType DWord -Force | Out-Null
}

Write-Output 'Configured Terminal Services GPU rendering and AVC hardware encoding policies.'
