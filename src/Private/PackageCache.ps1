# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# Cached view of what is already on the PC: winget packages (from the
# Install view's background export), modules in the usual 5.1 and pwsh
# folders, fonts from the resolver map, and saved Oh My Posh themes.
# The Terminal click path only reads this cache.

$script:WinToolPackageCache = $null
$script:WinToolConfigNeedCache = $null
$script:WinToolMinimumModuleVersion = @{
    "PSReadLine" = "2.2.0"
}

function New-WinToolIdSet {
    param(
        [string[]]$Id = @()
    )
    $set = @{}
    foreach ($item in @($Id)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $set[$item.ToLowerInvariant()] = $true
    }
    return $set
}

function New-WinToolPackageCache {
    return [pscustomobject]@{
        WingetReady = $false
        InstalledId = (New-WinToolIdSet)
        UpdateId    = (New-WinToolIdSet)
        Module      = @{}
        Theme       = @{}
        Font        = @{}
    }
}

function Get-WinToolPackageCache {
    if ($null -eq $script:WinToolPackageCache) {
        $script:WinToolPackageCache = New-WinToolPackageCache
    }
    return $script:WinToolPackageCache
}

function Reset-WinToolPackageCache {
    $script:WinToolPackageCache = New-WinToolPackageCache
    $script:WinToolConfigNeedCache = $null
    return $script:WinToolPackageCache
}

function Set-WinToolWingetPackageCache {
    param(
        [string[]]$InstalledId = @(),
        [string[]]$UpdateId = @()
    )
    $cache = Get-WinToolPackageCache
    $cache.InstalledId = New-WinToolIdSet -Id $InstalledId
    $cache.UpdateId = New-WinToolIdSet -Id $UpdateId
    $cache.WingetReady = $true
    return $cache
}

