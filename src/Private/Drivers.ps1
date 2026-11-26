# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolDriverCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Drivers")
}

function ConvertTo-WinToolHardwareId {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    return $Text.Trim().ToUpperInvariant()
}

function ConvertTo-WinToolHardwareIdList {
    param($Value)
    $list = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        $nested = $false
        if ($item -is [System.Array]) { $nested = $true }
        elseif (($item -is [System.Collections.IEnumerable]) -and ($item -isnot [string])) { $nested = $true }
        if ($nested) {
            foreach ($inner in @($item)) {
                $key = ConvertTo-WinToolHardwareId -Text ([string]$inner)
                if (-not [string]::IsNullOrWhiteSpace($key) -and -not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    $list.Add($key) | Out-Null
                }
            }
            continue
        }
        $key = ConvertTo-WinToolHardwareId -Text ([string]$item)
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $list.Add($key) | Out-Null
        }
    }
    return $list.ToArray()
}

function Test-WinToolHardwareIdMatch {
    param(
        [string[]]$DeviceId,
        [string[]]$UpdateId
    )
    foreach ($update in @($UpdateId)) {
        $want = ConvertTo-WinToolHardwareId -Text $update
        if ([string]::IsNullOrWhiteSpace($want)) { continue }
        foreach ($device in @($DeviceId)) {
            $have = ConvertTo-WinToolHardwareId -Text $device
            if ([string]::IsNullOrWhiteSpace($have)) { continue }
            if ($have -eq $want) { return $true }
            # A Windows Update hardware ID is often a shorter, more general
            # form of the device's ID (no SUBSYS or REV suffix).
            if ($have.StartsWith($want)) { return $true }
        }
    }
    return $false
}

