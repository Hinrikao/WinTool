# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

# English source of truth: data/i18n/en.json. Generated locales are overlaid
# at startup. Callers use Get-WinToolText / Get-WinToolCountText.

$script:WinToolShippedLanguages = @(
    "en", "pt-BR", "es", "fr", "de", "it", "ja", "ko",
    "zh-Hans", "zh-Hant", "pl", "nl", "ru", "tr"
)


# Display-language tags that should resolve to a shipped locale before the
# generic parent walk (zh-CN is not a parent of zh-Hans).
$script:WinToolCultureAliases = @{
    "zh-CN" = "zh-Hans"
    "zh-SG" = "zh-Hans"
    "zh-Hans-CN" = "zh-Hans"
    "zh-TW" = "zh-Hant"
    "zh-HK" = "zh-Hant"
    "zh-MO" = "zh-Hant"
    "zh-Hant-TW" = "zh-Hant"
    "pt-PT" = "pt-BR"
    "pt"    = "pt-BR"
}

function Get-WinToolPreferencePath {
    if (-not [string]::IsNullOrWhiteSpace($script:WinToolPreferencesPath)) {
        return $script:WinToolPreferencesPath
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $null
    }
    return (Join-Path $env:LOCALAPPDATA "WinTool\preferences.json")
}

function Get-WinToolPreference {
    $path = Get-WinToolPreferencePath
    $prefs = [pscustomobject]@{
        schemaVersion = 1
        language = "auto"
        modernHostOfferDismissed = $false
    }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        return $prefs
    }
    try {
        $loaded = ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($path))
        $language = [string](Get-WinToolNote -Object $loaded -Name "language" -Default "auto")
        if ([string]::IsNullOrWhiteSpace($language)) {
            $language = "auto"
        }
        $prefs.language = $language
        $dismissed = Get-WinToolNote -Object $loaded -Name "modernHostOfferDismissed" -Default $false
        $prefs.modernHostOfferDismissed = [bool]($dismissed -eq $true -or [string]$dismissed -eq "True" -or [string]$dismissed -eq "1")
    }
    catch {
        $null = $_.Exception.Message
    }
    return $prefs
}

function Save-WinToolPreference {
    param(
        [Parameter(Mandatory = $true)]$Preferences
    )
    $path = Get-WinToolPreferencePath
    if ([string]::IsNullOrWhiteSpace($path)) {
        return
    }
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $dismissed = Get-WinToolNote -Object $Preferences -Name "modernHostOfferDismissed" -Default $false
    $payload = [pscustomobject]@{
        schemaVersion = 1
        language = [string](Get-WinToolNote -Object $Preferences -Name "language" -Default "auto")
        modernHostOfferDismissed = [bool]($dismissed -eq $true -or [string]$dismissed -eq "True" -or [string]$dismissed -eq "1")
    }
    Write-WinToolJsonFile -Path $path -Value $payload
}

function Test-WinToolLocaleAvailable {
    param([Parameter(Mandatory = $true)][string]$Code)
    if ($Code -eq "en") {
        return $true
    }
    $embedded = $script:WinToolEmbedded
    $key = "Locales:" + $Code
    if ($null -ne $embedded -and $embedded.ContainsKey($key)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
        return $false
    }
    $generated = Join-Path $script:WinToolRoot ("data/i18n/generated/" + $Code + ".json")
    $override = Join-Path $script:WinToolRoot ("data/i18n/overrides/" + $Code + ".json")
    return (Test-Path -LiteralPath $generated) -or (Test-Path -LiteralPath $override)
}

function Read-WinToolLocaleObject {
    param([Parameter(Mandatory = $true)][string]$Code)
    $embedded = $script:WinToolEmbedded
    $key = "Locales:" + $Code
    if ($null -ne $embedded -and $embedded.ContainsKey($key)) {
        return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name $key))
    }

    if ([string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
        if ($Code -eq "en") {
            throw "WinTool locale files are not embedded and no source folder is set."
        }
        return $null
    }

    $root = Join-Path $script:WinToolRoot "data/i18n"
    if ($Code -eq "en") {
        $enPath = Join-Path $root "en.json"
        return (ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($enPath)))
    }

    $table = [ordered]@{}
    $generated = Join-Path $root ("generated/" + $Code + ".json")
    if (Test-Path -LiteralPath $generated) {
        $loaded = ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($generated))
        foreach ($property in $loaded.PSObject.Properties) {
            $table[$property.Name] = [string]$property.Value
        }
    }
    $override = Join-Path $root ("overrides/" + $Code + ".json")
    if (Test-Path -LiteralPath $override) {
        $loaded = ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($override))
        foreach ($property in $loaded.PSObject.Properties) {
            $table[$property.Name] = [string]$property.Value
        }
    }
    if ($table.Count -eq 0) {
        return $null
    }
    return [pscustomobject]$table
}

