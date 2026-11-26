# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolPalette {
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
        BrushBadSoft = "#3A1D24"
        BrushOkLine = "#2F6B4A"
        BrushWarnLine = "#7A5A1E"
        BrushWarnStrong = "#D39B2A"
        BrushOnWarn = "#1B1B1B"
        BrushAccent = "#6C9BFF"
        BrushAccentHover = "#8BB0FF"
        BrushAccentPressed = "#4E86F5"
        BrushAccentSoft = "#2A3A5C"
        BrushProgress = "#6C9BFF"
    }
    return ,$palette
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

function Initialize-WinToolAppearance {
    $palette = Get-WinToolPalette
    foreach ($key in @($palette.Keys)) {
        Set-WinToolBrushColor -Key ([string]$key) -Hex ([string]$palette[$key])
    }
}