function ConvertTo-WinToolDriverDate {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    if ($Value -is [datetime]) {
        return [datetime]$Value
    }
    $text = [string]$Value
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($text, [ref]$parsed)) {
        return $parsed
    }
    if ($text -match '^\d{14}') {
        try {
            return [System.Management.ManagementDateTimeConverter]::ToDateTime($text)
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    return $null
}

function ConvertTo-WinToolDriverVersion {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $trimmed = $Text.Trim()
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($piece in @($trimmed.Split("."))) {
        if ($piece -match '^[0-9]+$') { $parts.Add($piece) | Out-Null }
        else { break }
    }
    if ($parts.Count -lt 2) { return $null }
    while ($parts.Count -lt 2) { $parts.Add("0") | Out-Null }
    try { return [version]($parts.ToArray() -join ".") }
    catch { return $null }
}

function Compare-WinToolDriverVersion {
    param(
        [string]$Left,
        [string]$Right
    )
    $a = ConvertTo-WinToolDriverVersion -Text $Left
    $b = ConvertTo-WinToolDriverVersion -Text $Right
    if ($null -eq $a -or $null -eq $b) { return $null }
    return $a.CompareTo($b)
}

function Test-WinToolDriverNewer {
    param(
        $Update,
        $Device
    )
    $updateVersion = [string](Get-WinToolNote -Object $Update -Name "Version" -Default "")
    $deviceVersion = [string](Get-WinToolNote -Object $Device -Name "Version" -Default "")
    $compared = Compare-WinToolDriverVersion -Left $updateVersion -Right $deviceVersion
    if ($null -ne $compared) {
        return ($compared -gt 0)
    }
    $updateDate = ConvertTo-WinToolDriverDate -Value (Get-WinToolNote -Object $Update -Name "Date")
    $deviceDate = ConvertTo-WinToolDriverDate -Value (Get-WinToolNote -Object $Device -Name "Date")
    if ($null -ne $updateDate -and $null -ne $deviceDate) {
        return ($updateDate -gt $deviceDate)
    }
    # Windows Update is offering it (IsInstalled=0), so treat it as newer
    # when versions and dates cannot be compared.
    return $true
}

function Test-WinToolDriverSoftwareId {
    param([string]$InstanceId)
    $id = [string]$InstanceId
    return ($id -match '^(ROOT\\|SWD\\|UEFI\\|UMB\\|HTREE\\)')
}

function Test-WinToolDriverLikelyHardware {
    param(
        [string]$InstanceId,
        [string]$Class
    )
    $id = [string]$InstanceId
    if (Test-WinToolDriverSoftwareId -InstanceId $id) {
        return $false
    }
    if ($id -match '^(PCI\\|USB\\|HDAUDIO\\|DISPLAY\\|HID\\|SCSI\\|NVME\\|IDE\\|SD\\|ACPI\\PNP|SCSIADAPTER)') {
        return $true
    }
    $className = [string]$Class
    if ($className -match '^(Display|Net|Bluetooth|USB|HIDClass|Media|SCSIAdapter|HDC|Keyboard|Mouse|Monitor)$') {
        return $true
    }
    return $false
}

function Get-WinToolDriverProblemKind {
    param(
        [int]$Code,
        $Catalog
    )
    if ($null -eq $Catalog) {
        try { $Catalog = Get-WinToolDriverCatalog }
        catch { $Catalog = $null }
    }
    foreach ($item in @(Get-WinToolNote -Object $Catalog -Name "problem" -Default @())) {
        if ([int](Get-WinToolNote -Object $item -Name "code" -Default -1) -eq $Code) {
            return [string](Get-WinToolNote -Object $item -Name "kind" -Default "")
        }
    }
    switch ($Code) {
        1 { return "missing" }
        22 { return "disabled" }
        28 { return "missing" }
        31 { return "incompatible" }
        39 { return "incompatible" }
        43 { return "incompatible" }
        45 { return "ghost" }
        48 { return "incompatible" }
        52 { return "incompatible" }
    }
    return ""
}

function Get-WinToolDriverProblemName {
    param(
        [int]$Code,
        $Catalog
    )
    if ($null -eq $Catalog) { $Catalog = Get-WinToolDriverCatalog }
    foreach ($item in @(Get-WinToolNote -Object $Catalog -Name "problem" -Default @())) {
        if ([int](Get-WinToolNote -Object $item -Name "code" -Default -1) -eq $Code) {
            return [string](Get-WinToolNote -Object $item -Name "name" -Default "")
        }
    }
    if ($Code -gt 0) { return ("Problem code " + $Code) }
    return ""
}

function Test-WinToolDriverMissing {
    param($Device)
    $instanceId = [string](Get-WinToolNote -Object $Device -Name "InstanceId" -Default "")
    $class = [string](Get-WinToolNote -Object $Device -Name "Class" -Default "")
    # ROOT/SWD/UEFI software and leftover tree entries are not missing hardware,
    # even when Windows reports ConfigManagerErrorCode 1 or 28.
    if (Test-WinToolDriverSoftwareId -InstanceId $instanceId) { return $false }
    $code = [int](Get-WinToolNote -Object $Device -Name "Problem" -Default 0)
    $kind = Get-WinToolDriverProblemKind -Code $code
    $present = [bool](Get-WinToolNote -Object $Device -Name "Present" -Default $true)
    if (-not $present) { return $false }
    if ($kind -eq "ghost" -or $kind -eq "disabled") { return $false }
    if ($kind -eq "missing") { return $true }
    $version = [string](Get-WinToolNote -Object $Device -Name "Version" -Default "")
    $provider = [string](Get-WinToolNote -Object $Device -Name "Provider" -Default "")
    $hasDriver = (-not [string]::IsNullOrWhiteSpace($version) -or -not [string]::IsNullOrWhiteSpace($provider))
    if ($hasDriver) { return $false }
    return (Test-WinToolDriverLikelyHardware -InstanceId $instanceId -Class $class)
}

function Find-WinToolDriverUpdateMatch {
    param(
        [Parameter(Mandatory = $true)]$Device,
        $Update = @()
    )
    $ids = @(Get-WinToolNote -Object $Device -Name "HardwareId" -Default @())
    foreach ($item in @($Update)) {
        $updateIds = @(Get-WinToolNote -Object $item -Name "HardwareId" -Default @())
        if ((@($updateIds).Count -gt 0) -and (Test-WinToolHardwareIdMatch -DeviceId $ids -UpdateId $updateIds)) {
            return $item
        }
    }
    $name = [string](Get-WinToolNote -Object $Device -Name "Name" -Default "")
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    foreach ($item in @($Update)) {
        $model = [string](Get-WinToolNote -Object $item -Name "Model" -Default "")
        $title = [string](Get-WinToolNote -Object $item -Name "Title" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($model) -and $name.Equals($model, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $item
        }
        if (-not [string]::IsNullOrWhiteSpace($title) -and $title.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $item
        }
    }
    return $null
}

function ConvertTo-WinToolDriverRow {
    param(
        [Parameter(Mandatory = $true)]$Device,
        [string]$Group,
        $Offer
    )
    $name = [string](Get-WinToolNote -Object $Device -Name "Name" -Default "")
    $class = [string](Get-WinToolNote -Object $Device -Name "Class" -Default "")
    $version = [string](Get-WinToolNote -Object $Device -Name "Version" -Default "")
    $date = ConvertTo-WinToolDriverDate -Value (Get-WinToolNote -Object $Device -Name "Date")
    $availableVersion = ""
    $availableDate = $null
    $title = ""
    if ($null -ne $Offer) {
        $availableVersion = [string](Get-WinToolNote -Object $Offer -Name "Version" -Default "")
        $availableDate = ConvertTo-WinToolDriverDate -Value (Get-WinToolNote -Object $Offer -Name "Date")
        $title = [string](Get-WinToolNote -Object $Offer -Name "Title" -Default "")
    }
    return [pscustomobject]@{
        Id               = [string](Get-WinToolNote -Object $Device -Name "InstanceId" -Default $name)
        Name             = $name
        Class            = $class
        Group            = $Group
        Kind             = "device"
        Version          = $version
        Date             = $date
        AvailableVersion = $availableVersion
        AvailableDate    = $availableDate
        Title            = $title
        Problem          = [int](Get-WinToolNote -Object $Device -Name "Problem" -Default 0)
        Provider         = [string](Get-WinToolNote -Object $Device -Name "Provider" -Default "")
        Present          = [bool](Get-WinToolNote -Object $Device -Name "Present" -Default $true)
        Selected         = ($Group -eq "outdated" -or $Group -eq "missing" -or $Group -eq "runtime" -or $Group -eq "gpu")
        WingetId         = ""
        Scope            = ""
        Checkbox         = $null
        Device           = $Device
        Offer            = $Offer
    }
}

function Set-WinToolDriverRowCheckbox {
    param(
        $Row,
        $Checkbox
    )
    if ($null -eq $Row) { return $Row }
    $property = $Row.PSObject.Properties["Checkbox"]
    if ($null -eq $property) {
        Add-Member -InputObject $Row -NotePropertyName "Checkbox" -NotePropertyValue $Checkbox -Force
    }
    else {
        $Row.Checkbox = $Checkbox
    }
    return $Row
}

function Get-WinToolDriverDeviceGroup {
    param(
        [Parameter(Mandatory = $true)]$Device,
        $Update = @()
    )
    $code = [int](Get-WinToolNote -Object $Device -Name "Problem" -Default 0)
    $kind = Get-WinToolDriverProblemKind -Code $code
    $present = [bool](Get-WinToolNote -Object $Device -Name "Present" -Default $true)
    if (-not $present -or $kind -eq "ghost") {
        return [pscustomobject]@{ Group = "ghost"; Offer = $null }
    }
    $offer = Find-WinToolDriverUpdateMatch -Device $Device -Update $Update
    if (Test-WinToolDriverMissing -Device $Device) {
        return [pscustomobject]@{ Group = "missing"; Offer = $offer }
    }
    if ($null -ne $offer -and (Test-WinToolDriverNewer -Update $offer -Device $Device)) {
        return [pscustomobject]@{ Group = "outdated"; Offer = $offer }
    }
    return [pscustomobject]@{ Group = "current"; Offer = $null }
}

function Get-WinToolDriverRuntimeRow {
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        $Cache
    )
    if ($null -eq $Cache) { $Cache = Get-WinToolPackageCache }
    $id = [string](Get-WinToolNote -Object $Runtime -Name "wingetId" -Default "")
    $name = [string](Get-WinToolNote -Object $Runtime -Name "name" -Default $id)
    $ready = [bool]$Cache.WingetReady
    $installed = $false
    $upgrade = $false
    if ($ready -and -not [string]::IsNullOrWhiteSpace($id)) {
        $installed = Test-WinToolCachedWingetId -Id $id -Cache $Cache
        $upgrade = Test-WinToolCachedWingetUpgrade -Id $id -Cache $Cache
    }
    $group = "runtime-current"
    $selected = $false
    $available = ""
    if (-not $ready) {
        $group = "runtime-pending"
    }
    elseif ($upgrade) {
        $group = "runtime"
        $selected = $true
        $available = "Update available"
    }
    elseif (-not $installed) {
        $group = "runtime"
        $selected = $true
        $available = "Not installed"
    }
    return [pscustomobject]@{
        Id               = [string](Get-WinToolNote -Object $Runtime -Name "id" -Default $id)
        Name             = $name
        Class            = "Runtime"
        Group            = $group
        Kind             = "runtime"
        Version          = ""
        Date             = $null
        AvailableVersion = $available
        AvailableDate    = $null
        Title            = $name
        Problem          = 0
        Provider         = ""
        Present          = $true
        Selected         = $selected
        WingetId         = $id
        Scope            = [string](Get-WinToolNote -Object $Runtime -Name "scope" -Default "machine")
        Checkbox         = $null
        Device           = $null
        Offer            = $null
    }
}

function Get-WinToolDriverGpuRow {
    param(
        [string]$GpuName,
        $Catalog
    )
    if ($null -eq $Catalog) { $Catalog = Get-WinToolDriverCatalog }
    $vendor = Resolve-WinToolGpuVendor -Name $GpuName -Vendor @(Get-WinToolNote -Object $Catalog -Name "gpuApps" -Default @())
    if ($null -eq $vendor) { return $null }
    $cache = Get-WinToolPackageCache
    $id = [string]$vendor.wingetId
    $installed = $false
    $upgrade = $false
    if ([bool]$cache.WingetReady -and -not [string]::IsNullOrWhiteSpace($id)) {
        $installed = Test-WinToolCachedWingetId -Id $id -Cache $cache
        $upgrade = Test-WinToolCachedWingetUpgrade -Id $id -Cache $cache
    }
    $available = "Official installer"
    if ($upgrade) { $available = "Update available" }
    elseif ($installed) { $available = "Installed" }
    return [pscustomobject]@{
        Id               = [string]$vendor.id
        Name             = ([string]$vendor.name + " for " + $GpuName)
        Class            = "Display"
        Group            = "gpu"
        Kind             = "gpu"
        Version          = ""
        Date             = $null
        AvailableVersion = $available
        AvailableDate    = $null
        Title            = [string]$vendor.name
        Problem          = 0
        Provider         = [string]$vendor.name
        Present          = $true
        Selected         = (-not $installed -or $upgrade)
        WingetId         = $id
        Scope            = "machine"
        Checkbox         = $null
        Device           = $null
        Offer            = $null
    }
}

function Group-WinToolDriverRow {
    param(
        $Device = @(),
        $Update = @(),
        $Runtime = $null,
        $GpuName = @(),
        $Cache,
        $Catalog
    )
    if ($null -eq $Catalog) { $Catalog = Get-WinToolDriverCatalog }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Device)) {
        $present = [bool](Get-WinToolNote -Object $item -Name "Present" -Default $true)
        $kind = Get-WinToolDriverProblemKind -Code ([int](Get-WinToolNote -Object $item -Name "Problem" -Default 0))
        if (-not $present -or $kind -eq "ghost") { continue }
        $result = Get-WinToolDriverDeviceGroup -Device $item -Update $Update
        $rows.Add((ConvertTo-WinToolDriverRow -Device $item -Group ([string]$result.Group) -Offer $result.Offer)) | Out-Null
    }
    $runtimeItems = $Runtime
    if ($null -eq $runtimeItems) {
        $runtimeItems = @(Get-WinToolNote -Object $Catalog -Name "runtimes" -Default @())
    }
    foreach ($item in @($runtimeItems)) {
        $rows.Add((Get-WinToolDriverRuntimeRow -Runtime $item -Cache $Cache)) | Out-Null
    }
    foreach ($name in @($GpuName)) {
        $row = Get-WinToolDriverGpuRow -GpuName ([string]$name) -Catalog $Catalog
        if ($null -ne $row) { $rows.Add($row) | Out-Null }
    }
    return $rows.ToArray()
}

