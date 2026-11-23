# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolAccentChoice {
    $choices = @(
        [pscustomobject]@{ Id = "blue"; Name = "Blue"; Dark = "#6C9BFF"; DarkHover = "#8BB0FF"; DarkPressed = "#4E86F5"; DarkSoft = "#2A3A5C"; Light = "#2F6FED"; LightHover = "#1D5AD6"; LightPressed = "#184AAA"; LightSoft = "#E7EEFF" },
        [pscustomobject]@{ Id = "teal"; Name = "Teal"; Dark = "#3DCEB5"; DarkHover = "#67DCC8"; DarkPressed = "#2AAB96"; DarkSoft = "#1A3A36"; Light = "#0E8F78"; LightHover = "#0B7462"; LightPressed = "#085E50"; LightSoft = "#E3F6F2" },
        [pscustomobject]@{ Id = "violet"; Name = "Violet"; Dark = "#A594FF"; DarkHover = "#C0B4FF"; DarkPressed = "#8874F0"; DarkSoft = "#322C52"; Light = "#6D5BD0"; LightHover = "#5846B8"; LightPressed = "#46369A"; LightSoft = "#EEEAFF" },
        [pscustomobject]@{ Id = "amber"; Name = "Amber"; Dark = "#E0B15A"; DarkHover = "#ECC888"; DarkPressed = "#C8943A"; DarkSoft = "#3A3120"; Light = "#A87412"; LightHover = "#8A600C"; LightPressed = "#6E4C08"; LightSoft = "#FFF4E0" },
        [pscustomobject]@{ Id = "rose"; Name = "Rose"; Dark = "#F08AA8"; DarkHover = "#F6AEC4"; DarkPressed = "#D86B8C"; DarkSoft = "#3D2430"; Light = "#C4476C"; LightHover = "#A53658"; LightPressed = "#842A46"; LightSoft = "#FDECEF" }
    )
    return $choices
}

function Get-WinToolAccentById {
    param(
        [string]$Id
    )
    foreach ($choice in @(Get-WinToolAccentChoice)) {
        if ([string]$choice.Id -eq $Id) {
            return $choice
        }
    }
    foreach ($choice in @(Get-WinToolAccentChoice)) {
        if ([string]$choice.Id -eq "blue") {
            return $choice
        }
    }
    return $null
}

function Get-WinToolBasePalette {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("dark", "light")][string]$Resolved
    )
    if ($Resolved -eq "light") {
        $palette = @{
            BrushCanvas = "#F3F5F9"
            BrushCard = "#FFFFFF"
            BrushLine = "#E1E7F0"
            BrushInk = "#1C2434"
            BrushMuted = "#5C6B82"
            BrushSidebar = "#FFFFFF"
            BrushSidebarText = "#1C2434"
            BrushSidebarMuted = "#5C6B82"
            BrushNavHover = "#E7EEF8"
            BrushLog = "#E8EDF5"
            BrushLogText = "#1C2434"
            BrushProgressTrack = "#D5DEEA"
            BrushInput = "#FFFFFF"
            BrushInputBorder = "#D5DEEA"
            BrushHint = "#8A97AD"
            BrushOnAccent = "#FFFFFF"
            BrushOk = "#0F7A56"
            BrushOkSoft = "#E5F6EF"
            BrushWarn = "#8A5A00"
            BrushWarnSoft = "#FFF4E0"
            BrushBad = "#B42318"
        }
        return ,$palette
    }
    $palette = @{
        BrushCanvas = "#1B2230"
        BrushCard = "#262E40"
        BrushLine = "#3A445C"
        BrushInk = "#E8EDF7"
        BrushMuted = "#A7B3C9"
        BrushSidebar = "#141A27"
        BrushSidebarText = "#E8EEF8"
        BrushSidebarMuted = "#93A0B8"
        BrushNavHover = "#2A3348"
        BrushLog = "#121826"
        BrushLogText = "#D5DEEE"
        BrushProgressTrack = "#2A3348"
        BrushInput = "#1C2434"
        BrushInputBorder = "#44506A"
        BrushHint = "#8E9BB3"
        BrushOnAccent = "#FFFFFF"
        BrushOk = "#3DDC97"
        BrushOkSoft = "#17382E"
        BrushWarn = "#E6B15A"
        BrushWarnSoft = "#3A3120"
        BrushBad = "#F07178"
    }
    return ,$palette
}

