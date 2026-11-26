# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolFontDocument {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Fonts"))
}

function Get-WinToolOhMyPoshDocument {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "OmpThemes"))
}

function Select-WinToolFont {
    param(
        $Font,
        [string]$Query,
        [bool]$NerdOnly = $false,
        [bool]$PlainOnly = $false
    )
    $matched = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Font)) {
        $isNerd = $false
        if ($null -ne $item.PSObject.Properties["nerd"] -and $item.nerd) {
            $isNerd = $true
        }
        if ($NerdOnly -and -not $isNerd) {
            continue
        }
        if ($PlainOnly -and $isNerd) {
            continue
        }
        $haystack = (([string]$item.name) + " " + ([string]$item.face) + " " + ([string]$item.id))
        if (Test-WinToolTextMatch -Haystack $haystack -Query $Query) {
            $matched.Add($item)
        }
    }
    return $matched.ToArray()
}

function Get-WinToolOhMyPoshThemeFile {
    param(
        [string]$PromptStyle
    )
    $themeFile = "jandedobbeleer.omp.json"
    if (-not [string]::IsNullOrWhiteSpace($PromptStyle)) {
        if ($PromptStyle.EndsWith(".omp.json")) {
            $themeFile = $PromptStyle
        }
        else {
            $themeFile = $PromptStyle + ".omp.json"
        }
    }
    return $themeFile
}

function Get-WinToolPromptScript {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true,
        [string]$PromptStyle = "",
        [bool]$PsReadLine = $false,
        [bool]$Zoxide = $false
    )
    # The same text goes into the Windows PowerShell 5.1 and PowerShell 7
    # profiles. Every block is wrapped so a missing tool, an old module, or a
    # missing variable never prints an error when a terminal opens.
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Added by WinTool. Delete this block, or run WinTool again, to change it.")
    # Prompt and zoxide init only run in a real interactive console (Windows
    # Terminal, conhost, or the VS Code terminal). A script host, a remote
    # session, or TERM=dumb gets none, and empty init output is never run.
    $lines.Add('$wintoolInteractive = $false')
    $lines.Add('try {')
    $lines.Add('    $wintoolInteractive = [Environment]::UserInteractive -and ([string]$env:TERM -ne "dumb") -and (@("ConsoleHost", "Visual Studio Code Host") -contains [string]$Host.Name)')
    $lines.Add('}')
    $lines.Add('catch { $wintoolInteractive = $false }')
    if ($TerminalIcons) {
        $lines.Add('try {')
        $lines.Add('    if (Get-Module -ListAvailable -Name Terminal-Icons) {')
        $lines.Add('        Import-Module Terminal-Icons -ErrorAction Stop')
        $lines.Add('    }')
        $lines.Add('}')
        $lines.Add('catch { $null = $_ }')
    }
    if ($PsReadLine) {
        # Windows PowerShell 5.1 ships PSReadLine 2.0, which has neither
        # option. PredictionSource came in 2.1 and PredictionViewStyle in 2.2.
        # Predictions also refuse to start when output is redirected.
        $lines.Add('try {')
        $lines.Add('    $wintoolReadLine = $null')
        $lines.Add('    if (-not [Console]::IsOutputRedirected) { $wintoolReadLine = Get-Command -Name Set-PSReadLineOption -ErrorAction Ignore }')
        $lines.Add('    if ($null -ne $wintoolReadLine -and $wintoolReadLine.Parameters.ContainsKey("PredictionSource")) {')
        $lines.Add('        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop -WarningAction SilentlyContinue')
        $lines.Add('    }')
        $lines.Add('    if ($null -ne $wintoolReadLine -and $wintoolReadLine.Parameters.ContainsKey("PredictionViewStyle")) {')
        $lines.Add('        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop -WarningAction SilentlyContinue')
        $lines.Add('    }')
        $lines.Add('}')
        $lines.Add('catch { $null = $_ }')
    }
    if ($Zoxide) {
        $lines.Add('try {')
        $lines.Add('    $wintoolZoxide = $null')
        $lines.Add('    if ($wintoolInteractive) { $wintoolZoxide = Get-Command -Name zoxide -CommandType Application -ErrorAction Ignore | Select-Object -First 1 }')
        $lines.Add('    if ($wintoolInteractive -and $null -eq $wintoolZoxide) {')
        $lines.Add('        foreach ($wintoolPath in @(([string]$env:LOCALAPPDATA + "\Microsoft\WinGet\Links\zoxide.exe"), ([string]$env:USERPROFILE + "\.cargo\bin\zoxide.exe"), ([string]$env:LOCALAPPDATA + "\Programs\zoxide\bin\zoxide.exe"))) {')
        $lines.Add('            if (-not [string]::IsNullOrWhiteSpace($wintoolPath) -and (Test-Path -LiteralPath $wintoolPath)) { $wintoolZoxide = Get-Command -Name $wintoolPath -ErrorAction Ignore; break }')
        $lines.Add('        }')
        $lines.Add('    }')
        $lines.Add('    if ($null -ne $wintoolZoxide) {')
        $lines.Add('        $global:LASTEXITCODE = 0')
        $lines.Add('        $wintoolInit = (& $wintoolZoxide.Source init powershell 2>$null | Out-String)')
        $lines.Add('        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wintoolInit)) { Invoke-Expression $wintoolInit }')
        $lines.Add('    }')
        $lines.Add('}')
        $lines.Add('catch { $null = $_ }')
    }
    if ($PromptId -eq "starship") {
        $lines.Add('try {')
        $lines.Add('    $wintoolStarship = $null')
        $lines.Add('    if ($wintoolInteractive) { $wintoolStarship = Get-Command -Name starship -CommandType Application -ErrorAction Ignore | Select-Object -First 1 }')
        $lines.Add('    if ($wintoolInteractive -and $null -eq $wintoolStarship) {')
        $lines.Add('        foreach ($wintoolPath in @(([string]$env:ProgramFiles + "\starship\bin\starship.exe"), ([string]$env:LOCALAPPDATA + "\Programs\starship\bin\starship.exe"), ([string]$env:LOCALAPPDATA + "\Microsoft\WinGet\Links\starship.exe"), ([string]$env:USERPROFILE + "\.cargo\bin\starship.exe"))) {')
        $lines.Add('            if (-not [string]::IsNullOrWhiteSpace($wintoolPath) -and (Test-Path -LiteralPath $wintoolPath)) { $wintoolStarship = Get-Command -Name $wintoolPath -ErrorAction Ignore; break }')
        $lines.Add('        }')
        $lines.Add('    }')
        $lines.Add('    if ($null -ne $wintoolStarship) {')
        $lines.Add('        $global:LASTEXITCODE = 0')
        $lines.Add('        $wintoolInit = (& $wintoolStarship.Source init powershell 2>$null | Out-String)')
        $lines.Add('        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wintoolInit)) { Invoke-Expression $wintoolInit }')
        $lines.Add('    }')
        $lines.Add('}')
        $lines.Add('catch { $null = $_ }')
    }
    elseif ($PromptId -eq "oh-my-posh") {
        $themeFile = Get-WinToolOhMyPoshThemeFile -PromptStyle $PromptStyle
        # POSH_THEMES_PATH is not set by newer Oh My Posh builds, so WinTool
        # saves the theme under %LOCALAPPDATA%\WinTool\themes during setup and
        # also looks in the older theme folders.
        # oh-my-posh init needs "pwsh" for PowerShell Core 6+ and "powershell" for Windows PowerShell 5.1.
        $lines.Add('try {')
        $lines.Add('    $wintoolPosh = $null')
        $lines.Add('    if ($wintoolInteractive) { $wintoolPosh = Get-Command -Name oh-my-posh -CommandType Application -ErrorAction Ignore | Select-Object -First 1 }')
        $lines.Add('    if ($wintoolInteractive -and $null -eq $wintoolPosh) {')
        $lines.Add('        foreach ($wintoolPath in @(([string]$env:LOCALAPPDATA + "\Programs\oh-my-posh\bin\oh-my-posh.exe"), ([string]$env:ProgramFiles + "\oh-my-posh\bin\oh-my-posh.exe"), ([string]${env:ProgramFiles(x86)} + "\oh-my-posh\bin\oh-my-posh.exe"), ([string]$env:LOCALAPPDATA + "\Microsoft\WinGet\Links\oh-my-posh.exe"))) {')
        $lines.Add('            if (-not [string]::IsNullOrWhiteSpace($wintoolPath) -and (Test-Path -LiteralPath $wintoolPath)) { $wintoolPosh = Get-Command -Name $wintoolPath -ErrorAction Ignore; break }')
        $lines.Add('        }')
        $lines.Add('    }')
        $lines.Add('    if ($null -ne $wintoolPosh) {')
        $lines.Add('        $wintoolShell = "pwsh"')
        $lines.Add('        if ($PSVersionTable.PSEdition -ne "Core") { $wintoolShell = "powershell" }')
        $lines.Add('        $wintoolTheme = $null')
        $lines.Add('        foreach ($wintoolFolder in @([string]$env:POSH_THEMES_PATH, ([string]$env:LOCALAPPDATA + "\WinTool\themes"), ([string]$env:LOCALAPPDATA + "\Programs\oh-my-posh\themes"), ([string]$env:ProgramFiles + "\oh-my-posh\themes"), ([string]${env:ProgramFiles(x86)} + "\oh-my-posh\themes"))) {')
        $lines.Add('            if ([string]::IsNullOrWhiteSpace($wintoolFolder)) { continue }')
        $lines.Add('            $wintoolCandidate = Join-Path $wintoolFolder "' + $themeFile + '"')
        $lines.Add('            if (Test-Path -LiteralPath $wintoolCandidate) { $wintoolTheme = $wintoolCandidate; break }')
        $lines.Add('        }')
        $lines.Add('        $global:LASTEXITCODE = 0')
        $lines.Add('        $wintoolInit = $null')
        $lines.Add('        if ($null -ne $wintoolTheme) {')
        $lines.Add('            $wintoolInit = (& $wintoolPosh.Source init $wintoolShell --config $wintoolTheme 2>$null | Out-String)')
        $lines.Add('        }')
        $lines.Add('        else {')
        $lines.Add('            $wintoolInit = (& $wintoolPosh.Source init $wintoolShell 2>$null | Out-String)')
        $lines.Add('        }')
        $lines.Add('        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wintoolInit)) { Invoke-Expression $wintoolInit }')
        $lines.Add('    }')
        $lines.Add('}')
        $lines.Add('catch { $null = $_ }')
    }
    elseif ($PromptId -eq "powerline-go") {
        $styleArgs = @(Get-WinToolPromptVariantArgument -Variant (Get-WinToolPromptVariant -PromptId $PromptId -PromptStyle $PromptStyle))
        $argText = ""
        foreach ($arg in $styleArgs) { $argText += " '" + $arg + "'" }
        $lines.Add('if ($wintoolInteractive) {')
        $lines.Add('    function global:prompt {')
        $lines.Add('        $wintoolExit = $LASTEXITCODE')
        $lines.Add('        try {')
        $lines.Add('            $tool = [string]$env:LOCALAPPDATA + "\WinTool\bin\powerline-go.exe"')
        $lines.Add('            if (Test-Path -LiteralPath $tool) {')
        $lines.Add('                $global:LASTEXITCODE = 0')
        $lines.Add('                $wintoolLine = ((& $tool -error $wintoolExit -shell bare' + $argText + ') -join "")')
        $lines.Add('                if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($wintoolLine)) { return $wintoolLine }')
        $lines.Add('            }')
        $lines.Add('        }')
        $lines.Add('        catch { $null = $_ }')
        $lines.Add('        return "PS $($executionContext.SessionState.Path.CurrentLocation)> "')
        $lines.Add('    }')
        $lines.Add('}')
    }
    else {
        $lines.Add("# The prompt for this setup runs inside WSL, not in this PowerShell profile.")
    }
    return ($lines -join "`r`n")
}

function Update-WinToolManagedBlock {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Begin,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$Body
    )
    $block = $Begin + "`r`n" + $Body.Trim() + "`r`n" + $End
    $pattern = "(?s)" + [regex]::Escape($Begin) + ".*?" + [regex]::Escape($End)
    if ($Text -match $pattern) {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
            param($found)
            if ($null -eq $found) {
                return $block
            }
            return $block
        }.GetNewClosure()
        return [regex]::Replace($Text, $pattern, $evaluator)
    }
    $prefix = [string]$Text
    if ($prefix.Length -gt 0 -and -not $prefix.EndsWith("`n")) {
        $prefix += "`r`n"
    }
    if ($prefix.Length -gt 0) {
        $prefix += "`r`n"
    }
    return $prefix + $block + "`r`n"
}

function Get-WinToolShellProfilePath {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("powershell", "pwsh")][string]$HostName
    )
    $documents = [Environment]::GetFolderPath("MyDocuments")
    if ($HostName -eq "pwsh") {
        return (Join-Path $documents "PowerShell/Microsoft.PowerShell_profile.ps1")
    }
    return (Join-Path $documents "WindowsPowerShell/Microsoft.PowerShell_profile.ps1")
}

