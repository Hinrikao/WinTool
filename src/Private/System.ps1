# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# DNS servers per network adapter and the Ultimate Performance power plan,
# both from data/system.json. Changes run as Windows PowerShell scripts through
# the plan runner so they are logged and never block the window.

function Get-WinToolSystemCatalog {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "System"))
}

function Get-WinToolDnsProvider {
    param(
        $Catalog = (Get-WinToolSystemCatalog)
    )
    return @(Get-WinToolNote -Object $Catalog -Name "dns" -Default @())
}

function Find-WinToolDnsProvider {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Catalog = (Get-WinToolSystemCatalog)
    )
    foreach ($provider in (Get-WinToolDnsProvider -Catalog $Catalog)) {
        if ([string]$provider.id -eq $Id) {
            return $provider
        }
    }
    return $null
}

function Get-WinToolDnsServerList {
    param(
        [Parameter(Mandatory = $true)]$Provider,
        [bool]$IncludeIpv6 = $true
    )
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($address in @(Get-WinToolNote -Object $Provider -Name "ipv4" -Default @())) {
        $list.Add([string]$address)
    }
    if ($IncludeIpv6) {
        foreach ($address in @(Get-WinToolNote -Object $Provider -Name "ipv6" -Default @())) {
            $list.Add([string]$address)
        }
    }
    return $list.ToArray()
}

function Resolve-WinToolDnsProvider {
    param(
        [string[]]$Server = @(),
        $Catalog = (Get-WinToolSystemCatalog)
    )
    # Name the provider when every IPv4 server an adapter uses belongs to it.
    $ipv4 = @($Server | Where-Object { [string]$_ -match '^\d+\.\d+\.\d+\.\d+$' })
    if ($ipv4.Count -eq 0) {
        return $null
    }
    foreach ($provider in (Get-WinToolDnsProvider -Catalog $Catalog)) {
        $known = @(Get-WinToolNote -Object $provider -Name "ipv4" -Default @())
        if ($known.Count -eq 0) {
            continue
        }
        $all = $true
        foreach ($address in $ipv4) {
            if ($known -notcontains [string]$address) {
                $all = $false
            }
        }
        if ($all) {
            return $provider
        }
    }
    return $null
}

function Get-WinToolDnsAdapter {
    if (-not (Test-WinToolWindows)) {
        return @()
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { [string]$_.Status -eq "Up" } | Sort-Object -Property Name)) {
        $servers = New-Object System.Collections.Generic.List[string]
        foreach ($entry in @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue)) {
            foreach ($address in @($entry.ServerAddresses)) {
                $servers.Add([string]$address)
            }
        }
        $list.Add([pscustomobject]@{
            Index = [int]$adapter.ifIndex
            Name = [string]$adapter.Name
            Description = [string]$adapter.InterfaceDescription
            Servers = $servers.ToArray()
        })
    }
    return $list.ToArray()
}

function Format-WinToolDnsSummary {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        $Catalog = (Get-WinToolSystemCatalog)
    )
    $servers = @($Adapter.Servers)
    if ($servers.Count -eq 0) {
        return ("{0}: no DNS servers reported" -f [string]$Adapter.Name)
    }
    $text = "{0}: {1}" -f [string]$Adapter.Name, ($servers -join ", ")
    $provider = Resolve-WinToolDnsProvider -Server $servers -Catalog $Catalog
    if ($null -ne $provider) {
        $text += "  (" + [string]$provider.name + ")"
    }
    return $text
}

function ConvertTo-WinToolSingleQuoted {
    param(
        [AllowEmptyString()][string]$Text
    )
    return "'" + $Text.Replace("'", "''") + "'"
}

