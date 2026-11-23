# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# WSL shell setup. It works on a distro that already exists: nothing is
# reinstalled, the Linux part runs as root through wsl.exe (no sudo password),
# and the default shell is changed with chsh as root.

function Get-WinToolWslDistroName {
    param($Step)
    $name = [string](Get-WinToolNote -Object $Step -Name "Distro" -Default "Ubuntu")
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "Ubuntu"
    }
    if ($name -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Unexpected WSL distro name '$name'."
    }
    return $name
}

function ConvertTo-WinToolShellWord {
    param(
        [AllowEmptyString()][string]$Text
    )
    # Values that reach bash: letters, digits, and . _ / - only.
    return ([string]$Text -replace '[^A-Za-z0-9._/-]', '')
}

function Get-WinToolWslSetupText {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    $bash = Get-WinToolPayloadText -Name "Wsl"
    $bash = $bash -replace "`r`n", "`n" -replace "`r", "`n"
    $variant = ConvertTo-WinToolShellWord -Text ([string](Get-WinToolNote -Object $Step -Name "Variant" -Default ""))
    $style = ConvertTo-WinToolShellWord -Text ([string](Get-WinToolNote -Object $Step -Name "PromptStyle" -Default ""))
    $omzTheme = ConvertTo-WinToolShellWord -Text ([string](Get-WinToolNote -Object $Step -Name "OmzTheme" -Default ""))
    if ([string]::IsNullOrWhiteSpace($omzTheme)) { $omzTheme = "robbyrussell" }
    $styleFile = ""
    $styleSettings = ""
    $chosen = Get-WinToolPromptVariant -PromptId $variant -PromptStyle $style
    if ($null -ne $chosen) {
        # The style id that reaches bash is always one from the catalog.
        $style = ConvertTo-WinToolShellWord -Text ([string]$chosen.id)
        $styleFile = ConvertTo-WinToolShellWord -Text ([string](Get-WinToolNote -Object $chosen -Name "configFile" -Default ""))
        if ($styleFile.Contains("..")) { $styleFile = "" }
        $styleSettings = (@(Get-WinToolPromptVariantSetting -Variant $chosen) -join "`n")
    }
    $header = "export WINTOOL_SHELL_PROMPT='" + $variant + "'`nexport WINTOOL_PROMPT_STYLE='" + $style + "'`nexport WINTOOL_OMZ_THEME='" + $omzTheme + "'`nexport WINTOOL_STYLE_FILE='" + $styleFile + "'`nexport WINTOOL_STYLE_SETTINGS='" + $styleSettings + "'`n"
    if ($bash.StartsWith("#!")) {
        $cut = $bash.IndexOf("`n")
        return $bash.Substring(0, $cut + 1) + $header + $bash.Substring($cut + 1)
    }
    return $header + $bash
}

function Get-WinToolWslLookupText {
    return @'
$ErrorActionPreference = "Continue"
$env:WSL_UTF8 = "1"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $null = $_ }
function Get-WinToolWslEntry {
    param([string]$Name)
    foreach ($key in @(Get-ChildItem -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue)) {
        $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($null -ne $item -and [string]$item.DistributionName -eq $Name) {
            return $item
        }
    }
    return $null
}
function Write-WinToolWslOutput {
    process {
        $text = ([string]$_).Replace([string][char]0, "")
        if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Output $text.TrimEnd() }
    }
}
$wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
'@
}