function Resolve-WinToolAppearance {
    param(
        [string]$Theme,
        [string]$Accent,
        [bool]$SystemIsLight
    )
    $resolved = "dark"
    if ($Theme -eq "light") {
        $resolved = "light"
    }
    elseif ($Theme -eq "system" -and $SystemIsLight) {
        $resolved = "light"
    }
    $accentChoice = Get-WinToolAccentById -Id $Accent
    $base = Get-WinToolBasePalette -Resolved $resolved
    $brushes = @{}
    foreach ($key in @($base.Keys)) {
        $brushes[$key] = [string]$base[$key]
    }
    if ($resolved -eq "light") {
        $brushes["BrushAccent"] = [string]$accentChoice.Light
        $brushes["BrushAccentHover"] = [string]$accentChoice.LightHover
        $brushes["BrushAccentPressed"] = [string]$accentChoice.LightPressed
        $brushes["BrushAccentSoft"] = [string]$accentChoice.LightSoft
    }
    else {
        $brushes["BrushAccent"] = [string]$accentChoice.Dark
        $brushes["BrushAccentHover"] = [string]$accentChoice.DarkHover
        $brushes["BrushAccentPressed"] = [string]$accentChoice.DarkPressed
        $brushes["BrushAccentSoft"] = [string]$accentChoice.DarkSoft
    }
    $brushes["BrushProgress"] = $brushes["BrushAccent"]
    return [pscustomobject]@{
        Resolved = $resolved
        Brushes = $brushes
    }
}

function Get-WinToolSettingsPath {
    param(
        [string]$Path
    )
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return $null
    }
    return (Join-Path $env:APPDATA "WinTool/settings.json")
}

function Get-WinToolDefaultSetting {
    return [pscustomobject]@{
        schemaVersion = 1
        theme = "dark"
        accent = "blue"
    }
}

function Read-WinToolSetting {
    param(
        [string]$Path
    )
    $defaults = Get-WinToolDefaultSetting
    $settingsPath = Get-WinToolSettingsPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($settingsPath) -or -not (Test-Path -LiteralPath $settingsPath)) {
        return $defaults
    }
    try {
        $raw = Read-WinToolJsonFile -Path $settingsPath
    }
    catch {
        return $defaults
    }
    $theme = [string](Get-WinToolNote -Object $raw -Name "theme" -Default "dark")
    if (@("dark", "light", "system") -notcontains $theme) {
        $theme = "dark"
    }
    $accent = [string](Get-WinToolNote -Object $raw -Name "accent" -Default "blue")
    $known = $false
    foreach ($choice in @(Get-WinToolAccentChoice)) {
        if ([string]$choice.Id -eq $accent) {
            $known = $true
        }
    }
    if (-not $known) {
        $accent = "blue"
    }
    return [pscustomobject]@{
        schemaVersion = 1
        theme = $theme
        accent = $accent
    }
}

function Save-WinToolSetting {
    param(
        [Parameter(Mandatory = $true)]$Setting,
        [string]$Path
    )
    $settingsPath = Get-WinToolSettingsPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($settingsPath)) {
        return
    }
    $directory = Split-Path -Parent $settingsPath
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $payload = [pscustomobject]@{
        schemaVersion = 1
        theme = [string]$Setting.theme
        accent = [string]$Setting.accent
    }
    Write-WinToolJsonFile -Path $settingsPath -Value $payload
}

function Test-WinToolSystemLightTheme {
    if (-not (Test-WinToolWindows)) {
        return $false
    }
    try {
        $item = Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop
        return ([int]$item.AppsUseLightTheme -ne 0)
    }
    catch {
        return $false
    }
}

function Set-WinToolBrushColor {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Hex
    )
    $converted = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $color = [System.Windows.Media.Color]$converted
    $brush = [System.Windows.Media.SolidColorBrush]::new($color)
    if ($script:WinToolWindow.Resources.Contains($Key)) {
        $script:WinToolWindow.Resources.Remove($Key)
    }
    $script:WinToolWindow.Resources.Add($Key, $brush)
}