function Get-WinToolDnsScript {
    param(
        [Parameter(Mandatory = $true)][int[]]$InterfaceIndex,
        [Parameter(Mandatory = $true)]$Provider,
        [bool]$IncludeIpv6 = $true
    )
    $servers = @(Get-WinToolDnsServerList -Provider $Provider -IncludeIpv6 $IncludeIpv6)
    foreach ($address in $servers) {
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$address, [ref]$parsed)) {
            throw "DNS provider '$([string]$Provider.id)' has an invalid address '$address'."
        }
    }
    $indexText = (@($InterfaceIndex | ForEach-Object { [string][int]$_ })) -join ", "
    $serverText = (@($servers | ForEach-Object { ConvertTo-WinToolSingleQuoted -Text ([string]$_) })) -join ", "
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$ErrorActionPreference = "Stop"')
    $lines.Add('$failed = 0')
    $lines.Add('$servers = @(' + $serverText + ')')
    $lines.Add('foreach ($index in @(' + $indexText + ')) {')
    $lines.Add('    $name = [string](Get-NetAdapter -InterfaceIndex $index).Name')
    $lines.Add('    try {')
    $lines.Add('        if ($servers.Count -eq 0) {')
    $lines.Add('            Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses')
    $lines.Add('            Write-Output ($name + ": DNS is automatic again")')
    $lines.Add('        }')
    $lines.Add('        else {')
    $lines.Add('            Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $servers')
    $lines.Add('            Write-Output ($name + ": DNS set to " + ($servers -join ", "))')
    $lines.Add('        }')
    $lines.Add('    }')
    $lines.Add('    catch {')
    $lines.Add('        $failed++')
    $lines.Add('        Write-Output ($name + ": " + $_.Exception.Message)')
    $lines.Add('    }')
    $lines.Add('}')
    $lines.Add('Clear-DnsClientCache')
    $lines.Add('if ($failed -gt 0) { exit 2 }')
    return ($lines -join [Environment]::NewLine)
}

function Get-WinToolDnsPlan {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)]$Provider,
        [bool]$IncludeIpv6 = $true
    )
    $adapters = @($Adapter)
    if ($adapters.Count -eq 0) {
        throw "Pick a network adapter first."
    }
    $names = (@($adapters | ForEach-Object { [string]$_.Name })) -join ", "
    return @([pscustomobject]@{
        Type = "inline-script"
        Label = ("Set DNS to {0} on {1}" -f [string]$Provider.name, $names)
        Name = "dns"
        Text = (Get-WinToolDnsScript -InterfaceIndex @($adapters | ForEach-Object { [int]$_.Index }) -Provider $Provider -IncludeIpv6 $IncludeIpv6)
    })
}

function Get-WinToolSystemProbeScript {
    # Runs off the UI thread. Returns adapter rows and powercfg text as strings.
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Continue"
try {
    $records = New-Object System.Collections.Generic.List[string]
    $unit = [string][char]31
    $record = [string][char]30
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { [string]$_.Status -eq "Up" } | Sort-Object -Property Name)
    foreach ($adapter in $adapters) {
        $servers = New-Object System.Collections.Generic.List[string]
        foreach ($entry in @(Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue)) {
            foreach ($address in @($entry.ServerAddresses)) {
                $text = [string]$address
                if (-not [string]::IsNullOrWhiteSpace($text)) { $servers.Add($text) }
            }
        }
        $name = ([string]$adapter.Name).Replace($unit, " ").Replace($record, " ").Replace("`r", " ").Replace("`n", " ")
        $description = ([string]$adapter.InterfaceDescription).Replace($unit, " ").Replace($record, " ").Replace("`r", " ").Replace("`n", " ")
        $records.Add(([string][int]$adapter.ifIndex) + $unit + $name + $unit + $description + $unit + (($servers.ToArray()) -join ","))
    }
    $Sync.Adapters = ($records.ToArray() -join $record)
    try {
        $Sync.Power = [string]((& powercfg.exe /list) | Out-String)
        $Sync.PowerError = ""
    }
    catch {
        $Sync.Power = ""
        $Sync.PowerError = $_.Exception.Message
    }
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
finally {
    $Sync.Done = $true
}
'@
    return $scriptText
}

