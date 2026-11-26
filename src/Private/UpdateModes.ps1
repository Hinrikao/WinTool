# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# Windows Update modes from data/updates.json. A mode is a set of policy
# values under HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate plus a
# startup type for the update services. Applying a mode first clears every
# policy value any mode knows about, so switching modes never stacks, and
# "Default" is the revert.

$script:WinToolUpdatePolicyRoot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
$script:WinToolServiceStartTypes = @("Manual", "Automatic", "AutomaticDelayed", "Disabled")

function Get-WinToolUpdateMode {
    param(
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    return @(Get-WinToolNote -Object $Catalog -Name "modes" -Default @())
}

function Find-WinToolUpdateMode {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    foreach ($mode in (Get-WinToolUpdateMode -Catalog $Catalog)) {
        if ([string]$mode.id -eq $Id) {
            return $mode
        }
    }
    return $null
}

function Get-WinToolUpdatePolicyKey {
    param(
        [Parameter(Mandatory = $true)]$Policy
    )
    return ([string]$Policy.path + "|" + [string]$Policy.name).ToLowerInvariant()
}

function Get-WinToolManagedUpdatePolicy {
    param(
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    # Every policy value any mode sets, once each.
    $seen = @{}
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($mode in (Get-WinToolUpdateMode -Catalog $Catalog)) {
        foreach ($policy in @(Get-WinToolNote -Object $mode -Name "policies" -Default @())) {
            $key = Get-WinToolUpdatePolicyKey -Policy $policy
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $list.Add([pscustomobject]@{ path = [string]$policy.path; name = [string]$policy.name })
            }
        }
    }
    return $list.ToArray()
}

function Get-WinToolUpdateModeChange {
    param(
        [Parameter(Mandatory = $true)][string]$ModeId,
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    $mode = Find-WinToolUpdateMode -Id $ModeId -Catalog $Catalog
    if ($null -eq $mode) {
        throw (Get-WinToolText "msg.unknown-update-mode-n" $ModeId)
    }
    $set = New-Object System.Collections.Generic.List[object]
    foreach ($policy in @(Get-WinToolNote -Object $mode -Name "policies" -Default @())) {
        $set.Add([pscustomobject]@{ path = [string]$policy.path; name = [string]$policy.name; value = [int]$policy.value })
    }
    $services = New-Object System.Collections.Generic.List[object]
    foreach ($service in @(Get-WinToolNote -Object $mode -Name "services" -Default @())) {
        $services.Add([pscustomobject]@{
            name = [string]$service.name
            startupType = [string]$service.startupType
            stop = [bool](Get-WinToolNote -Object $service -Name "stop" -Default $false)
        })
    }
    return [pscustomobject]@{
        Mode = [string]$mode.id
        Name = [string]$mode.name
        Remove = @(Get-WinToolManagedUpdatePolicy -Catalog $Catalog)
        Set = $set.ToArray()
        Services = $services.ToArray()
    }
}

function Get-WinToolUpdateModeScript {
    param(
        [Parameter(Mandatory = $true)][string]$ModeId,
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    $change = Get-WinToolUpdateModeChange -ModeId $ModeId -Catalog $Catalog
    $json = ConvertTo-Json -InputObject $change -Depth 6 -Compress
    $body = @'
$ErrorActionPreference = "Stop"
$change = ConvertFrom-Json -InputObject '__CHANGE__'
$failed = 0
foreach ($item in @($change.Remove)) {
    if ((Test-Path -LiteralPath $item.path) -and ($null -ne (Get-ItemProperty -LiteralPath $item.path -Name $item.name -ErrorAction SilentlyContinue))) {
        Remove-ItemProperty -LiteralPath $item.path -Name $item.name
        Write-Output ("Removed policy " + $item.name)
    }
}
foreach ($item in @($change.Set)) {
    if (-not (Test-Path -LiteralPath $item.path)) {
        New-Item -Path $item.path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $item.path -Name $item.name -Value ([int]$item.value) -PropertyType DWord -Force | Out-Null
    Write-Output ("Set policy {0} = {1}" -f $item.name, $item.value)
}
$startNames = @{ Manual = "demand"; Automatic = "auto"; AutomaticDelayed = "delayed-auto"; Disabled = "disabled" }
foreach ($service in @($change.Services)) {
    if ($null -eq (Get-Service -Name $service.name -ErrorAction SilentlyContinue)) {
        Write-Output ("Service {0} is not on this PC." -f $service.name)
        continue
    }
    if ($service.stop) {
        try {
            Stop-Service -Name $service.name -Force -ErrorAction Stop
            Write-Output ("Stopped " + $service.name)
        }
        catch {
            Write-Output ("Could not stop {0}: {1}" -f $service.name, $_.Exception.Message)
        }
    }
    $output = & sc.exe config $service.name start= $startNames[[string]$service.startupType] 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Output ("{0} startup is now {1}" -f $service.name, $service.startupType)
    }
    else {
        $failed++
        Write-Output ("Could not change {0}: {1}" -f $service.name, (($output | Out-String).Trim()))
    }
}
Write-Output ("Update mode is now: " + $change.Name)
if ($failed -gt 0) {
    exit 2
}
'@
    return $body.Replace("__CHANGE__", $json.Replace("'", "''"))
}

function Get-WinToolUpdateModePlan {
    param(
        [Parameter(Mandatory = $true)][string]$ModeId,
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    $mode = Find-WinToolUpdateMode -Id $ModeId -Catalog $Catalog
    if ($null -eq $mode) {
        throw (Get-WinToolText "msg.unknown-update-mode-n" $ModeId)
    }
    return @([pscustomobject]@{
        Type = "inline-script"
        Label = "Set Windows Update to: " + [string]$mode.name
        Name = "update-mode"
        Text = (Get-WinToolUpdateModeScript -ModeId $ModeId -Catalog $Catalog)
    })
}

function Get-WinToolUpdateModeSnapshot {
    param(
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    $values = @{}
    foreach ($policy in (Get-WinToolManagedUpdatePolicy -Catalog $Catalog)) {
        $item = Get-ItemProperty -LiteralPath $policy.path -Name $policy.name -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            $values[(Get-WinToolUpdatePolicyKey -Policy $policy)] = [int]$item.($policy.name)
        }
    }
    $services = @{}
    foreach ($name in @("wuauserv", "UsoSvc")) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $service) {
            $services[$name] = [string]$service.StartType
        }
    }
    return [pscustomobject]@{ Values = $values; Services = $services }
}

function Resolve-WinToolUpdateMode {
    param(
        [hashtable]$Values = @{},
        [hashtable]$Services = @{},
        $Catalog = (Get-WinToolUpdateCatalog)
    )
    # The current mode is the one whose policies are all in place and whose
    # disabled services really are disabled. Leftover values from another
    # tool show as "custom" so nothing gets mislabeled as Default.
    foreach ($mode in (Get-WinToolUpdateMode -Catalog $Catalog)) {
        $policies = @(Get-WinToolNote -Object $mode -Name "policies" -Default @())
        if ($policies.Count -eq 0) {
            continue
        }
        $match = $true
        foreach ($policy in $policies) {
            $key = Get-WinToolUpdatePolicyKey -Policy $policy
            if (-not $Values.ContainsKey($key) -or [int]$Values[$key] -ne [int]$policy.value) {
                $match = $false
            }
        }
        if ($match -and $Values.Count -eq $policies.Count) {
            return [string]$mode.id
        }
    }
    foreach ($name in @($Services.Keys)) {
        if ([string]$Services[$name] -eq "Disabled") {
            return "custom"
        }
    }
    if ($Values.Count -gt 0) {
        return "custom"
    }
    return "default"
}

function Test-WinToolUpdateModeCatalog {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        $Errors
    )
    $modes = @(Get-WinToolUpdateMode -Catalog $Catalog)
    $ids = @{}
    foreach ($mode in $modes) {
        $id = [string](Get-WinToolNote -Object $mode -Name "id" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) {
            $Errors.Add("An update mode has a missing or repeated id '$id'.")
            continue
        }
        $ids[$id] = $true
        foreach ($field in @("name", "description")) {
            if ([string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $mode -Name $field -Default ""))) {
                $Errors.Add("Update mode '$id' needs a $field.")
            }
        }
        foreach ($policy in @(Get-WinToolNote -Object $mode -Name "policies" -Default @())) {
            if (-not ([string]$policy.path).StartsWith($script:WinToolUpdatePolicyRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $Errors.Add("Update mode '$id' writes outside the Windows Update policy key.")
            }
            if ([string]$policy.name -notmatch '^[A-Za-z]+$') {
                $Errors.Add("Update mode '$id' has an invalid policy name '$([string]$policy.name)'.")
            }
        }
        foreach ($service in @(Get-WinToolNote -Object $mode -Name "services" -Default @())) {
            if ($script:WinToolServiceStartTypes -notcontains [string]$service.startupType) {
                $Errors.Add("Update mode '$id' has an unknown startup type for $([string]$service.name).")
            }
            if ([string]$service.name -notmatch '^[A-Za-z]+$') {
                $Errors.Add("Update mode '$id' has an invalid service name.")
            }
        }
    }
    $default = Find-WinToolUpdateMode -Id "default" -Catalog $Catalog
    if ($null -eq $default) {
        $Errors.Add("updates.json needs a 'default' mode to revert to.")
    }
    elseif (@(Get-WinToolNote -Object $default -Name "policies" -Default @()).Count -ne 0) {
        $Errors.Add("The default update mode must not set policies.")
    }
}