function Get-WinToolDefaultModuleRoot {
    $roots = New-Object System.Collections.Generic.List[object]
    $docs = [Environment]::GetFolderPath("MyDocuments")
    if (-not [string]::IsNullOrWhiteSpace($docs)) {
        $roots.Add([pscustomobject]@{ Host = "powershell"; Path = (Join-Path $docs "WindowsPowerShell\Modules") }) | Out-Null
        $roots.Add([pscustomobject]@{ Host = "pwsh"; Path = (Join-Path $docs "PowerShell\Modules") }) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $roots.Add([pscustomobject]@{ Host = "powershell"; Path = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\Modules") }) | Out-Null
        $roots.Add([pscustomobject]@{ Host = "powershell"; Path = (Join-Path $env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\Modules") }) | Out-Null
    }
    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $roots.Add([pscustomobject]@{ Host = "powershell"; Path = (Join-Path $programFiles "WindowsPowerShell\Modules") }) | Out-Null
        $roots.Add([pscustomobject]@{ Host = "pwsh"; Path = (Join-Path $programFiles "PowerShell\7\Modules") }) | Out-Null
        $roots.Add([pscustomobject]@{ Host = "pwsh"; Path = (Join-Path $programFiles "PowerShell\Modules") }) | Out-Null
    }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $roots.Add([pscustomobject]@{ Host = "powershell"; Path = (Join-Path $programFilesX86 "WindowsPowerShell\Modules") }) | Out-Null
    }
    return $roots.ToArray()
}

function ConvertTo-WinToolModuleVersion {
    param(
        [string]$Text
    )
    $raw = [string]$Text
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [version]"0.0.0"
    }
    $trimmed = $raw.Trim().Trim("'", '"')
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($piece in @($trimmed.Split("."))) {
        if ($piece -match '^[0-9]+$') {
            $parts.Add($piece) | Out-Null
        }
        else {
            break
        }
    }
    if ($parts.Count -eq 0) {
        return [version]"0.0.0"
    }
    while ($parts.Count -lt 2) {
        $parts.Add("0") | Out-Null
    }
    try {
        return [version]($parts.ToArray() -join ".")
    }
    catch {
        return [version]"0.0.0"
    }
}

function Get-WinToolModuleFolderVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    $highest = [version]"0.0.0"
    $found = $false
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $manifests = @(Get-ChildItem -LiteralPath $Path -Filter "*.psd1" -File -ErrorAction SilentlyContinue)
    if ($manifests.Count -eq 0) {
        $manifests = @(Get-ChildItem -LiteralPath $Path -Filter "*.psd1" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue)
    }
    foreach ($manifest in $manifests) {
        $found = $true
        try {
            $text = [System.IO.File]::ReadAllText($manifest.FullName)
            if ($text -match "(?im)ModuleVersion\s*=\s*['`"]?([0-9][0-9.]*)") {
                $version = ConvertTo-WinToolModuleVersion -Text $Matches[1]
                if ($version -gt $highest) { $highest = $version }
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    $children = @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        $version = ConvertTo-WinToolModuleVersion -Text $child.Name
        if ($version -gt [version]"0.0.0") {
            $found = $true
            if ($version -gt $highest) { $highest = $version }
        }
        $scriptFiles = @(Get-ChildItem -LiteralPath $child.FullName -Include "*.psd1", "*.psm1" -File -ErrorAction SilentlyContinue)
        if ($scriptFiles.Count -gt 0) {
            $found = $true
        }
    }
    $rootScripts = @(Get-ChildItem -LiteralPath $Path -Include "*.psm1", "*.psd1" -File -ErrorAction SilentlyContinue)
    if ($rootScripts.Count -gt 0) {
        $found = $true
    }
    if (-not $found) {
        return $null
    }
    return $highest
}

function Get-WinToolModuleCacheKey {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$HostName
    )
    return ($HostName.ToLowerInvariant() + "|" + $Name.ToLowerInvariant())
}

function Update-WinToolLocalPackageCache {
    param(
        [object[]]$ModuleRoot,
        [string]$ThemeFolder
    )
    $cache = Get-WinToolPackageCache
    $roots = @($ModuleRoot)
    if ($roots.Count -eq 0) {
        $roots = @(Get-WinToolDefaultModuleRoot)
    }
    $modules = @{}
    foreach ($root in $roots) {
        $hostName = [string](Get-WinToolNote -Object $root -Name "Host" -Default "powershell")
        $path = [string](Get-WinToolNote -Object $root -Name "Path" -Default "")
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            continue
        }
        $folders = @(Get-ChildItem -LiteralPath $path -Directory -ErrorAction SilentlyContinue)
        foreach ($folder in $folders) {
            $version = Get-WinToolModuleFolderVersion -Path $folder.FullName
            if ($null -eq $version) { continue }
            $key = Get-WinToolModuleCacheKey -Name $folder.Name -HostName $hostName
            if ($modules.ContainsKey($key)) {
                $current = ConvertTo-WinToolModuleVersion -Text ([string]$modules[$key])
                if ($version -gt $current) {
                    $modules[$key] = [string]$version
                }
            }
            else {
                $modules[$key] = [string]$version
            }
        }
    }
    $cache.Module = $modules

    $themes = @{}
    $themePath = $ThemeFolder
    if ([string]::IsNullOrWhiteSpace($themePath) -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $themePath = Join-Path $env:LOCALAPPDATA "WinTool\themes"
    }
    if (-not [string]::IsNullOrWhiteSpace($themePath) -and (Test-Path -LiteralPath $themePath)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $themePath -File -ErrorAction SilentlyContinue)) {
            $themes[$file.Name.ToLowerInvariant()] = $true
        }
    }
    $cache.Theme = $themes
    $script:WinToolConfigNeedCache = $null
    return $cache
}

function Test-WinToolCachedWingetId {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Cache
    )
    if ($null -eq $Cache -or -not [bool]$Cache.WingetReady) {
        return $false
    }
    return $Cache.InstalledId.ContainsKey($Id.ToLowerInvariant())
}

function Test-WinToolCachedWingetUpgrade {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Cache
    )
    if ($null -eq $Cache -or -not [bool]$Cache.WingetReady) {
        return $false
    }
    return $Cache.UpdateId.ContainsKey($Id.ToLowerInvariant())
}

function Test-WinToolCachedModule {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$HostName = "powershell",
        $Cache,
        [string]$MinimumVersion
    )
    if ($null -eq $Cache) {
        $Cache = Get-WinToolPackageCache
    }
    $key = Get-WinToolModuleCacheKey -Name $Name -HostName $HostName
    if (-not $Cache.Module.ContainsKey($key)) {
        return $false
    }
    $minimum = $MinimumVersion
    if ([string]::IsNullOrWhiteSpace($minimum) -and $script:WinToolMinimumModuleVersion.ContainsKey($Name)) {
        $minimum = [string]$script:WinToolMinimumModuleVersion[$Name]
    }
    if ([string]::IsNullOrWhiteSpace($minimum)) {
        return $true
    }
    $have = ConvertTo-WinToolModuleVersion -Text ([string]$Cache.Module[$key])
    $need = ConvertTo-WinToolModuleVersion -Text $minimum
    return ($have -ge $need)
}

