# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function ConvertTo-WinToolProfile {
    param(
        [string[]]$AppId,
        [string[]]$TweakId,
        $Terminal,
        [string]$Name = "My WinTool profile"
    )
    if ($null -eq $AppId) {
        $AppId = @()
    }
    if ($null -eq $TweakId) {
        $TweakId = @()
    }
    $stamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    return [pscustomobject]@{
        schemaVersion = 1
        name = $Name
        exportedBy = "WinTool " + $script:WinToolVersion
        exportedAt = $stamp
        apps = @($AppId)
        tweaks = @($TweakId)
        terminal = $Terminal
    }
}

function Read-WinToolProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Profile not found: $Path"
    }
    $toolProfile = Read-WinToolJsonFile -Path $Path
    $version = 0
    $versionProperty = $toolProfile.PSObject.Properties["schemaVersion"]
    if ($null -ne $versionProperty -and $null -ne $versionProperty.Value) {
        $version = [int]$versionProperty.Value
    }
    if ($version -ne 1) {
        throw "This file is not a WinTool profile (schema version 1)."
    }
    return $toolProfile
}

function Write-WinToolProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Profile
    )
    Write-WinToolJsonFile -Path $Path -Value $Profile
}

function Resolve-WinToolProfileSelection {
    param(
        [Parameter(Mandatory = $true)]$Profile
    )
    $apps = Get-WinToolAppCatalog
    $tweaks = Get-WinToolTweakCatalog
    $knownApps = @{}
    foreach ($category in @(Get-WinToolNote -Object $apps -Name "categories" -Default @())) {
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $knownApps[[string]$app.id] = $app
        }
    }
    $knownTweaks = @{}
    foreach ($tweak in @(Get-WinToolNote -Object $tweaks -Name "tweaks" -Default @())) {
        $knownTweaks[[string]$tweak.id] = $tweak
    }

    $selectedApps = New-Object System.Collections.Generic.List[object]
    $unknownApps = New-Object System.Collections.Generic.List[string]
    foreach ($id in @(Get-WinToolNote -Object $Profile -Name "apps" -Default @())) {
        $key = [string]$id
        if ($knownApps.ContainsKey($key)) {
            $selectedApps.Add($knownApps[$key])
        }
        elseif (-not [string]::IsNullOrWhiteSpace($key)) {
            $unknownApps.Add($key)
        }
    }

    $selectedTweaks = New-Object System.Collections.Generic.List[object]
    $unknownTweaks = New-Object System.Collections.Generic.List[string]
    foreach ($id in @(Get-WinToolNote -Object $Profile -Name "tweaks" -Default @())) {
        $key = [string]$id
        if ($knownTweaks.ContainsKey($key)) {
            $selectedTweaks.Add($knownTweaks[$key])
        }
        elseif (-not [string]::IsNullOrWhiteSpace($key)) {
            $unknownTweaks.Add($key)
        }
    }

    return [pscustomobject]@{
        AppRecords = $selectedApps.ToArray()
        TweakRecords = $selectedTweaks.ToArray()
        UnknownApps = $unknownApps.ToArray()
        UnknownTweaks = $unknownTweaks.ToArray()
    }
}