function Format-WinToolDriverDate {
    param($Value)
    $date = ConvertTo-WinToolDriverDate -Value $Value
    if ($null -eq $date) { return "" }
    return $date.ToString("d MMM yyyy", [System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
}

function Format-WinToolDriverDetail {
    param($Row)
    $group = [string]$Row.Group
    if ($group -eq "outdated" -or $group -eq "missing" -or $group -eq "runtime" -or $group -eq "gpu") {
        $available = [string]$Row.AvailableVersion
        $dateText = Format-WinToolDriverDate -Value $Row.AvailableDate
        if (-not [string]::IsNullOrWhiteSpace($dateText) -and -not [string]::IsNullOrWhiteSpace($available) -and $available -notmatch 'available|installed|Official|Not ') {
            return ("Available: " + $available + " (" + $dateText + ")")
        }
        if (-not [string]::IsNullOrWhiteSpace($dateText)) {
            return ("Available: " + $dateText)
        }
        if (-not [string]::IsNullOrWhiteSpace($available)) {
            return ("Available: " + $available)
        }
        return "Available from Windows Update"
    }
    $current = [string]$Row.Version
    $dateText = Format-WinToolDriverDate -Value $Row.Date
    if (-not [string]::IsNullOrWhiteSpace($current) -and -not [string]::IsNullOrWhiteSpace($dateText)) {
        return ("Current: " + $current + " (" + $dateText + ")")
    }
    if (-not [string]::IsNullOrWhiteSpace($dateText)) {
        return ("Current: " + $dateText)
    }
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        return ("Current: " + $current)
    }
    return "Up to date"
}

function Format-WinToolDriverHeader {
    param(
        [int]$Outdated = 0,
        [int]$Missing = 0,
        [int]$Runtime = 0
    )
    $head = ""
    if ($Outdated -gt 0 -and $Missing -gt 0) {
        $left = "1 device driver is outdated"
        if ($Outdated -gt 1) { $left = "$Outdated device drivers are outdated" }
        $right = "1 is missing"
        if ($Missing -gt 1) { $right = "$Missing are missing" }
        $head = $left + " and " + $right + "."
    }
    elseif ($Outdated -eq 1) { $head = "1 device driver is outdated." }
    elseif ($Outdated -gt 1) { $head = "$Outdated device drivers are outdated." }
    elseif ($Missing -eq 1) { $head = "1 device driver is missing." }
    elseif ($Missing -gt 1) { $head = "$Missing device drivers are missing." }
    if ($Runtime -eq 1) {
        $extra = "1 game runtime needs attention."
    }
    elseif ($Runtime -gt 1) {
        $extra = "$Runtime game runtimes need attention."
    }
    else {
        $extra = ""
    }
    if ([string]::IsNullOrWhiteSpace($head) -and [string]::IsNullOrWhiteSpace($extra)) {
        return "No outdated or missing drivers were found."
    }
    if ([string]::IsNullOrWhiteSpace($head)) { return $extra }
    if ([string]::IsNullOrWhiteSpace($extra)) { return $head }
    return ($head + " " + $extra)
}

function Get-WinToolDriverProblemDevice {
    param($Device = @())
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Device)) {
        $code = [int](Get-WinToolNote -Object $item -Name "Problem" -Default 0)
        $present = [bool](Get-WinToolNote -Object $item -Name "Present" -Default $true)
        if ($code -le 0) { continue }
        $kind = Get-WinToolDriverProblemKind -Code $code
        if ($kind -eq "ghost" -or -not $present) { continue }
        $list.Add($item) | Out-Null
    }
    return $list.ToArray()
}