function Get-WinToolTerminalSettingsPath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $null
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"),
        (Join-Path $env:LOCALAPPDATA "Microsoft/Windows Terminal/settings.json")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    $directories = @(
        (Join-Path $env:LOCALAPPDATA "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"),
        (Join-Path $env:LOCALAPPDATA "Microsoft/Windows Terminal")
    )
    foreach ($directory in $directories) {
        if (Test-Path -LiteralPath $directory) {
            return (Join-Path $directory "settings.json")
        }
    }
    return $null
}

function ConvertTo-WinToolFontFace {
    param(
        [Parameter(Mandatory = $true)][string]$RegistryName
    )
    $face = $RegistryName -replace '\s*\((TrueType|OpenType)\)\s*$', ''
    return $face.Trim()
}

function Add-WinToolTerminalFont {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][string]$Face,
        [int]$Size = 12
    )
    if ($null -eq $Settings.PSObject.Properties["profiles"]) {
        $Settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([pscustomobject]@{})
    }
    $profiles = $Settings.profiles
    if ($null -eq $profiles.PSObject.Properties["defaults"]) {
        $profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([pscustomobject]@{})
    }
    $defaults = $profiles.defaults
    # Only face and size change; other font settings (features, weight,
    # axes) the user already has are kept.
    $font = Get-WinToolNote -Object $defaults -Name "font"
    if ($null -eq $font -or $font -isnot [System.Management.Automation.PSCustomObject]) {
        $font = [pscustomobject]@{}
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue $font -Force
    }
    $font | Add-Member -NotePropertyName "face" -NotePropertyValue $Face -Force
    $font | Add-Member -NotePropertyName "size" -NotePropertyValue $Size -Force
    if ($null -eq $defaults.PSObject.Properties["fontFace"]) {
        $defaults | Add-Member -NotePropertyName "fontFace" -NotePropertyValue $Face
    }
    else {
        $defaults.fontFace = $Face
    }
    return $Settings
}

$script:WinToolLigatureFeatures = [ordered]@{ calt = 1; liga = 1 }

function Set-WinToolFontFeatureObject {
    param(
        [Parameter(Mandatory = $true)]$Font
    )
    # Adds calt=1 and liga=1 to font.features and keeps every other feature.
    $features = Get-WinToolNote -Object $Font -Name "features"
    if ($null -eq $features -or $features -isnot [System.Management.Automation.PSCustomObject]) {
        $features = [pscustomobject]@{}
        $Font | Add-Member -NotePropertyName "features" -NotePropertyValue $features -Force
    }
    foreach ($key in $script:WinToolLigatureFeatures.Keys) {
        $features | Add-Member -NotePropertyName $key -NotePropertyValue ([int]$script:WinToolLigatureFeatures[$key]) -Force
    }
}

function Add-WinToolTerminalLigature {
    param(
        [Parameter(Mandatory = $true)]$Settings
    )
    # Turns on font ligatures for every Windows Terminal profile: the shared
    # profiles.defaults.font.features gets calt and liga, and any profile
    # with its own features list (which would hide the default) gets them too.
    $profiles = $null
    if ($null -ne $Settings.PSObject.Properties["profiles"]) { $profiles = $Settings.PSObject.Properties["profiles"].Value }
    if ($null -ne $profiles -and $profiles -is [System.Array]) {
        # Old settings files keep profiles as a plain list.
        $profiles = [pscustomobject]@{ defaults = [pscustomobject]@{}; list = $profiles }
        $Settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue $profiles -Force
    }
    if ($null -eq $profiles) {
        $profiles = [pscustomobject]@{}
        $Settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue $profiles -Force
    }
    $defaults = Get-WinToolNote -Object $profiles -Name "defaults"
    if ($null -eq $defaults) {
        $defaults = [pscustomobject]@{}
        $profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue $defaults -Force
    }
    $font = Get-WinToolNote -Object $defaults -Name "font"
    if ($null -eq $font -or $font -isnot [System.Management.Automation.PSCustomObject]) {
        $font = [pscustomobject]@{}
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue $font -Force
    }
    Set-WinToolFontFeatureObject -Font $font
    $count = 0
    foreach ($item in @(Get-WinToolNote -Object $profiles -Name "list" -Default @())) {
        if ($null -eq $item) { continue }
        $own = Get-WinToolNote -Object $item -Name "font"
        if ($null -eq $own -or $null -eq (Get-WinToolNote -Object $own -Name "features")) { continue }
        Set-WinToolFontFeatureObject -Font $own
        $count++
    }
    return $count
}

function Backup-WinToolTerminalSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $backup = $Path + ".wintool-backup"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-WinToolLog -Message "Saved a backup of Terminal settings next to settings.json." -Level "info"
    }
}

function Invoke-WinToolTerminalLigature {
    $path = Get-WinToolTerminalSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-WinToolLog -Message "Windows Terminal settings were not found. Open Terminal once, then run terminal setup again to turn on font ligatures." -Level "warn"
        return
    }
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path) {
        Backup-WinToolTerminalSetting -Path $path
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $settings = ConvertFrom-WinToolJsonText -Text $raw
        }
    }
    $own = Add-WinToolTerminalLigature -Settings $settings
    Write-WinToolUtf8File -Path $path -Text ((ConvertTo-WinToolJsonText -Value $settings) + "`n")
    $message = "Turned on font ligatures (calt, liga) for all Windows Terminal profiles."
    if ($own -gt 0) { $message += " Also updated " + $own + " profile(s) with their own font features." }
    Write-WinToolLog -Message $message -Level "ok"
}

$script:WinToolSchemeColorKeys = @("black", "red", "green", "yellow", "blue", "purple", "cyan", "white", "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue", "brightPurple", "brightCyan", "brightWhite")

function Add-WinToolTerminalScheme {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)]$Scheme
    )
    # Windows Terminal ignores a scheme that lacks any of the 16 table colors,
    # so the full palette is written before a profile points at the name.
    $fields = [ordered]@{
        name = [string]$Scheme.name
        background = [string]$Scheme.background
        foreground = [string]$Scheme.foreground
        cursorColor = [string]$Scheme.cursor
        selectionBackground = [string]$Scheme.selection
    }
    $palette = Get-WinToolNote -Object $Scheme -Name "palette"
    foreach ($key in $script:WinToolSchemeColorKeys) {
        $value = [string](Get-WinToolNote -Object $palette -Name $key -Default "")
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw ("The color scheme " + [string]$Scheme.name + " has no " + $key + " color.")
        }
        $fields[$key] = $value
    }
    $entry = [pscustomobject]$fields
    $existing = @()
    if ($null -ne $Settings.PSObject.Properties["schemes"] -and $null -ne $Settings.schemes) {
        $existing = @($Settings.schemes)
    }
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($item in $existing) {
        if ([string]$item.name -ne [string]$entry.name) {
            $kept.Add($item)
        }
    }
    $kept.Add($entry)
    if ($null -eq $Settings.PSObject.Properties["schemes"]) {
        $Settings | Add-Member -NotePropertyName "schemes" -NotePropertyValue ($kept.ToArray())
    }
    else {
        $Settings.schemes = $kept.ToArray()
    }
    if ($null -eq $Settings.PSObject.Properties["profiles"]) {
        $Settings | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $Settings.profiles.PSObject.Properties["defaults"]) {
        $Settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $Settings.profiles.defaults.PSObject.Properties["colorScheme"]) {
        $Settings.profiles.defaults | Add-Member -NotePropertyName "colorScheme" -NotePropertyValue ([string]$entry.name)
    }
    else {
        $Settings.profiles.defaults.colorScheme = [string]$entry.name
    }
    return $Settings
}

function Save-WinToolOhMyPoshTheme {
    param(
        [Parameter(Mandatory = $true)][string]$ThemeFile
    )
    # Keeps a copy of the theme where the profile can always find it.
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $null
    }
    $folder = Join-Path $env:LOCALAPPDATA "WinTool\themes"
    $target = Join-Path $folder $ThemeFile
    $part = $target + ".part"
    try {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $url = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/" + [uri]::EscapeDataString($ThemeFile)
        Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 30
        if (-not (Test-Path -LiteralPath $part) -or (Get-Item -LiteralPath $part).Length -le 2) {
            throw "Downloaded theme file was empty."
        }
        Move-Item -LiteralPath $part -Destination $target -Force
        if ($null -ne $script:WinToolOmpThemeCache) {
            $script:WinToolOmpThemeCache.Remove($ThemeFile)
        }
        Write-WinToolLog -Message "Saved the Oh My Posh theme to $target" -Level "ok"
        return $target
    }
    catch {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $target) {
            Write-WinToolLog -Message "Could not refresh the Oh My Posh theme, so the saved copy is kept. $($_.Exception.Message)" -Level "warn"
            return $target
        }
        Write-WinToolLog -Message "Could not download the Oh My Posh theme $ThemeFile, so the default theme will be used. $($_.Exception.Message)" -Level "warn"
        return $null
    }
}

function Write-WinToolShellProfile {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true,
        [string]$PromptStyle = "",
        [bool]$PsReadLine = $false,
        [bool]$Zoxide = $false
    )
    if ($PromptId -eq "oh-my-posh") {
        Save-WinToolOhMyPoshTheme -ThemeFile (Get-WinToolOhMyPoshThemeFile -PromptStyle $PromptStyle) | Out-Null
    }
    $body = Get-WinToolPromptScript -PromptId $PromptId -TerminalIcons $TerminalIcons -PromptStyle $PromptStyle -PsReadLine $PsReadLine -Zoxide $Zoxide
    $paths = @(
        (Get-WinToolShellProfilePath -HostName "powershell"),
        (Get-WinToolShellProfilePath -HostName "pwsh")
    )
    foreach ($path in $paths) {
        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $existing = ""
        if (Test-Path -LiteralPath $path) {
            $existing = [System.IO.File]::ReadAllText($path)
        }
        $updated = Update-WinToolManagedBlock -Text $existing -Begin $script:WinToolProfileBegin -End $script:WinToolProfileEnd -Body $body
        Write-WinToolUtf8File -Path $path -Text $updated -Bom
        Write-WinToolLog -Message "Updated $path" -Level "ok"
    }
}

function ConvertTo-WinToolFontToken {
    param(
        [AllowEmptyString()][string]$Text
    )
    return ([string]$Text).ToLowerInvariant().Replace(" ", "").Replace("-", "").Replace("_", "")
}

function Find-WinToolInstalledFontFile {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [object[]]$Entry
    )
    # Entries are registry font values: Name like "CaskaydiaCoveNerdFont-Regular
    # (TrueType)", Data the file. The regular style is preferred, and the
    # proportional Nerd Font variant is skipped when another one exists.
    if ($null -eq $Entry) {
        $Entry = @(Get-WinToolRegisteredFont)
    }
    $want = ConvertTo-WinToolFontToken -Text $Token
    if ([string]::IsNullOrWhiteSpace($want)) {
        return $null
    }
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Entry)) {
        $name = ConvertTo-WinToolFontToken -Text ([string]$item.Name)
        $file = ConvertTo-WinToolFontToken -Text ([System.IO.Path]::GetFileName([string]$item.Data))
        if ($name.Contains($want) -or $file.Contains($want)) {
            $hits.Add($item)
        }
    }
    if ($hits.Count -eq 0) {
        return $null
    }
    $best = $null
    $bestScore = -1
    foreach ($item in $hits) {
        $text = ConvertTo-WinToolFontToken -Text ([string]$item.Name)
        $score = 0
        if ($text.Contains("regular")) { $score += 2 }
        if (-not $text.Contains("propo")) { $score += 1 }
        # Mono is the terminal face. Proportional and Propo stay usable, just behind it.
        if ($text.Contains("mono") -and -not $text.Contains("propo")) { $score += 1 }
        if ($score -gt $bestScore) {
            $best = $item
            $bestScore = $score
        }
    }
    return $best
}

