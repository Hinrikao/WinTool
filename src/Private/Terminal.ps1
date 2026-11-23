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

function Get-WinToolPromptScript {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true,
        [string]$PromptStyle = "",
        [bool]$PsReadLine = $false,
        [bool]$Zoxide = $false
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Added by WinTool. Delete this block, or run WinTool again, to change it.")
    if ($TerminalIcons) {
        $lines.Add("if (Get-Module -ListAvailable -Name Terminal-Icons) {")
        $lines.Add("    Import-Module Terminal-Icons")
        $lines.Add("}")
    }
    if ($PsReadLine) {
        $lines.Add("if (Get-Module -ListAvailable -Name PSReadLine) {")
        $lines.Add("    Set-PSReadLineOption -PredictionSource History")
        $lines.Add("    Set-PSReadLineOption -PredictionViewStyle ListView")
        $lines.Add("}")
    }
    if ($Zoxide) {
        $lines.Add("if (Get-Command zoxide -ErrorAction SilentlyContinue) {")
        $lines.Add("    Invoke-Expression (& { (zoxide init powershell | Out-String) })")
        $lines.Add("}")
    }
    if ($PromptId -eq "starship") {
        $lines.Add("if (Get-Command starship -ErrorAction SilentlyContinue) {")
        $lines.Add("    Invoke-Expression (& starship init powershell)")
        $lines.Add("}")
    }
    elseif ($PromptId -eq "oh-my-posh") {
        $themeFile = "jandedobbeleer.omp.json"
        if (-not [string]::IsNullOrWhiteSpace($PromptStyle)) {
            if ($PromptStyle.EndsWith(".omp.json")) {
                $themeFile = $PromptStyle
            }
            else {
                $themeFile = $PromptStyle + ".omp.json"
            }
        }
        $lines.Add("if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {")
        $lines.Add('    $theme = Join-Path $env:POSH_THEMES_PATH "' + $themeFile + '"')
        $lines.Add("    if (Test-Path -LiteralPath `$theme) {")
        $lines.Add("        oh-my-posh init pwsh --config `$theme | Invoke-Expression")
        $lines.Add("    }")
        $lines.Add("    else {")
        $lines.Add("        oh-my-posh init pwsh | Invoke-Expression")
        $lines.Add("    }")
        $lines.Add("}")
    }
    elseif ($PromptId -eq "powerline-go") {
        $lines.Add('function global:prompt {')
        $lines.Add('    $tool = Join-Path $env:LOCALAPPDATA "WinTool\bin\powerline-go.exe"')
        $lines.Add('    if (Test-Path -LiteralPath $tool) {')
        $lines.Add('        return (& $tool -error $LASTEXITCODE -shell powershell)')
        $lines.Add('    }')
        $lines.Add('    return "PS $($executionContext.SessionState.Path.CurrentLocation)> "')
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
    $font = [pscustomobject]@{
        face = $Face
        size = $Size
    }
    if ($null -eq $defaults.PSObject.Properties["font"]) {
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue $font
    }
    else {
        $defaults.font = $font
    }
    if ($null -eq $defaults.PSObject.Properties["fontFace"]) {
        $defaults | Add-Member -NotePropertyName "fontFace" -NotePropertyValue $Face
    }
    else {
        $defaults.fontFace = $Face
    }
    return $Settings
}

function Add-WinToolTerminalScheme {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)]$Scheme
    )
    $entry = [pscustomobject]@{
        name = [string]$Scheme.name
        background = [string]$Scheme.background
        foreground = [string]$Scheme.foreground
        cursorColor = [string]$Scheme.cursor
        selectionBackground = [string]$Scheme.selection
    }
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