function Test-WinToolCachedTheme {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        $Cache
    )
    if ($null -eq $Cache) {
        $Cache = Get-WinToolPackageCache
    }
    if ($null -eq $Cache.Theme) {
        return $false
    }
    return $Cache.Theme.ContainsKey($FileName.ToLowerInvariant())
}

function Test-WinToolCachedFont {
    param(
        [string]$FontId,
        [string]$Face,
        $Cache
    )
    if ($null -ne $Cache -and $null -ne $Cache.Font) {
        if (-not [string]::IsNullOrWhiteSpace($FontId) -and $Cache.Font.ContainsKey($FontId.ToLowerInvariant())) {
            return [bool]$Cache.Font[$FontId.ToLowerInvariant()]
        }
        if (-not [string]::IsNullOrWhiteSpace($Face) -and $Cache.Font.ContainsKey($Face.ToLowerInvariant())) {
            return [bool]$Cache.Font[$Face.ToLowerInvariant()]
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($FontId)) {
        try {
            return [bool](Test-WinToolFontResolve -FontId $FontId)
        }
        catch {
            return $false
        }
    }
    return $false
}

function Get-WinToolStepPackageId {
    param($Step)
    $id = [string](Get-WinToolNote -Object $Step -Name "Id" -Default "")
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = [string](Get-WinToolNote -Object $Step -Name "WingetId" -Default "")
    }
    return $id
}

function Get-WinToolStepChipName {
    param($Step)
    $type = [string]$Step.Type
    $label = [string]$Step.Label
    if ($type -eq "winget" -or $type -eq "font-download") {
        if ($label -match '^(Install|Download|Upgrade|Update)\s+(.+)$') {
            return $Matches[2]
        }
        return $label
    }
    if ($type -eq "module") {
        if ($label -match '^(Install|Update)\s+') {
            return ($label -replace '^(Install|Update)\s+', '')
        }
        return $label
    }
    if ($type -eq "font") {
        $text = "Terminal font"
        if ($null -ne $Step.PSObject.Properties["Size"] -and [int]$Step.Size -ne 12) {
            $text += " " + [int]$Step.Size + " pt"
        }
        return $text
    }
    if ($type -eq "ligatures") { return (Get-WinToolText "msg.font-ligatures-on") }
    if ($type -eq "scheme") { return ($label -replace '^Set the Windows Terminal color scheme to ', 'Scheme ') }
    if ($type -eq "banner") {
        if ([bool](Get-WinToolNote -Object $Step -Name "Undo" -Default $false)) { return (Get-WinToolText "msg.startup-banner-shown") }
        return (Get-WinToolText "msg.startup-banner-hidden")
    }
    if ($type -eq "profile") { return (Get-WinToolText "msg.powershell-profile") }
    if ($type -eq "starship-preset") { return $label }
    return $label
}