function ConvertFrom-WinToolSystemProbe {
    param([AllowEmptyString()][string]$Text)
    $list = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }
    $record = [string][char]30
    foreach ($line in @($Text -split [regex]::Escape($record))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $part = @($line.Split([char]31))
        $index = 0
        [void][int]::TryParse([string]$part[0], [ref]$index)
        $name = ""
        $description = ""
        $servers = @()
        if ($part.Length -ge 2) { $name = [string]$part[1] }
        if ($part.Length -ge 3) { $description = [string]$part[2] }
        if ($part.Length -ge 4 -and -not [string]::IsNullOrWhiteSpace([string]$part[3])) {
            $servers = @([string]$part[3] -split ",")
        }
        $list.Add([pscustomobject]@{
            Index = $index
            Name = $name
            Description = $description
            Servers = $servers
        })
    }
    return $list.ToArray()
}

function ConvertFrom-WinToolPowerList {
    param(
        [string]$Text
    )
    # powercfg /list is translated, so read only the GUID, the name in
    # parentheses, and the trailing * that marks the active plan.
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in @($Text -split "`r?`n")) {
        $match = [regex]::Match($line, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\((.*)\)\s*(\*?)\s*$')
        if ($match.Success) {
            $list.Add([pscustomobject]@{
                Guid = $match.Groups[1].Value.ToLowerInvariant()
                Name = $match.Groups[2].Value
                Active = ($match.Groups[3].Value -eq "*")
            })
        }
    }
    return $list.ToArray()
}

function Get-WinToolPowerPlanState {
    param(
        $Scheme = @(),
        $Catalog = (Get-WinToolSystemCatalog)
    )
    $plan = Get-WinToolNote -Object $Catalog -Name "powerPlan"
    $copy = ([string]$plan.copyGuid).ToLowerInvariant()
    $base = ([string]$plan.baseGuid).ToLowerInvariant()
    $state = [pscustomobject]@{ Added = $false; BuiltIn = $false; Active = $false }
    foreach ($item in @($Scheme)) {
        if ([string]$item.Guid -eq $copy) {
            $state.Added = $true
            if ($item.Active) { $state.Active = $true }
        }
        if ([string]$item.Guid -eq $base) {
            $state.BuiltIn = $true
            if ($item.Active) { $state.Active = $true }
        }
    }
    return $state
}

function Format-WinToolPowerPlanStatus {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$Name = "Ultimate Performance"
    )
    if ($State.Added) {
        if ($State.Active) { return "$Name is added and active." }
        return "$Name is added but another plan is active."
    }
    if ($State.BuiltIn) {
        if ($State.Active) { return "$Name is built into this Windows and active." }
        return "$Name is built into this Windows. Adding it switches to it."
    }
    return "$Name is not on this PC."
}

