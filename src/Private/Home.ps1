# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# Home: a quick local health check. The collectors run in background
# runspaces and return plain data; the ConvertTo-WinToolHome* functions turn
# that data into a result row and are pure, so tests can feed them stubs.

function Get-WinToolHomeCheckList {
    # The fixed order of the checks on the Home page.
    return @(
        [pscustomobject]@{ Id = "junk"; Name = (Get-WinToolText "msg.junk-files") },
        [pscustomobject]@{ Id = "tweaks"; Name = (Get-WinToolText "msg.recommended-tweaks") },
        [pscustomobject]@{ Id = "startup"; Name = (Get-WinToolText "msg.startup-programs") },
        [pscustomobject]@{ Id = "drivers"; Name = (Get-WinToolText "msg.drivers") },
        [pscustomobject]@{ Id = "disk"; Name = (Get-WinToolText "msg.disk-health") }
    )
}

function Format-WinToolByteSize {
    param([double]$Bytes)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1TB) { return ([string]::Format($culture, "{0:0.0} TB", $Bytes / 1TB)) }
    if ($Bytes -ge 100GB) { return ([string]::Format($culture, "{0:0} GB", $Bytes / 1GB)) }
    if ($Bytes -ge 1GB) { return ([string]::Format($culture, "{0:0.0} GB", $Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ([string]::Format($culture, "{0:0} MB", $Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ([string]::Format($culture, "{0:0} KB", $Bytes / 1KB)) }
    return (Get-WinToolText "msg.n-bytes" ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:0}", $Bytes)))
}

function New-WinToolHomeResult {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet("ok", "warn", "bad", "unknown")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet("fix", "review", "none")][string]$Action = "none",
        [int]$Penalty = 0,
        [string[]]$Detail = @(),
        [double]$Amount = 0
    )
    $name = [string](@(Get-WinToolHomeCheckList | Where-Object { $_.Id -eq $Id })[0].Name)
    return [pscustomobject]@{
        Id = $Id
        Name = $name
        Status = $Status
        Text = $Text
        Action = $Action
        Fixable = ($Action -eq "fix")
        Penalty = $Penalty
        Detail = @($Detail)
        Amount = $Amount
    }
}

function ConvertTo-WinToolHomeErrorResult {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Message
    )
    $text = Get-WinToolText "msg.could-not-check"
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $detail = @($Message)
    }
    else {
        $detail = @()
    }
    return (New-WinToolHomeResult -Id $Id -Status "unknown" -Text $text -Detail $detail)
}

function ConvertTo-WinToolHomeJunkResult {
    # Data: one item per location with Name and Bytes (what can be deleted).
    param([object[]]$Data)
    $total = [double]0
    $detail = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Data)) {
        if ($null -eq $item) { continue }
        $bytes = [double]$item.Bytes
        if ($bytes -lt 0) { $bytes = 0 }
        $total += $bytes
        $detail.Add(("{0}: {1}" -f [string]$item.Name, (Format-WinToolByteSize -Bytes $bytes)))
    }
    if ($total -lt 50MB) {
        return (New-WinToolHomeResult -Id "junk" -Status "ok" -Text (Get-WinToolText "msg.nothing-worth-cleaning") -Detail $detail.ToArray() -Amount $total)
    }
    $text = (Get-WinToolText "msg.can-be-deleted" (Format-WinToolByteSize -Bytes $total))
    if ($total -lt 200MB) {
        # Too little to be worth a Fix.
        return (New-WinToolHomeResult -Id "junk" -Status "ok" -Text $text -Detail $detail.ToArray() -Amount $total)
    }
    $status = "warn"
    $penalty = 4
    if ($total -ge 1GB) { $status = "bad"; $penalty = 12 }
    return (New-WinToolHomeResult -Id "junk" -Status $status -Text $text -Action "fix" -Penalty $penalty -Detail $detail.ToArray() -Amount $total)
}