function Get-WinToolRegisteredFont {
    if (-not (Test-WinToolWindows)) {
        return @()
    }
    if ($null -ne $script:WinToolRegisteredFontCache) {
        return @($script:WinToolRegisteredFontCache)
    }
    $list = New-Object System.Collections.Generic.List[object]
    $sources = @(
        @{ Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; Folder = (Join-Path $env:windir "Fonts"); Source = "HKLM" },
        @{ Key = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; Folder = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"); Source = "HKCU" }
    )
    foreach ($source in $sources) {
        if (-not (Test-Path -LiteralPath $source.Key)) {
            continue
        }
        $item = Get-Item -LiteralPath $source.Key
        foreach ($name in @($item.GetValueNames())) {
            if ([string]::IsNullOrWhiteSpace([string]$name)) {
                continue
            }
            $data = [string]$item.GetValue($name)
            if (-not [string]::IsNullOrWhiteSpace($data) -and -not [System.IO.Path]::IsPathRooted($data)) {
                $data = Join-Path $source.Folder $data
            }
            $list.Add([pscustomobject]@{ Name = [string]$name; Data = $data; Source = [string]$source.Source })
        }
    }
    $script:WinToolRegisteredFontCache = $list.ToArray()
    return @($script:WinToolRegisteredFontCache)
}

function Get-WinToolFontFamilyName {
    param(
        [string]$Path
    )
    # The family name inside the file is what Terminal needs in "face".
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        Add-Type -AssemblyName PresentationCore
        $glyph = New-Object System.Windows.Media.GlyphTypeface ([uri]$Path)
        $names = $glyph.Win32FamilyNames
        $english = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
        if ($names.ContainsKey($english)) {
            return [string]$names[$english]
        }
        foreach ($value in $names.Values) {
            return [string]$value
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    return $null
}

function Reset-WinToolFontResolution {
    # Drop cached faces after a font is installed or removed. The theme list
    # rebuilds its pictures the next time the preview font changes.
    $script:WinToolRegisteredFontCache = $null
    $script:WinToolLoadedFontCache = $null
    $script:WinToolGlyphCache = $null
    $script:WinToolFileFamilyCache = $null
    $script:WinToolResolvedFontMap = $null
    $script:WinToolPreviewFontChain = $null
    $script:WinToolPreviewFontChainKey = $null
    $script:WinToolThemePreviewFontKey = $null
    Reset-WinToolPreviewDrawCache
}

function Reset-WinToolPreviewDrawCache {
    # Outline and picture caches are filled while painting. Drop them when a
    # font is installed or a test wants a cold measurement.
    if ($null -ne ("WinToolGlyphDraw" -as [type])) { [WinToolGlyphDraw]::Clear() }
    $script:WinToolPreviewImageCache = @{}
    $script:WinToolCoveredTextCache = @{}
    $script:WinToolLivePreviewCache = @{}
    $script:WinToolLastPreviewDrawn = @()
}

function Get-WinToolTextCode {
    param(
        [AllowEmptyString()][string]$Text
    )
    # One UTF-32 codepoint per item, so an emoji is not split into surrogates.
    $codes = New-Object System.Collections.Generic.List[int]
    $chars = ([string]$Text).ToCharArray()
    for ($index = 0; $index -lt $chars.Length; $index++) {
        $char = $chars[$index]
        if ([char]::IsHighSurrogate($char) -and ($index + 1) -lt $chars.Length -and [char]::IsLowSurrogate($chars[$index + 1])) {
            $codes.Add([char]::ConvertToUtf32($char, $chars[$index + 1]))
            $index++
        }
        else {
            $codes.Add([int]$char)
        }
    }
    return $codes.ToArray()
}

function ConvertTo-WinToolGlyphFallback {
    param(
        [int]$Code
    )
    # Used only when no loaded face has the codepoint. The result is ASCII,
    # so Consolas can draw it and the preview never shows an empty box.
    if ($null -eq $script:WinToolGlyphFallback) {
        $map = @{}
        # code=ascii, one row each. A nested array would be flattened by PowerShell.
        $rows = @"
00BB=>
03BB=L
2039=<
203A=>
2261==
2302=^
2500=-
250C=+
256D=+
2591=.
2592=:
2593=#
25B3=^
25B6=>
25C9=*
25CE=o
2665=<3
276F=>
279C=>
27A4=>
2B22=*
E0A0=git
E0B0=>
E0B1=>
E0B2=<
E0B4=>
E0B6=<
E0B8=>
E0BA=<
E0C4=>
E0C5=<
E0C6=>
E0C7=<
E0D7=/
E70F=ps
E718=js
E795=>
E7AD=py
F07B=/
F07C=/
F105=>
F126=git
F418=git
F432=>
F43A=:
F489=.
1F3E0=home
1F4AC=msg
1F600=:)
"@
        foreach ($row in ($rows -split "`n")) {
            $line = $row.Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $splitAt = $line.IndexOf("=")
            $map[[Convert]::ToInt32($line.Substring(0, $splitAt), 16)] = $line.Substring($splitAt + 1)
        }
        $script:WinToolGlyphFallback = $map
    }
    $key = [int]$Code
    if ($script:WinToolGlyphFallback.ContainsKey($key)) {
        return [string]$script:WinToolGlyphFallback[$key]
    }
    if (($key -ge 0xE000 -and $key -le 0xF8FF) -or $key -gt 0xFFFF) {
        return ">"
    }
    return $null
}

function Add-WinToolPreviewSampleValue {
    param(
        $Value,
        $List
    )
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in @($Value)) {
            Add-WinToolPreviewSampleValue -Value $item -List $List
        }
        return
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        $name = [string]$property.Name
        if (($name -eq "text" -or $name -eq "Text") -and $property.Value -is [string] -and -not [string]::IsNullOrEmpty([string]$property.Value)) {
            [void]$List.Add([string]$property.Value)
        }
        else {
            Add-WinToolPreviewSampleValue -Value $property.Value -List $List
        }
    }
}

function Get-WinToolPreviewSampleText {
    # Every string the prompt previews draw, including the folder and file
    # icons on the live sample. Callers use this to check glyph coverage.
    $list = New-Object System.Collections.Generic.List[string]
    Add-WinToolPreviewSampleValue -Value (Get-WinToolOhMyPoshDocument) -List $list
    Add-WinToolPreviewSampleValue -Value (Get-WinToolTerminalCatalog) -List $list
    [void]$list.Add([string][char]0xF07B)
    [void]$list.Add([string][char]0xF489)
    [void]$list.Add([string][char]0xE0B0)
    return $list.ToArray()
}

function Get-WinToolGlyphFamilyName {
    param(
        $Glyph,
        [string]$Table = "family",
        [switch]$All
    )
    # Every stored family name when -All is set. The file URI has to use the
    # one WPF accepts, and the two name tables do not always agree.
    if ($null -eq $Glyph) {
        if ($All) { return @() }
        return $null
    }
    # The file URI wants the Win32 name more often than the typographic one.
    if ($All) { $tables = @($Glyph.Win32FamilyNames, $Glyph.FamilyNames) }
    elseif ($Table -eq "win32") { $tables = @($Glyph.Win32FamilyNames) }
    else { $tables = @($Glyph.FamilyNames) }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($names in $tables) {
        if ($null -eq $names) { continue }
        if (-not $All) {
            $english = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
            if ($names.ContainsKey($english)) { return [string]$names[$english] }
            foreach ($value in $names.Values) { return [string]$value }
            return $null
        }
        foreach ($value in @($names.Values)) {
            $name = [string]$value
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if (-not $found.Contains($name)) { [void]$found.Add($name) }
        }
    }
    if ($All) { return $found.ToArray() }
    return $null
}

function Get-WinToolTypefaceGlyph {
    param($Typeface)
    if ($null -eq $Typeface) { return $null }
    $loaded = $null
    $ok = $false
    try {
        $ok = $Typeface.TryGetGlyphTypeface([ref]$loaded)
    }
    catch {
        $null = $_.Exception.Message
        return $null
    }
    if (-not $ok -or $null -eq $loaded) { return $null }
    return $loaded
}

function Initialize-WinToolGlyphMap {
    # PowerShell's call into CharacterToGlyphMap is unreliable on 5.1.
    # Glyph 0 is the font's empty box, so a codepoint that maps to it is missing.
    if ($null -ne ("WinToolGlyphMap" -as [type])) { return }
    Add-Type -AssemblyName PresentationCore
    Add-Type -ReferencedAssemblies ([System.Windows.Media.GlyphTypeface].Assembly.Location) -TypeDefinition @"
using System.Windows.Media;
public static class WinToolGlyphMap {
    public static bool Has(GlyphTypeface face, int code) {
        if (face == null) return false;
        ushort index;
        return face.CharacterToGlyphMap.TryGetValue(code, out index) && index > 0;
    }
}
"@
}

function Test-WinToolGlyphMapped {
    param(
        $Glyph,
        [int]$Code
    )
    if ($null -eq $Glyph -or -not (Test-WinToolWindows)) { return $false }
    Initialize-WinToolGlyphMap
    return [WinToolGlyphMap]::Has($Glyph, [int]$Code)
}