function Get-WinToolPlanStepDecision {
    param(
        [Parameter(Mandatory = $true)]$Step,
        $Cache,
        [switch]$Update
    )
    if ($null -eq $Cache) {
        $Cache = Get-WinToolPackageCache
    }
    $type = [string]$Step.Type
    if ($type -eq "winget") {
        $id = Get-WinToolStepPackageId -Step $Step
        $ready = [bool]$Cache.WingetReady
        $present = $false
        if ($ready -and -not [string]::IsNullOrWhiteSpace($id)) {
            $present = Test-WinToolCachedWingetId -Id $id -Cache $Cache
        }
        if ($ready -and $present) {
            if ($Update) {
                $upgradable = Test-WinToolCachedWingetUpgrade -Id $id -Cache $Cache
                if ($upgradable) {
                    return [pscustomobject]@{ Run = $true; Action = "upgrade"; Outcome = "update"; Reason = "upgrade available" }
                }
                return [pscustomobject]@{ Run = $false; Action = "install"; Outcome = "already-had"; Reason = "already installed" }
            }
            return [pscustomobject]@{ Run = $false; Action = "install"; Outcome = "already-had"; Reason = "already installed" }
        }
        return [pscustomobject]@{ Run = $true; Action = "install"; Outcome = "install"; Reason = "missing" }
    }
    if ($type -eq "font-download") {
        $fontId = [string](Get-WinToolNote -Object $Step -Name "FontId" -Default "")
        $face = [string](Get-WinToolNote -Object $Step -Name "Face" -Default "")
        if (Test-WinToolCachedFont -FontId $fontId -Face $face -Cache $Cache) {
            return [pscustomobject]@{ Run = $false; Action = ""; Outcome = "already-had"; Reason = "font installed" }
        }
        return [pscustomobject]@{ Run = $true; Action = ""; Outcome = "install"; Reason = "missing" }
    }
    if ($type -eq "module") {
        $name = [string](Get-WinToolNote -Object $Step -Name "Name" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string](Get-WinToolNote -Object $Step -Name "Module" -Default "")
        }
        if ([string]::IsNullOrWhiteSpace($name) -and [string]$Step.Label -match '^(Install|Update) (.+?) for ') {
            $name = $Matches[2]
        }
        $hostName = [string](Get-WinToolNote -Object $Step -Name "Host" -Default "powershell")
        if (Test-WinToolCachedModule -Name $name -HostName $hostName -Cache $Cache) {
            if ($Update) {
                return [pscustomobject]@{ Run = $true; Action = ""; Outcome = "update"; Reason = "update module" }
            }
            return [pscustomobject]@{ Run = $false; Action = ""; Outcome = "already-had"; Reason = "module installed" }
        }
        return [pscustomobject]@{ Run = $true; Action = ""; Outcome = "install"; Reason = "missing" }
    }
    if ($type -eq "profile") {
        return [pscustomobject]@{ Run = $true; Action = ""; Outcome = "config"; Reason = "profile"; RefreshTheme = [bool]$Update }
    }
    return [pscustomobject]@{ Run = $true; Action = ""; Outcome = "config"; Reason = $type; RefreshTheme = $false }
}

function New-WinToolPlanTally {
    return [pscustomobject]@{
        Installed       = New-Object System.Collections.Generic.List[string]
        AlreadyHad      = New-Object System.Collections.Generic.List[string]
        Updated         = New-Object System.Collections.Generic.List[string]
        ConfigChanged   = New-Object System.Collections.Generic.List[string]
        ConfigUnchanged = New-Object System.Collections.Generic.List[string]
        Failed          = New-Object System.Collections.Generic.List[string]
    }
}

function Add-WinToolPlanTally {
    param(
        [Parameter(Mandatory = $true)]$Tally,
        [Parameter(Mandatory = $true)][string]$Bucket,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $target = $null
    switch ($Bucket) {
        "Installed" { $target = $Tally.Installed }
        "AlreadyHad" { $target = $Tally.AlreadyHad }
        "Updated" { $target = $Tally.Updated }
        "ConfigChanged" { $target = $Tally.ConfigChanged }
        "ConfigUnchanged" { $target = $Tally.ConfigUnchanged }
        "Failed" { $target = $Tally.Failed }
        default { return }
    }
    if ($target.Contains($Name)) {
        return
    }
    $target.Add($Name) | Out-Null
}

function Join-WinToolNameList {
    param(
        [string[]]$Name
    )
    $items = @($Name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) { return "" }
    if ($items.Count -eq 1) { return [string]$items[0] }
    if ($items.Count -eq 2) { return ([string]$items[0] + " and " + [string]$items[1]) }
    $head = $items[0..($items.Count - 2)] -join ", "
    return ($head + ", and " + [string]$items[$items.Count - 1])
}

function Format-WinToolPlanSummary {
    param(
        [Parameter(Mandatory = $true)]$Tally
    )
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Tally.Installed.Count -gt 0) {
        $parts.Add("Installed " + (Join-WinToolNameList -Name $Tally.Installed.ToArray()) + ".") | Out-Null
    }
    if ($Tally.AlreadyHad.Count -gt 0) {
        $parts.Add("Already had " + (Join-WinToolNameList -Name $Tally.AlreadyHad.ToArray()) + ".") | Out-Null
    }
    if ($Tally.Updated.Count -gt 0) {
        $parts.Add("Updated " + (Join-WinToolNameList -Name $Tally.Updated.ToArray()) + ".") | Out-Null
    }
    if ($Tally.ConfigChanged.Count -gt 0) {
        $parts.Add("Updated settings: " + (Join-WinToolNameList -Name $Tally.ConfigChanged.ToArray()) + ".") | Out-Null
    }
    if ($Tally.ConfigUnchanged.Count -gt 0) {
        $parts.Add("Already set " + (Join-WinToolNameList -Name $Tally.ConfigUnchanged.ToArray()) + ".") | Out-Null
    }
    if ($Tally.Failed.Count -gt 0) {
        $parts.Add("Failed: " + (Join-WinToolNameList -Name $Tally.Failed.ToArray()) + ".") | Out-Null
    }
    if ($parts.Count -eq 0) {
        return (Get-WinToolText "msg.nothing-to-do")
    }
    return ($parts.ToArray() -join " ")
}

