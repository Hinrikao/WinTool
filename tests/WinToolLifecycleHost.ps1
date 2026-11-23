# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Child process for Test-WinToolLifecycle.ps1.
.DESCRIPTION
    Opens the real WinTool window the way the hidden relaunch does, writes a
    marker once the window is on screen, and closes it after a few seconds.
    The process must then end by itself.
#>
param(
    [Parameter(Mandatory = $true)][string]$Marker,
    [int]$CloseAfterSeconds = 8
)
$ErrorActionPreference = "Stop"
$env:WINTOOL_HIDDEN = "1"

$script:WinToolApplyProfile = $null
$script:WinToolUnattended = $false
$script:WinToolShowConsole = $false
$script:WinToolEntryPath = $null
$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()
foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        continue
    }
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
}

Add-Type -AssemblyName PresentationFramework
$script:LifecycleStart = [DateTime]::UtcNow
$script:LifecycleMarker = $Marker
$script:LifecycleClose = $CloseAfterSeconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.add_Tick({
        $window = $script:WinToolWindow
        if ($null -eq $window -or -not $window.IsVisible) { return }
        if (-not (Test-Path -LiteralPath $script:LifecycleMarker)) {
            Set-Content -LiteralPath $script:LifecycleMarker -Value ([string]$PID)
        }
        if (([DateTime]::UtcNow - $script:LifecycleStart).TotalSeconds -ge $script:LifecycleClose) {
            $window.Close()
        }
    })
$timer.Start()
Show-WinToolWindow
# Show-WinToolWindow ends a hidden relaunch with Environment.Exit(0), so this
# line only runs if that did not happen.
exit 3