function Get-WinToolWslInstallScript {
    param(
        [Parameter(Mandatory = $true)][string]$Distro
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((Get-WinToolWslLookupText))
    $lines.Add('$distro = ' + (ConvertTo-WinToolSingleQuoted -Text $Distro))
    $lines.Add(@'
if ($null -ne (Get-WinToolWslEntry -Name $distro)) {
    Write-Output ("WSL already has " + $distro + ", so it is kept as it is.")
    exit 0
}
if (-not (Test-Path -LiteralPath $wsl)) {
    Write-Output "wsl.exe was not found. WSL needs Windows 10 2004 or later."
    exit 1
}
& $wsl --install -d $distro --no-launch 2>&1 | Write-WinToolWslOutput
$code = $LASTEXITCODE
if ($code -eq 0) {
    Write-Output ("Open " + $distro + " once from the Start menu to create your Linux user, then run the shell setup again.")
}
exit $code
'@)
    return ($lines -join [Environment]::NewLine)
}

function Get-WinToolWslShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$Distro,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((Get-WinToolWslLookupText))
    $lines.Add('$distro = ' + (ConvertTo-WinToolSingleQuoted -Text $Distro))
    $lines.Add('$script = ' + (ConvertTo-WinToolSingleQuoted -Text $ScriptPath))
    $lines.Add(@'
$entry = Get-WinToolWslEntry -Name $distro
if ($null -eq $entry) {
    Write-Output ("WSL has no distro named " + $distro + ". If it was just installed, open it once from the Start menu to create your Linux user, then run the shell setup again.")
    exit 3
}
if (-not (Test-Path -LiteralPath $wsl)) {
    Write-Output "wsl.exe was not found."
    exit 1
}
$uid = 0
if ($null -ne $entry.PSObject.Properties["DefaultUid"]) { $uid = [int64]$entry.DefaultUid }
$unix = ""
$converted = & $wsl -d $distro -u root -- wslpath -a $script 2>$null
foreach ($line in @($converted)) {
    $text = ([string]$line).Replace([string][char]0, "").Trim()
    if ($text.StartsWith("/")) { $unix = $text }
}
if ([string]::IsNullOrWhiteSpace($unix)) {
    $unix = "/mnt/" + $script.Substring(0, 1).ToLowerInvariant() + $script.Substring(2).Replace("\", "/")
}
Write-Output ("Running the shell setup in " + $distro + " as root for uid " + $uid + ".")
& $wsl -d $distro -u root -- env ("WINTOOL_UID=" + $uid) bash $unix 2>&1 | Write-WinToolWslOutput
exit $LASTEXITCODE
'@)
    return ($lines -join [Environment]::NewLine)
}

function Set-WinToolWslProfileFont {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][string]$Distro,
        [Parameter(Mandatory = $true)][string]$Face
    )
    # Sets the font on the distro's own Terminal profile, so an older
    # per-profile font cannot hide the Nerd Font. Returns how many changed.
    $profiles = Get-WinToolNote -Object $Settings -Name "profiles"
    $list = @(Get-WinToolNote -Object $profiles -Name "list" -Default @())
    $count = 0
    foreach ($item in $list) {
        $name = [string](Get-WinToolNote -Object $item -Name "name" -Default "")
        $source = [string](Get-WinToolNote -Object $item -Name "source" -Default "")
        $isWsl = $source -match '(?i)wsl'
        if (-not ($name -eq $Distro -or ($isWsl -and $name.StartsWith($Distro, [System.StringComparison]::OrdinalIgnoreCase)))) {
            continue
        }
        $font = Get-WinToolNote -Object $item -Name "font"
        if ($null -eq $font) {
            $item | Add-Member -NotePropertyName "font" -NotePropertyValue ([pscustomobject]@{ face = $Face }) -Force
        }
        elseif ($null -eq $font.PSObject.Properties["face"]) {
            $font | Add-Member -NotePropertyName "face" -NotePropertyValue $Face
        }
        else {
            $font.face = $Face
        }
        if ($null -ne $item.PSObject.Properties["fontFace"]) {
            $item.PSObject.Properties.Remove("fontFace")
        }
        $count++
    }
    return $count
}

function Invoke-WinToolWslTerminalProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Distro,
        [string]$Face,
        [string]$Match
    )
    if ([string]::IsNullOrWhiteSpace($Face)) {
        return
    }
    $chosen = Resolve-WinToolInstalledFontFace -Face $Face -Match $Match
    if ($null -eq $chosen) {
        return
    }
    $path = Get-WinToolTerminalSettingsPath
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        Write-WinToolLog -Message "Windows Terminal settings were not found, so the $Distro profile font was not set." -Level "warn"
        return
    }
    Backup-WinToolTerminalSetting -Path $path
    $raw = [System.IO.File]::ReadAllText($path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-WinToolLog -Message "Windows Terminal settings are empty, so the $Distro profile font was not set." -Level "warn"
        return
    }
    $settings = ConvertFrom-WinToolJsonText -Text $raw
    $count = Set-WinToolWslProfileFont -Settings $settings -Distro $Distro -Face $chosen
    if ($count -eq 0) {
        Write-WinToolLog -Message "Windows Terminal has no $Distro profile yet. It will use the default font, $chosen, when it appears." -Level "info"
        return
    }
    Write-WinToolUtf8File -Path $path -Text ((ConvertTo-WinToolJsonText -Value $settings) + "`n")
    Write-WinToolLog -Message "Set the $Distro profile font in Windows Terminal to $chosen." -Level "ok"
}

