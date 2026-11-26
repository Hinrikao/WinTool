# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Run the same checks as GitHub Actions: analyzer, tests, and the launcher build.
#>
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if ($null -eq (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    Install-Module -Name PSScriptAnalyzer -MinimumVersion 1.21.0 -Scope CurrentUser -Force -AllowClobber
}
Import-Module PSScriptAnalyzer

$settings = Join-Path $root "tools/PSScriptAnalyzerSettings.psd1"
$targets = @(
    (Join-Path $root "src"),
    (Join-Path $root "build"),
    (Join-Path $root "tests")
)
$results = @()
foreach ($target in $targets) {
    $results += @(Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settings)
}
if ($results.Count -gt 0) {
    foreach ($result in $results) {
        Write-Output ("{0}:{1} {2} {3}" -f $result.ScriptName, $result.Line, $result.RuleName, $result.Message)
    }
    throw "PSScriptAnalyzer reported $($results.Count) issue(s)."
}
Write-Output "PSScriptAnalyzer reported no issues."

& (Join-Path $root "tests/Invoke-WinToolTests.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "WinTool tests failed."
}

& (Join-Path $root "build/Build-WinTool.ps1") -Check
Write-Output "CI checks passed."
