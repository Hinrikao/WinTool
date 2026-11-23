# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1
<#
Runs only the WSL shell part of terminal setup, without the window:
zsh, the prompt, ~/.zshrc, the default shell, and the distro's Terminal font.

    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-WinToolWslSetup.ps1 -Distro Ubuntu

The distro must already exist unless -Install is passed.
#>
param(
    [string]$Distro = "Ubuntu",
    [string]$PromptId = "oh-my-posh",
    [string]$PromptStyle = "jandedobbeleer",
    [string]$FontId = "cascadiacode-nf",
    [switch]$Install
)

$ErrorActionPreference = "Stop"
$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()
foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#") -or -not $trimmed.StartsWith("src/Private/")) {
        continue
    }
    . (Join-Path $script:WinToolRoot $trimmed)
}

Invoke-WinToolWslShellSetup -Distro $Distro -PromptId $PromptId -PromptStyle $PromptStyle -FontId $FontId -Install:$Install