function ConvertTo-WinToolTextMap {
    param($Source)
    $map = New-Object "System.Collections.Generic.Dictionary[string,string]" ([StringComparer]::Ordinal)
    if ($null -eq $Source) {
        return $map
    }
    if ($Source -is [System.Collections.IDictionary]) {
        foreach ($key in @($Source.Keys)) {
            $map[[string]$key] = [string]$Source[$key]
        }
        return $map
    }
    foreach ($property in $Source.PSObject.Properties) {
        $map[[string]$property.Name] = [string]$property.Value
    }
    return $map
}

function Get-WinToolLocaleTable {
    param([Parameter(Mandatory = $true)][string]$Code)
    if ($null -eq $script:WinToolLocaleTables) {
        $script:WinToolLocaleTables = @{}
    }
    if ($script:WinToolLocaleTables.ContainsKey($Code)) {
        return $script:WinToolLocaleTables[$Code]
    }
    $loaded = Read-WinToolLocaleObject -Code $Code
    if ($null -ne $loaded) {
        $script:WinToolLocaleTables[$Code] = $loaded
    }
    return $loaded
}

function Get-WinToolAvailableLanguage {
    $codes = New-Object System.Collections.Generic.List[string]
    $codes.Add("en") | Out-Null
    foreach ($code in @($script:WinToolShippedLanguages)) {
        if ($code -eq "en") { continue }
        if (Test-WinToolLocaleAvailable -Code $code) {
            $codes.Add($code) | Out-Null
        }
    }
    return $codes.ToArray()
}

function ConvertTo-WinToolShippedLanguage {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $null
    }
    $available = @{}
    foreach ($code in @(Get-WinToolAvailableLanguage)) {
        $available[$code] = $true
    }
    $current = $Tag.Trim()
    $seen = @{}
    while (-not [string]::IsNullOrWhiteSpace($current) -and -not $seen.ContainsKey($current)) {
        $seen[$current] = $true
        if ($script:WinToolCultureAliases.ContainsKey($current) -and $available.ContainsKey($script:WinToolCultureAliases[$current])) {
            return $script:WinToolCultureAliases[$current]
        }
        if ($available.ContainsKey($current)) {
            return $current
        }
        $dash = $current.LastIndexOf("-")
        if ($dash -le 0) {
            # Same language, different region: pt-PT already tried pt, then pt-BR via alias.
            foreach ($code in @($available.Keys)) {
                if ($code.Equals($current, [StringComparison]::OrdinalIgnoreCase) -or $code.StartsWith($current + "-", [StringComparison]::OrdinalIgnoreCase)) {
                    return $code
                }
            }
            break
        }
        $current = $current.Substring(0, $dash)
    }
    return $null
}

function Resolve-WinToolLanguage {
    param(
        [string]$Requested,
        [string]$UiCulture,
        [string[]]$PreferredLanguages
    )
    $available = @(Get-WinToolAvailableLanguage)
    if (-not [string]::IsNullOrWhiteSpace($Requested) -and $Requested -ne "auto") {
        $direct = ConvertTo-WinToolShippedLanguage -Tag $Requested
        if (-not [string]::IsNullOrWhiteSpace($direct)) {
            return $direct
        }
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($UiCulture)) {
        $candidates.Add($UiCulture) | Out-Null
    }
    else {
        try { $candidates.Add([System.Globalization.CultureInfo]::CurrentUICulture.Name) | Out-Null } catch { $null = $_.Exception.Message }
    }
    if ($null -ne $PreferredLanguages) {
        foreach ($item in @($PreferredLanguages)) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $candidates.Add($item) | Out-Null
            }
        }
    }
    else {
        try {
            if (Get-Command -Name Get-WinUserLanguageList -ErrorAction SilentlyContinue) {
                foreach ($item in @(Get-WinUserLanguageList)) {
                    $name = [string]$item.LanguageTag
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $candidates.Add($name) | Out-Null
                    }
                }
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }

    foreach ($tag in $candidates) {
        $matched = ConvertTo-WinToolShippedLanguage -Tag $tag
        if (-not [string]::IsNullOrWhiteSpace($matched)) {
            return $matched
        }
    }
    if ($available -contains "en") {
        return "en"
    }
    return $available[0]
}