function Initialize-WinToolGlyphDraw {
    # GlyphRun and GetGlyphOutline live here so previews can paint a file
    # face without going through FontFamily by name.
    if ($null -ne ("WinToolGlyphDraw" -as [type])) { return }
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    $refs = @(
        [System.Windows.Media.GlyphTypeface].Assembly.Location,
        [System.Windows.Point].Assembly.Location
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
public static class WinToolGlyphDraw {
    static readonly Dictionary<string, Dictionary<int, bool>> OutlineCache = new Dictionary<string, Dictionary<int, bool>>(StringComparer.OrdinalIgnoreCase);

    static string FaceKey(GlyphTypeface face) {
        if (face == null) return "";
        try {
            Uri uri = face.FontUri;
            if (uri != null) return uri.ToString();
        }
        catch {
        }
        return "h:" + face.GetHashCode().ToString();
    }

    public static void Clear() {
        OutlineCache.Clear();
    }

    public static bool HasOutline(GlyphTypeface face, int code) {
        if (face == null) return false;
        string key = FaceKey(face);
        Dictionary<int, bool> map;
        if (!OutlineCache.TryGetValue(key, out map)) {
            map = new Dictionary<int, bool>();
            OutlineCache[key] = map;
        }
        bool cached;
        if (map.TryGetValue(code, out cached)) return cached;
        bool drawn = MeasureOutline(face, code);
        map[code] = drawn;
        return drawn;
    }

    static bool MeasureOutline(GlyphTypeface face, int code) {
        ushort index;
        if (!face.CharacterToGlyphMap.TryGetValue(code, out index) || index == 0) return false;
        try {
            Geometry geometry = face.GetGlyphOutline(index, 12.0, 12.0);
            if (geometry == null || geometry.IsEmpty()) return false;
            Rect bounds = geometry.Bounds;
            return bounds.Width > 0.15 || bounds.Height > 0.15;
        }
        catch {
            return false;
        }
    }

    public static GlyphRun MakeRun(GlyphTypeface face, int[] codes, double emSize, double x, double y) {
        if (face == null || codes == null || codes.Length == 0 || emSize <= 0) return null;
        List<ushort> indices = new List<ushort>();
        List<double> advances = new List<double>();
        for (int i = 0; i < codes.Length; i++) {
            ushort index;
            if (!face.CharacterToGlyphMap.TryGetValue(codes[i], out index) || index == 0) continue;
            indices.Add(index);
            advances.Add(face.AdvanceWidths[index] * emSize);
        }
        if (indices.Count == 0) return null;
        return new GlyphRun(
            face,
            0,
            false,
            emSize,
            1.0f,
            indices,
            new Point(x, y),
            advances,
            null,
            null,
            null,
            null,
            null,
            null);
    }

    public static double Measure(GlyphTypeface face, int[] codes, double emSize) {
        if (face == null || codes == null || emSize <= 0) return 0;
        double width = 0;
        for (int i = 0; i < codes.Length; i++) {
            ushort index;
            if (!face.CharacterToGlyphMap.TryGetValue(codes[i], out index) || index == 0) continue;
            width += face.AdvanceWidths[index] * emSize;
        }
        return width;
    }

    public static double LineHeight(GlyphTypeface face, double emSize) {
        if (face == null || emSize <= 0) return emSize;
        double height = face.Height * emSize;
        if (height <= 0) return emSize * 1.2;
        return height;
    }

    public static double Baseline(GlyphTypeface face, double emSize) {
        if (face == null || emSize <= 0) return emSize * 0.8;
        double baseline = face.Baseline * emSize;
        if (baseline <= 0) return emSize * 0.8;
        return baseline;
    }
}
"@
}

function Test-WinToolGlyphDrawable {
    param(
        $Glyph,
        [int]$Code
    )
    # A cmap hit is not enough: some faces reserve a private-use slot and
    # still draw an empty box. Spaces are advance-only and have no outline.
    if (-not (Test-WinToolGlyphMapped -Glyph $Glyph -Code $Code)) { return $false }
    if ($Code -eq 0x20 -or $Code -eq 0xA0 -or $Code -eq 0x3000) { return $true }
    Initialize-WinToolGlyphDraw
    return [WinToolGlyphDraw]::HasOutline($Glyph, [int]$Code)
}

function Test-WinToolSameFontFile {
    param(
        $Glyph,
        [string]$Path
    )
    # TryGetGlyphTypeface can hand back a different installed face. The preview
    # only keeps a family whose glyph file is the one that was opened.
    if ($null -eq $Glyph -or [string]::IsNullOrWhiteSpace($Path)) { return $false }
    $fontUri = $null
    try { $fontUri = $Glyph.FontUri } catch { $null = $_.Exception.Message; return $false }
    if ($null -eq $fontUri -or -not $fontUri.IsFile) { return $false }
    try {
        $left = [System.IO.Path]::GetFullPath($fontUri.LocalPath)
        $right = [System.IO.Path]::GetFullPath($Path)
        return $left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        $null = $_.Exception.Message
        return $false
    }
}

function Get-WinToolFontFolderUri {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    # WPF wants the folder, with a trailing slash, as the base URI.
    $full = [System.IO.Path]::GetFullPath($Path)
    $folder = [System.IO.Path]::GetDirectoryName($full)
    $slash = [System.IO.Path]::DirectorySeparatorChar
    if (-not $folder.EndsWith([string]$slash) -and -not $folder.EndsWith("/")) {
        $folder = $folder + $slash
    }
    return New-Object System.Uri -ArgumentList $folder, ([System.UriKind]::Absolute)
}

function Test-WinToolFileTypeface {
    param(
        [string]$Path,
        [string]$FamilyName
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($FamilyName)) { return $null }
    if ($null -eq $script:WinToolFileFamilyCache) { $script:WinToolFileFamilyCache = @{} }
    $full = [System.IO.Path]::GetFullPath($Path)
    $fileName = [System.IO.Path]::GetFileName($full)
    $baseUri = $null
    try {
        $baseUri = Get-WinToolFontFolderUri -Path $full
    }
    catch {
        $null = $_.Exception.Message
        return $null
    }
    # Folder URI plus ./file.ttf#Family is the documented WPF form. ./#Family
    # loads any face in that folder and is the fallback when the file name
    # is not accepted.
    $forms = @(
        ("./" + $fileName + "#" + $FamilyName),
        ("./#" + $FamilyName)
    )
    foreach ($form in $forms) {
        $familyKey = $full + "|" + $form
        $family = $null
        if ($script:WinToolFileFamilyCache.ContainsKey($familyKey)) {
            $family = $script:WinToolFileFamilyCache[$familyKey]
        }
        else {
            try {
                $family = New-Object System.Windows.Media.FontFamily -ArgumentList $baseUri, $form
            }
            catch {
                $null = $_.Exception.Message
                $family = $null
            }
            # FontFamily is not freezable. The object itself is the cache.
            $script:WinToolFileFamilyCache[$familyKey] = $family
        }
        if ($null -eq $family) { continue }
        $typeface = $null
        $drawn = $null
        try {
            $typeface = New-Object System.Windows.Media.Typeface(
                $family,
                [System.Windows.FontStyles]::Normal,
                [System.Windows.FontWeights]::Normal,
                [System.Windows.FontStretches]::Normal)
            $drawn = Get-WinToolTypefaceGlyph -Typeface $typeface
        }
        catch {
            $null = $_.Exception.Message
            $drawn = $null
        }
        if ($null -eq $drawn) { continue }
        if (-not (Test-WinToolSameFontFile -Glyph $drawn -Path $Path)) { continue }
        if ($drawn.CanFreeze) {
            try { $drawn.Freeze() } catch { $null = $_.Exception.Message }
        }
        return [pscustomobject]@{ Family = $family; Typeface = $typeface; Glyph = $drawn }
    }
    return $null
}

function New-WinToolLoadedFont {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [bool]$Nerd = $false,
        [string]$Id = "",
        [string]$Face = "",
        [string]$Name = "",
        [string]$Source = ""
    )
    # WPF does not see per-user fonts by family name. The face is opened
    # from the file, and FontFamily uses the folder URI plus ./file.ttf#Name.
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $null }
    if ($null -eq $script:WinToolLoadedFontCache) { $script:WinToolLoadedFontCache = @{} }
    $cacheKey = $Path + "|" + $Id
    if ($script:WinToolLoadedFontCache.ContainsKey($cacheKey)) {
        return $script:WinToolLoadedFontCache[$cacheKey]
    }
    $record = $null
    try {
        Add-Type -AssemblyName PresentationCore
        if ($null -eq $script:WinToolGlyphCache) { $script:WinToolGlyphCache = @{} }
        $glyph = $null
        if ($script:WinToolGlyphCache.ContainsKey($Path)) {
            $glyph = $script:WinToolGlyphCache[$Path]
        }
        else {
            $glyph = New-Object System.Windows.Media.GlyphTypeface ([uri]$Path)
            $script:WinToolGlyphCache[$Path] = $glyph
        }
        if ($glyph.CanFreeze) {
            try { $glyph.Freeze() } catch { $null = $_.Exception.Message }
        }
        $loadedFace = $null
        foreach ($familyName in @(Get-WinToolGlyphFamilyName -Glyph $glyph -All)) {
            $loadedFace = Test-WinToolFileTypeface -Path $Path -FamilyName $familyName
            if ($null -ne $loadedFace) { break }
        }
        if ($null -eq $loadedFace) { throw "The font file did not load." }
        $family = $loadedFace.Family
        $typeface = $loadedFace.Typeface
        $drawn = $loadedFace.Glyph
        $record = [pscustomobject]@{
            Id = $Id
            Face = $Face
            Name = $Name
            Path = $Path
            Source = $Source
            FamilyName = ""
            Family = $family
            Typeface = $typeface
            Glyph = $drawn
            Nerd = [bool]$Nerd
        }
        try {
            $record.FamilyName = [string](Get-WinToolGlyphFamilyName -Glyph $glyph -Table "win32")
            if ([string]::IsNullOrWhiteSpace([string]$record.FamilyName)) {
                $record.FamilyName = [string](Get-WinToolGlyphFamilyName -Glyph $glyph -Table "family")
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    catch {
        $null = $_.Exception.Message
        $record = $null
    }
    $script:WinToolLoadedFontCache[$cacheKey] = $record
    return $record
}

function Test-WinToolNerdFontRecord {
    param(
        $Record,
        [string]$RegistryName
    )
    if ($null -eq $Record) { return $false }
    $blob = ConvertTo-WinToolFontToken -Text (([string]$Record.FamilyName) + " " + $RegistryName + " " + [System.IO.Path]::GetFileName([string]$Record.Path))
    return $blob.Contains("nerd")
}

function Get-WinToolResolvedFontMap {
    if ($null -ne $script:WinToolResolvedFontMap) { return $script:WinToolResolvedFontMap }
    $map = @{}
    if (Test-WinToolWindows) {
        $registered = @(Get-WinToolRegisteredFont)
        $fonts = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())
        foreach ($extra in @($script:WinToolExtraFont)) {
            if ($null -ne $extra) { $fonts += $extra }
        }
        foreach ($font in $fonts) {
            $match = [string](Get-WinToolNote -Object $font -Name "match" -Default "")
            if ([string]::IsNullOrWhiteSpace($match)) { $match = [string]$font.face }
            $found = Find-WinToolInstalledFontFile -Token $match -Entry $registered
            if ($null -eq $found) { continue }
            $nerd = ($null -ne $font.PSObject.Properties["nerd"] -and [bool]$font.nerd)
            $loaded = New-WinToolLoadedFont -Path ([string]$found.Data) -Nerd $nerd -Id ([string]$font.id) -Face ([string]$font.face) -Name ([string]$font.name) -Source ([string]$found.Source)
            if ($null -eq $loaded) { continue }
            if ($nerd -and -not (Test-WinToolNerdFontRecord -Record $loaded -RegistryName ([string]$found.Name))) { continue }
            $map[[string]$font.id] = $loaded
        }
    }
    $script:WinToolResolvedFontMap = $map
    return $map
}

function Get-WinToolResolvableFont {
    # Catalog rows whose font file opened. The dropdown lists only these.
    $map = Get-WinToolResolvedFontMap
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($font in @(Get-WinToolActiveFont)) {
        if ($map.ContainsKey([string]$font.id)) { [void]$rows.Add($font) }
    }
    return $rows.ToArray()
}

function Test-WinToolFontResolve {
    param(
        [Parameter(Mandatory = $true)][string]$Id
    )
    return (Get-WinToolResolvedFontMap).ContainsKey($Id)
}

function Get-WinToolSystemFont {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$FileName
    )
    if (-not (Test-WinToolWindows)) { return $null }
    $path = ""
    $source = "HKLM"
    $found = Find-WinToolInstalledFontFile -Token $Token
    if ($null -ne $found -and -not [string]::IsNullOrWhiteSpace([string]$found.Data) -and (Test-Path -LiteralPath ([string]$found.Data))) {
        $path = [string]$found.Data
        $source = [string]$found.Source
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        $candidate = Join-Path (Join-Path $env:windir "Fonts") $FileName
        if (Test-Path -LiteralPath $candidate) { $path = $candidate }
    }
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return (New-WinToolLoadedFont -Path $path -Nerd $false -Id $Token -Face $Token -Name $Token -Source $source)
}