function ConvertTo-WinToolHomeTweakResult {
    # Data: one item per Recommended tweak with Id, Name and State (on/off/unknown).
    param([object[]]$Data)
    $off = @(@($Data) | Where-Object { $null -ne $_ -and [string]$_.State -eq "off" })
    $read = @(@($Data) | Where-Object { $null -ne $_ -and [string]$_.State -ne "unknown" })
    if (@($Data).Count -gt 0 -and $read.Count -eq 0) {
        return (New-WinToolHomeResult -Id "tweaks" -Status "unknown" -Text (Get-WinToolText "msg.could-not-read-the-tweaks"))
    }
    $names = @($off | ForEach-Object { [string]$_.Name })
    if ($off.Count -eq 0) {
        return (New-WinToolHomeResult -Id "tweaks" -Status "ok" -Text (Get-WinToolText "msg.all-recommended-tweaks-are-on"))
    }
    $text = Get-WinToolCountText "msg.n-tweaks-not-applied-yet" $off.Count
    $penalty = [Math]::Min(16, 2 * $off.Count)
    return (New-WinToolHomeResult -Id "tweaks" -Status "warn" -Text $text -Action "fix" -Penalty $penalty -Detail $names -Amount $off.Count)
}

function Test-WinToolStartupApproved {
    # StartupApproved stores a binary value; an odd first byte (0x03, 0x07)
    # means the user turned the entry off. No value means it is on.
    param($FirstByte)
    if ($null -eq $FirstByte) { return $true }
    $value = [int]$FirstByte
    if ($value -lt 0) { return $true }
    return (($value % 2) -eq 0)
}

function ConvertTo-WinToolHomeStartupResult {
    # Data: one item per Run value or Startup-folder shortcut with Name,
    # Source and Approved (first StartupApproved byte, or -1 when missing).
    param([object[]]$Data)
    $enabled = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($item in @($Data)) {
        if ($null -eq $item) { continue }
        $name = [string]$item.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (-not (Test-WinToolStartupApproved -FirstByte $item.Approved)) { continue }
        $key = ([string]$item.Source + "|" + $name).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $enabled.Add(("{0} ({1})" -f $name, [string]$item.Source))
    }
    $count = $enabled.Count
    if ($count -eq 0) {
        return (New-WinToolHomeResult -Id "startup" -Status "ok" -Text (Get-WinToolText "msg.no-programs-start-with-windows"))
    }
    $text = Get-WinToolCountText "msg.n-programs-start-with-windows" $count
    $status = "ok"
    $penalty = 0
    if ($count -gt 8) { $status = "warn"; $penalty = 6 }
    if ($count -gt 12) { $penalty = 10 }
    return (New-WinToolHomeResult -Id "startup" -Status $status -Text $text -Action "review" -Penalty $penalty -Detail $enabled.ToArray() -Amount $count)
}

function Get-WinToolDriverProblemText {
    param([int]$Code)
    switch ($Code) {
        1 { return (Get-WinToolText "msg.not-configured") }
        10 { return (Get-WinToolText "msg.cannot-start") }
        12 { return (Get-WinToolText "msg.not-enough-resources") }
        14 { return (Get-WinToolText "msg.restart-required") }
        18 { return (Get-WinToolText "msg.reinstall-driver") }
        19 { return (Get-WinToolText "msg.registry-entry-damaged") }
        24 { return (Get-WinToolText "msg.missing-or-not-working") }
        28 { return (Get-WinToolText "msg.driver-not-installed") }
        31 { return (Get-WinToolText "msg.driver-could-not-load") }
        32 { return (Get-WinToolText "msg.driver-service-disabled") }
        37 { return (Get-WinToolText "msg.driver-failed-to-initialize") }
        39 { return (Get-WinToolText "msg.driver-missing-or-corrupted") }
        43 { return (Get-WinToolText "msg.reported-a-problem") }
        48 { return (Get-WinToolText "msg.driver-blocked") }
        52 { return (Get-WinToolText "msg.driver-signature-invalid") }
    }
    if ($Code -gt 0) { return ("code " + $Code) }
    return ""
}