function Get-WinToolPluralCategory {
    param(
        [Parameter(Mandatory = $true)][int]$Count,
        [string]$Language
    )
    if ([string]::IsNullOrWhiteSpace($Language)) {
        $Language = [string]$script:WinToolLanguage
    }
    $n = [math]::Abs($Count)
    if ($Language -eq "ru") {
        $mod10 = $n % 10
        $mod100 = $n % 100
        if ($mod10 -eq 1 -and $mod100 -ne 11) { return "one" }
        if ($mod10 -ge 2 -and $mod10 -le 4 -and ($mod100 -lt 12 -or $mod100 -gt 14)) { return "few" }
        return "many"
    }
    if ($n -eq 1) {
        return "one"
    }
    return "other"
}

function Merge-WinToolTextTable {
    param(
        [Parameter(Mandatory = $true)][string]$Language
    )
    $merged = New-Object "System.Collections.Generic.Dictionary[string,string]" ([StringComparer]::Ordinal)
    $english = ConvertTo-WinToolTextMap -Source (Get-WinToolLocaleTable -Code "en")
    foreach ($key in @($english.Keys)) {
        $merged[$key] = $english[$key]
    }
    if ($Language -ne "en") {
        $overlay = ConvertTo-WinToolTextMap -Source (Get-WinToolLocaleTable -Code $Language)
        if ($null -ne $overlay) {
            foreach ($key in @($overlay.Keys)) {
                $value = [string]$overlay[$key]
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $merged[$key] = $value
                }
            }
        }
    }
    return $merged
}

function Initialize-WinToolLocale {
    param(
        [string]$Language,
        [string]$UiCulture,
        [string[]]$PreferredLanguages,
        [switch]$Force
    )
    $requested = $Language
    if ([string]::IsNullOrWhiteSpace($requested)) {
        $requested = [string](Get-WinToolNote -Object (Get-WinToolPreference) -Name "language" -Default "auto")
    }
    if ([string]::IsNullOrWhiteSpace($requested)) {
        $requested = "auto"
    }
    $resolved = Resolve-WinToolLanguage -Requested $requested -UiCulture $UiCulture -PreferredLanguages $PreferredLanguages
    if (-not $Force -and $script:WinToolLocaleReady -eq $true -and $script:WinToolLanguage -eq $resolved -and $script:WinToolLanguagePreference -eq $requested) {
        return $resolved
    }

    $script:WinToolLanguagePreference = $requested
    $script:WinToolLanguage = $resolved
    $localeStamp = Get-Date
    $script:WinToolText = Merge-WinToolTextTable -Language $resolved
    $script:WinToolEnglishText = Merge-WinToolTextTable -Language "en"
    $script:WinToolLocaleReady = $true
    if (Get-Command -Name Write-WinToolStartupMark -ErrorAction SilentlyContinue) {
        Write-WinToolStartupMark -Name "localeInit" -Started $localeStamp
    }
    if ($null -ne $script:WinToolPayloadObject) {
        $script:WinToolPayloadObject = @{}
    }
    return $resolved
}

function Test-WinToolTextKey {
    param([Parameter(Mandatory = $true)][string]$Key)
    if ($null -eq $script:WinToolText) {
        return $false
    }
    return $script:WinToolText.ContainsKey($Key)
}

function Get-WinToolText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$Format
    )
    if ($script:WinToolLocaleReady -ne $true) {
        Initialize-WinToolLocale | Out-Null
    }
    $text = $null
    if ($null -ne $script:WinToolText -and $script:WinToolText.ContainsKey($Key)) {
        $text = [string]$script:WinToolText[$Key]
    }
    elseif ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($Key)) {
        $text = [string]$script:WinToolEnglishText[$Key]
    }
    if ([string]::IsNullOrEmpty($text)) {
        return $Key
    }
    $values = @($Format | Where-Object { $null -ne $_ })
    if ($values.Count -gt 0) {
        try {
            return ($text -f $values)
        }
        catch {
            return $text
        }
    }
    return $text
}