function Get-WinToolOutcomeBucket {
    param(
        [string]$Outcome
    )
    switch ($Outcome) {
        "install" { return "Installed" }
        "already-had" { return "AlreadyHad" }
        "update" { return "Updated" }
        "config-changed" { return "ConfigChanged" }
        "config-unchanged" { return "ConfigUnchanged" }
        "failed" { return "Failed" }
        default { return "" }
    }
}

function Select-WinToolInstallApp {
    param(
        $App,
        [bool]$Detected
    )
    $pending = New-Object System.Collections.Generic.List[object]
    $already = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($App)) {
        $installed = $false
        if ($Detected) {
            $installed = [bool](Get-WinToolNote -Object $item -Name "Installed" -Default $false)
        }
        if ($installed) {
            $already.Add($item) | Out-Null
        }
        else {
            $pending.Add($item) | Out-Null
        }
    }
    return [pscustomobject]@{
        Pending = $pending.ToArray()
        Already = $already.ToArray()
    }
}

function Test-WinToolSettingsFontMatch {
    param(
        $Settings,
        [string]$Face,
        [int]$Size
    )
    $profiles = Get-WinToolNote -Object $Settings -Name "profiles"
    $defaults = Get-WinToolNote -Object $profiles -Name "defaults"
    $font = Get-WinToolNote -Object $defaults -Name "font"
    $currentFace = [string](Get-WinToolNote -Object $font -Name "face" -Default (Get-WinToolNote -Object $defaults -Name "fontFace" -Default ""))
    $currentSize = Get-WinToolNote -Object $font -Name "size"
    if ([string]$currentFace -ne [string]$Face) {
        return $false
    }
    if ($null -eq $currentSize) {
        return ($Size -eq 12)
    }
    return ([int]$currentSize -eq [int]$Size)
}

function Test-WinToolFontFeatureEnabled {
    param($Font)
    $features = Get-WinToolNote -Object $Font -Name "features"
    if ($null -eq $features) { return $false }
    foreach ($key in $script:WinToolLigatureFeatures.Keys) {
        $value = Get-WinToolNote -Object $features -Name $key
        if ($null -eq $value -or [int]$value -ne [int]$script:WinToolLigatureFeatures[$key]) {
            return $false
        }
    }
    return $true
}

function Test-WinToolSettingsLigatureMatch {
    param($Settings)
    $profiles = Get-WinToolNote -Object $Settings -Name "profiles"
    $defaults = Get-WinToolNote -Object $profiles -Name "defaults"
    $font = Get-WinToolNote -Object $defaults -Name "font"
    if (-not (Test-WinToolFontFeatureEnabled -Font $font)) {
        return $false
    }
    foreach ($item in @(Get-WinToolNote -Object $profiles -Name "list" -Default @())) {
        if ($null -eq $item) { continue }
        $own = Get-WinToolNote -Object $item -Name "font"
        if ($null -eq $own -or $null -eq (Get-WinToolNote -Object $own -Name "features")) { continue }
        if (-not (Test-WinToolFontFeatureEnabled -Font $own)) {
            return $false
        }
    }
    return $true
}

function Test-WinToolSettingsSchemeMatch {
    param(
        $Settings,
        $Scheme
    )
    $fields = Get-WinToolJsoncSchemeEntry -Scheme $Scheme
    $profiles = Get-WinToolNote -Object $Settings -Name "profiles"
    $defaults = Get-WinToolNote -Object $profiles -Name "defaults"
    $current = [string](Get-WinToolNote -Object $defaults -Name "colorScheme" -Default "")
    if ($current -ne [string]$fields.name) {
        return $false
    }
    $entries = @(Get-WinToolNote -Object $Settings -Name "schemes" -Default @())
    foreach ($entry in $entries) {
        if ([string](Get-WinToolNote -Object $entry -Name "name" -Default "") -ne [string]$fields.name) {
            continue
        }
        foreach ($key in $fields.Keys) {
            if ([string](Get-WinToolNote -Object $entry -Name $key -Default "") -ne [string]$fields[$key]) {
                return $false
            }
        }
        return $true
    }
    return $false
}