function Get-WinToolDriverGhostDevice {
    param($Device = @())
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Device)) {
        $code = [int](Get-WinToolNote -Object $item -Name "Problem" -Default 0)
        $present = [bool](Get-WinToolNote -Object $item -Name "Present" -Default $true)
        $kind = Get-WinToolDriverProblemKind -Code $code
        if (-not $present -or $kind -eq "ghost") {
            $list.Add($item) | Out-Null
        }
    }
    return $list.ToArray()
}

function Get-WinToolDriverIncompatibleDevice {
    param(
        $Device = @(),
        [bool]$MemoryIntegrity = $false
    )
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Device)) {
        $code = [int](Get-WinToolNote -Object $item -Name "Problem" -Default 0)
        $kind = Get-WinToolDriverProblemKind -Code $code
        if ($kind -eq "incompatible") {
            $list.Add($item) | Out-Null
            continue
        }
        if ($MemoryIntegrity -and $code -eq 52) {
            $list.Add($item) | Out-Null
        }
    }
    return $list.ToArray()
}

function Format-WinToolMachineSummary {
    param($Info)
    if ($null -eq $Info) { return "System information is not available yet." }
    $lines = New-Object System.Collections.Generic.List[string]
    $map = [ordered]@{
        Os      = "System"
        Version = "Version"
        Cpu     = "Processor"
        Gpu     = "Graphics"
        Board   = "Board"
        Memory  = "Memory"
        Bios    = "BIOS"
    }
    foreach ($key in $map.Keys) {
        $value = [string](Get-WinToolNote -Object $Info -Name $key -Default "")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $lines.Add(([string]$map[$key] + ": " + $value)) | Out-Null
        }
    }
    if ($lines.Count -eq 0) { return "System information is not available yet." }
    return ($lines.ToArray() -join [Environment]::NewLine)
}