function Get-WinToolCountText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][int]$Count,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$Format
    )
    $extra = @()
    if ($null -ne $Format) {
        $extra = @($Format)
    }
    $category = Get-WinToolPluralCategory -Count $Count
    $suffixes = @()
    if ($category -eq "one") {
        $suffixes = @(".one")
    }
    elseif ($category -eq "few") {
        $suffixes = @(".few", ".many", ".other")
    }
    elseif ($category -eq "many") {
        $suffixes = @(".many", ".other")
    }
    else {
        $suffixes = @(".many", ".other")
    }
    $chosen = $null
    foreach ($suffix in $suffixes) {
        $candidate = $Key + $suffix
        if (Test-WinToolTextKey -Key $candidate) {
            $chosen = $candidate
            break
        }
        if ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($candidate)) {
            $chosen = $candidate
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($chosen)) {
        $chosen = $Key + ".many"
    }
    if ($category -eq "one" -and $extra.Count -gt 0) {
        return (Get-WinToolText -Key $chosen -Format $extra)
    }
    if ($category -eq "one") {
        return (Get-WinToolText -Key $chosen)
    }
    $values = @($Count) + $extra
    return (Get-WinToolText -Key $chosen -Format $values)
}

function Set-WinToolXamlText {
    param($Root)
    if ($null -eq $Root) {
        $Root = $script:WinToolWindow
    }
    if ($null -eq $Root) {
        return
    }
    if ($script:WinToolLocaleReady -ne $true) {
        Initialize-WinToolLocale | Out-Null
    }

    $visit = New-Object System.Collections.Generic.Queue[object]
    $visit.Enqueue($Root)
    $seen = New-Object System.Collections.Generic.HashSet[int]
    while ($visit.Count -gt 0) {
        $node = $visit.Dequeue()
        if ($null -eq $node) { continue }
        try {
            $hash = [int]$node.GetHashCode()
            if (-not $seen.Add($hash)) { continue }
        }
        catch {
            $null = $_.Exception.Message
        }

        $ids = New-Object System.Collections.Generic.List[string]
        try {
            $uid = [string]$node.Uid
            if (-not [string]::IsNullOrWhiteSpace($uid)) { $ids.Add($uid) | Out-Null }
        }
        catch { $null = $_.Exception.Message }
        try {
            $elementName = [string]$node.Name
            if (-not [string]::IsNullOrWhiteSpace($elementName) -and -not $ids.Contains($elementName)) {
                $ids.Add($elementName) | Out-Null
            }
        }
        catch { $null = $_.Exception.Message }

        foreach ($id in $ids) {
            foreach ($pair in @(
                    @{ Key = "ui.$id.Text"; Property = "Text" },
                    @{ Key = "ui.$id.Content"; Property = "Content" },
                    @{ Key = "ui.$id.Title"; Property = "Title" },
                    @{ Key = "ui.$id.ToolTip"; Property = "ToolTip" },
                    @{ Key = "ui.$id.Header"; Property = "Header" }
                )) {
                if (-not (Test-WinToolTextKey -Key $pair.Key) -and -not ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($pair.Key))) {
                    continue
                }
                $value = Get-WinToolText -Key $pair.Key
                try {
                    if ($pair.Property -eq "Content") {
                        $current = $node.Content
                        if ($current -is [string] -or $null -eq $current) {
                            $node.Content = $value
                        }
                    }
                    elseif ($pair.Property -eq "ToolTip") {
                        $tip = $node.ToolTip
                        if ($tip -is [string] -or $null -eq $tip) {
                            $node.ToolTip = $value
                        }
                        elseif ($null -ne $tip.PSObject.Properties["Content"] -and $tip.Content -is [string]) {
                            $tip.Content = $value
                        }
                    }
                    else {
                        $node.($pair.Property) = $value
                    }
                }
                catch {
                    $null = $_.Exception.Message
                }
            }
            $autoKey = "ui.$id.AutomationName"
            if ((Test-WinToolTextKey -Key $autoKey) -or ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($autoKey))) {
                try {
                    [System.Windows.Automation.AutomationProperties]::SetName($node, (Get-WinToolText -Key $autoKey))
                }
                catch {
                    $null = $_.Exception.Message
                }
            }
        }

        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
                if ($child -is [System.Windows.DependencyObject]) {
                    $visit.Enqueue($child)
                }
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
}

