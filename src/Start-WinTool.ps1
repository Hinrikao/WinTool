# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Run WinTool from the source tree on Windows.
.DESCRIPTION
    Loads the modules under src/ and data/ without building wintool.ps1.
    Use this while editing. The published one-liner runs the built wintool.ps1.
#>
param(
    [string]$ApplyProfile,
    [switch]$Unattended
)

$script:WinToolApplyProfile = $ApplyProfile
$script:WinToolUnattended = [bool]$Unattended
$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$versionPath = Join-Path $script:WinToolRoot "build/version.txt"
$script:WinToolVersion = ([System.IO.File]::ReadAllText($versionPath)).Trim()

$listPath = Join-Path $script:WinToolRoot "build/files.txt"
foreach ($relative in [System.IO.File]::ReadAllLines($listPath)) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        continue
    }
    $path = Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/')
    . $path
}

Start-WinTool
