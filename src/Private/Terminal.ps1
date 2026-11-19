# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolPromptScript {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true
    )
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Added by WinTool. Delete this block, or run WinTool again, to change it.")
    if ($TerminalIcons) {
        $lines.Add("if (Get-Module -ListAvailable -Name Terminal-Icons) {")
        $lines.Add("    Import-Module Terminal-Icons")
        $lines.Add("}")
    }
    if ($PromptId -eq "starship") {
        $lines.Add("if (Get-Command starship -ErrorAction SilentlyContinue) {")
        $lines.Add("    Invoke-Expression (& starship init powershell)")
        $lines.Add("}")
    }
    else {
        $lines.Add("if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {")
        $lines.Add('    $theme = Join-Path $env:POSH_THEMES_PATH "jandedobbeleer.omp.json"')
        $lines.Add("    if (Test-Path -LiteralPath `$theme) {")
        $lines.Add("        oh-my-posh init pwsh --config `$theme | Invoke-Expression")
        $lines.Add("    }")
        $lines.Add("    else {")
        $lines.Add("        oh-my-posh init pwsh | Invoke-Expression")
        $lines.Add("    }")
        $lines.Add("}")
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

function Get-WinToolInstalledFontFace {
    param(
        [Parameter(Mandatory = $true)][string]$Token
    )
    if (-not (Test-WinToolWindows)) {
        return $null
    }
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    )
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $item = Get-Item -LiteralPath $path
        foreach ($name in @($item.GetValueNames())) {
            if ([string]$name -eq "") {
                continue
            }
            if ($name.IndexOf($Token, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return (ConvertTo-WinToolFontFace -RegistryName $name)
            }
        }
    }
    return $null
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

function Write-WinToolShellProfile {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId,
        [bool]$TerminalIcons = $true
    )
    $body = Get-WinToolPromptScript -PromptId $PromptId -TerminalIcons $TerminalIcons
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

function Invoke-WinToolTerminalFont {
    param(
        [Parameter(Mandatory = $true)][string]$Face,
        [string]$Match
    )
    $chosen = $Face
    if (-not [string]::IsNullOrWhiteSpace($Match)) {
        $found = Get-WinToolInstalledFontFace -Token $Match
        if (-not [string]::IsNullOrWhiteSpace($found)) {
            $chosen = $found
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

function Get-WinToolTerminalPlan {
    param(
        [Parameter(Mandatory = $true)]$Selection
    )
    $catalog = Get-WinToolTerminalCatalog
    $promptId = [string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "")
    if ([string]::IsNullOrWhiteSpace($promptId)) {
        $promptId = [string](Get-WinToolNote -Object $Selection -Name "Prompt" -Default "oh-my-posh")
    }
    $fontId = [string](Get-WinToolNote -Object $Selection -Name "fontId" -Default "")
    if ([string]::IsNullOrWhiteSpace($fontId)) {
        $fontId = [string](Get-WinToolNote -Object $Selection -Name "FontId" -Default "")
    }
    $icons = Get-WinToolNote -Object $Selection -Name "terminalIcons"
    if ($null -eq $icons) {
        $icons = Get-WinToolNote -Object $Selection -Name "TerminalIcons" -Default $true
    }
    $wsl = Get-WinToolNote -Object $Selection -Name "wsl"
    if ($null -eq $wsl) {
        $wsl = Get-WinToolNote -Object $Selection -Name "Wsl" -Default $false
    }
    $zsh = Get-WinToolNote -Object $Selection -Name "zsh"
    if ($null -eq $zsh) {
        $zsh = Get-WinToolNote -Object $Selection -Name "Zsh" -Default $false
    }

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

    $fonts = @(Get-WinToolNote -Object $catalog -Name "fonts" -Default @())
    $font = $null
    if ([string]::IsNullOrWhiteSpace($fontId) -and $fonts.Count -gt 0) {
        $font = $fonts[0]
    }
    else {
        foreach ($item in $fonts) {
            if ([string]$item.id -eq $fontId) {
                $font = $item
                break
            }
        }
    }
    if ($null -eq $font) {
        throw "Unknown terminal font '$fontId'."
    }

    $components = Get-WinToolNote -Object $catalog -Name "components"
    $steps = New-Object System.Collections.Generic.List[object]
    $steps.Add([pscustomobject]@{
        Type = "winget"
        Label = "Install Windows Terminal"
        WingetId = [string]$components.windowsTerminal
        Scope = ""
    })
    $steps.Add([pscustomobject]@{
        Type = "winget"
        Label = "Install PowerShell 7"
        WingetId = [string]$components.powerShell
        Scope = ""
    })
    $steps.Add([pscustomobject]@{
        Type = "winget"
        Label = "Install $($prompt.name)"
        WingetId = [string]$prompt.wingetId
        Scope = ""
    })
    $steps.Add([pscustomobject]@{
        Type = "winget"
        Label = "Install $($font.name)"
        WingetId = [string]$font.wingetId
        Scope = ""
    })
    $steps.Add([pscustomobject]@{
        Type = "font"
        Label = "Set the Windows Terminal font"
        Face = [string]$font.face
        Match = [string]$font.match
    })
    $steps.Add([pscustomobject]@{
        Type = "profile"
        Label = "Update PowerShell profiles"
        Prompt = $promptId
        TerminalIcons = [bool]$icons
    })
    if ([bool]$icons) {
        $steps.Add([pscustomobject]@{
            Type = "module"
            Label = "Install Terminal-Icons for Windows PowerShell"
            Host = "powershell"
        })
        $steps.Add([pscustomobject]@{
            Type = "module"
            Label = "Install Terminal-Icons for PowerShell 7"
            Host = "pwsh"
        })
    }
    if ([bool]$wsl) {
        $steps.Add([pscustomobject]@{
            Type = "wsl-install"
            Label = "Install WSL with Ubuntu"
        })
        if ([bool]$zsh) {
            $steps.Add([pscustomobject]@{
                Type = "wsl-shell"
                Label = "Install zsh and Oh My Zsh in Ubuntu"
            })
        }
    }
    return $steps.ToArray()
}
