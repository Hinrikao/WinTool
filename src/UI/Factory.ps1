# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolUi {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    $control = $script:WinToolWindow.FindName($Name)
    if ($null -eq $control) {
        throw (Get-WinToolText "msg.wintool-could-not-find-the-window-control-n" $Name)
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
        # Leave -Size out: every text uses the shared FontSizeBody resource.
        [double]$Size = 0,
        [string]$Weight = "Normal",
        [string]$Brush = "BrushInk",
        [switch]$Wrap,
        [System.Windows.Thickness]$Margin = ([System.Windows.Thickness]::new(0)),
        [string]$VerticalAlignment = ""
    )
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text
    if ($Size -gt 0) { $block.FontSize = $Size }
    else { $null = $block.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody") }
    $weights = [type]"System.Windows.FontWeights"
    $flags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static
    $weightProperty = $weights.GetProperty($Weight, $flags)
    if ($null -eq $weightProperty) {
        throw (Get-WinToolText "msg.unknown-font-weight-n" $Weight)
    }
    $block.FontWeight = $weightProperty.GetValue($null, $null)
    $null = $block.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $Brush)
    $block.Margin = $Margin
    if ($Wrap) {
        $block.TextWrapping = "Wrap"
    }
    if (-not [string]::IsNullOrWhiteSpace($VerticalAlignment)) {
        $block.VerticalAlignment = $VerticalAlignment
    }
    return $block
}

function Set-WinToolAutoButton {
    # Drop fixed Width/Height so longer translations are not clipped.
    param(
        [Parameter(Mandatory = $true)][System.Windows.Controls.Button]$Button,
        [double]$MinWidth = 88,
        [double]$MinHeight = 32
    )
    $Button.MinWidth = $MinWidth
    $Button.MinHeight = $MinHeight
    $Button.Padding = [System.Windows.Thickness]::new(12, 7, 12, 7)
    $Button.ClearValue([System.Windows.FrameworkElement]::WidthProperty)
    $Button.ClearValue([System.Windows.FrameworkElement]::HeightProperty)
}


function New-WinToolCard {
    $border = New-Object System.Windows.Controls.Border
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushCard")
    $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
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
    $label.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
    $label.FontWeight = "SemiBold"
    if ($Kind -eq "caution") {
        $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushWarnSoft")
        $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushWarn")
    }
    else {
        $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushOkSoft")
        $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushOk")
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

# Event handlers are registered through Register-WinToolUiEvent instead of
# scriptblock.GetNewClosure(). A closure runs in its own dynamic module, so
# $script: inside it does not reach WinTool's state and reads as $null. That is
# what crashed the Terminal tab with "The property 'prompt' cannot be found".
# Per-control values travel in -Data, and every handler runs inside try/catch.
function Register-WinToolUiEvent {
    param(
        [Parameter(Mandatory = $true)]$Control,
        [Parameter(Mandatory = $true)][string]$EventName,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        $Data
    )
    if ($null -eq $script:WinToolUiHandlers) {
        $script:WinToolUiHandlers = New-Object System.Collections.Generic.List[object]
    }
    $id = $script:WinToolUiHandlers.Count
    $script:WinToolUiHandlers.Add([pscustomobject]@{
            Id = $id
            Name = $Name
            EventName = $EventName
            Control = $Control
            Action = $Action
            Data = $Data
        })
    $dispatch = [scriptblock]::Create(('Invoke-WinToolUiEvent -Id {0} -Source $args[0] -EventData $args[1]' -f $id))
    $method = "add_" + $EventName
    $null = $Control.$method($dispatch)
}

function Invoke-WinToolUiEvent {
    param(
        [Parameter(Mandatory = $true)][int]$Id,
        $Source,
        $EventData
    )
    $entry = $script:WinToolUiHandlers[$Id]
    try {
        $null = & $entry.Action $Source $EventData $entry.Data
    }
    catch {
        Write-WinToolUiError -Name ([string]$entry.Name) -ErrorRecord $_
    }
}

function Write-WinToolUiError {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $ErrorRecord
    )
    if ($null -eq $script:WinToolUiErrors) {
        $script:WinToolUiErrors = New-Object System.Collections.Generic.List[object]
    }
    $message = "Unknown error."
    if ($null -ne $ErrorRecord -and $null -ne $ErrorRecord.Exception) {
        $message = [string]$ErrorRecord.Exception.Message
    }
    $script:WinToolUiErrors.Add([pscustomobject]@{ Name = $Name; Message = $message; Record = $ErrorRecord })
    $logPath = $null
    try {
        $detail = Format-WinToolErrorText -ErrorRecord $ErrorRecord -Title (Get-WinToolText "msg.a-wintool-action-failed-n" $Name)
        $logPath = Write-WinToolFailureLog -Text $detail
        Write-WinToolLog -Message ((Get-WinToolText "msg.n-failed-n-2") -f $Name, $message) -Level "error"
    }
    catch {
        $null = $_.Exception.Message
    }
    if ($script:WinToolUiQuiet) {
        return
    }
    # Show each failing action once, so a repeating event cannot flood the screen.
    if ($null -eq $script:WinToolUiErrorShown) {
        $script:WinToolUiErrorShown = @{}
    }
    if ($script:WinToolUiErrorShown.ContainsKey($Name)) {
        return
    }
    $script:WinToolUiErrorShown[$Name] = $true
    try {
        $text = "Something went wrong in '" + $Name + "'. WinTool is still open.`r`n`r`n" + $message
        if (-not [string]::IsNullOrWhiteSpace($logPath)) {
            $text += "`r`n`r`nDetails: " + $logPath
        }
        [System.Windows.MessageBox]::Show($text, "WinTool") | Out-Null
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Get-WinToolUiError {
    # ToArray() keeps this on object[]; @() around a generic list fails on 5.1.
    if ($null -eq $script:WinToolUiErrors) {
        return , @()
    }
    return , $script:WinToolUiErrors.ToArray()
}
