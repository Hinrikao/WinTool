# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolUi {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    $control = $script:WinToolWindow.FindName($Name)
    if ($null -eq $control) {
        throw "WinTool could not find the window control '$Name'."
    }
    return $control
}

function Get-WinToolBrush {
    param(
        [Parameter(Mandatory = $true)][string]$Key
    )
    return $script:WinToolWindow.FindResource($Key)
}

function New-WinToolText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [int]$Size = 14,
        [string]$Weight = "Normal",
        [string]$Brush = "BrushInk",
        [switch]$Wrap,
        [System.Windows.Thickness]$Margin = ([System.Windows.Thickness]::new(0))
    )
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text
    $block.FontSize = $Size
    $weights = [type]"System.Windows.FontWeights"
    $flags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static
    $weightProperty = $weights.GetProperty($Weight, $flags)
    if ($null -eq $weightProperty) {
        throw "Unknown font weight '$Weight'."
    }
    $block.FontWeight = $weightProperty.GetValue($null, $null)
    $block.Foreground = Get-WinToolBrush -Key $Brush
    $block.Margin = $Margin
    if ($Wrap) {
        $block.TextWrapping = "Wrap"
    }
    return $block
}

function New-WinToolCard {
    $border = New-Object System.Windows.Controls.Border
    $border.Background = Get-WinToolBrush -Key "BrushCard"
    $border.BorderBrush = Get-WinToolBrush -Key "BrushLine"
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(12)
    $border.Padding = [System.Windows.Thickness]::new(16)
    $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    return $border
}

function New-WinToolBadge {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Kind
    )
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
    $border.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $border.VerticalAlignment = "Center"
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Text
    $label.FontSize = 11
    $label.FontWeight = "SemiBold"
    if ($Kind -eq "caution") {
        $border.Background = Get-WinToolBrush -Key "BrushWarnSoft"
        $label.Foreground = Get-WinToolBrush -Key "BrushWarn"
    }
    else {
        $border.Background = Get-WinToolBrush -Key "BrushOkSoft"
        $label.Foreground = Get-WinToolBrush -Key "BrushOk"
    }
    $border.Child = $label
    return $border
}

function New-WinToolColumn {
    param(
        [switch]$Auto
    )
    $column = New-Object System.Windows.Controls.ColumnDefinition
    if ($Auto) {
        $column.Width = [System.Windows.GridLength]::Auto
    }
    else {
        $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    }
    return $column
}

function Sync-WinToolSearchHint {
    param(
        [Parameter(Mandatory = $true)][string]$BoxName,
        [Parameter(Mandatory = $true)][string]$HintName
    )
    $box = Get-WinToolUi -Name $BoxName
    $hint = Get-WinToolUi -Name $HintName
    if ([string]::IsNullOrEmpty($box.Text)) {
        $hint.Visibility = "Visible"
    }
    else {
        $hint.Visibility = "Collapsed"
    }
}