function Get-WinToolBestNerdFont {
    # Prefer CaskaydiaCove Nerd Font Mono, then the proportional Cove face,
    # then any other installed Nerd Font.
    $map = Get-WinToolResolvedFontMap
    $best = $null
    $bestScore = -1
    foreach ($id in @($map.Keys)) {
        $record = $map[$id]
        if ($null -eq $record -or -not $record.Nerd) { continue }
        $family = [string]$record.FamilyName
        $score = 1
        if ($family -eq "CaskaydiaCove Nerd Font Mono") { $score += 100 }
        elseif ($family -eq "CaskaydiaCove Nerd Font") { $score += 80 }
        elseif ([string]$id -eq "cascadiacode-nf") { $score += 60 }
        elseif ([string]$id -eq "cascadiamono-nf") { $score += 40 }
        if ($family.IndexOf("Mono", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $family.IndexOf("Propo", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $score += 10
        }
        if ($score -gt $bestScore) {
            $best = $record
            $bestScore = $score
        }
    }
    return $best
}

function Get-WinToolPreviewFontKey {
    $selectedId = ""
    if ($null -ne $script:WinToolTerminalChoice) { $selectedId = [string]$script:WinToolTerminalChoice.fontId }
    $bestPath = ""
    $best = Get-WinToolBestNerdFont
    if ($null -ne $best) { $bestPath = [string]$best.Path }
    return ($selectedId + "|" + $bestPath)
}

function Get-WinToolPreviewFontChain {
    # Selected Nerd Font, then the best installed Nerd Font, then faces that
    # cover symbols, emoji, and ASCII. Missing codepoints are substituted.
    $key = Get-WinToolPreviewFontKey
    if ($key -eq [string]$script:WinToolPreviewFontChainKey -and $null -ne $script:WinToolPreviewFontChain) {
        return @($script:WinToolPreviewFontChain)
    }
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $selectedId = ""
    if ($null -ne $script:WinToolTerminalChoice) { $selectedId = [string]$script:WinToolTerminalChoice.fontId }
    $map = Get-WinToolResolvedFontMap
    $candidates = New-Object System.Collections.Generic.List[object]
    if (-not [string]::IsNullOrWhiteSpace($selectedId) -and $map.ContainsKey($selectedId)) {
        [void]$candidates.Add($map[$selectedId])
    }
    $bestNerd = Get-WinToolBestNerdFont
    if ($null -ne $bestNerd) { [void]$candidates.Add($bestNerd) }
    foreach ($systemFont in @(
            (Get-WinToolSystemFont -Token "Segoe UI Symbol" -FileName "seguisym.ttf"),
            (Get-WinToolSystemFont -Token "Segoe UI Emoji" -FileName "seguiemj.ttf"),
            (Get-WinToolSystemFont -Token "Consolas" -FileName "consola.ttf")
        )) {
        if ($null -ne $systemFont) { [void]$candidates.Add($systemFont) }
    }
    foreach ($record in $candidates) {
        $path = [string]$record.Path
        if ([string]::IsNullOrWhiteSpace($path) -or $seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        [void]$list.Add($record)
    }
    if ($list.Count -eq 0 -and (Test-WinToolWindows)) {
        try {
            Add-Type -AssemblyName PresentationCore
            $family = [System.Windows.Media.FontFamily]::new("Consolas")
            $typeface = New-Object System.Windows.Media.Typeface(
                $family,
                [System.Windows.FontStyles]::Normal,
                [System.Windows.FontWeights]::Normal,
                [System.Windows.FontStretches]::Normal)
            $glyph = Get-WinToolTypefaceGlyph -Typeface $typeface
            if ($null -ne $glyph) {
                [void]$list.Add([pscustomobject]@{
                    Id = "Consolas"; Face = "Consolas"; Name = "Consolas"; Path = "Consolas"; Source = "name"
                    FamilyName = "Consolas"; Family = $family; Typeface = $typeface; Glyph = $glyph; Nerd = $false
                })
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    $script:WinToolPreviewFontChain = $list.ToArray()
    $script:WinToolPreviewFontChainKey = $key
    return @($script:WinToolPreviewFontChain)
}

function Split-WinToolCoveredText {
    param(
        [AllowEmptyString()][string]$Text
    )
    # Break the text into runs that each fit one loaded face. A codepoint no
    # face can draw is replaced with ASCII before it becomes an empty box.
    $result = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    if ($null -eq $script:WinToolCoveredTextCache) { $script:WinToolCoveredTextCache = @{} }
    $coverKey = (Get-WinToolPreviewFontKey) + "`n" + $Text
    if ($script:WinToolCoveredTextCache.ContainsKey($coverKey)) {
        return @($script:WinToolCoveredTextCache[$coverKey])
    }
    $chain = @(Get-WinToolPreviewFontChain)
    $builder = New-Object System.Text.StringBuilder
    $current = $null
    foreach ($code in @(Get-WinToolTextCode -Text $Text)) {
        $privateUse = ($code -ge 0xE000 -and $code -le 0xF8FF)
        $face = $null
        foreach ($item in $chain) {
            # A system face can claim a private-use slot and still draw an empty
            # box. Those icons stay only when the face is a Nerd Font.
            if ($privateUse -and -not $item.Nerd) { continue }
            if (Test-WinToolGlyphDrawable -Glyph $item.Glyph -Code $code) { $face = $item; break }
        }
        $chunk = [char]::ConvertFromUtf32($code)
        if ($null -eq $face) {
            $chunk = ConvertTo-WinToolGlyphFallback -Code $code
            if ([string]::IsNullOrEmpty($chunk)) { $chunk = ">" }
            foreach ($item in $chain) {
                $fits = $true
                foreach ($part in @(Get-WinToolTextCode -Text $chunk)) {
                    if (-not (Test-WinToolGlyphDrawable -Glyph $item.Glyph -Code $part)) { $fits = $false; break }
                }
                if ($fits) { $face = $item; break }
            }
            if ($null -eq $face -and $chain.Count -gt 0) { $face = $chain[$chain.Count - 1] }
        }
        if ($null -eq $face) { continue }
        $same = ($null -ne $current -and [string]$current.Path -eq [string]$face.Path)
        if (-not $same) {
            if ($builder.Length -gt 0 -and $null -ne $current) {
                [void]$result.Add([pscustomobject]@{
                    Text = $builder.ToString()
                    Path = [string]$current.Path
                    Family = $current.Family
                    Typeface = $current.Typeface
                    Glyph = $current.Glyph
                })
            }
            [void]$builder.Clear()
            $current = $face
        }
        [void]$builder.Append($chunk)
    }
    if ($builder.Length -gt 0 -and $null -ne $current) {
        [void]$result.Add([pscustomobject]@{
            Text = $builder.ToString()
            Path = [string]$current.Path
            Family = $current.Family
            Typeface = $current.Typeface
            Glyph = $current.Glyph
        })
    }
    $pieces = $result.ToArray()
    if ($script:WinToolCoveredTextCache.Count -lt 1024) {
        $script:WinToolCoveredTextCache[$coverKey] = $pieces
    }
    return $pieces
}

function Test-WinToolPreviewTextCovered {
    param(
        [AllowEmptyString()][string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) { return $true }
    $pieces = @(Split-WinToolCoveredText -Text $Text)
    if ($pieces.Count -eq 0) { return $false }
    foreach ($piece in $pieces) {
        $pieceText = [string]$piece.Text
        if ([string]::IsNullOrEmpty($pieceText)) { return $false }
        foreach ($code in @(Get-WinToolTextCode -Text $pieceText)) {
            if (-not (Test-WinToolGlyphDrawable -Glyph $piece.Glyph -Code $code)) { return $false }
        }
    }
    return $true
}

function Sync-WinToolPreviewGlyphCache {
    # Fill the outline cache for the visible theme samples and the live
    # preview alphabet so a later click does not call GetGlyphOutline.
    $builder = New-Object System.Text.StringBuilder
    foreach ($row in @($script:WinToolTerminalRows)) {
        if ($null -eq $row) { continue }
        foreach ($segment in @($row.Preview)) {
            if ($null -ne $segment) { [void]$builder.Append([string]$segment.Text) }
        }
    }
    [void]$builder.Append(" PowerShell 7 Ubuntu on WSL zsh fish git status On branch main Changes not staged for commit: modified: src/app.ts const same = (a, b) => a === b || a >= b; cd wintool z wintool ls assets build data src wintool.ps1 head -1 ")
    if ($builder.Length -eq 0) { return }
    $null = Split-WinToolCoveredText -Text $builder.ToString()
}

function Resolve-WinToolInstalledFontFace {
    param(
        [Parameter(Mandatory = $true)][string]$Face,
        [string]$Match
    )
    # Returns the face to write into Terminal settings, or $null (with a
    # warning) when the font is not installed.
    $chosen = $Face
    if (-not [string]::IsNullOrWhiteSpace($Match) -and (Test-WinToolWindows)) {
        $found = Find-WinToolInstalledFontFile -Token $Match
        if ($null -eq $found) {
            Write-WinToolLog -Message ("{0} is not installed, so the Windows Terminal font was left as it is. Run terminal setup again after the font installs." -f $Face) -Level "warn"
            return $null
        }
        $family = Get-WinToolFontFamilyName -Path ([string]$found.Data)
        if (-not [string]::IsNullOrWhiteSpace($family)) {
            $chosen = $family
        }
        if ($chosen -ne $Face) {
            Write-WinToolLog -Message "Using the installed font name: $chosen" -Level "info"
        }
    }
    return $chosen
}

function Invoke-WinToolTerminalFont {
    param(
        [Parameter(Mandatory = $true)][string]$Face,
        [string]$Match,
        [int]$Size = 12
    )
    if ($Size -lt 6 -or $Size -gt 48) { $Size = 12 }
    $chosen = Resolve-WinToolInstalledFontFace -Face $Face -Match $Match
    if ($null -eq $chosen) {
        return
    }
    $path = Get-WinToolTerminalSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-WinToolLog -Message "Windows Terminal settings were not found. Open Terminal once, then run terminal setup again to set the font." -Level "warn"
        return
    }
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path) {
        Backup-WinToolTerminalSetting -Path $path
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $settings = ConvertFrom-WinToolJsonText -Text $raw
        }
    }
    Add-WinToolTerminalFont -Settings $settings -Face $chosen -Size $Size | Out-Null
    $json = ConvertTo-WinToolJsonText -Value $settings
    Write-WinToolUtf8File -Path $path -Text ($json + "`n")
    Write-WinToolLog -Message "Set the Windows Terminal font to $chosen. Comments in settings.json are not kept." -Level "ok"
}

function Invoke-WinToolTerminalScheme {
    param(
        [Parameter(Mandatory = $true)][string]$SchemeId
    )
    $scheme = $null
    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
        if ([string]$item.id -eq $SchemeId) {
            $scheme = $item
            break
        }
    }
    if ($null -eq $scheme) {
        Write-WinToolLog -Message "Unknown color scheme '$SchemeId'." -Level "warn"
        return
    }
    $path = Get-WinToolTerminalSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-WinToolLog -Message "Windows Terminal settings were not found, so the color scheme was skipped." -Level "warn"
        return
    }
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path) {
        Backup-WinToolTerminalSetting -Path $path
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $settings = ConvertFrom-WinToolJsonText -Text $raw
        }
    }
    Add-WinToolTerminalScheme -Settings $settings -Scheme $scheme | Out-Null
    Write-WinToolUtf8File -Path $path -Text ((ConvertTo-WinToolJsonText -Value $settings) + "`n")
    Write-WinToolLog -Message "Set the Windows Terminal color scheme to $($scheme.name)." -Level "ok"
}

function Invoke-WinToolStarshipPreset {
    param(
        [Parameter(Mandatory = $true)][string]$Preset
    )
    Sync-WinToolProcessPath
    $command = Get-Command -Name "starship" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        foreach ($candidate in @(
                ([string]$env:ProgramFiles + "\starship\bin\starship.exe"),
                ([string]$env:LOCALAPPDATA + "\Programs\starship\bin\starship.exe"),
                ([string]$env:LOCALAPPDATA + "\Microsoft\WinGet\Links\starship.exe"),
                ([string]$env:USERPROFILE + "\.cargo\bin\starship.exe")
            )) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
                $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
                break
            }
        }
    }
    if ($null -eq $command) {
        Write-WinToolLog -Message "Starship is not on PATH yet, so the preset was skipped." -Level "warn"
        return
    }
    $directory = Join-Path $env:USERPROFILE ".config"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $destination = Join-Path $directory "starship.toml"
    $global:LASTEXITCODE = 0
    & $command.Source preset $Preset -o $destination
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destination)) {
        Write-WinToolLog -Message ("Starship could not apply the preset '{0}' (exit {1})." -f $Preset, $LASTEXITCODE) -Level "warn"
        return
    }
    Write-WinToolLog -Message "Wrote the Starship preset to $destination." -Level "ok"
}

function Get-WinToolFontInstallStep {
    param(
        [Parameter(Mandatory = $true)]$Font
    )
    # Nerd Fonts come from the official ryanoasis/nerd-fonts release. Plain
    # fonts come from their own GitHub releases, or from winget only when the
    # id was checked in winget-pkgs (fonts.json keeps just those).
    $name = [string]$Font.name
    $wingetId = [string](Get-WinToolNote -Object $Font -Name "wingetId" -Default "")
    $asset = [string](Get-WinToolNote -Object $Font -Name "asset" -Default "")
    $github = Get-WinToolNote -Object $Font -Name "github"
    if (-not [string]::IsNullOrWhiteSpace($asset)) {
        $release = [string](Get-WinToolNote -Object $Font -Name "release" -Default "")
        if ([string]::IsNullOrWhiteSpace($release)) {
            $release = [string](Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "nerdFontsRelease" -Default "v3.5.1")
        }
        return @([pscustomobject]@{ Type = "font-download"; Label = ("Download " + $name); Release = $release; Asset = $asset; Face = [string]$Font.face })
    }
    if ($null -ne $github) {
        return @([pscustomobject]@{ Type = "font-download"; Label = ("Download " + $name); Repo = [string]$github.repo; AssetPattern = [string]$github.asset; Files = @($github.files); Face = [string]$Font.face })
    }
    if (-not [string]::IsNullOrWhiteSpace($wingetId)) {
        return @([pscustomobject]@{ Type = "winget"; Label = ("Install " + $name); WingetId = $wingetId; Scope = "" })
    }
    return @()
}

function Get-WinToolFontDownloadScript {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    # Two kinds of source: a Nerd Fonts release zip (fixed release and file
    # name), or the latest release of a font's own GitHub repository, found
    # by a file name pattern. Fonts go to the user's font folder and are
    # registered for the user, then loaded so Terminal sees them right away.
    $url = ""
    $release = [string](Get-WinToolNote -Object $Step -Name "Release" -Default "")
    $asset = [string](Get-WinToolNote -Object $Step -Name "Asset" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($asset)) {
        $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/" + $release + "/" + $asset
    }
    $repo = [string](Get-WinToolNote -Object $Step -Name "Repo" -Default "")
    $pattern = [string](Get-WinToolNote -Object $Step -Name "AssetPattern" -Default "")
    if ([string]::IsNullOrWhiteSpace($url) -and ([string]::IsNullOrWhiteSpace($repo) -or [string]::IsNullOrWhiteSpace($pattern))) {
        throw "The font download needs a Nerd Fonts asset or a GitHub repository and file pattern."
    }
    $files = @(Get-WinToolNote -Object $Step -Name "Files" -Default @())
    $fileText = (@($files | ForEach-Object { ConvertTo-WinToolSingleQuoted -Text ([string]$_) })) -join ", "
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('$ErrorActionPreference = "Stop"')
    $lines.Add('[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12')
    $lines.Add('Add-Type -AssemblyName System.IO.Compression.FileSystem')
    $lines.Add('$url = ' + (ConvertTo-WinToolSingleQuoted -Text $url))
    $lines.Add('$repo = ' + (ConvertTo-WinToolSingleQuoted -Text $repo))
    $lines.Add('$pattern = ' + (ConvertTo-WinToolSingleQuoted -Text $pattern))
    $lines.Add('$wanted = @(' + $fileText + ')')
    $body = @'
if ([string]::IsNullOrWhiteSpace($url)) {
    $latest = Invoke-RestMethod -Uri ("https://api.github.com/repos/" + $repo + "/releases/latest") -Headers @{ "User-Agent" = "WinTool" } -UseBasicParsing
    $match = @($latest.assets | Where-Object { [string]$_.name -like $pattern })
    if ($match.Count -eq 0) {
        throw ("The latest " + $repo + " release has no file named like " + $pattern + ".")
    }
    $url = [string]$match[0].browser_download_url
    Write-Output ("Downloading " + [string]$match[0].name + " from " + $repo + " " + [string]$latest.tag_name)
}
else {
    Write-Output ("Downloading " + $url)
}
$name = [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
$zip = Join-Path $env:TEMP ("WinTool-" + $name)
$folder = Join-Path $env:TEMP ("WinTool-" + [IO.Path]::GetFileNameWithoutExtension($name))
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $folder)
$all = @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { @(".ttf", ".otf", ".ttc") -contains $_.Extension.ToLowerInvariant() })
$picked = @{}
foreach ($file in $all) {
    $take = ($wanted.Count -eq 0)
    foreach ($want in $wanted) {
        if ($file.Name -like $want) { $take = $true }
    }
    if ($take -and -not $picked.ContainsKey($file.Name.ToLowerInvariant())) {
        $picked[$file.Name.ToLowerInvariant()] = $file
    }
}
if ($picked.Count -eq 0) {
    throw ("No font files were found in " + $name + ".")
}
if (-not ("WinToolFontLoader" -as [type])) {
    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class WinToolFontLoader { [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern int AddFontResource(string file); }'
}
$dest = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
$key = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
foreach ($file in $picked.Values) {
    $target = Join-Path $dest $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $label = [IO.Path]::GetFileNameWithoutExtension($file.Name) + " (TrueType)"
    New-ItemProperty -LiteralPath $key -Name $label -Value $target -PropertyType String -Force | Out-Null
    $null = [WinToolFontLoader]::AddFontResource($target)
}
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ("Installed " + $picked.Count + " font files from " + $name)
'@
    $lines.Add($body)
    return ($lines -join [Environment]::NewLine)
}

function Get-WinToolToolDownloadScript {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$FileName
    )
    $text = @'
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$url = "URL"
$name = "FILENAME"
$dest = Join-Path $env:LOCALAPPDATA "WinTool\bin"
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
$path = Join-Path $dest $name
$part = $path + ".part"
try {
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 60
    Move-Item -LiteralPath $part -Destination $path -Force
}
finally {
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
}
Write-Output ("Downloaded " + $path)
'@
    return $text.Replace("URL", $Url).Replace("FILENAME", $FileName)
}