function Format-WinToolDisplayAdvice {
    param($Display)
    if ($null -eq $Display) {
        return "No display was reported. After a graphics driver update, open Settings > System > Display and choose the recommended resolution."
    }
    $name = [string](Get-WinToolNote -Object $Display -Name "Name" -Default "This display")
    $currentWidth = [int](Get-WinToolNote -Object $Display -Name "Width" -Default 0)
    $currentHeight = [int](Get-WinToolNote -Object $Display -Name "Height" -Default 0)
    $nativeWidth = [int](Get-WinToolNote -Object $Display -Name "NativeWidth" -Default 0)
    $nativeHeight = [int](Get-WinToolNote -Object $Display -Name "NativeHeight" -Default 0)
    $gpu = [string](Get-WinToolNote -Object $Display -Name "Gpu" -Default "")
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($name) | Out-Null
    if ($currentWidth -gt 0 -and $currentHeight -gt 0) {
        $parts.Add("is running at " + $currentWidth + " x " + $currentHeight + ".") | Out-Null
    }
    else {
        $parts.Add("was found.") | Out-Null
    }
    if ($nativeWidth -gt 0 -and $nativeHeight -gt 0) {
        if ($currentWidth -ne $nativeWidth -or $currentHeight -ne $nativeHeight) {
            $parts.Add("The preferred resolution is " + $nativeWidth + " x " + $nativeHeight + ". Open Settings > System > Display and choose that recommended size.") | Out-Null
        }
        else {
            $parts.Add("That already matches the preferred resolution.") | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($gpu)) {
        $parts.Add("If the picture looks wrong, install or update the official graphics app for " + $gpu + " from the list above, then check Display settings again.") | Out-Null
    }
    else {
        $parts.Add("If the picture looks wrong, update the official graphics app from the list above, then check Display settings.") | Out-Null
    }
    return ($parts.ToArray() -join " ")
}

function New-WinToolDriverDeviceRecord {
    param(
        [string]$Name,
        [string]$Class,
        [string]$InstanceId,
        [int]$Problem = 0,
        [bool]$Present = $true,
        [string]$Version = "",
        [string]$Provider = "",
        $Date = $null,
        $HardwareId = @()
    )
    return [pscustomobject]@{
        Name       = $Name
        Class      = $Class
        InstanceId = $InstanceId
        Problem    = $Problem
        Present    = $Present
        Version    = $Version
        Provider   = $Provider
        Date       = $Date
        HardwareId = @(ConvertTo-WinToolHardwareIdList -Value $HardwareId)
    }
}

function New-WinToolDriverUpdateRecord {
    param(
        [string]$Title,
        [string]$Model = "",
        [string]$Version = "",
        $Date = $null,
        $HardwareId = @()
    )
    return [pscustomobject]@{
        Title      = $Title
        Model      = $Model
        Version    = $Version
        Date       = $Date
        HardwareId = @(ConvertTo-WinToolHardwareIdList -Value $HardwareId)
    }
}

function Get-WinToolDriverScanScript {
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Stop"
function Convert-WinToolJobDate($Value) {
    if ($null -eq $Value) { return "" }
    try {
        if ($Value -is [datetime]) { return ([datetime]$Value).ToString("o") }
        $text = [string]$Value
        if ($text -match '^\d{14}') {
            return ([System.Management.ManagementDateTimeConverter]::ToDateTime($text)).ToString("o")
        }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, [ref]$parsed)) { return $parsed.ToString("o") }
    }
    catch { }
    return [string]$Value
}
try {
    $devices = New-Object System.Collections.Generic.List[object]
    $signed = @{}
    try {
        foreach ($row in @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop)) {
            $key = [string]$row.DeviceID
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $signed[$key.ToUpperInvariant()] = $row
        }
    }
    catch { }
    $entities = @()
    try { $entities = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop) }
    catch { $entities = @() }
    foreach ($entity in $entities) {
        $instance = [string]$entity.DeviceID
        if ([string]::IsNullOrWhiteSpace($instance)) { $instance = [string]$entity.PNPDeviceID }
        if ([string]::IsNullOrWhiteSpace($instance)) { continue }
        $name = [string]$entity.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$entity.Caption }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $instance }
        $code = 0
        if ($null -ne $entity.ConfigManagerErrorCode) { $code = [int]$entity.ConfigManagerErrorCode }
        $present = $true
        if ($code -eq 45) { $present = $false }
        if ($null -ne $entity.PSObject.Properties["Present"] -and $null -ne $entity.Present) {
            $present = [bool]$entity.Present
        }
        $hardware = @()
        if ($null -ne $entity.HardwareID) { $hardware += @($entity.HardwareID) }
        if ($null -ne $entity.CompatibleID) { $hardware += @($entity.CompatibleID) }
        if ($null -ne $entity.PNPDeviceID -and -not [string]::IsNullOrWhiteSpace([string]$entity.PNPDeviceID)) { $hardware += [string]$entity.PNPDeviceID }
        $driver = $null
        $lookup = $instance.ToUpperInvariant()
        if ($signed.ContainsKey($lookup)) { $driver = $signed[$lookup] }
        $version = ""
        $provider = ""
        $date = ""
        if ($null -ne $driver) {
            $version = [string]$driver.DriverVersion
            $provider = [string]$driver.Manufacturer
            if ([string]::IsNullOrWhiteSpace($provider)) { $provider = [string]$driver.DriverProviderName }
            $date = Convert-WinToolJobDate $driver.DriverDate
            if ($null -ne $driver.HardWareID -and -not [string]::IsNullOrWhiteSpace([string]$driver.HardWareID)) {
                $hardware += [string]$driver.HardWareID
            }
        }
        $devices.Add([pscustomobject]@{
            Name = $name
            Class = [string]$entity.PNPClass
            InstanceId = $instance
            Problem = $code
            Present = $present
            Version = $version
            Provider = $provider
            Date = $date
            HardwareId = @($hardware | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Select-Object -Unique)
        }) | Out-Null
    }

    $updates = New-Object System.Collections.Generic.List[object]
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
        for ($i = 0; $i -lt $result.Updates.Count; $i++) {
            $update = $result.Updates.Item($i)
            $ids = @()
            foreach ($name in @("DriverHardwareID", "DriverHardwareId")) {
                if ($null -ne $update.PSObject.Properties[$name] -and $null -ne $update.$name) {
                    $ids += @($update.$name)
                }
            }
            $version = ""
            if ($null -ne $update.PSObject.Properties["DriverVerVersion"]) { $version = [string]$update.DriverVerVersion }
            $date = ""
            if ($null -ne $update.PSObject.Properties["DriverVerDate"]) { $date = Convert-WinToolJobDate $update.DriverVerDate }
            $model = ""
            if ($null -ne $update.PSObject.Properties["DriverModel"]) { $model = [string]$update.DriverModel }
            $updates.Add([pscustomobject]@{
                Title = (([string]$update.Title) -replace "[\r\n\t]", " ")
                Model = $model
                Version = $version
                Date = $date
                HardwareId = @($ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Select-Object -Unique)
            }) | Out-Null
        }
    }
    catch {
        if ($devices.Count -eq 0) { throw }
        $Sync.Warning = $_.Exception.Message
    }

    $displays = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($gpu in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
            if ([string]::IsNullOrWhiteSpace([string]$gpu.Name)) { continue }
            $width = 0
            $height = 0
            if ($null -ne $gpu.CurrentHorizontalResolution) { $width = [int]$gpu.CurrentHorizontalResolution }
            if ($null -ne $gpu.CurrentVerticalResolution) { $height = [int]$gpu.CurrentVerticalResolution }
            $displays.Add([pscustomobject]@{
                Name = [string]$gpu.Name
                Gpu = [string]$gpu.Name
                Width = $width
                Height = $height
                NativeWidth = $width
                NativeHeight = $height
            }) | Out-Null
        }
    }
    catch { }

    try {
        $monitors = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop)
        $index = 0
        foreach ($monitor in $monitors) {
            $nativeWidth = 0
            $nativeHeight = 0
            if ($null -ne $monitor.MaxHorizontalImageSize -and $null -ne $monitor.MaxVerticalImageSize) {
                # Physical size in cm is not a pixel resolution; leave native
                # at the current mode unless a better source is present.
            }
            $index++
        }
        $modes = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue)
        foreach ($item in @($modes)) {
            $bestW = 0
            $bestH = 0
            try {
                foreach ($mode in @($item.MonitorSourceModes)) {
                    $w = 0; $h = 0
                    if ($null -ne $mode.HorizontalActivePixels) { $w = [int]$mode.HorizontalActivePixels }
                    if ($null -ne $mode.VerticalActivePixels) { $h = [int]$mode.VerticalActivePixels }
                    if (($w * $h) -gt ($bestW * $bestH)) { $bestW = $w; $bestH = $h }
                }
            }
            catch { }
            if ($bestW -gt 0 -and $displays.Count -gt 0) {
                $displays[0].NativeWidth = $bestW
                $displays[0].NativeHeight = $bestH
            }
        }
    }
    catch { }

    $hvci = $false
    try {
        $guard = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        if (@($guard.SecurityServicesRunning) -contains 2) { $hvci = $true }
    }
    catch {
        try {
            $item = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -ErrorAction Stop
            if ([int]$item.Enabled -eq 1) { $hvci = $true }
        }
        catch { }
    }

    if ($devices.Count -gt 0) { $Sync.DeviceJson = ($devices.ToArray() | ConvertTo-Json -Compress -Depth 5) }
    else { $Sync.DeviceJson = "[]" }
    if ($updates.Count -gt 0) { $Sync.UpdateJson = ($updates.ToArray() | ConvertTo-Json -Compress -Depth 5) }
    else { $Sync.UpdateJson = "[]" }
    if ($displays.Count -gt 0) { $Sync.DisplayJson = ($displays.ToArray() | ConvertTo-Json -Compress -Depth 5) }
    else { $Sync.DisplayJson = "[]" }
    $Sync.Hvci = $hvci
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function ConvertFrom-WinToolJsonArray {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text) -or $Text.Trim() -eq "[]") { return @() }
    $parsed = ConvertFrom-WinToolJsonText -Text $Text
    return @($parsed)
}