function Get-WinToolWslStep {
    param(
        [string]$Distro = "Ubuntu",
        [string]$PromptId = "oh-my-zsh",
        [string]$PromptStyle = "",
        $Font,
        [bool]$Install = $true,
        [bool]$Shell = $true
    )
    $steps = New-Object System.Collections.Generic.List[object]
    if ($Install) {
        [void]$steps.Add([pscustomobject]@{ Type = "wsl-install"; Label = "Install WSL with $Distro (kept if it already exists)"; Distro = $Distro })
    }
    if ($Shell) {
        $label = "Install zsh and Oh My Zsh in $Distro"
        if ($PromptId -eq "tide") { $label = "Install Fish and Tide in $Distro" }
        elseif ($PromptId -eq "powerlevel10k") { $label = "Install Powerlevel10k in $Distro" }
        elseif ($PromptId -eq "pure") { $label = "Install Pure in $Distro" }
        elseif ($PromptId -eq "spaceship") { $label = "Install Spaceship in $Distro" }
        elseif ($PromptId -eq "oh-my-zsh") { $label = "Install the Oh My Zsh theme in $Distro" }
        elseif ($PromptId -eq "oh-my-posh") { $label = "Install zsh and Oh My Posh in $Distro" }
        elseif ($PromptId -eq "starship") { $label = "Install zsh and Starship in $Distro" }
        $chosen = Get-WinToolPromptVariant -PromptId $PromptId -PromptStyle $PromptStyle
        if ($null -ne $chosen) {
            $label += " (" + [string]$chosen.name + " style)"
            $PromptStyle = [string]$chosen.id
        }
        [void]$steps.Add([pscustomobject]@{ Type = "wsl-shell"; Label = $label; Distro = $Distro; Variant = $PromptId; PromptStyle = $PromptStyle; OmzTheme = $PromptStyle })
    }
    if ($null -ne $Font) {
        [void]$steps.Add([pscustomobject]@{ Type = "wsl-profile"; Label = ("Use " + [string]$Font.name + " in the $Distro Terminal profile"); Distro = $Distro; Face = [string]$Font.face; Match = [string]$Font.match })
    }
    return $steps.ToArray()
}

function Get-WinToolWslShellPlan {
    param(
        [string]$Distro = "Ubuntu",
        [string]$PromptId = "oh-my-posh",
        [string]$PromptStyle = "jandedobbeleer",
        [string]$FontId = "cascadiacode-nf",
        [switch]$Install
    )
    # Only the WSL part of terminal setup: no Windows packages, profiles, or
    # color schemes. Without -Install an existing distro is required.
    $font = $null
    if (-not [string]::IsNullOrWhiteSpace($FontId)) {
        foreach ($item in @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())) {
            if ([string]$item.id -eq $FontId) {
                $font = $item
                break
            }
        }
        if ($null -eq $font) {
            throw "Unknown terminal font '$FontId'."
        }
    }
    return @(Get-WinToolWslStep -Distro $Distro -PromptId $PromptId -PromptStyle $PromptStyle -Font $font -Install ([bool]$Install) -Shell $true)
}

function Invoke-WinToolWslShellSetup {
    param(
        [string]$Distro = "Ubuntu",
        [string]$PromptId = "oh-my-posh",
        [string]$PromptStyle = "jandedobbeleer",
        [string]$FontId = "cascadiacode-nf",
        [switch]$Install
    )
    $plan = @(Get-WinToolWslShellPlan -Distro $Distro -PromptId $PromptId -PromptStyle $PromptStyle -FontId $FontId -Install:$Install)
    Invoke-WinToolPlan -Step $plan
}