function ConvertTo-WinToolHomeDriverResult {
    # Data: devices that report a problem, with Name, Class, Status and optional Problem code.
    # Devices manually disabled by the user (Problem 22) or disconnected (Problem 45) are ignored.
    param([object[]]$Data)
    $bad = @(@($Data) | Where-Object {
            if ($null -eq $_ -or [string]$_.Status -eq "OK") { return $false }
            $code = -1
            if ($null -ne $_.PSObject.Properties["Problem"] -and $null -ne $_.Problem) { $code = [int]$_.Problem }
            return ($code -ne 22 -and $code -ne 45)
        })
    if ($bad.Count -eq 0) {
        return (New-WinToolHomeResult -Id "drivers" -Status "ok" -Text (Get-WinToolText "msg.no-device-with-problems"))
    }
    $detail = @($bad | ForEach-Object {
            $label = [string]$_.Name
            if ([string]::IsNullOrWhiteSpace($label) -and $null -ne $_.PSObject.Properties["InstanceId"]) {
                $label = [string]$_.InstanceId
            }
            if ([string]::IsNullOrWhiteSpace($label)) { $label = Get-WinToolText "msg.unknown-device" }
            if (-not [string]::IsNullOrWhiteSpace([string]$_.Class)) { $label += " (" + [string]$_.Class + ")" }
            $code = -1
            if ($null -ne $_.PSObject.Properties["Problem"] -and $null -ne $_.Problem) { $code = [int]$_.Problem }
            $reason = Get-WinToolDriverProblemText -Code $code
            if (-not [string]::IsNullOrWhiteSpace($reason)) {
                if ($reason.StartsWith("code ")) { $label += " - " + $reason }
                else { $label += " - {0} (code {1})" -f $reason, $code }
            }
            $label
        })
    $text = Get-WinToolCountText "msg.n-devices-have-problems" $bad.Count
    $penalty = [Math]::Min(20, 10 * $bad.Count)
    return (New-WinToolHomeResult -Id "drivers" -Status "bad" -Text $text -Action "review" -Penalty $penalty -Detail $detail -Amount $bad.Count)
}

function ConvertTo-WinToolHomeDiskResult {
    # Data: one item per physical disk with Name, MediaType and Health.
    param([object[]]$Data)
    $disks = @(@($Data) | Where-Object { $null -ne $_ })
    if ($disks.Count -eq 0) {
        return (New-WinToolHomeResult -Id "disk" -Status "unknown" -Text (Get-WinToolText "msg.no-drive-reported-its-health"))
    }
    $detail = @($disks | ForEach-Object { "{0}: {1}" -f [string]$_.Name, [string]$_.Health })
    $bad = @($disks | Where-Object { [string]$_.Health -ne "Healthy" })
    if ($bad.Count -eq 0) {
        $text = Get-WinToolText "msg.all-drives-report-healthy"
        if ($disks.Count -eq 1) { $text = Get-WinToolText "msg.the-drive-reports-healthy" }
        return (New-WinToolHomeResult -Id "disk" -Status "ok" -Text $text -Detail $detail)
    }
    $text = Get-WinToolCountText "msg.n-drives-need-attention" $bad.Count
    if ($bad.Count -eq 1) { $text = (Get-WinToolText "msg.drive-reports-health" ([string]$bad[0].Name) ([string]$bad[0].Health)) }
    return (New-WinToolHomeResult -Id "disk" -Status "bad" -Text $text -Action "review" -Penalty 30 -Detail $detail -Amount $bad.Count)
}

function ConvertTo-WinToolHomeResult {
    # Turns one finished check into its row. A failed check shows "Could not check".
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Data,
        [string]$ErrorMessage
    )
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        return (ConvertTo-WinToolHomeErrorResult -Id $Id -Message $ErrorMessage)
    }
    try {
        switch ($Id) {
            "junk" { return (ConvertTo-WinToolHomeJunkResult -Data @($Data)) }
            "tweaks" { return (ConvertTo-WinToolHomeTweakResult -Data @($Data)) }
            "startup" { return (ConvertTo-WinToolHomeStartupResult -Data @($Data)) }
            "drivers" { return (ConvertTo-WinToolHomeDriverResult -Data @($Data)) }
            "disk" { return (ConvertTo-WinToolHomeDiskResult -Data @($Data)) }
        }
    }
    catch {
        return (ConvertTo-WinToolHomeErrorResult -Id $Id -Message $_.Exception.Message)
    }
    throw (Get-WinToolText "msg.unknown-home-check-n" $Id)
}

function Get-WinToolHomeScore {
    param([object[]]$Result)
    $score = 100
    foreach ($item in @($Result)) {
        if ($null -ne $item) { $score -= [int]$item.Penalty }
    }
    return [Math]::Max(0, [Math]::Min(100, $score))
}

function Get-WinToolHomeVerdict {
    param([int]$Score)
    if ($Score -ge 90) { return [pscustomobject]@{ Text = (Get-WinToolText "msg.healthy"); Tone = "ok" } }
    if ($Score -ge 60) { return [pscustomobject]@{ Text = (Get-WinToolText "msg.needs-attention"); Tone = "warn" } }
    return [pscustomobject]@{ Text = (Get-WinToolText "msg.needs-care"); Tone = "bad" }
}