function ConvertFrom-WinToolDriverScan {
    param(
        [AllowEmptyString()][string]$DeviceJson,
        [AllowEmptyString()][string]$UpdateJson
    )
    $devices = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(ConvertFrom-WinToolJsonArray -Text $DeviceJson)) {
        $devices.Add((New-WinToolDriverDeviceRecord `
                    -Name ([string](Get-WinToolNote -Object $item -Name "Name" -Default "")) `
                    -Class ([string](Get-WinToolNote -Object $item -Name "Class" -Default "")) `
                    -InstanceId ([string](Get-WinToolNote -Object $item -Name "InstanceId" -Default "")) `
                    -Problem ([int](Get-WinToolNote -Object $item -Name "Problem" -Default 0)) `
                    -Present ([bool](Get-WinToolNote -Object $item -Name "Present" -Default $true)) `
                    -Version ([string](Get-WinToolNote -Object $item -Name "Version" -Default "")) `
                    -Provider ([string](Get-WinToolNote -Object $item -Name "Provider" -Default "")) `
                    -Date (Get-WinToolNote -Object $item -Name "Date") `
                    -HardwareId @(Get-WinToolNote -Object $item -Name "HardwareId" -Default @()))) | Out-Null
    }
    $updates = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(ConvertFrom-WinToolJsonArray -Text $UpdateJson)) {
        $updates.Add((New-WinToolDriverUpdateRecord `
                    -Title ([string](Get-WinToolNote -Object $item -Name "Title" -Default "")) `
                    -Model ([string](Get-WinToolNote -Object $item -Name "Model" -Default "")) `
                    -Version ([string](Get-WinToolNote -Object $item -Name "Version" -Default "")) `
                    -Date (Get-WinToolNote -Object $item -Name "Date") `
                    -HardwareId @(Get-WinToolNote -Object $item -Name "HardwareId" -Default @()))) | Out-Null
    }
    return [pscustomobject]@{
        Device = $devices.ToArray()
        Update = $updates.ToArray()
    }
}