function Set-WinToolTheme {
    param(
        [string]$Theme,
        [string]$Accent
    )
    if ([string]::IsNullOrWhiteSpace($Theme)) {
        $Theme = "dark"
    }
    if ([string]::IsNullOrWhiteSpace($Accent)) {
        $Accent = "blue"
    }
    $appearance = Resolve-WinToolAppearance -Theme $Theme -Accent $Accent -SystemIsLight (Test-WinToolSystemLightTheme)
    foreach ($key in @($appearance.Brushes.Keys)) {
        Set-WinToolBrushColor -Key ([string]$key) -Hex ([string]$appearance.Brushes[$key])
    }
    $script:WinToolResolvedTheme = [string]$appearance.Resolved
    $script:WinToolSetting = [pscustomobject]@{
        schemaVersion = 1
        theme = $Theme
        accent = $Accent
    }
    if ($null -ne $script:WinToolWindow -and $null -ne $script:WinToolWindow.FindName("AccentSwatches")) {
        Sync-WinToolAccentSwatch
    }
}

function Sync-WinToolAccentSwatch {
    $panel = Get-WinToolUi -Name "AccentSwatches"
    $resolved = [string]$script:WinToolResolvedTheme
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = "dark"
    }
    $selected = "blue"
    if ($null -ne $script:WinToolSetting) {
        $selected = [string]$script:WinToolSetting.accent
    }
    for ($index = 0; $index -lt $panel.Children.Count; $index++) {
        $swatch = $panel.Children[$index]
        $choice = Get-WinToolAccentById -Id ([string]$swatch.Tag)
        if ($null -eq $choice) {
            continue
        }
        $hex = [string]$choice.Dark
        if ($resolved -eq "light") {
            $hex = [string]$choice.Light
        }
        $converted = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $swatch.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]$converted)
        if ([string]$swatch.Tag -eq $selected) {
            $swatch.BorderThickness = [System.Windows.Thickness]::new(2)
            $swatch.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushSidebarText")
        }
        else {
            $swatch.BorderThickness = [System.Windows.Thickness]::new(0)
        }
    }
}

function Initialize-WinToolAppearance {
    $setting = Read-WinToolSetting
    $script:WinToolSetting = $setting
    Set-WinToolTheme -Theme ([string]$setting.theme) -Accent ([string]$setting.accent)

    $picker = Get-WinToolUi -Name "ThemePicker"
    $script:WinToolState.UpdatingTheme = $true
    $picker.Items.Clear()
    foreach ($choice in @(
            [pscustomobject]@{ Id = "dark"; Name = "Dark" },
            [pscustomobject]@{ Id = "light"; Name = "Light" },
            [pscustomobject]@{ Id = "system"; Name = "System" }
        )) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$choice.Name
        $item.Tag = [string]$choice.Id
        [void]$picker.Items.Add($item)
        if ([string]$choice.Id -eq [string]$setting.theme) {
            $picker.SelectedItem = $item
        }
    }
    $script:WinToolState.UpdatingTheme = $false
    Register-WinToolUiEvent -Control $picker -EventName "SelectionChanged" -Name "Appearance: theme" -Action {
        if ($script:WinToolState.UpdatingTheme) {
            return
        }
        $selectedItem = (Get-WinToolUi -Name "ThemePicker").SelectedItem
        if ($null -eq $selectedItem) {
            return
        }
        $themeId = [string]$selectedItem.Tag
        $accentId = "blue"
        if ($null -ne $script:WinToolSetting) {
            $accentId = [string]$script:WinToolSetting.accent
        }
        Set-WinToolTheme -Theme $themeId -Accent $accentId
        Save-WinToolSetting -Setting $script:WinToolSetting
    }

    $panel = Get-WinToolUi -Name "AccentSwatches"
    $panel.Children.Clear()
    $template = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="11"/>
</ControlTemplate>
"@)
    foreach ($accent in @(Get-WinToolAccentChoice)) {
        $swatch = New-Object System.Windows.Controls.Button
        $swatch.Width = 22
        $swatch.Height = 22
        $swatch.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $swatch.Tag = [string]$accent.Id
        $swatch.ToolTip = [string]$accent.Name
        $swatch.Cursor = [System.Windows.Input.Cursors]::Hand
        $swatch.Padding = [System.Windows.Thickness]::new(0)
        $swatch.Template = $template
        Register-WinToolUiEvent -Control $swatch -EventName "Click" -Name "Appearance: accent color" -Data ([string]$accent.Id) -Action {
            param($source, $eventData, $accentId)
            $null = $source, $eventData
            $themeId = "dark"
            if ($null -ne $script:WinToolSetting) {
                $themeId = [string]$script:WinToolSetting.theme
            }
            Set-WinToolTheme -Theme $themeId -Accent $accentId
            Save-WinToolSetting -Setting $script:WinToolSetting
        }
        [void]$panel.Children.Add($swatch)
    }
    Sync-WinToolAccentSwatch
}
