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
    [int]$CloseAfterSeconds = 8,
    [string]$Log = "",
    [switch]$OwnedHost,
    [switch]$CloseAfterShown
)
$ErrorActionPreference = "Stop"
# -OwnedHost is the hidden relaunch (WINTOOL_HIDDEN=1). Without it, this is
# powershell -WindowStyle Hidden -File, the launch that flashed a taskbar button.
if ($OwnedHost) {
    $env:WINTOOL_HIDDEN = "1"
}
$script:LifecycleLog = $Log
trap {
    if (-not [string]::IsNullOrWhiteSpace($script:LifecycleLog)) {
        try { [System.IO.File]::WriteAllText($script:LifecycleLog, ($_ | Out-String)) } catch { $null = $_.Exception.Message }
    }
    exit 1
}

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
$script:LifecycleAfterShown = [bool]$CloseAfterShown
$script:LifecycleShown = $null
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.add_Tick({
        $window = $script:WinToolWindow
        if ($null -eq $window -or -not $window.IsVisible) { return }
        if (-not (Test-Path -LiteralPath $script:LifecycleMarker)) {
            [System.IO.File]::WriteAllText($script:LifecycleMarker, [string]$PID)
            $script:LifecycleShown = [DateTime]::UtcNow
        }
        $started = $script:LifecycleStart
        if ($script:LifecycleAfterShown) {
            $started = $script:LifecycleShown
            if ($null -eq $started) { return }
        }
        if (([DateTime]::UtcNow - $started).TotalSeconds -ge $script:LifecycleClose) {
            $window.Close()
        }
    })
$timer.Start()
Show-WinToolWindow
# A hidden launch ends in Environment.Exit before this line. Reaching it means
# the process kept running after the window closed.
if ($env:WINTOOL_HIDDEN -eq "1") {
    exit 3
}
exit 0