function Test-WinToolTextNeedsManagedBlock {
    param(
        [string]$Text,
        [string]$Body
    )
    $updated = Update-WinToolManagedBlock -Text $Text -Begin $script:WinToolProfileBegin -End $script:WinToolProfileEnd -Body $Body
    return ($updated -ne $Text)
}

function Get-WinToolTerminalConfigNeed {
    param(
        $Selection,
        [string[]]$SettingsPath,
        [string[]]$ProfilePath,
        [bool]$SkipRead
    )
    $need = @{
        font      = $true
        ligatures = $true
        scheme    = $true
        banner    = $true
        profile   = $true
    }
    if ($SkipRead) {
        return $need
    }
    $paths = @($SettingsPath)
    if ($paths.Count -eq 0) {
        try { $paths = @(Get-WinToolTerminalSettingsPathList) } catch { $paths = @() }
    }
    $face = ""
    $size = 12
    $schemeId = ""
    $hideBanner = $true
    if ($null -ne $Selection) {
        $face = [string](Get-WinToolNote -Object $Selection -Name "fontFace" -Default (Get-WinToolNote -Object $Selection -Name "Face" -Default ""))
        if ([string]::IsNullOrWhiteSpace($face)) {
            $fontId = [string](Get-WinToolNote -Object $Selection -Name "fontId" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($fontId)) {
                try {
                    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "fonts" -Default @())) {
                        if ([string]$item.id -eq $fontId) {
                            $face = [string]$item.face
                            break
                        }
                    }
                }
                catch {
                    $face = $face
                }
            }
        }
        $sizeValue = Get-WinToolNote -Object $Selection -Name "fontSize"
        if ($null -ne $sizeValue) { $size = [int]$sizeValue }
        $schemeId = [string](Get-WinToolNote -Object $Selection -Name "schemeId" -Default "")
        $hideValue = Get-WinToolNote -Object $Selection -Name "hideStartupBanner"
        if ($null -ne $hideValue) { $hideBanner = [bool]$hideValue }
    }
    if ($paths.Count -eq 0) {
        return $need
    }
    $fontNeed = $false
    $ligatureNeed = $false
    $schemeNeed = $false
    $scheme = $null
    if (-not [string]::IsNullOrWhiteSpace($schemeId)) {
        try {
            foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
                if ([string]$item.id -eq $schemeId) { $scheme = $item; break }
            }
        }
        catch {
            $scheme = $null
        }
    }
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            $fontNeed = $true
            $ligatureNeed = $true
            $schemeNeed = $true
            continue
        }
        try {
            $raw = [System.IO.File]::ReadAllText($path)
            $settings = ConvertFrom-WinToolJsonText -Text $raw
        }
        catch {
            $fontNeed = $true
            $ligatureNeed = $true
            $schemeNeed = $true
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($face) -and -not (Test-WinToolSettingsFontMatch -Settings $settings -Face $face -Size $size)) {
            $fontNeed = $true
        }
        if (-not (Test-WinToolSettingsLigatureMatch -Settings $settings)) {
            $ligatureNeed = $true
        }
        if ($null -ne $scheme -and -not (Test-WinToolSettingsSchemeMatch -Settings $settings -Scheme $scheme)) {
            $schemeNeed = $true
        }
    }
    $need.font = $fontNeed
    $need.ligatures = $ligatureNeed
    $need.scheme = $schemeNeed
    # Banner and profile stay "needed" unless a later check proves otherwise.
    # Banner apply is already a no-op when nothing would change; the chip
    # still shows a change until that file walk is cheap enough to cache.
    $profiles = @($ProfilePath)
    if ($profiles.Count -eq 0) {
        try {
            $profiles = @(
                (Get-WinToolShellProfilePath -HostName "powershell"),
                (Get-WinToolShellProfilePath -HostName "pwsh")
            )
        }
        catch {
            $profiles = @()
        }
    }
    if ($profiles.Count -gt 0 -and $null -ne $Selection) {
        try {
            $body = Get-WinToolPromptScript -PromptId ([string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "")) -TerminalIcons ([bool](Get-WinToolNote -Object $Selection -Name "terminalIcons" -Default $false)) -PromptStyle ([string](Get-WinToolNote -Object $Selection -Name "promptStyle" -Default "")) -PsReadLine ([bool](Get-WinToolNote -Object $Selection -Name "psReadLine" -Default $false)) -Zoxide ([bool](Get-WinToolNote -Object $Selection -Name "zoxide" -Default $false))
            $profileNeed = $false
            foreach ($path in $profiles) {
                $existing = ""
                if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
                    $existing = [System.IO.File]::ReadAllText($path)
                }
                if (Test-WinToolTextNeedsManagedBlock -Text $existing -Body $body) {
                    $profileNeed = $true
                }
            }
            $need.profile = $profileNeed
        }
        catch {
            $need.profile = $true
        }
    }
    $null = $hideBanner
    return $need
}

