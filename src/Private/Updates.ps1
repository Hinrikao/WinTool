# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Resolve-WinToolGpuVendor {
    param(
        [string]$Name,
        $Vendor
    )
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }
    foreach ($item in @($Vendor)) {
        foreach ($token in @(Get-WinToolNote -Object $item -Name "match" -Default @())) {
            if ($Name.IndexOf([string]$token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $item
            }
        }
    }
    return $null
}

function Get-WinToolGpuInfo {
    if (-not (Test-WinToolWindows)) {
        return @()
    }
    $rows = New-Object System.Collections.Generic.List[object]
    try {
        $items = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
    }
    catch {
        return @()
    }
    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Name)) {
            continue
        }
        $rows.Add([pscustomobject]@{
            Name = [string]$item.Name
            DriverVersion = [string]$item.DriverVersion
        })
    }
    return $rows.ToArray()
}

function Get-WinToolUpdateSearchScript {
    $scriptText = @'
param($Sync, $Criteria)
$ErrorActionPreference = "Stop"
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search($Criteria)
    $lines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        $isDriver = $false
        foreach ($category in @($update.Categories)) {
            if ([string]$category.Name -match "Driver") {
                $isDriver = $true
            }
        }
        $kind = "update"
        if ($isDriver) { $kind = "driver" }
        $title = ([string]$update.Title) -replace "[\r\n\t]", " "
        $lines.Add($kind + "`t" + $title)
    }
    $Sync.Lines = $lines.ToArray()
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

function Get-WinToolUpdateInstallScript {
    $scriptText = @'
param($Sync, $Criteria, $TitleText)
$ErrorActionPreference = "Stop"
try {
    $wanted = @{}
    foreach ($title in @(([string]$TitleText) -split "`n")) {
        if (-not [string]::IsNullOrWhiteSpace([string]$title)) {
            $wanted[[string]$title] = $true
        }
    }
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search($Criteria)
    $toInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        if ($wanted.ContainsKey([string]$update.Title)) {
            if (-not $update.EulaAccepted) {
                $update.EulaAccepted = $true
            }
            [void]$toInstall.Add($update)
        }
    }
    if ($toInstall.Count -eq 0) {
        $Sync.Ok = $true
        $Sync.Count = 0
        $Sync.Reboot = $false
        $Sync.Done = $true
        return
    }
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    [void]$downloader.Download()
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $toInstall
    $installResult = $installer.Install()
    $Sync.Ok = $true
    $Sync.Count = [int]$toInstall.Count
    $Sync.Reboot = [bool]$installResult.RebootRequired
    $Sync.ResultCode = [int]$installResult.ResultCode
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Open-WinToolUri {
    param(
        [Parameter(Mandatory = $true)][string]$Uri
    )
    if ($Uri -notmatch '^(https://|ms-settings:)') {
        Write-WinToolLog -Message (Get-WinToolText "msg.blocked-unexpected-link-n" $Uri) -Level "warn"
        return
    }
    try {
        Start-Process -FilePath $Uri | Out-Null
    }
    catch {
        Write-WinToolLog -Message (Get-WinToolText "msg.could-not-open-n-n" $Uri $_.Exception.Message) -Level "warn"
    }
}