function Get-WinToolSimpleTerminalChoice {
    $catalog = Get-WinToolTerminalCatalog
    $simple = Get-WinToolNote -Object $catalog -Name "simple"
    return [pscustomobject]@{
        prompt = [string](Get-WinToolNote -Object $simple -Name "prompt" -Default "oh-my-posh")
        promptStyle = [string](Get-WinToolNote -Object $simple -Name "promptStyle" -Default "jandedobbeleer")
        fontId = [string](Get-WinToolNote -Object $simple -Name "fontId" -Default "cascadiacode-nf")
        schemeId = [string](Get-WinToolNote -Object $simple -Name "schemeId" -Default "wintool-night")
        terminalIcons = [bool](Get-WinToolNote -Object $simple -Name "terminalIcons" -Default $true)
        psReadLine = [bool](Get-WinToolNote -Object $simple -Name "psReadLine" -Default $true)
        zoxide = [bool](Get-WinToolNote -Object $simple -Name "zoxide" -Default $false)
        fzf = [bool](Get-WinToolNote -Object $simple -Name "fzf" -Default $false)
        fontSize = [int](Get-WinToolNote -Object $simple -Name "fontSize" -Default 12)
    }
}

function Get-WinToolTerminalSummary {
    param(
        [Parameter(Mandatory = $true)]$Selection
    )
    $plan = @(Get-WinToolTerminalPlan -Selection $Selection)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($step in $plan) {
        $lines.Add([string]$step.Label)
    }
    return $lines.ToArray()
}

function Get-WinToolTerminalPlan {
    param(
        [Parameter(Mandatory = $true)]$Selection
    )
    $catalog = Get-WinToolTerminalCatalog
    $promptId = [string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "")
    if ([string]::IsNullOrWhiteSpace($promptId)) {
        $promptId = [string](Get-WinToolNote -Object $Selection -Name "Prompt" -Default "oh-my-posh")
    }
    $promptStyle = [string](Get-WinToolNote -Object $Selection -Name "promptStyle" -Default "")
    $fontId = [string](Get-WinToolNote -Object $Selection -Name "fontId" -Default "")
    if ([string]::IsNullOrWhiteSpace($fontId)) {
        $fontId = [string](Get-WinToolNote -Object $Selection -Name "FontId" -Default "")
    }
    $schemeId = [string](Get-WinToolNote -Object $Selection -Name "schemeId" -Default "")
    $icons = Get-WinToolNote -Object $Selection -Name "terminalIcons"
    if ($null -eq $icons) { $icons = $true }
    $psReadLine = Get-WinToolNote -Object $Selection -Name "psReadLine"
    if ($null -eq $psReadLine) { $psReadLine = $false }
    $zoxide = Get-WinToolNote -Object $Selection -Name "zoxide"
    if ($null -eq $zoxide) { $zoxide = $false }
    $fzf = Get-WinToolNote -Object $Selection -Name "fzf"
    if ($null -eq $fzf) { $fzf = $false }
    $wsl = Get-WinToolNote -Object $Selection -Name "wsl"
    if ($null -eq $wsl) { $wsl = $false }
    $zsh = Get-WinToolNote -Object $Selection -Name "zsh"
    if ($null -eq $zsh) { $zsh = $false }

    $prompt = $null
    foreach ($item in @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @())) {
        if ([string]$item.id -eq $promptId) {
            $prompt = $item
            break
        }
    }
    if ($null -eq $prompt) {
        throw "Unknown terminal prompt '$promptId'."
    }
    $shellKind = [string](Get-WinToolNote -Object $prompt -Name "shell" -Default "powershell")
    if ($shellKind -like "wsl-*") {
        $wsl = $true
        $zsh = $true
    }

    $font = $null
    # Fonts added by the online refresh live in $script:WinToolExtraFont.
    $fontRows = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @()) + @($script:WinToolExtraFont | Where-Object { $null -ne $_ })
    foreach ($item in $fontRows) {
        if ([string]$item.id -eq $fontId) {
            $font = $item
            break
        }
    }
    if ($null -eq $font) {
        throw "Unknown terminal font '$fontId'."
    }
    $scheme = $null
    foreach ($item in @(Get-WinToolNote -Object $catalog -Name "schemes" -Default @())) {
        if ([string]$item.id -eq $schemeId) {
            $scheme = $item
            break
        }
    }

    $components = Get-WinToolNote -Object $catalog -Name "components"
    $steps = New-Object System.Collections.Generic.List[object]
    [void]$steps.Add([pscustomobject]@{ Type = "winget"; Label = "Install Windows Terminal"; WingetId = [string]$components.windowsTerminal; Scope = "" })
    [void]$steps.Add([pscustomobject]@{ Type = "winget"; Label = "Install PowerShell 7"; WingetId = [string]$components.powerShell; Scope = "" })
    $promptWinget = [string](Get-WinToolNote -Object $prompt -Name "wingetId" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($promptWinget)) {
        [void]$steps.Add([pscustomobject]@{ Type = "winget"; Label = ("Install " + [string]$prompt.name); WingetId = $promptWinget; Scope = "" })
    }
    foreach ($fontStep in @(Get-WinToolFontInstallStep -Font $font)) {
        [void]$steps.Add($fontStep)
    }
    $fontSize = 12
    $sizeValue = Get-WinToolNote -Object $Selection -Name "fontSize"
    if ($null -ne $sizeValue -and [int]$sizeValue -ge 6 -and [int]$sizeValue -le 48) { $fontSize = [int]$sizeValue }
    $fontLabel = "Set the Windows Terminal font to " + [string]$font.name
    if ($fontSize -ne 12) { $fontLabel += " " + $fontSize + " pt" }
    [void]$steps.Add([pscustomobject]@{ Type = "font"; Label = $fontLabel; Face = [string]$font.face; Match = [string]$font.match; Size = $fontSize })
    [void]$steps.Add([pscustomobject]@{ Type = "ligatures"; Label = "Turn on font ligatures in Windows Terminal for all profiles" })
    if ($null -ne $scheme) {
        [void]$steps.Add([pscustomobject]@{ Type = "scheme"; Label = ("Set the Windows Terminal color scheme to " + [string]$scheme.name); SchemeId = [string]$scheme.id })
    }
    if ($promptId -eq "starship" -and -not [string]::IsNullOrWhiteSpace($promptStyle)) {
        [void]$steps.Add([pscustomobject]@{ Type = "starship-preset"; Label = ("Apply the Starship preset " + $promptStyle); Preset = $promptStyle })
    }
    if ($promptId -eq "powerline-go") {
        [void]$steps.Add([pscustomobject]@{ Type = "tool-download"; Label = "Download powerline-go"; Url = [string](Get-WinToolNote -Object $prompt -Name "downloadUrl" -Default ""); FileName = "powerline-go.exe" })
    }
    foreach ($extra in @(Get-WinToolNote -Object $catalog -Name "extras" -Default @())) {
        $extraId = [string]$extra.id
        $enabled = $false
        if ($extraId -eq "terminal-icons") { $enabled = [bool]$icons }
        elseif ($extraId -eq "psreadline") { $enabled = [bool]$psReadLine }
        elseif ($extraId -eq "zoxide") { $enabled = [bool]$zoxide }
        elseif ($extraId -eq "fzf") { $enabled = [bool]$fzf }
        if ($enabled -and [string]$extra.kind -eq "winget") {
            [void]$steps.Add([pscustomobject]@{ Type = "winget"; Label = ("Install " + [string]$extra.name); WingetId = [string]$extra.wingetId; Scope = "" })
        }
    }
    if ([bool]$icons) {
        [void]$steps.Add([pscustomobject]@{ Type = "module"; Label = "Install Terminal-Icons for Windows PowerShell"; Host = "powershell" })
        [void]$steps.Add([pscustomobject]@{ Type = "module"; Label = "Install Terminal-Icons for PowerShell 7"; Host = "pwsh" })
    }
    if ([bool]$psReadLine) {
        # 5.1 ships PSReadLine 2.0, too old for history predictions.
        [void]$steps.Add([pscustomobject]@{ Type = "module"; Label = "Update PSReadLine for Windows PowerShell"; Host = "powershell"; Module = "PSReadLine" })
    }
    [void]$steps.Add([pscustomobject]@{ Type = "profile"; Label = "Update PowerShell profiles"; Prompt = $promptId; PromptStyle = $promptStyle; TerminalIcons = [bool]$icons; PsReadLine = [bool]$psReadLine; Zoxide = [bool]$zoxide })
    if ([bool]$wsl) {
        $distro = [string](Get-WinToolNote -Object $Selection -Name "wslDistro" -Default "Ubuntu")
        $withShell = ([bool]$zsh -or $shellKind -like "wsl-*")
        foreach ($wslStep in @(Get-WinToolWslStep -Distro $distro -PromptId $promptId -PromptStyle $promptStyle -Font $font -Install $true -Shell $withShell)) {
            [void]$steps.Add($wslStep)
        }
    }
    return $steps.ToArray()
}

# Prompt preview: a list of colored segments that approximates what the
# chosen prompt and theme look like. Oh My Posh themes are read from their
# JSON (palette, segment colors, powerline or diamond style); other prompts
# use the small samples in terminal.json "previews".
$script:WinToolPreviewNamedColor = @{
    black = "#0C0C0C"; red = "#C50F1F"; green = "#13A10E"; yellow = "#C19C00"; blue = "#0037DA"; magenta = "#881798"; cyan = "#3A96DD"; white = "#CCCCCC"
    darkGray = "#767676"; lightBlack = "#767676"; lightRed = "#E74856"; lightGreen = "#16C60C"; lightYellow = "#F9F1A5"; lightBlue = "#3B78FF"; lightMagenta = "#B4009E"; lightCyan = "#61D6D6"; lightWhite = "#F2F2F2"
}

$script:WinToolPreviewSampleText = @{
    path = "~/src"; git = "main"; session = "user"; time = "23:14"; executiontime = "12ms"
    node = "20.11"; python = "3.12"; go = "1.22"; dotnet = "8.0"; rust = "1.79"; java = "21"
    shell = "pwsh"; battery = "87%"; az = "dev"; aws = "dev"; kubectl = "dev"; docker = "dev"
}

function ConvertTo-WinToolPreviewColor {
    param(
        [AllowEmptyString()][string]$Value,
        $Palette
    )
    $text = [string]$Value
    for ($depth = 0; $depth -lt 3 -and $text.StartsWith("p:"); $depth++) {
        $text = [string](Get-WinToolNote -Object $Palette -Name $text.Substring(2) -Default "")
    }
    if ($text -match '^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$') {
        return ("#" + $Matches[1].ToUpperInvariant())
    }
    if ($text -match '^#([0-9A-Fa-f])([0-9A-Fa-f])([0-9A-Fa-f])$') {
        return ("#" + $Matches[1] + $Matches[1] + $Matches[2] + $Matches[2] + $Matches[3] + $Matches[3]).ToUpperInvariant()
    }
    if ($script:WinToolPreviewNamedColor.ContainsKey($text)) {
        return $script:WinToolPreviewNamedColor[$text]
    }
    return $null
}

function New-WinToolPreviewSegment {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Foreground,
        [string]$Background
    )
    $fg = $null
    $bg = $null
    if (-not [string]::IsNullOrWhiteSpace($Foreground)) { $fg = $Foreground }
    if (-not [string]::IsNullOrWhiteSpace($Background)) { $bg = $Background }
    return [pscustomobject]@{ Text = $Text; Foreground = $fg; Background = $bg }
}

function Get-WinToolOmpPreviewSegment {
    param(
        [Parameter(Mandatory = $true)]$Theme
    )
    $palette = Get-WinToolNote -Object $Theme -Name "palette"
    $parts = New-Object System.Collections.Generic.List[object]
    foreach ($block in @(Get-WinToolNote -Object $Theme -Name "blocks" -Default @())) {
        if ([string](Get-WinToolNote -Object $block -Name "type" -Default "prompt") -ne "prompt") { continue }
        if ([string](Get-WinToolNote -Object $block -Name "alignment" -Default "left") -eq "right") { continue }
        foreach ($segment in @(Get-WinToolNote -Object $block -Name "segments" -Default @())) {
            if ($parts.Count -ge 4) { break }
            $type = [string](Get-WinToolNote -Object $segment -Name "type" -Default "")
            $text = ""
            if ($script:WinToolPreviewSampleText.ContainsKey($type)) {
                $text = [string]$script:WinToolPreviewSampleText[$type]
            }
            elseif ($type -eq "text") {
                $template = [string](Get-WinToolNote -Object $segment -Name "template" -Default "")
                if (-not $template.Contains("{{")) { $text = $template.Trim() }
            }
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $style = [string](Get-WinToolNote -Object $segment -Name "style" -Default "plain")
            $background = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $segment -Name "background" -Default "")) -Palette $palette
            $foreground = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $segment -Name "foreground" -Default "")) -Palette $palette
            if ($style -eq "plain") { $background = $null }
            $parts.Add([pscustomobject]@{
                Text = $text
                Foreground = $foreground
                Background = $background
                Style = $style
                Symbol = [string](Get-WinToolNote -Object $segment -Name "powerline_symbol" -Default ([string][char]0xE0B0))
                Leading = [string](Get-WinToolNote -Object $segment -Name "leading_diamond" -Default "")
                Trailing = [string](Get-WinToolNote -Object $segment -Name "trailing_diamond" -Default "")
            })
        }
        if ($parts.Count -gt 0) { break }
    }
    $result = New-Object System.Collections.Generic.List[object]
    $parentBackground = $null
    $parentForeground = $null
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $part = $parts[$index]
        $markup = @{ Palette = $palette; SegmentForeground = $part.Foreground; SegmentBackground = $part.Background; ParentForeground = $parentForeground; ParentBackground = $parentBackground }
        if ($index + 1 -lt $parts.Count) { $markup.ChildBackground = $parts[$index + 1].Background }
        if ($null -ne $part.Background) { $parentBackground = $part.Background }
        $parentForeground = $part.Foreground
        $nextBackground = $null
        if ($index + 1 -lt $parts.Count) { $nextBackground = $parts[$index + 1].Background }
        if ($null -eq $part.Background) {
            foreach ($piece in @(Split-WinToolOmpMarkup -Text ($part.Text + " ") -Foreground $part.Foreground @markup)) { $result.Add($piece) }
            continue
        }
        if ($part.Style -eq "diamond" -and -not [string]::IsNullOrEmpty($part.Leading)) {
            foreach ($piece in @(Split-WinToolOmpMarkup -Text $part.Leading -Foreground $part.Background @markup)) { $result.Add($piece) }
        }
        foreach ($piece in @(Split-WinToolOmpMarkup -Text (" " + $part.Text + " ") -Foreground $part.Foreground -Background $part.Background @markup)) { $result.Add($piece) }
        if ($part.Style -eq "powerline") {
            foreach ($piece in @(Split-WinToolOmpMarkup -Text $part.Symbol -Foreground $part.Background -Background $nextBackground @markup)) { $result.Add($piece) }
        }
        elseif ($part.Style -eq "diamond" -and -not [string]::IsNullOrEmpty($part.Trailing)) {
            foreach ($piece in @(Split-WinToolOmpMarkup -Text $part.Trailing -Foreground $part.Background @markup)) { $result.Add($piece) }
        }
    }
    return $result.ToArray()
}