function Set-WinToolCatalogLocale {
    param($Catalog, [Parameter(Mandatory = $true)][string]$Kind)
    if ($null -eq $Catalog) {
        return $Catalog
    }
    $set = {
        param($Object, $Name, $Key)
        if ($null -eq $Object) { return }
        if (-not (Test-WinToolTextKey -Key $Key) -and -not ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($Key))) {
            return
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return
        }
        $property.Value = Get-WinToolText -Key $Key
    }
    switch ($Kind) {
        "Apps" {
            foreach ($category in @(Get-WinToolNote -Object $Catalog -Name "categories" -Default @())) {
                $cid = [string](Get-WinToolNote -Object $category -Name "id" -Default "")
                & $set $category "name" "catalog.apps.category.$cid.name"
                & $set $category "chip" "catalog.apps.category.$cid.chip"
                & $set $category "description" "catalog.apps.category.$cid.description"
                foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
                    $aid = [string](Get-WinToolNote -Object $app -Name "id" -Default "")
                    & $set $app "description" "catalog.apps.$aid.description"
                }
            }
        }
        "Tweaks" {
            foreach ($preset in @(Get-WinToolNote -Object $Catalog -Name "presets" -Default @())) {
                $presetId = [string](Get-WinToolNote -Object $preset -Name "id" -Default "")
                & $set $preset "name" "catalog.tweaks.preset.$presetId.name"
                & $set $preset "description" "catalog.tweaks.preset.$presetId.description"
            }
            foreach ($tweak in @(Get-WinToolNote -Object $Catalog -Name "tweaks" -Default @())) {
                $tid = [string](Get-WinToolNote -Object $tweak -Name "id" -Default "")
                & $set $tweak "name" "catalog.tweaks.$tid.name"
                & $set $tweak "description" "catalog.tweaks.$tid.description"
                $category = [string](Get-WinToolNote -Object $tweak -Name "category" -Default "")
                if (-not [string]::IsNullOrWhiteSpace($category)) {
                    $slug = ($category.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim("-")
                    $key = "catalog.tweaks.category.$slug"
                    if ((Test-WinToolTextKey -Key $key) -or ($null -ne $script:WinToolEnglishText -and $script:WinToolEnglishText.ContainsKey($key))) {
                        $tweak.category = Get-WinToolText -Key $key
                    }
                }
            }
        }
        "Terminal" {
            foreach ($prompt in @(Get-WinToolNote -Object $Catalog -Name "prompts" -Default @())) {
                $promptId = [string](Get-WinToolNote -Object $prompt -Name "id" -Default "")
                & $set $prompt "summary" "catalog.terminal.prompt.$promptId.summary"
            }
            foreach ($extra in @(Get-WinToolNote -Object $Catalog -Name "extras" -Default @())) {
                $eid = [string](Get-WinToolNote -Object $extra -Name "id" -Default "")
                & $set $extra "name" "catalog.terminal.extra.$eid.name"
                & $set $extra "description" "catalog.terminal.extra.$eid.description"
            }
            foreach ($scheme in @(Get-WinToolNote -Object $Catalog -Name "schemes" -Default @())) {
                $sid = [string](Get-WinToolNote -Object $scheme -Name "id" -Default "")
                & $set $scheme "name" "catalog.terminal.scheme.$sid.name"
            }
            foreach ($preset in @(Get-WinToolNote -Object $Catalog -Name "starshipPresets" -Default @())) {
                $sid = [string](Get-WinToolNote -Object $preset -Name "id" -Default "")
                & $set $preset "name" "catalog.terminal.starship.$sid.name"
            }
            $variants = Get-WinToolNote -Object $Catalog -Name "promptVariants" -Default $null
            if ($null -ne $variants) {
                foreach ($engineProp in $variants.PSObject.Properties) {
                    foreach ($variant in @($engineProp.Value)) {
                        $vid = [string](Get-WinToolNote -Object $variant -Name "id" -Default "")
                        & $set $variant "name" ("catalog.terminal.variant.{0}.{1}.name" -f $engineProp.Name, $vid)
                        & $set $variant "description" ("catalog.terminal.variant.{0}.{1}.description" -f $engineProp.Name, $vid)
                    }
                }
            }
        }
        "Updates" {
            foreach ($mode in @(Get-WinToolNote -Object $Catalog -Name "modes" -Default @())) {
                $mid = [string](Get-WinToolNote -Object $mode -Name "id" -Default "")
                & $set $mode "name" "catalog.updates.mode.$mid.name"
                & $set $mode "description" "catalog.updates.mode.$mid.description"
            }
            foreach ($vendor in @(Get-WinToolNote -Object $Catalog -Name "vendors" -Default @())) {
                $vid = [string](Get-WinToolNote -Object $vendor -Name "id" -Default "")
                & $set $vendor "note" "catalog.updates.vendor.$vid.note"
            }
        }
        "Features" {
            foreach ($item in @(Get-WinToolNote -Object $Catalog -Name "features" -Default @())) {
                $fid = [string](Get-WinToolNote -Object $item -Name "id" -Default "")
                & $set $item "description" "catalog.features.$fid.description"
            }
        }
        "Fixes" {
            foreach ($item in @(Get-WinToolNote -Object $Catalog -Name "fixes" -Default @())) {
                $fid = [string](Get-WinToolNote -Object $item -Name "id" -Default "")
                & $set $item "name" "catalog.fixes.$fid.name"
                & $set $item "description" "catalog.fixes.$fid.description"
                $index = 0
                foreach ($step in @(Get-WinToolNote -Object $item -Name "steps" -Default @())) {
                    & $set $step "label" "catalog.fixes.$fid.step.$index"
                    $index += 1
                }
            }
        }
        "System" {
            foreach ($dns in @(Get-WinToolNote -Object $Catalog -Name "dns" -Default @())) {
                $did = [string](Get-WinToolNote -Object $dns -Name "id" -Default "")
                & $set $dns "name" "catalog.system.dns.$did.name"
                & $set $dns "description" "catalog.system.dns.$did.description"
            }
            $plan = Get-WinToolNote -Object $Catalog -Name "powerPlan" -Default $null
            if ($null -ne $plan) {
                & $set $plan "name" "catalog.system.powerPlan.name"
                & $set $plan "description" "catalog.system.powerPlan.description"
            }
        }
        "Drivers" {
            foreach ($gpu in @(Get-WinToolNote -Object $Catalog -Name "gpuApps" -Default @())) {
                $gid = [string](Get-WinToolNote -Object $gpu -Name "id" -Default "")
                & $set $gpu "note" "catalog.drivers.gpu.$gid.note"
            }
            foreach ($problem in @(Get-WinToolNote -Object $Catalog -Name "problem" -Default @())) {
                $code = [string](Get-WinToolNote -Object $problem -Name "code" -Default "")
                & $set $problem "name" "catalog.drivers.problem.$code.name"
            }
        }
    }
    return $Catalog
}