function Get-WinToolPowerPlanScript {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("add", "remove")][string]$Action,
        $Catalog = (Get-WinToolSystemCatalog)
    )
    $plan = Get-WinToolNote -Object $Catalog -Name "powerPlan"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$base = ' + (ConvertTo-WinToolSingleQuoted -Text ([string]$plan.baseGuid)))
    $lines.Add('$copy = ' + (ConvertTo-WinToolSingleQuoted -Text ([string]$plan.copyGuid)))
    $lines.Add('$fallback = ' + (ConvertTo-WinToolSingleQuoted -Text ([string]$plan.fallbackGuid)))
    $lines.Add('$list = (& powercfg.exe /list | Out-String)')
    if ($Action -eq "add") {
        $lines.Add('if ($list -match $copy) {')
        $lines.Add('    $target = $copy')
        $lines.Add('}')
        $lines.Add('elseif ($list -match $base) {')
        $lines.Add('    $target = $base')
        $lines.Add('}')
        $lines.Add('else {')
        $lines.Add('    & powercfg.exe -duplicatescheme $base $copy')
        $lines.Add('    if ($LASTEXITCODE -ne 0) {')
        $lines.Add('        Write-Output "Windows did not allow the Ultimate Performance plan on this PC. Some laptops with Modern Standby block it."')
        $lines.Add('        exit 2')
        $lines.Add('    }')
        $lines.Add('    $target = $copy')
        $lines.Add('    Write-Output "Added the Ultimate Performance plan."')
        $lines.Add('}')
        $lines.Add('& powercfg.exe -setactive $target')
        $lines.Add('if ($LASTEXITCODE -ne 0) { exit 2 }')
        $lines.Add('Write-Output "Ultimate Performance is now the active plan."')
    }
    else {
        $lines.Add('if ($list -notmatch $copy) {')
        $lines.Add('    Write-Output "WinTool did not add an Ultimate Performance plan, so there is nothing to remove."')
        $lines.Add('    if ($list -match $base) { Write-Output "The built-in copy stays. Pick another plan in Control Panel if you want to stop using it." }')
        $lines.Add('    exit 0')
        $lines.Add('}')
        $lines.Add('$active = (& powercfg.exe /getactivescheme | Out-String)')
        $lines.Add('if ($active -match $copy) {')
        $lines.Add('    & powercfg.exe -setactive $fallback')
        $lines.Add('    Write-Output "Switched back to the Balanced plan."')
        $lines.Add('}')
        $lines.Add('& powercfg.exe -delete $copy')
        $lines.Add('if ($LASTEXITCODE -ne 0) { exit 2 }')
        $lines.Add('Write-Output "Removed the Ultimate Performance plan."')
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-WinToolPowerPlanPlan {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("add", "remove")][string]$Action,
        $Catalog = (Get-WinToolSystemCatalog)
    )
    $label = "Add the Ultimate Performance power plan"
    if ($Action -eq "remove") {
        $label = "Remove the Ultimate Performance power plan"
    }
    return @([pscustomobject]@{
        Type = "inline-script"
        Label = $label
        Name = "power-plan"
        Text = (Get-WinToolPowerPlanScript -Action $Action -Catalog $Catalog)
    })
}

function Test-WinToolSystemCatalog {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        $Errors
    )
    if ([int](Get-WinToolNote -Object $Catalog -Name "schemaVersion" -Default 0) -ne 1) {
        $Errors.Add("system.json schemaVersion must be 1.")
    }
    $ids = @{}
    foreach ($provider in (Get-WinToolDnsProvider -Catalog $Catalog)) {
        $id = [string](Get-WinToolNote -Object $provider -Name "id" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) {
            $Errors.Add("A DNS provider has a missing or repeated id '$id'.")
            continue
        }
        $ids[$id] = $true
        foreach ($family in @("ipv4", "ipv6")) {
            $expected = [System.Net.Sockets.AddressFamily]::InterNetwork
            if ($family -eq "ipv6") {
                $expected = [System.Net.Sockets.AddressFamily]::InterNetworkV6
            }
            foreach ($address in @(Get-WinToolNote -Object $provider -Name $family -Default @())) {
                $parsed = $null
                if (-not [System.Net.IPAddress]::TryParse([string]$address, [ref]$parsed) -or $parsed.AddressFamily -ne $expected) {
                    $Errors.Add("DNS provider '$id' has an invalid $family address '$address'.")
                }
            }
        }
    }
    if (-not $ids.ContainsKey("dhcp")) {
        $Errors.Add("system.json needs a 'dhcp' DNS choice to go back to automatic.")
    }
    $plan = Get-WinToolNote -Object $Catalog -Name "powerPlan"
    foreach ($field in @("baseGuid", "copyGuid", "fallbackGuid")) {
        $value = [string](Get-WinToolNote -Object $plan -Name $field -Default "")
        if ($value -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $Errors.Add("powerPlan.$field must be a lowercase GUID.")
        }
    }
}