function Get-WinToolPromptPreview {
    param(
        [string]$PromptId,
        [string]$PromptStyle,
        $Theme
    )
    $catalog = Get-WinToolTerminalCatalog
    $previews = Get-WinToolNote -Object $catalog -Name "previews"
    if ($PromptId -eq "oh-my-posh" -and $null -ne $Theme) {
        $segments = @(Get-WinToolOmpPreviewSegment -Theme $Theme)
        if ($segments.Count -gt 0) {
            return $segments
        }
    }
    if ($PromptId -eq "oh-my-posh") {
        # Without the theme file, use the sample stored in omp-themes.json.
        foreach ($row in @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @())) {
            if ([string]$row.id -ne $PromptStyle) { continue }
            $segments = @(ConvertTo-WinToolPreviewSegmentList -Item @(Get-WinToolNote -Object $row -Name "preview" -Default @()))
            if ($segments.Count -gt 0) { return $segments }
        }
    }
    if ($PromptId -eq "starship") {
        foreach ($preset in @(Get-WinToolNote -Object $catalog -Name "starshipPresets" -Default @())) {
            if ([string]$preset.id -ne $PromptStyle) { continue }
            $list = New-Object System.Collections.Generic.List[object]
            foreach ($item in @(Get-WinToolNote -Object $preset -Name "preview" -Default @())) {
                $fg = [string](Get-WinToolNote -Object $item -Name "fg" -Default "")
                if ([string]::IsNullOrWhiteSpace($fg)) { $fg = [string](Get-WinToolNote -Object $item -Name "color" -Default "") }
                $list.Add((New-WinToolPreviewSegment -Text ([string]$item.text) -Foreground $fg -Background ([string](Get-WinToolNote -Object $item -Name "bg" -Default ""))))
            }
            if ($list.Count -gt 0) {
                return (Add-WinToolPreviewSeparator -Segments $list.ToArray())
            }
        }
    }
    $variant = Get-WinToolPromptVariant -PromptId $PromptId -PromptStyle $PromptStyle
    if ($null -ne $variant) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Get-WinToolNote -Object $variant -Name "preview" -Default @())) {
            $list.Add((New-WinToolPreviewSegment -Text ([string]$item.text) -Foreground ([string](Get-WinToolNote -Object $item -Name "fg" -Default "")) -Background ([string](Get-WinToolNote -Object $item -Name "bg" -Default ""))))
        }
        if ($list.Count -gt 0) {
            return (Add-WinToolPreviewSeparator -Segments $list.ToArray())
        }
    }
    $key = $PromptId
    if ($PromptId -eq "oh-my-zsh" -and $null -ne $previews -and $null -ne $previews.PSObject.Properties[("oh-my-zsh:" + $PromptStyle)]) {
        $key = "oh-my-zsh:" + $PromptStyle
    }
    $sample = @(Get-WinToolNote -Object $previews -Name $key -Default @())
    if ($sample.Count -eq 0) {
        $sample = @(Get-WinToolNote -Object $previews -Name "oh-my-posh" -Default @())
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($item in $sample) {
        $out.Add((New-WinToolPreviewSegment -Text ([string]$item.text) -Foreground ([string](Get-WinToolNote -Object $item -Name "fg" -Default "")) -Background ([string](Get-WinToolNote -Object $item -Name "bg" -Default ""))))
    }
    return (Add-WinToolPreviewSeparator -Segments $out.ToArray())
}

function Get-WinToolPromptVariantList {
    param(
        [AllowEmptyString()][string]$PromptId
    )
    # The styles a prompt offers (data/terminal.json "promptVariants").
    if ([string]::IsNullOrWhiteSpace($PromptId)) { return @() }
    $variants = Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "promptVariants"
    if ($null -eq $variants -or $null -eq $variants.PSObject.Properties[$PromptId]) { return @() }
    return @($variants.PSObject.Properties[$PromptId].Value | Where-Object { $null -ne $_ })
}

function Get-WinToolPromptVariant {
    param(
        [AllowEmptyString()][string]$PromptId,
        [AllowEmptyString()][string]$PromptStyle
    )
    # The chosen style, or the prompt's first style when the id is unknown.
    $rows = @(Get-WinToolPromptVariantList -PromptId $PromptId)
    if ($rows.Count -eq 0) { return $null }
    foreach ($row in $rows) {
        if ([string]$row.id -eq $PromptStyle) { return $row }
    }
    return $rows[0]
}

function Get-WinToolPromptVariantSetting {
    param(
        $Variant
    )
    # Lines that go into ~/.zshrc for Spaceship and Pure. Only plain words,
    # spaces, and = : . _ - are allowed so nothing can break out into a shell.
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(Get-WinToolNote -Object $Variant -Name "settings" -Default @())) {
        $text = [string]$line
        if ($text -match '^[A-Za-z0-9_:=. -]+$') { $out.Add($text) }
    }
    return $out.ToArray()
}

function Get-WinToolPromptVariantArgument {
    param(
        $Variant
    )
    # powerline-go flags such as "-theme gruvbox" or "-mode flat".
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($arg in @(Get-WinToolNote -Object $Variant -Name "args" -Default @())) {
        $text = [string]$arg
        if ($text -match '^-?[A-Za-z0-9._-]+$') { $out.Add($text) }
    }
    return $out.ToArray()
}

function Test-WinToolPreviewSeparator {
    param(
        [AllowEmptyString()][string]$Text
    )
    $trim = ([string]$Text).Trim()
    if ($trim.Length -ne 1) { return $false }
    $code = [int][char]$trim
    return (($code -ge 0xE0B0 -and $code -le 0xE0D4) -or $code -eq 0x25B6 -or $code -eq 0x25C0)
}

function Add-WinToolPreviewSeparator {
    param(
        [object[]]$Segments
    )
    # Where a colored block ends and the next part has another background (or
    # none), put a Powerline arrow between them unless the data already has one.
    $list = @($Segments | Where-Object { $null -ne $_ })
    $out = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $list.Count; $i++) {
        $item = $list[$i]
        $out.Add($item)
        $bg = [string]$item.Background
        if ([string]::IsNullOrWhiteSpace($bg) -or (Test-WinToolPreviewSeparator -Text ([string]$item.Text))) { continue }
        $nextBg = ""
        if ($i + 1 -lt $list.Count) {
            $next = $list[$i + 1]
            if (Test-WinToolPreviewSeparator -Text ([string]$next.Text)) { continue }
            $nextBg = [string]$next.Background
        }
        if ($nextBg -eq $bg) { continue }
        $out.Add((New-WinToolPreviewSegment -Text ([string][char]0xE0B0) -Foreground $bg -Background $nextBg))
    }
    return $out.ToArray()
}

function Get-WinToolOmpThemeFileName {
    param(
        [AllowEmptyString()][string]$ThemeId,
        [object[]]$Themes
    )
    foreach ($theme in @($Themes)) {
        if ($null -ne $theme -and [string]$theme.id -eq $ThemeId) {
            $file = [string](Get-WinToolNote -Object $theme -Name "file" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($file)) { return $file }
        }
    }
    if ([string]::IsNullOrWhiteSpace($ThemeId)) {
        return "jandedobbeleer.omp.json"
    }
    return (Get-WinToolOhMyPoshThemeFile -PromptStyle $ThemeId)
}

function Read-WinToolCachedOmpTheme {
    param(
        [Parameter(Mandatory = $true)][string]$File
    )
    # Memory first, then the copy under %LOCALAPPDATA%\WinTool\themes.
    if ($null -eq $script:WinToolOmpThemeCache) {
        $script:WinToolOmpThemeCache = @{}
    }
    if ($script:WinToolOmpThemeCache.ContainsKey($File)) {
        return $script:WinToolOmpThemeCache[$File]
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or $File -notmatch '^[A-Za-z0-9._-]+$') {
        return $null
    }
    $path = Join-Path $env:LOCALAPPDATA ("WinTool\themes\" + $File)
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    try {
        $theme = ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($path))
        $script:WinToolOmpThemeCache[$File] = $theme
        return $theme
    }
    catch {
        return $null
    }
}

function Get-WinToolSummaryRow {
    # Joins the summary lines into a few rows ("a - b - c") so the summary
    # card keeps a fixed height.
    param(
        [AllowEmptyCollection()][string[]]$Line,
        [int]$Count = 3
    )
    $items = @($Line | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($items.Count -eq 0) {
        return @()
    }
    if ($Count -lt 1) { $Count = 1 }
    $perRow = [int][Math]::Ceiling($items.Count / [double]$Count)
    $separator = " " + [string][char]0x00B7 + " "
    $rows = New-Object System.Collections.Generic.List[string]
    for ($start = 0; $start -lt $items.Count; $start += $perRow) {
        $end = [Math]::Min($items.Count, $start + $perRow) - 1
        $rows.Add((($items[$start..$end]) -join $separator))
    }
    return $rows.ToArray()
}

# Advanced Terminal page helpers. They only read the catalogs, so the tests
# can check them without a window.

$script:WinToolPromptEngineColor = @{
    "oh-my-posh" = "#2F74C0"; "starship" = "#C2185B"; "powerline-go" = "#0E8FB0"
    "powerlevel10k" = "#4B6584"; "pure" = "#9C27B0"; "spaceship" = "#6B4FBB"
    "oh-my-zsh" = "#2E9E55"; "tide" = "#0E7490"
}

function Get-WinToolPromptEngineInfo {
    param(
        [Parameter(Mandatory = $true)]$Prompt,
        [int]$OhMyPoshCount = -1
    )
    # Group, the short line under the name ("WSL - zsh - 6 styles"), and the
    # icon color for one prompt engine.
    $catalog = Get-WinToolTerminalCatalog
    $id = [string]$Prompt.id
    $shellKind = [string](Get-WinToolNote -Object $Prompt -Name "shell" -Default "powershell")
    $group = "PowerShell"
    $where = "PowerShell"
    if ($shellKind -like "wsl-*") {
        $group = "WSL Ubuntu"
        $where = "WSL " + [string][char]0x00B7 + " " + $shellKind.Substring(4)
    }
    $count = ""
    if ($id -eq "oh-my-posh") {
        $total = $OhMyPoshCount
        if ($total -lt 0) { $total = @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @()).Count }
        $count = [string]$total + " themes"
    }
    elseif ($id -eq "starship") {
        $count = [string]@(Get-WinToolNote -Object $catalog -Name "starshipPresets" -Default @()).Count + " presets"
    }
    elseif ($id -eq "oh-my-zsh") {
        $count = [string]@(Get-WinToolNote -Object $catalog -Name "omzThemes" -Default @()).Count + " themes"
    }
    else {
        $variants = @(Get-WinToolPromptVariantList -PromptId $id)
        if ($variants.Count -gt 0) { $count = [string]$variants.Count + " styles" }
    }
    $sub = $where
    if (-not [string]::IsNullOrWhiteSpace($count)) { $sub += " " + [string][char]0x00B7 + " " + $count }
    $color = "#5B6680"
    if ($script:WinToolPromptEngineColor.ContainsKey($id)) { $color = $script:WinToolPromptEngineColor[$id] }
    $runs = "Runs in PowerShell 7 and Windows PowerShell, no WSL needed."
    if ($shellKind -eq "wsl-zsh") { $runs = "Runs in zsh inside WSL Ubuntu." }
    elseif ($shellKind -eq "wsl-fish") { $runs = "Runs in Fish inside WSL Ubuntu." }
    return [pscustomobject]@{ Id = $id; Group = $group; Sub = $sub; Color = $color; Runs = $runs; Wsl = ($shellKind -like "wsl-*") }
}