function Get-WinToolHomeLead {
    param([object[]]$Result)
    $items = @(@($Result) | Where-Object { $null -ne $_ })
    $fixable = @($items | Where-Object { $_.Fixable }).Count
    if ($fixable -gt 0) {
        return (Get-WinToolCountText "msg.items-can-be-fixed-nothing-changed" $fixable)
    }
    $needsAttention = @($items | Where-Object {
            $_.Status -eq "warn" -or $_.Status -eq "bad" -or $_.Action -eq "review" -or [int]$_.Penalty -gt 0
        }).Count
    if ($needsAttention -gt 0) {
        return (Get-WinToolText "msg.review-items-that-need-attention-nothing-changed")
    }
    return (Get-WinToolText "msg.nothing-needs-fixing-nothing-was-changed-during-the-anal")
}

function Format-WinToolHomeWhen {
    param(
        [Parameter(Mandatory = $true)][datetime]$Time,
        [datetime]$Now = (Get-Date)
    )
    $clock = $Time.ToString("HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Time.Date -eq $Now.Date) { return (Get-WinToolText "msg.today-at" $clock) }
    if ($Time.Date -eq $Now.Date.AddDays(-1)) { return (Get-WinToolText "msg.yesterday-at" $clock) }
    return ($Time.ToString("MMM d", [System.Globalization.CultureInfo]::InvariantCulture) + " " + $clock)
}

function Format-WinToolHomeMeta {
    param(
        $Last,
        [datetime]$Now = (Get-Date)
    )
    if ($null -eq $Last) {
        return (Get-WinToolText "ui.HomeMetaText.Text")
    }
    $when = Format-WinToolHomeWhen -Time ([datetime]$Last.Time) -Now $Now
    return (Get-WinToolText "msg.last-analysis-score" $when ([int]$Last.Score))
}

function Get-WinToolMemoryTypeName {
    # SMBIOS memory type codes from Win32_PhysicalMemory.
    param([int]$Code)
    switch ($Code) {
        20 { return "DDR" }
        21 { return "DDR2" }
        24 { return "DDR3" }
        26 { return "DDR4" }
        27 { return "LPDDR" }
        28 { return "LPDDR2" }
        29 { return "LPDDR3" }
        30 { return "LPDDR4" }
        34 { return "DDR5" }
        35 { return "LPDDR5" }
    }
    return ""
}

function Format-WinToolCpuName {
    param([string]$Name)
    $text = [string]$Name
    $text = $text -replace '\((R|TM|tm|r)\)', '' -replace '\s+CPU\s+@.*$', '' -replace '\s+\d+-Core Processor.*$', '' -replace '\s+with Radeon.*$', '' -replace '\s+Processor$', ''
    return (($text -replace '\s+', ' ').Trim())
}

function Get-WinToolHomeDiskTone {
    param([double]$FreePercent)
    if ($FreePercent -lt 15) { return "bad" }
    if ($FreePercent -lt 30) { return "warn" }
    return "ok"
}

function Get-WinToolHomeHistoryPath {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { $base = [System.IO.Path]::GetTempPath() }
    return (Join-Path $base "WinTool\home-history.json")
}

function Read-WinToolHomeHistory {
    param([string]$Path = (Get-WinToolHomeHistoryPath))
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $items = @((Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) | ConvertFrom-Json)
        $list = foreach ($item in $items) {
            if ($null -eq $item) { continue }
            [pscustomobject]@{
                Time = [datetime]::Parse([string]$item.Time, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                Score = [int]$item.Score
                Seconds = [int]$item.Seconds
            }
        }
        return @($list)
    }
    catch {
        return @()
    }
}

function Write-WinToolHomeHistoryList {
    param(
        [object[]]$Item,
        [string]$Path = (Get-WinToolHomeHistoryPath)
    )
    $keep = @(@($Item) | Select-Object -Last 20 | ForEach-Object {
            [pscustomobject]@{ Time = ([datetime]$_.Time).ToString("o"); Score = [int]$_.Score; Seconds = [int]$_.Seconds }
        })
    try {
        $folder = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $keep -Depth 3))
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Add-WinToolHomeHistory {
    # Keeps the last 20 analyses in %LOCALAPPDATA%\WinTool\home-history.json.
    param(
        [Parameter(Mandatory = $true)][datetime]$Time,
        [Parameter(Mandatory = $true)][int]$Score,
        [int]$Seconds,
        [string]$Path = (Get-WinToolHomeHistoryPath)
    )
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Read-WinToolHomeHistory -Path $Path)) { $items.Add($item) }
    $items.Add([pscustomobject]@{ Time = $Time; Score = $Score; Seconds = $Seconds })
    Write-WinToolHomeHistoryList -Item $items.ToArray() -Path $Path
}

