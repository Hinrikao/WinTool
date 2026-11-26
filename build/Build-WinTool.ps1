# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Build the single-file WinTool launcher.
.DESCRIPTION
    Reads src/, data/, and assets/ and writes wintool.ps1.
    Pass -Check to fail when the committed launcher is out of date.
#>
param(
    [string]$OutputPath,
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root "wintool.ps1"
}

function Read-BuildText {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    $text = [System.IO.File]::ReadAllText($Path)
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    return $text
}

function ConvertTo-BuildBase64 {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (ConvertTo-BuildWrappedBase64 -Bytes $bytes)
}

function ConvertTo-BuildWrappedBase64 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $encoded = [Convert]::ToBase64String($Bytes)
    $lines = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $encoded.Length; $index += 80) {
        $length = [Math]::Min(80, $encoded.Length - $index)
        $lines.Add($encoded.Substring($index, $length))
    }
    return ($lines -join "`n")
}


function ConvertTo-BuildJsonString {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) {
        return "null"
    }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($char in $Text.ToCharArray()) {
        $code = [int]$char
        if ($code -eq 34) { [void]$builder.Append('\"') }
        elseif ($code -eq 92) { [void]$builder.Append('\\') }
        elseif ($code -eq 8) { [void]$builder.Append('\b') }
        elseif ($code -eq 12) { [void]$builder.Append('\f') }
        elseif ($code -eq 10) { [void]$builder.Append('\n') }
        elseif ($code -eq 13) { [void]$builder.Append('\r') }
        elseif ($code -eq 9) { [void]$builder.Append('\t') }
        elseif ($code -lt 32) {
            [void]$builder.Append('\u')
            [void]$builder.Append($code.ToString("x4"))
        }
        else { [void]$builder.Append($char) }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-BuildFlatJsonObject {
    param($Table)
    $map = @{}
    if ($Table -is [System.Collections.IDictionary]) {
        foreach ($key in @($Table.Keys)) {
            $map[[string]$key] = [string]$Table[$key]
        }
    }
    elseif ($null -ne $Table) {
        foreach ($property in $Table.PSObject.Properties) {
            $map[[string]$property.Name] = [string]$property.Value
        }
    }
    $names = @($map.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("{")
    $first = $true
    foreach ($name in $names) {
        if (-not $first) { [void]$builder.Append(",") }
        $first = $false
        [void]$builder.Append((ConvertTo-BuildJsonString -Text $name))
        [void]$builder.Append(":")
        [void]$builder.Append((ConvertTo-BuildJsonString -Text $map[$name]))
    }
    [void]$builder.Append("}")
    return $builder.ToString()
}

function Get-BuildLocaleJson {
    param([Parameter(Mandatory = $true)][string]$Code)
    $i18n = Join-Path $root "data/i18n"
    if ($Code -eq "en") {
        $enPath = Join-Path $i18n "en.json"
        if (-not (Test-Path -LiteralPath $enPath)) {
            throw "data/i18n/en.json is missing."
        }
        return (ConvertTo-BuildFlatJsonObject -Table (ConvertFrom-Json -InputObject (Read-BuildText -Path $enPath)))
    }
    $table = [ordered]@{}
    $generated = Join-Path $i18n ("generated/" + $Code + ".json")
    if (Test-Path -LiteralPath $generated) {
        $loaded = ConvertFrom-Json -InputObject (Read-BuildText -Path $generated)
        foreach ($property in $loaded.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }
    }
    $override = Join-Path $i18n ("overrides/" + $Code + ".json")
    if (Test-Path -LiteralPath $override) {
        $loaded = ConvertFrom-Json -InputObject (Read-BuildText -Path $override)
        foreach ($property in $loaded.PSObject.Properties) {
            $table[$property.Name] = $property.Value
        }
    }
    if ($table.Count -eq 0) {
        return $null
    }
    return (ConvertTo-BuildFlatJsonObject -Table $table)
}

function ConvertTo-BuildGzipBase64 {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $output = New-Object System.IO.MemoryStream
    $gzip = New-Object System.IO.Compression.GzipStream($output, [System.IO.Compression.CompressionMode]::Compress, $true)
    try {
        $gzip.Write($Bytes, 0, $Bytes.Length)
    }
    finally {
        $gzip.Dispose()
    }
    return (ConvertTo-BuildWrappedBase64 -Bytes $output.ToArray())
}

function Get-BuildAppIcon {
    $catalog = ConvertFrom-Json -InputObject (Read-BuildText -Path (Join-Path $root "data/apps.json"))
    $names = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($category in @($catalog.categories)) {
        foreach ($app in @($category.apps)) {
            $icon = ""
            if ($null -ne $app.PSObject.Properties["icon"]) {
                $icon = [string]$app.icon
            }
            if ([string]::IsNullOrWhiteSpace($icon)) {
                continue
            }
            if ($icon -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.png$') {
                throw "App '$($app.id)' has an icon name that is not a PNG file name."
            }
            if ($seen.ContainsKey($icon)) {
                continue
            }
            $seen[$icon] = $true
            $names.Add($icon)
        }
    }
    # The Terminal Simple page uses the Oh My Posh mark. It is not an Install app.
    if (-not $seen.ContainsKey("posh.png")) {
        $names.Add("posh.png")
    }
    $sorted = $names.ToArray()
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    return $sorted
}

$version = (Read-BuildText -Path (Join-Path $root "build/version.txt")).Trim()
$payloads = [ordered]@{
    Apps = "data/apps.json"
    Tweaks = "data/tweaks.json"
    Terminal = "data/terminal.json"
    Fonts = "data/fonts.json"
    OmpThemes = "data/omp-themes.json"
    Updates = "data/updates.json"
    Drivers = "data/drivers.json"
    Fixes = "data/fixes.json"
    Features = "data/features.json"
    System = "data/system.json"
    Xaml = "assets/MainWindow.xaml"
    Wsl = "data/wsl-setup.sh"
}

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine("#requires -Version 5.1")
[void]$builder.AppendLine("<#")
[void]$builder.AppendLine("    WinTool $version")
[void]$builder.AppendLine("    A friendly Windows 11 setup helper.")
[void]$builder.AppendLine("    Copyright (c) 2026 Henrique")
[void]$builder.AppendLine("    SPDX-License-Identifier: MIT")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("    Generated by build/Build-WinTool.ps1. Do not edit this file.")
[void]$builder.AppendLine("    Change the files under src/, data/, and assets/, then rebuild.")
[void]$builder.AppendLine("#>")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("param(")
[void]$builder.AppendLine('    [string]$ApplyProfile,')
[void]$builder.AppendLine('    [switch]$Unattended,')
[void]$builder.AppendLine('    [switch]$ShowConsole')
[void]$builder.AppendLine(")")
[void]$builder.AppendLine("")
[void]$builder.AppendLine('$script:WinToolVersion = "' + $version + '"')
[void]$builder.AppendLine('$script:WinToolApplyProfile = $ApplyProfile')
[void]$builder.AppendLine('$script:WinToolUnattended = [bool]$Unattended')
[void]$builder.AppendLine('$script:WinToolShowConsole = [bool]$ShowConsole')
[void]$builder.AppendLine('$script:WinToolEntryPath = $PSCommandPath')
[void]$builder.AppendLine('$script:WinToolSelfText = [string]$MyInvocation.MyCommand.ScriptBlock')
[void]$builder.AppendLine('$script:WinToolRoot = $null')
[void]$builder.AppendLine('$script:WinToolEmbedded = @{')
foreach ($name in $payloads.Keys) {
    $payloadText = Read-BuildText -Path (Join-Path $root $payloads[$name])
    $encoded = ConvertTo-BuildGzipBase64 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($payloadText))
    [void]$builder.AppendLine("    $name = @'")
    [void]$builder.AppendLine($encoded)
    [void]$builder.AppendLine("'@")
}
$localeCodes = @("en", "pt-BR", "es", "fr", "de", "it", "ja", "ko", "zh-Hans", "zh-Hant", "pl", "nl", "ru", "tr")
foreach ($localeCode in $localeCodes) {
    $localeJson = Get-BuildLocaleJson -Code $localeCode
    if ([string]::IsNullOrWhiteSpace($localeJson)) { continue }
    [void]$builder.AppendLine("    'Locales:$localeCode' = @'")
    [void]$builder.AppendLine((ConvertTo-BuildGzipBase64 -Bytes ([System.Text.Encoding]::UTF8.GetBytes($localeJson))))
    [void]$builder.AppendLine("'@")
}
[void]$builder.AppendLine("}")
[void]$builder.AppendLine('$script:WinToolIcons = @{')
foreach ($iconName in @(Get-BuildAppIcon)) {
    $iconPath = Join-Path $root ("assets/icons/" + $iconName)
    if (-not (Test-Path -LiteralPath $iconPath)) {
        throw "App icon '$iconName' is missing from assets/icons."
    }
    $iconBytes = [System.IO.File]::ReadAllBytes($iconPath)
    $png = ($iconBytes.Length -ge 8 -and $iconBytes[0] -eq 137 -and $iconBytes[1] -eq 80 -and $iconBytes[2] -eq 78 -and $iconBytes[3] -eq 71)
    if (-not $png) {
        throw "App icon '$iconName' is not a PNG."
    }
    [void]$builder.AppendLine("    '$iconName' = @'")
    [void]$builder.AppendLine((ConvertTo-BuildWrappedBase64 -Bytes $iconBytes))
    [void]$builder.AppendLine("'@")
}
[void]$builder.AppendLine('}')
[void]$builder.AppendLine("")

$manifest = Read-BuildText -Path (Join-Path $root "build/files.txt")
foreach ($relative in ($manifest -split "`n")) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        continue
    }
    $sourcePath = Join-Path $root ($trimmed -replace '\\', '/')
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Build manifest is missing $trimmed"
    }
    $source = Read-BuildText -Path $sourcePath
    if (-not $source.EndsWith("`n")) {
        $source += "`n"
    }
    [void]$builder.AppendLine("# region $trimmed")
    [void]$builder.Append($source)
    [void]$builder.AppendLine("# endregion")
    [void]$builder.AppendLine("")
}

[void]$builder.AppendLine("Start-WinTool")
[void]$builder.AppendLine("")
$generated = $builder.ToString().Replace("`r`n", "`n")

if ($Check) {
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "wintool.ps1 is missing. Run build/Build-WinTool.ps1 and commit it."
    }
    $current = Read-BuildText -Path $OutputPath
    if (-not $current.EndsWith("`n")) {
        $current += "`n"
    }
    if ($current -ne $generated) {
        throw "wintool.ps1 does not match the source tree. Run build/Build-WinTool.ps1 and commit the result."
    }
    Write-Output "wintool.ps1 matches the source tree."
    return
}

$encoding = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($OutputPath, $generated, $encoding)
Write-Output "Wrote $OutputPath"