function Test-WinToolTextTable {
    param($Errors)
    if ($null -eq $Errors) {
        $Errors = New-Object System.Collections.Generic.List[string]
    }
    if ($script:WinToolLocaleReady -ne $true) {
        Initialize-WinToolLocale -Language "en" | Out-Null
    }
    if ($null -eq $script:WinToolEnglishText -or $script:WinToolEnglishText.Count -eq 0) {
        Add-WinToolDataError -Errors $Errors -Message "The English UI text table is empty."
        return $Errors
    }
    foreach ($key in @($script:WinToolEnglishText.Keys)) {
        $value = [string]$script:WinToolEnglishText[$key]
        if ([string]::IsNullOrWhiteSpace($value)) {
            Add-WinToolDataError -Errors $Errors -Message ("UI text '" + $key + "' is empty.")
        }
    }
    $previous = $script:WinToolLanguage
    $previousPref = $script:WinToolLanguagePreference
    $previousTable = $script:WinToolText
    try {
        $script:WinToolLanguage = "en"
        $script:WinToolText = $script:WinToolEnglishText
        $sample = Get-WinToolText "activity.count.warning.many" 3
        if ($sample -ne "3 warnings") {
            Add-WinToolDataError -Errors $Errors -Message "Get-WinToolText did not format a known English string."
        }
    }
    finally {
        $script:WinToolLanguage = $previous
        $script:WinToolLanguagePreference = $previousPref
        $script:WinToolText = $previousTable
    }
    return $Errors
}

Initialize-WinToolLocale | Out-Null