function Get-WinToolCachedConfigNeed {
    param($Selection)
    $key = ""
    if ($null -ne $Selection) {
        $key = ([string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "promptStyle" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "fontFace" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "fontSize" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "schemeId" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "terminalIcons" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "psReadLine" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "zoxide" -Default "") + "|" + [string](Get-WinToolNote -Object $Selection -Name "hideStartupBanner" -Default ""))
    }
    $stamp = $key
    try {
        foreach ($path in @(Get-WinToolTerminalSettingsPathList)) {
            if (Test-Path -LiteralPath $path) {
                $stamp += "|" + $path + ":" + [string](Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
            }
        }
    }
    catch {
        $stamp += "|settings"
    }
    if ($null -ne $script:WinToolConfigNeedCache -and [string]$script:WinToolConfigNeedCache.Stamp -eq $stamp) {
        return $script:WinToolConfigNeedCache.Need
    }
    $need = Get-WinToolTerminalConfigNeed -Selection $Selection
    $script:WinToolConfigNeedCache = [pscustomobject]@{ Stamp = $stamp; Need = $need }
    return $need
}


function Set-WinToolPlanStepDecision {
    param(
        [Parameter(Mandatory = $true)]$Step,
        $Cache,
        [switch]$Update
    )
    $decision = Get-WinToolPlanStepDecision -Step $Step -Cache $Cache -Update:$Update
    if ([bool](Get-WinToolNote -Object $decision -Name "RefreshTheme" -Default $false)) {
        $Step | Add-Member -NotePropertyName "RefreshTheme" -NotePropertyValue $true -Force
    }
    if ([string](Get-WinToolNote -Object $decision -Name "Action" -Default "") -eq "upgrade") {
        $Step | Add-Member -NotePropertyName "Action" -NotePropertyValue "upgrade" -Force
    }
    return $decision
}

function Add-WinToolPlanStepOutcome {
    param(
        [Parameter(Mandatory = $true)]$Tally,
        [Parameter(Mandatory = $true)]$Step,
        [string]$Outcome
    )
    $bucket = Get-WinToolOutcomeBucket -Outcome $Outcome
    if ([string]::IsNullOrWhiteSpace($bucket)) {
        return
    }
    Add-WinToolPlanTally -Tally $Tally -Bucket $bucket -Name (Get-WinToolStepChipName -Step $Step)
}


function Get-WinToolTerminalWingetId {
    $ids = New-Object System.Collections.Generic.List[string]
    try {
        $catalog = Get-WinToolTerminalCatalog
        $components = Get-WinToolNote -Object $catalog -Name "components"
        foreach ($name in @("windowsTerminal", "powerShell")) {
            $id = [string](Get-WinToolNote -Object $components -Name $name -Default "")
            if (-not [string]::IsNullOrWhiteSpace($id)) { $ids.Add($id) | Out-Null }
        }
        foreach ($prompt in @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @())) {
            $id = [string](Get-WinToolNote -Object $prompt -Name "wingetId" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($id)) { $ids.Add($id) | Out-Null }
        }
        foreach ($extra in @(Get-WinToolNote -Object $catalog -Name "extras" -Default @())) {
            $id = [string](Get-WinToolNote -Object $extra -Name "wingetId" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($id)) { $ids.Add($id) | Out-Null }
        }
        foreach ($font in @(Get-WinToolNote -Object $catalog -Name "fonts" -Default @())) {
            $id = [string](Get-WinToolNote -Object $font -Name "wingetId" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($id)) { $ids.Add($id) | Out-Null }
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    return $ids.ToArray()
}