function Set-WinToolHomeLatestHistory {
    # Updates the latest saved analysis score after a Home fix completes, so
    # the ring, the meta line and the history dialog stay consistent.
    param(
        [Parameter(Mandatory = $true)][int]$Score,
        [string]$Path = (Get-WinToolHomeHistoryPath)
    )
    $items = @(Read-WinToolHomeHistory -Path $Path)
    if ($items.Count -eq 0) { return }
    $items[-1].Score = $Score
    Write-WinToolHomeHistoryList -Item $items -Path $Path
}

function Get-WinToolHomeJunkLocation {
    # The places the junk check measures and the Fix cleans. Temp folders keep
    # anything touched in the last day, so running programs are left alone.
    $windows = $env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($windows)) { $windows = "C:\Windows" }
    $list = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $list.Add([pscustomobject]@{ Id = "temp"; Name = (Get-WinToolText "msg.your-temporary-files"); Path = $env:TEMP; Filter = "*"; Recurse = $true; MinAgeHours = 24 })
    }
    $list.Add([pscustomobject]@{ Id = "wintemp"; Name = (Get-WinToolText "msg.windows-temporary-files"); Path = (Join-Path $windows "Temp"); Filter = "*"; Recurse = $true; MinAgeHours = 24 })
    $list.Add([pscustomobject]@{ Id = "delivery"; Name = (Get-WinToolText "msg.delivery-optimization-cache"); Path = (Join-Path $windows "ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"); Filter = "*"; Recurse = $true; MinAgeHours = 0 })
    $list.Add([pscustomobject]@{ Id = "recycle"; Name = (Get-WinToolText "msg.recycle-bin"); Path = ""; Filter = "*"; Recurse = $true; MinAgeHours = 0 })
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $list.Add([pscustomobject]@{ Id = "thumbs"; Name = (Get-WinToolText "msg.thumbnail-cache"); Path = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"); Filter = "thumbcache_*.db"; Recurse = $false; MinAgeHours = 0 })
    }
    return $list.ToArray()
}

function Get-WinToolHomeCheckScript {
    # The runspace script for one check. Each script gets the shared sync
    # hashtable first, sets Data or Error, and always sets Done.
    param([Parameter(Mandatory = $true)][string]$Id)
    $common = @'
function Test-HomeReparsePoint {
    param($Item)
    if ($null -eq $Item) { return $false }
    try { return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) } catch { return $true }
}