function Write-WinToolShellProfile {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true,
        [string]$PromptStyle = "",
        [bool]$PsReadLine = $false,
        [bool]$Zoxide = $false
    )
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
        Write-WinToolUtf8File -Path $path -Text $updated
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
    $list = New-Object System.Collections.Generic.List[object]
    $sources = @(
        @{ Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; Folder = (Join-Path $env:windir "Fonts") },
        @{ Key = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"; Folder = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts") }
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
            $list.Add([pscustomobject]@{ Name = [string]$name; Data = $data })
        }
    }
    return $list.ToArray()
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

function Invoke-WinToolTerminalFont {
    param(
        [Parameter(Mandatory = $true)][string]$Face,
        [string]$Match
    )
    $chosen = $Face
    if (-not [string]::IsNullOrWhiteSpace($Match) -and (Test-WinToolWindows)) {
        $found = Find-WinToolInstalledFontFile -Token $Match
        if ($null -eq $found) {
            Write-WinToolLog -Message ("{0} is not installed, so the Windows Terminal font was left as it is. Run terminal setup again after the font installs." -f $Face) -Level "warn"
            return
        }
        $family = Get-WinToolFontFamilyName -Path ([string]$found.Data)
        if (-not [string]::IsNullOrWhiteSpace($family)) {
            $chosen = $family
        }
        if ($chosen -ne $Face) {
            Write-WinToolLog -Message "Using the installed font name: $chosen" -Level "info"
        }
    }
    $path = Get-WinToolTerminalSettingsPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-WinToolLog -Message "Windows Terminal settings were not found. Open Terminal once, then run terminal setup again to set the font." -Level "warn"
        return
    }
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path) {
        $backup = $path + ".wintool-backup"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $path -Destination $backup -Force
            Write-WinToolLog -Message "Saved a backup of Terminal settings next to settings.json." -Level "info"
        }
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $settings = ConvertFrom-WinToolJsonText -Text $raw
        }
    }
    Add-WinToolTerminalFont -Settings $settings -Face $chosen -Size 12 | Out-Null
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
    $command = Get-Command -Name "starship" -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        Write-WinToolLog -Message "Starship is not on PATH yet, so the preset was skipped." -Level "warn"
        return
    }
    $directory = Join-Path $env:USERPROFILE ".config"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $destination = Join-Path $directory "starship.toml"
    & $command.Source preset $Preset -o $destination
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
$url = "URL"
$name = "FILENAME"
$dest = Join-Path $env:LOCALAPPDATA "WinTool\bin"
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
$path = Join-Path $dest $name
Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
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
    [void]$steps.Add([pscustomobject]@{ Type = "font"; Label = ("Set the Windows Terminal font to " + [string]$font.name); Face = [string]$font.face; Match = [string]$font.match })
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
    [void]$steps.Add([pscustomobject]@{ Type = "profile"; Label = "Update PowerShell profiles"; Prompt = $promptId; PromptStyle = $promptStyle; TerminalIcons = [bool]$icons; PsReadLine = [bool]$psReadLine; Zoxide = [bool]$zoxide })
    if ([bool]$wsl) {
        [void]$steps.Add([pscustomobject]@{ Type = "wsl-install"; Label = "Install WSL with Ubuntu" })
        if ([bool]$zsh -or $shellKind -like "wsl-*") {
            $label = "Install zsh and Oh My Zsh in Ubuntu"
            if ($shellKind -eq "wsl-fish") { $label = "Install Fish and Tide in Ubuntu" }
            elseif ($promptId -eq "powerlevel10k") { $label = "Install Powerlevel10k in Ubuntu" }
            elseif ($promptId -eq "pure") { $label = "Install Pure in Ubuntu" }
            elseif ($promptId -eq "spaceship") { $label = "Install Spaceship in Ubuntu" }
            elseif ($promptId -eq "oh-my-zsh") { $label = "Install the Oh My Zsh theme in Ubuntu" }
            [void]$steps.Add([pscustomobject]@{ Type = "wsl-shell"; Label = $label; Variant = $promptId; OmzTheme = $promptStyle })
        }
    }
    return $steps.ToArray()
}
