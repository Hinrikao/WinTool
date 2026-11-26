# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# Optional Windows features from data/features.json. State is read with
# Get-WindowsOptionalFeature in a background runspace; changes go through
# Dism.exe so each one shows its own progress in the log.

$script:WinToolDismRestartCode = 3010

function Get-WinToolFeatureCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Features")
}

function Get-WinToolFeatureStateScript {
    $scriptText = @'
param($Sync, $Names)
$ErrorActionPreference = "Stop"
try {
    if ($PSVersionTable.PSEdition -eq "Core") {
        try { Import-Module DISM -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop } catch { Import-Module DISM -ErrorAction SilentlyContinue }
    }
    else {
        Import-Module DISM -ErrorAction SilentlyContinue
    }
    $states = @{}
    foreach ($name in @($Names)) {
        try {
            $item = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
            if ($null -eq $item) {
                $states[$name] = "Missing"
            }
            else {
                $states[$name] = [string]$item.State
            }
        }
        catch {
            $states[$name] = "Missing"
        }
    }
    $Sync.States = $states
    $Sync.Ok = $true
}
catch {
    $Sync.Error = $_.Exception.Message
}
finally {
    $Sync.Done = $true
}
'@
    return $scriptText
}

function Get-WinToolFeatureStatus {
    param(
        [Parameter(Mandatory = $true)]$Feature,
        [hashtable]$State
    )
    # A feature counts as on only when every underlying name is enabled.
    $names = @($Feature.names)
    $enabled = 0
    $missing = 0
    foreach ($name in $names) {
        $value = ""
        if ($null -ne $State -and $State.ContainsKey([string]$name)) {
            $value = [string]$State[[string]$name]
        }
        if ($value -eq "Enabled" -or $value -eq "EnablePending") {
            $enabled++
        }
        elseif ($value -eq "Missing" -or [string]::IsNullOrWhiteSpace($value)) {
            $missing++
        }
    }
    if ($missing -gt 0) {
        return "Unavailable"
    }
    if ($enabled -eq $names.Count) {
        return "On"
    }
    if ($enabled -gt 0) {
        return "Partial"
    }
    return "Off"
}

function Get-WinToolFeaturePlan {
    param(
        $Enable,
        $Disable
    )
    $steps = New-Object System.Collections.Generic.List[object]
    $dism = Get-WinToolSystemFile -RelativePath "System32\Dism.exe"
    foreach ($feature in @($Enable)) {
        if ($null -eq $feature) { continue }
        foreach ($name in @($feature.names)) {
            $steps.Add([pscustomobject]@{
                Type = "process"
                Label = (Get-WinToolText "msg.turn-on-n-n" ([string]$feature.name) ([string]$name))
                FilePath = $dism
                Arguments = @("/Online", "/Enable-Feature", ("/FeatureName:" + [string]$name), "/All", "/NoRestart")
                SuccessCodes = @(0, $script:WinToolDismRestartCode)
            })
        }
    }
    foreach ($feature in @($Disable)) {
        if ($null -eq $feature) { continue }
        $names = @($feature.names)
        # Turn off the parent last, so dependent parts go first.
        [array]::Reverse($names)
        foreach ($name in $names) {
            $steps.Add([pscustomobject]@{
                Type = "process"
                Label = (Get-WinToolText "msg.turn-off-n-n" ([string]$feature.name) ([string]$name))
                FilePath = $dism
                Arguments = @("/Online", "/Disable-Feature", ("/FeatureName:" + [string]$name), "/NoRestart")
                SuccessCodes = @(0, $script:WinToolDismRestartCode)
            })
        }
    }
    return $steps.ToArray()
}

function Test-WinToolFeatureCatalog {
    param(
        $Catalog,
        $Errors
    )
    if ([int](Get-WinToolNote -Object $Catalog -Name "schemaVersion" -Default 0) -ne 1) {
        $Errors.Add("features.json schemaVersion must be 1.")
    }
    $ids = @{}
    foreach ($feature in @(Get-WinToolNote -Object $Catalog -Name "features" -Default @())) {
        $id = [string](Get-WinToolNote -Object $feature -Name "id" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) {
            $Errors.Add("A Windows feature is missing an id or uses one twice: '$id'.")
        }
        $ids[$id] = $true
        if ([string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $feature -Name "name" -Default "")) -or [string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $feature -Name "description" -Default ""))) {
            $Errors.Add("Windows feature '$id' needs a name and description.")
        }
        $names = @(Get-WinToolNote -Object $feature -Name "names" -Default @())
        if ($names.Count -eq 0) {
            $Errors.Add("Windows feature '$id' has no DISM feature names.")
        }
        foreach ($name in $names) {
            if ([string]$name -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
                $Errors.Add("Windows feature '$id' has an invalid DISM name '$name'.")
            }
        }
    }
    if ($ids.Count -lt 8) {
        $Errors.Add("features.json should list the common optional features.")
    }
}
