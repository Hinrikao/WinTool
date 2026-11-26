# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Check that Windows PowerShell 5.1 only hands off to PowerShell 7.
.DESCRIPTION
    Loads the source tree in Windows PowerShell 5.1 and confirms the GUI is
    not opened there. PowerShell 7 is located (or would be installed), and
    the child start info uses pwsh with no window.
#>
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "Skipping the bootstrap test: this test runs on Windows."
    exit 0
}

if ($PSVersionTable.PSVersion.Major -ge 7) {
    throw "The bootstrap test must run in Windows PowerShell 5.1, not PowerShell 7."
}

$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolApplyProfile = $null
$script:WinToolUnattended = $false
$script:WinToolShowConsole = $false
$script:WinToolEntryPath = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()

foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
}

Initialize-WinToolLocale -Language en -Force | Out-Null

if (Test-WinToolIsPowerShell7) {
    throw "Test-WinToolIsPowerShell7 should be false in Windows PowerShell 5.1."
}

$entry = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Entry.ps1"))
if ($entry.IndexOf("Invoke-WinToolPowerShell7Handoff") -lt 0 -or $entry.IndexOf("Invoke-WinToolPowerShell7Handoff") -gt $entry.IndexOf("Show-WinToolWindow")) {
    throw "Start-WinTool must hand off to PowerShell 7 before it opens the window."
}
if ($entry.Contains("Show-WinToolModernHostOffer")) {
    throw "The 5.1 bootstrap must not offer to continue on 5.1."
}

$pwsh = Get-WinToolPowerShell7Path
if ([string]::IsNullOrWhiteSpace($pwsh)) {
    Write-Output "PowerShell 7 is not installed on this runner; install helpers were still checked."
    $hostSource = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/LaunchHost.ps1"))
    if (-not $hostSource.Contains("Microsoft.PowerShell") -or -not $hostSource.Contains("Get-WinToolPowerShell7MsiUri")) {
        throw "The bootstrap should install Microsoft.PowerShell with winget and fall back to the official MSI."
    }
}
else {
    Write-Output ("Found PowerShell 7 at " + $pwsh)
    if ((Get-WinToolPreferredGuiHostPath) -ne $pwsh) {
        throw "The preferred GUI host should be the installed pwsh."
    }
    $start = New-WinToolGuiChildStartInfo -FileName $pwsh -Argument @("-STA", "-NoProfile", "-File", "C:\Temp\relaunch.ps1")
    if ($start.CreateNoWindow -ne $true -or $start.UseShellExecute -ne $false) {
        throw "The PowerShell 7 child must start with CreateNoWindow and without ShellExecute."
    }
    if ([string]$start.ArgumentText -like "*-WindowStyle Hidden*") {
        throw "The PowerShell 7 child must not use -WindowStyle Hidden."
    }
}

$helper = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/ElevatedHelper.ps1"))
if ($helper -notmatch "Get-WinToolPreferredGuiHostPath") {
    throw "The elevated helper must start with PowerShell 7."
}

Write-Output "Windows PowerShell 5.1 hands off to PowerShell 7 and does not open the GUI."
exit 0