function Test-HomeFileDeletable {
    param($File)
    if ($null -eq $File) { return $false }
    if (Test-HomeReparsePoint -Item $File) { return $false }
    try {
        $access = [System.IO.FileAccess]::ReadWrite
        if (($File.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0) {
            $access = [System.IO.FileAccess]::Read
        }
        $stream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, $access, [System.IO.FileShare]::None)
        $stream.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Get-HomeJunkFile {
    param($Location)
    $roots = @()
    if ($Location.Id -eq "recycle") {
        $sid = $null
        try { $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $sid = $null }
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if ($drive.DriveType -eq "Fixed" -and $drive.IsReady) {
                $bin = Join-Path $drive.RootDirectory.FullName '$Recycle.Bin'
                if (-not [string]::IsNullOrWhiteSpace($sid)) {
                    $userBin = Join-Path $bin $sid
                    if (Test-Path -LiteralPath $userBin) { $roots += $userBin }
                }
                elseif (Test-Path -LiteralPath $bin) {
                    $roots += $bin
                }
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Location.Path)) {
        $roots += [string]$Location.Path
    }
    $cutoff = (Get-Date).AddHours(-1 * [double]$Location.MinAgeHours)
    $filter = [string]$Location.Filter
    if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "*" }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($root)
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            foreach ($file in @(Get-ChildItem -LiteralPath $current -Filter $filter -Force -File -ErrorAction SilentlyContinue)) {
                if (Test-HomeReparsePoint -Item $file) { continue }
                if ($file.Name -eq "desktop.ini") { continue }
                if ($Location.MinAgeHours -gt 0 -and $file.LastWriteTime -gt $cutoff) { continue }
                if (-not (Test-HomeFileDeletable -File $file)) { continue }
                $file
            }
            if ($Location.Recurse) {
                foreach ($dir in @(Get-ChildItem -LiteralPath $current -Force -Directory -ErrorAction SilentlyContinue)) {
                    if (Test-HomeReparsePoint -Item $dir) { continue }
                    $stack.Push($dir.FullName)
                }
            }
        }
    }
}
'@
    $body = switch ($Id) {
        "junk" {
            @'
param($sync, $locations)
try {
    $list = foreach ($location in @($locations)) {
        $sum = [double]0
        foreach ($file in @(Get-HomeJunkFile -Location $location)) { $sum += [double]$file.Length }
        [pscustomobject]@{ Id = [string]$location.Id; Name = [string]$location.Name; Bytes = $sum }
    }
    $sync.Data = @($list)
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "clean" {
            @'
param($sync, $locations)
try {
    $freed = [double]0
    foreach ($location in @($locations)) {
        if ($location.Id -eq "recycle") {
            $before = [double]0
            $files = @(Get-HomeJunkFile -Location $location)
            foreach ($file in $files) { $before += [double]$file.Length }
            try { Clear-RecycleBin -Force -ErrorAction Stop } catch { $null = $_ }
            foreach ($file in @(Get-HomeJunkFile -Location $location)) {
                try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop } catch { $null = $_ }
            }
            $after = [double]0
            foreach ($file in @(Get-HomeJunkFile -Location $location)) { $after += [double]$file.Length }
            if ($before -gt $after) { $freed += ($before - $after) }
            continue
        }
        if ($location.Id -eq "delivery") {
            $before = [double]0
            foreach ($file in @(Get-HomeJunkFile -Location $location)) { $before += [double]$file.Length }
            if ($null -ne (Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
                try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { $null = $_ }
            }
            foreach ($file in @(Get-HomeJunkFile -Location $location)) {
                try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop } catch { $null = $_ }
            }
            $after = [double]0
            foreach ($file in @(Get-HomeJunkFile -Location $location)) { $after += [double]$file.Length }
            if ($before -gt $after) { $freed += ($before - $after) }
            continue
        }
        foreach ($file in @(Get-HomeJunkFile -Location $location)) {
            $size = [double]$file.Length
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $file.FullName)) { $freed += $size }
            }
            catch { $null = $_ }
        }
        if ($location.Recurse -and $location.MinAgeHours -gt 0 -and (Test-Path -LiteralPath $location.Path)) {
            # Empty non-reparse folders left behind in the temp folders.
            $visited = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]
            $dirStack = New-Object System.Collections.Generic.Stack[string]
            $dirStack.Push([string]$location.Path)
            while ($dirStack.Count -gt 0) {
                $currentDir = $dirStack.Pop()
                foreach ($sub in @(Get-ChildItem -LiteralPath $currentDir -Force -Directory -ErrorAction SilentlyContinue)) {
                    if (Test-HomeReparsePoint -Item $sub) { continue }
                    $visited.Add($sub)
                    $dirStack.Push($sub.FullName)
                }
            }
            foreach ($folder in @($visited.ToArray() | Sort-Object { $_.FullName.Length } -Descending)) {
                try {
                    if (@(Get-ChildItem -LiteralPath $folder.FullName -Force -ErrorAction Stop).Count -eq 0) {
                        Remove-Item -LiteralPath $folder.FullName -Force -ErrorAction Stop
                    }
                }
                catch { $null = $_ }
            }
        }
    }
    $sync.Data = $freed
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "tweaks" {
            @'
param($sync, $tweaks)
try {
    $probe = Get-WinToolTweakProbe
    $list = foreach ($tweak in @($tweaks)) {
        $state = "unknown"
        try { $state = Get-WinToolTweakState -Tweak $tweak -Probe $probe } catch { $state = "unknown" }
        [pscustomobject]@{ Id = [string]$tweak.id; Name = [string]$tweak.name; State = [string]$state }
    }
    $sync.Data = @($list)
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "startup" {
            @'
param($sync)
try {
    $approvedRoot = "\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\"
    function Get-Approved($hive, $kind, $name) {
        $path = $hive + ":" + $approvedRoot + $kind
        try {
            $value = (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name
            if ($value -is [byte[]] -and $value.Length -gt 0) { return [int]$value[0] }
        } catch { $null = $_ }
        return -1
    }
    $list = New-Object System.Collections.Generic.List[object]
    $runKeys = @(
        @{ Hive = "HKCU"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Kind = "Run"; Source = "Run, this user" },
        @{ Hive = "HKLM"; Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"; Kind = "Run"; Source = "Run, all users" },
        @{ Hive = "HKLM"; Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Kind = "Run32"; Source = "Run, all users (32-bit)" }
    )
    foreach ($key in $runKeys) {
        if (-not (Test-Path -LiteralPath $key.Path)) { continue }
        $item = Get-Item -LiteralPath $key.Path -ErrorAction SilentlyContinue
        if ($null -eq $item) { continue }
        foreach ($name in @($item.GetValueNames())) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $list.Add([pscustomobject]@{ Name = $name; Source = $key.Source; Approved = (Get-Approved $key.Hive $key.Kind $name) })
        }
    }
    $folders = @(
        @{ Hive = "HKCU"; Path = [Environment]::GetFolderPath("Startup"); Source = "Startup folder" },
        @{ Hive = "HKLM"; Path = [Environment]::GetFolderPath("CommonStartup"); Source = "Startup folder, all users" }
    )
    foreach ($folder in $folders) {
        if ([string]::IsNullOrWhiteSpace($folder.Path) -or -not (Test-Path -LiteralPath $folder.Path)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder.Path -File -Force -ErrorAction SilentlyContinue)) {
            if ($file.Name -eq "desktop.ini") { continue }
            $list.Add([pscustomobject]@{ Name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name); Source = $folder.Source; Approved = (Get-Approved $folder.Hive "StartupFolder" $file.Name) })
        }
    }
    $sync.Data = $list.ToArray()
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "drivers" {
            @'
param($sync)
try {
    $list = @()
    $queried = $false
    try {
        $entities = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter "ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22 AND ConfigManagerErrorCode <> 45" -ErrorAction Stop)
        $queried = $true
        $list = @($entities | ForEach-Object {
                $devName = [string]$_.Name
                if ([string]::IsNullOrWhiteSpace($devName)) { $devName = [string]$_.Caption }
                if ([string]::IsNullOrWhiteSpace($devName)) { $devName = [string]$_.DeviceID }
                [pscustomobject]@{
                    Name = $devName
                    Class = [string]$_.PNPClass
                    Status = "Error"
                    Problem = [int]$_.ConfigManagerErrorCode
                    InstanceId = [string]$_.DeviceID
                }
            })
    }
    catch {
        $queried = $false
    }
    if (-not $queried -and $null -ne (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue)) {
        $list = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { [string]$_.Status -eq "Error" -or [string]$_.Status -eq "Degraded" } | ForEach-Object {
                $devName = [string]$_.FriendlyName
                if ([string]::IsNullOrWhiteSpace($devName)) { $devName = [string]$_.Name }
                if ([string]::IsNullOrWhiteSpace($devName)) { $devName = [string]$_.InstanceId }
                $prob = -1
                if ($null -ne $_.PSObject.Properties["Problem"] -and $null -ne $_.Problem) { $prob = [int]$_.Problem }
                [pscustomobject]@{
                    Name = $devName
                    Class = [string]$_.Class
                    Status = [string]$_.Status
                    Problem = $prob
                    InstanceId = [string]$_.InstanceId
                }
            } | Where-Object { $_.Problem -ne 22 -and $_.Problem -ne 45 })
    }
    $sync.Data = @($list)
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "disk" {
            @'
param($sync)
try {
    $list = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_.FriendlyName; MediaType = [string]$_.MediaType; Health = [string]$_.HealthStatus }
        })
    $sync.Data = @($list)
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "info" {
            @'
param($sync)
$info = @{ Os = ""; Version = ""; Cpu = ""; MemoryTotal = [double]0; MemoryType = 0; DiskSize = [double]0; DiskMedia = "" }
try {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.Os = ([string]$os.Caption -replace '^Microsoft\s+', '').Trim()
        $info.MemoryTotal = [double]$os.TotalVisibleMemorySize * 1KB
    } catch { $null = $_ }
    try { $info.Version = [string](Get-ItemProperty -LiteralPath "HKLM:\Software\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop).DisplayVersion } catch { $null = $_ }
    try { $info.Cpu = [string](@(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)[0].Name) } catch { $null = $_ }
    try {
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        $total = [double]0
        foreach ($module in $modules) { $total += [double]$module.Capacity }
        if ($total -gt 0) { $info.MemoryTotal = $total }
        if ($modules.Count -gt 0) { $info.MemoryType = [int]$modules[0].SMBIOSMemoryType }
    } catch { $null = $_ }
    try {
        $letter = ([string]$env:SystemDrive).TrimEnd(':')
        $info.DiskSize = [double](New-Object System.IO.DriveInfo($letter)).TotalSize
        $number = (Get-Partition -DriveLetter $letter -ErrorAction Stop | Select-Object -First 1).DiskNumber
        $physical = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$number })
        if ($physical.Count -gt 0) {
            $info.DiskMedia = [string]$physical[0].MediaType
            $info.DiskSize = [double]$physical[0].Size
        }
    } catch { $null = $_ }
    $sync.Data = [pscustomobject]$info
    $sync.Ok = $true
}
catch { $sync.Error = $_.Exception.Message }
finally { $sync.Done = $true }
'@
        }
        "sampler" {
            @'
param($sync)
# Samples memory, the Windows drive and processor load for the Home cards.
$letter = ([string]$env:SystemDrive).TrimEnd(':')
while (-not $sync.Stop) {
    if (-not $sync.Paused) {
        $sample = @{ Time = Get-Date; MemoryUsed = -1.0; MemoryTotal = -1.0; DiskFree = -1.0; DiskTotal = -1.0; DiskBusy = -1.0; Cpu = -1.0 }
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $sample.MemoryTotal = [double]$os.TotalVisibleMemorySize * 1KB
            $sample.MemoryUsed = ([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) * 1KB
        } catch { $null = $_ }
        try {
            $drive = New-Object System.IO.DriveInfo($letter)
            $sample.DiskFree = [double]$drive.AvailableFreeSpace
            $sample.DiskTotal = [double]$drive.TotalSize
        } catch { $null = $_ }
        try { $sample.DiskBusy = [Math]::Min(100.0, [double](Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop).PercentDiskTime) } catch { $null = $_ }
        try { $sample.Cpu = [double](Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch { $null = $_ }
        $sync.Queue.Enqueue([pscustomobject]$sample)
    }
    Start-Sleep -Milliseconds 2500
}
$sync.Done = $true
'@
        }
        default { throw (Get-WinToolText "msg.unknown-home-check-n" $Id) }
    }
    # param() has to stay first; the shared helper goes right after it.
    $text = ([string]$body).Trim()
    $split = $text.IndexOf("`n")
    return ($text.Substring(0, $split).TrimEnd() + "`n" + $common + "`n" + $text.Substring($split + 1))
}

function Start-WinToolHomeJob {
    # A background runspace for one check. With -WithWinTool the runspace gets
    # the WinTool functions, so the tweak check reads state the same way as
    # the Tweaks page.
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [object[]]$Argument,
        [switch]$WithWinTool
    )
    $sync = [hashtable]::Synchronized(@{
            Done = $false
            Ok = $false
            Error = $null
            Data = $null
            Stop = $false
            Paused = $false
            Queue = (New-Object System.Collections.Concurrent.ConcurrentQueue[object])
        })
    $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ($WithWinTool) {
        $copyStamp = Get-Date
        foreach ($function in @(Get-ChildItem -Path Function:\ | Where-Object { $_.Name -like "*-WinTool*" })) {
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $function.Name, $function.Definition
            $state.Commands.Add($entry)
        }
        Write-WinToolStartupMark -Name "homeJob.copyFunctions" -Started $copyStamp
    }
    $runspace = [runspacefactory]::CreateRunspace($state)
    $runspace.ApartmentState = "STA"
    $openStamp = Get-Date
    $runspace.Open()
    Write-WinToolStartupMark -Name "homeJob.openRunspace" -Started $openStamp
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript($ScriptText)
    [void]$powershell.AddArgument($sync)
    foreach ($item in @($Argument)) {
        [void]$powershell.AddArgument($item)
    }
    [void]$powershell.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $powershell
        Handle = $null
        Sync = $sync
        Runspace = $runspace
    }
}