function Get-WinToolDriverBackupScript {
    $scriptText = @'
param($Sync, $Folder)
$ErrorActionPreference = "Stop"
try {
    if ([string]::IsNullOrWhiteSpace($Folder)) { throw "No folder was chosen." }
    if (-not (Test-Path -LiteralPath $Folder)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }
    $exporter = Get-Command -Name Export-WindowsDriver -ErrorAction SilentlyContinue
    if ($null -ne $exporter) {
        Export-WindowsDriver -Online -Destination $Folder | Out-Null
    }
    else {
        $pnputil = Join-Path $env:SystemRoot "System32\pnputil.exe"
        & $pnputil /export-driver * $Folder
        if ($LASTEXITCODE -ne 0) { throw "pnputil could not export the drivers (exit $LASTEXITCODE)." }
    }
    $count = @(Get-ChildItem -LiteralPath $Folder -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue).Count
    $Sync.Count = $count
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverOfflineScript {
    $scriptText = @'
param($Sync, $Folder)
$ErrorActionPreference = "Stop"
try {
    if ([string]::IsNullOrWhiteSpace($Folder) -or -not (Test-Path -LiteralPath $Folder)) {
        throw "The backup folder was not found."
    }
    $pnputil = Join-Path $env:SystemRoot "System32\pnputil.exe"
    $pattern = Join-Path $Folder "*.inf"
    & $pnputil /add-driver $pattern /subdirs /install
    $Sync.ExitCode = [int]$LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010 -and $LASTEXITCODE -ne 259) {
        throw "pnputil could not install the drivers (exit $LASTEXITCODE)."
    }
    $Sync.Reboot = ($LASTEXITCODE -eq 3010)
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverAudioScript {
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Continue"
$log = New-Object System.Collections.Generic.List[string]
try {
    foreach ($name in @("AudioEndpointBuilder", "Audiosrv")) {
        try {
            Restart-Service -Name $name -Force -ErrorAction Stop
            $log.Add("Restarted $name.")
        }
        catch { $log.Add("Could not restart ${name}: $($_.Exception.Message)") }
    }
    $enabled = 0
    $devices = @()
    try { $devices = @(Get-PnpDevice -ErrorAction Stop) } catch { $devices = @() }
    foreach ($device in $devices) {
        $className = [string]$device.Class
        $status = [string]$device.Status
        if ($status -ne "Error" -and $status -ne "Unknown" -and $status -ne "Disabled" -and $status -ne "Degraded") { continue }
        if ($className -notmatch '^(MEDIA|AudioEndpoint|System)$' -and [string]$device.FriendlyName -notmatch '(?i)audio|sound|speaker|headphone') { continue }
        if ($status -eq "OK") { continue }
        try {
            Enable-PnpDevice -InstanceId ([string]$device.InstanceId) -Confirm:$false -ErrorAction Stop
            $enabled++
            $log.Add("Re-enabled " + [string]$device.FriendlyName + ".")
        }
        catch { $log.Add("Could not enable " + [string]$device.FriendlyName + ": " + $_.Exception.Message) }
    }
    $troubleshooter = Join-Path $env:SystemRoot "System32\msdt.exe"
    if (Test-Path -LiteralPath $troubleshooter) {
        Start-Process -FilePath $troubleshooter -ArgumentList @("/id", "AudioPlaybackDiagnostic") | Out-Null
        $log.Add("Opened the audio troubleshooter.")
    }
    else {
        Start-Process "ms-settings:sound" | Out-Null
        $log.Add("Opened Sound settings.")
    }
    $Sync.Log = $log.ToArray()
    $Sync.Enabled = $enabled
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
    $Sync.Log = $log.ToArray()
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverNetworkScript {
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Continue"
$log = New-Object System.Collections.Generic.List[string]
try {
    $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
    $ipconfig = Join-Path $env:SystemRoot "System32\ipconfig.exe"
    & $netsh winsock reset | Out-Null
    $log.Add("Reset the Winsock catalog.")
    & $netsh int ip reset | Out-Null
    $log.Add("Reset the TCP/IP stack.")
    & $ipconfig /flushdns | Out-Null
    $log.Add("Flushed the DNS cache.")
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" -or $_.Status -eq "Disconnected" })
        foreach ($adapter in $adapters) {
            try {
                Restart-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                $log.Add("Restarted adapter " + $adapter.Name + ".")
            }
            catch { $log.Add("Could not restart " + $adapter.Name + ": " + $_.Exception.Message) }
        }
    }
    catch { $log.Add("Could not restart network adapters: $($_.Exception.Message)") }
    & $ipconfig /release | Out-Null
    & $ipconfig /renew | Out-Null
    $log.Add("Released and renewed IP addresses.")
    $Sync.Log = $log.ToArray()
    $Sync.Reboot = $true
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
    $Sync.Log = $log.ToArray()
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverRemoveScript {
    $scriptText = @'
param($Sync, $IdText)
$ErrorActionPreference = "Continue"
$log = New-Object System.Collections.Generic.List[string]
$removed = 0
$failed = 0
try {
    $pnputil = Join-Path $env:SystemRoot "System32\pnputil.exe"
    foreach ($id in @(([string]$IdText) -split "`n")) {
        $instance = [string]$id
        if ([string]::IsNullOrWhiteSpace($instance)) { continue }
        & $pnputil /remove-device $instance
        if ($LASTEXITCODE -eq 0) {
            $removed++
            $log.Add("Removed $instance.")
        }
        else {
            $failed++
            $log.Add("Could not remove $instance (exit $LASTEXITCODE).")
        }
    }
    $Sync.Removed = $removed
    $Sync.Failed = $failed
    $Sync.Log = $log.ToArray()
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
    $Sync.Log = $log.ToArray()
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverRescanScript {
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Stop"
try {
    $pnputil = Join-Path $env:SystemRoot "System32\pnputil.exe"
    & $pnputil /scan-devices
    if ($LASTEXITCODE -ne 0) { throw "pnputil could not rescan devices (exit $LASTEXITCODE)." }
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverToggleScript {
    $scriptText = @'
param($Sync, $IdText, $Action)
$ErrorActionPreference = "Continue"
$log = New-Object System.Collections.Generic.List[string]
$count = 0
try {
    foreach ($id in @(([string]$IdText) -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        try {
            if ($Action -eq "enable") {
                Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
                $log.Add("Enabled $id.")
            }
            else {
                Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
                $log.Add("Disabled $id.")
            }
            $count++
        }
        catch { $log.Add("Could not change ${id}: $($_.Exception.Message)") }
    }
    $Sync.Count = $count
    $Sync.Log = $log.ToArray()
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
    $Sync.Log = $log.ToArray()
}
$Sync.Done = $true
'@
    return $scriptText
}

function Get-WinToolDriverInfoScript {
    $scriptText = @'
param($Sync)
$ErrorActionPreference = "Continue"
$info = @{ Os = ""; Version = ""; Cpu = ""; Gpu = ""; Board = ""; Memory = ""; Bios = "" }
try {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.Os = ([string]$os.Caption -replace '^Microsoft\s+', '').Trim()
        $gb = [math]::Round(([double]$os.TotalVisibleMemorySize * 1KB) / 1GB, 1)
        if ($gb -gt 0) { $info.Memory = ("{0} GB" -f $gb) }
    } catch { }
    try { $info.Version = [string](Get-ItemProperty -LiteralPath "HKLM:\Software\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop).DisplayVersion } catch { }
    try { $info.Cpu = [string](@(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)[0].Name).Trim() } catch { }
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Name) } | ForEach-Object { [string]$_.Name })
        if ($gpus.Count -gt 0) { $info.Gpu = ($gpus -join ", ") }
    } catch { }
    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
        $info.Board = (([string]$board.Manufacturer).Trim() + " " + ([string]$board.Product).Trim()).Trim()
    } catch { }
    try {
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        $total = [double]0
        foreach ($module in $modules) { $total += [double]$module.Capacity }
        if ($total -gt 0) { $info.Memory = ("{0} GB" -f [math]::Round($total / 1GB, 1)) }
    } catch { }
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $info.Bios = (([string]$bios.Manufacturer).Trim() + " " + ([string]$bios.SMBIOSBIOSVersion).Trim()).Trim()
    } catch { }
    $Sync.Info = [pscustomobject]$info
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Test-WinToolDriverCatalog {
    param(
        $Catalog,
        $Errors
    )
    if ([int](Get-WinToolNote -Object $Catalog -Name "schemaVersion" -Default 0) -ne 1) {
        Add-WinToolDataError -Errors $Errors -Message "drivers.json schemaVersion must be 1."
    }
    $ids = @{}
    $runtimes = @(Get-WinToolNote -Object $Catalog -Name "runtimes" -Default @())
    if ($runtimes.Count -eq 0) {
        Add-WinToolDataError -Errors $Errors -Message "drivers.json has no game runtimes."
    }
    foreach ($item in $runtimes) {
        $id = [string](Get-WinToolNote -Object $item -Name "id" -Default "")
        $name = [string](Get-WinToolNote -Object $item -Name "name" -Default "")
        $wingetId = [string](Get-WinToolNote -Object $item -Name "wingetId" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name)) {
            Add-WinToolDataError -Errors $Errors -Message "A game runtime is missing an id or name."
        }
        if ($ids.ContainsKey($id)) {
            Add-WinToolDataError -Errors $Errors -Message "Duplicate driver catalog id '$id'."
        }
        else {
            $ids[$id] = $true
        }
        if (-not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $Errors -Message "Runtime '$id' has an unexpected winget id '$wingetId'."
        }
        $scope = [string](Get-WinToolNote -Object $item -Name "scope" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($scope) -and @("user", "machine") -notcontains $scope) {
            Add-WinToolDataError -Errors $Errors -Message "Runtime '$id' has an unknown scope."
        }
    }
    $apps = @(Get-WinToolNote -Object $Catalog -Name "gpuApps" -Default @())
    if ($apps.Count -lt 3) {
        Add-WinToolDataError -Errors $Errors -Message "drivers.json should list the official AMD, NVIDIA, and Intel apps."
    }
    foreach ($item in $apps) {
        $id = [string](Get-WinToolNote -Object $item -Name "id" -Default "")
        $name = [string](Get-WinToolNote -Object $item -Name "name" -Default "")
        $wingetId = [string](Get-WinToolNote -Object $item -Name "wingetId" -Default "")
        $match = @(Get-WinToolNote -Object $item -Name "match" -Default @())
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or $match.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message "A graphics app is missing an id, name, or match list."
        }
        if (-not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $Errors -Message "Graphics app '$id' has an unexpected winget id '$wingetId'."
        }
    }
    $codes = @{}
    foreach ($item in @(Get-WinToolNote -Object $Catalog -Name "problem" -Default @())) {
        $code = [int](Get-WinToolNote -Object $item -Name "code" -Default -1)
        $name = [string](Get-WinToolNote -Object $item -Name "name" -Default "")
        $kind = [string](Get-WinToolNote -Object $item -Name "kind" -Default "")
        if ($code -le 0 -or [string]::IsNullOrWhiteSpace($name) -or @("missing", "disabled", "ghost", "incompatible") -notcontains $kind) {
            Add-WinToolDataError -Errors $Errors -Message "A problem code entry is missing a code, name, or known kind."
        }
        if ($codes.ContainsKey($code)) {
            Add-WinToolDataError -Errors $Errors -Message "Duplicate problem code $code."
        }
        else {
            $codes[$code] = $true
        }
    }
    foreach ($needed in @(1, 22, 28, 31, 39, 43, 45, 48, 52)) {
        if (-not $codes.ContainsKey($needed)) {
            Add-WinToolDataError -Errors $Errors -Message "drivers.json is missing problem code $needed."
        }
    }
}