function Get-WinToolThemeTitle {
    param(
        [AllowEmptyString()][string]$PromptId
    )
    # Card title and search hint for the theme column of one engine.
    if ($PromptId -eq "oh-my-posh") { return [pscustomobject]@{ Title = "Oh My Posh theme"; Hint = "Search themes"; Noun = "themes" } }
    if ($PromptId -eq "starship") { return [pscustomobject]@{ Title = "Starship preset"; Hint = "Search presets"; Noun = "presets" } }
    if ($PromptId -eq "oh-my-zsh") { return [pscustomobject]@{ Title = "Oh My Zsh theme"; Hint = "Search themes"; Noun = "themes" } }
    $name = $PromptId
    foreach ($prompt in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())) {
        if ([string]$prompt.id -eq $PromptId) { $name = [string]$prompt.name; break }
    }
    return [pscustomobject]@{ Title = ($name + " style"); Hint = "Search styles"; Noun = "styles" }
}

function Test-WinToolNerdGlyph {
    param(
        [AllowEmptyString()][string]$Text
    )
    # True when the text uses a Private Use Area glyph, which only shows with
    # a Nerd Font (or a Powerline-patched font).
    foreach ($char in ([string]$Text).ToCharArray()) {
        $code = [int]$char
        if (($code -ge 0xE000 -and $code -le 0xF8FF) -or [char]::IsSurrogate($char)) { return $true }
    }
    return $false
}

function New-WinToolThemeRow {
    param(
        [string]$Id,
        [string]$Name,
        [object[]]$Preview,
        $NerdFont,
        [string]$Description = ""
    )
    $segments = @($Preview | Where-Object { $null -ne $_ })
    $powerline = $null
    $nerd = $NerdFont
    if ($segments.Count -gt 0) {
        $powerline = (@($segments | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Background) }).Count -gt 0)
        if ($null -eq $nerd) {
            $nerd = (Test-WinToolNerdGlyph -Text ((@($segments | ForEach-Object { [string]$_.Text })) -join ""))
        }
    }
    return [pscustomobject]@{ Id = $Id; Name = $Name; Preview = $segments; Powerline = $powerline; NerdFont = $nerd; Description = $Description }
}

function Get-WinToolThemeRow {
    param(
        [AllowEmptyString()][string]$PromptId,
        [object[]]$OhMyPoshTheme
    )
    # Every theme, preset, or style the engine offers, with a sample prompt
    # line when one is known. Powerline and NerdFont stay $null when unknown.
    $catalog = Get-WinToolTerminalCatalog
    $rows = New-Object System.Collections.Generic.List[object]
    if ($PromptId -eq "oh-my-posh") {
        $themes = @($OhMyPoshTheme | Where-Object { $null -ne $_ })
        if ($themes.Count -eq 0) { $themes = @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @()) }
        foreach ($theme in $themes) {
            $preview = @()
            $file = [string](Get-WinToolNote -Object $theme -Name "file" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($file)) {
                $json = Read-WinToolCachedOmpTheme -File $file
                if ($null -ne $json) { $preview = @(Get-WinToolOmpPreviewSegment -Theme $json) }
            }
            if ($preview.Count -eq 0) { $preview = @(ConvertTo-WinToolPreviewSegmentList -Item @(Get-WinToolNote -Object $theme -Name "preview" -Default @())) }
            $rows.Add((New-WinToolThemeRow -Id ([string]$theme.id) -Name ([string]$theme.name) -Preview $preview -NerdFont $null))
        }
    }
    elseif ($PromptId -eq "starship") {
        foreach ($preset in @(Get-WinToolNote -Object $catalog -Name "starshipPresets" -Default @())) {
            $preview = @(Get-WinToolPromptPreview -PromptId "starship" -PromptStyle ([string]$preset.id))
            $nerd = Get-WinToolNote -Object $preset -Name "nerdFont"
            if ($null -ne $nerd) { $nerd = [bool]$nerd }
            $rows.Add((New-WinToolThemeRow -Id ([string]$preset.id) -Name ([string]$preset.name) -Preview $preview -NerdFont $nerd))
        }
    }
    elseif ($PromptId -eq "oh-my-zsh") {
        $previews = Get-WinToolNote -Object $catalog -Name "previews"
        foreach ($name in @(Get-WinToolNote -Object $catalog -Name "omzThemes" -Default @())) {
            $preview = @()
            if ($null -ne $previews -and $null -ne $previews.PSObject.Properties[("oh-my-zsh:" + [string]$name)]) {
                $preview = @(Get-WinToolPromptPreview -PromptId "oh-my-zsh" -PromptStyle ([string]$name))
            }
            $rows.Add((New-WinToolThemeRow -Id ([string]$name) -Name ([string]$name) -Preview $preview -NerdFont $null))
        }
    }
    else {
        foreach ($variant in @(Get-WinToolPromptVariantList -PromptId $PromptId)) {
            $preview = @(Get-WinToolPromptPreview -PromptId $PromptId -PromptStyle ([string]$variant.id))
            $about = [string](Get-WinToolNote -Object $variant -Name "description" -Default "")
            $rows.Add((New-WinToolThemeRow -Id ([string]$variant.id) -Name ([string]$variant.name) -Preview $preview -NerdFont $null -Description $about))
        }
    }
    return $rows.ToArray()
}

function Select-WinToolThemeRow {
    param(
        [AllowEmptyCollection()][object[]]$Row,
        [AllowEmptyString()][string]$Query = "",
        [AllowEmptyString()][string]$Filter = "all"
    )
    # Search and the All / Powerline / Minimal / No Nerd Font needed chips.
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Row | Where-Object { $null -ne $_ })) {
        $hay = [string]$item.Name + " " + [string]$item.Id + " " + [string]$item.Description
        if (-not (Test-WinToolTextMatch -Haystack $hay -Query $Query)) { continue }
        if ($Filter -eq "powerline" -and $item.Powerline -ne $true) { continue }
        if ($Filter -eq "minimal" -and $item.Powerline -ne $false) { continue }
        if ($Filter -eq "no-nerd" -and $item.NerdFont -ne $false) { continue }
        $out.Add($item)
    }
    return $out.ToArray()
}

function Get-WinToolSummaryChip {
    param(
        [AllowEmptyCollection()][object[]]$Step
    )
    # Short "+ install" and "~ change" chips for the action bar, one per
    # thing, in plan order.
    $chips = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $add = {
        param($kind, $text)
        $key = $kind + "|" + $text
        if ([string]::IsNullOrWhiteSpace($text) -or $seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $chips.Add([pscustomobject]@{ Kind = $kind; Text = $text })
    }
    foreach ($item in @($Step | Where-Object { $null -ne $_ })) {
        $type = [string]$item.Type
        $label = [string]$item.Label
        switch ($type) {
            "winget" { & $add "add" ($label -replace '^Install ', '') }
            "font-download" { & $add "add" ($label -replace '^Download ', '') }
            "tool-download" { & $add "add" ($label -replace '^Download ', '') }
            "wsl-install" { & $add "add" ("WSL " + [string]$item.Distro) }
            "module" {
                if ($label -match '^Install (.+?) for ') { & $add "add" $Matches[1] }
                elseif ($label -match '^Update (.+?) for ') { & $add "change" ($Matches[1] + " predictions") }
                else { & $add "change" $label }
            }
            "font" {
                $text = "Terminal font"
                if ($null -ne $item.PSObject.Properties["Size"] -and [int]$item.Size -ne 12) { $text += " " + [int]$item.Size + " pt" }
                & $add "change" $text
            }
            "ligatures" { & $add "change" "Font ligatures on" }
            "scheme" { & $add "change" ($label -replace '^Set the Windows Terminal color scheme to ', 'Scheme ') }
            "starship-preset" { & $add "change" ("Starship preset " + [string]$item.Preset) }
            "profile" { & $add "change" "PowerShell `$PROFILE" }
            "wsl-shell" {
                $text = $label -replace '^Install ', ''
                $style = ""
                if ($text -match '^(.*) \((.+) style\)$') { $text = $Matches[1]; $style = $Matches[2] }
                & $add "add" $text
                if (-not [string]::IsNullOrWhiteSpace($style)) { & $add "change" ($style + " style") }
            }
            "wsl-profile" { & $add "change" ("Font in the " + [string]$item.Distro + " profile") }
            default { & $add "change" $label }
        }
    }
    return $chips.ToArray()
}

function ConvertTo-WinToolPreviewSegmentList {
    param(
        [AllowEmptyCollection()][object[]]$Item
    )
    # Catalog samples ({ text, fg or color, bg }) as preview segments.
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @($Item | Where-Object { $null -ne $_ })) {
        $fg = [string](Get-WinToolNote -Object $entry -Name "fg" -Default "")
        if ([string]::IsNullOrWhiteSpace($fg)) { $fg = [string](Get-WinToolNote -Object $entry -Name "color" -Default "") }
        $out.Add((New-WinToolPreviewSegment -Text ([string]$entry.text) -Foreground $fg -Background ([string](Get-WinToolNote -Object $entry -Name "bg" -Default ""))))
    }
    return $out.ToArray()
}

$script:WinToolPreviewTransparent = "#121826"

function Resolve-WinToolOmpMarkupColor {
    param(
        [AllowEmptyString()][string]$Value,
        $Palette,
        [string]$SegmentForeground,
        [string]$SegmentBackground,
        [string]$ParentForeground,
        [string]$ParentBackground,
        [string]$ChildBackground,
        [switch]$IsForeground
    )
    # Color names inside Oh My Posh markup: hex, palette, named colors, and
    # the keywords that point at the segment, its parent, or its child.
    $text = ([string]$Value).Trim()
    switch -Regex ($text) {
        '^$' { return $null }
        '^transparent$' { if ($IsForeground) { return $script:WinToolPreviewTransparent } return $null }
        '^foreground$' { return $SegmentForeground }
        '^background$' { return $SegmentBackground }
        '^parentForeground$' { return $ParentForeground }
        '^parentBackground$' { if ([string]::IsNullOrWhiteSpace($ParentBackground) -and $IsForeground) { return $script:WinToolPreviewTransparent } return $ParentBackground }
        '^childBackground$' { if ([string]::IsNullOrWhiteSpace($ChildBackground) -and $IsForeground) { return $script:WinToolPreviewTransparent } return $ChildBackground }
        '^childForeground$' { return $null }
    }
    return (ConvertTo-WinToolPreviewColor -Value $text -Palette $Palette)
}

function Split-WinToolOmpMarkup {
    param(
        [AllowEmptyString()][string]$Text,
        [string]$Foreground,
        [string]$Background,
        $Palette,
        [string]$SegmentForeground,
        [string]$SegmentBackground,
        [string]$ParentForeground,
        [string]$ParentBackground,
        [string]$ChildBackground
    )
    # Turns "<fg,bg>text</>" color tags into separate preview segments and
    # drops other tags such as <b> or <i>. Text outside tags keeps the
    # given colors.
    $out = New-Object System.Collections.Generic.List[object]
    $source = [string]$Text
    if (-not $source.Contains("<")) {
        $out.Add((New-WinToolPreviewSegment -Text $source -Foreground $Foreground -Background $Background))
        return $out.ToArray()
    }
    $colors = @{ Palette = $Palette; SegmentForeground = $SegmentForeground; SegmentBackground = $SegmentBackground; ParentForeground = $ParentForeground; ParentBackground = $ParentBackground; ChildBackground = $ChildBackground }
    $pattern = '<([^<>/]*)>(.*?)</[^<>]*>'
    $position = 0
    foreach ($match in [regex]::Matches($source, $pattern)) {
        if ($match.Index -gt $position) {
            $out.Add((New-WinToolPreviewSegment -Text $source.Substring($position, $match.Index - $position) -Foreground $Foreground -Background $Background))
        }
        $spec = $match.Groups[1].Value
        $inner = $match.Groups[2].Value
        $fg = $Foreground
        $bg = $Background
        if ($spec -notmatch '^(b|i|u|s|d|f|r|blink|reverse|dimmed)$') {
            $pair = $spec.Split(",")
            if ($pair.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($pair[0])) { $fg = Resolve-WinToolOmpMarkupColor -Value $pair[0] @colors -IsForeground }
            if ($pair.Count -ge 2) { $bg = Resolve-WinToolOmpMarkupColor -Value $pair[1] @colors }
        }
        $out.Add((New-WinToolPreviewSegment -Text $inner -Foreground $fg -Background $bg))
        $position = $match.Index + $match.Length
    }
    if ($position -lt $source.Length) {
        $out.Add((New-WinToolPreviewSegment -Text $source.Substring($position) -Foreground $Foreground -Background $Background))
    }
    # Anything left that still looks like a tag (an unclosed one) is dropped.
    $clean = New-Object System.Collections.Generic.List[object]
    foreach ($piece in $out.ToArray()) {
        $piece.Text = [regex]::Replace([string]$piece.Text, '</?[A-Za-z#][^<>]*>|</>', '')
        if ([string]::IsNullOrEmpty($piece.Text)) { continue }
        $clean.Add($piece)
    }
    return $clean.ToArray()
}
