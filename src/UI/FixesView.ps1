# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolFixView {
    $hostPanel = Get-WinToolUi -Name "FixList"
    $hostPanel.Children.Clear()
    foreach ($fix in @(Get-WinToolNote -Object (Get-WinToolFixCatalog) -Name "fixes" -Default @())) {
        $card = New-WinToolCard
        $grid = New-Object System.Windows.Controls.Grid
        $grid.ColumnDefinitions.Add((New-WinToolColumn))
        $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $text = New-Object System.Windows.Controls.StackPanel
        $title = New-Object System.Windows.Controls.StackPanel
        $title.Orientation = "Horizontal"
        [void]$title.Children.Add((New-WinToolText -Text ([string]$fix.name) -Size 16 -Weight "SemiBold"))
        if ([bool](Get-WinToolNote -Object $fix -Name "restart" -Default $false)) {
            [void]$title.Children.Add((New-WinToolBadge -Text "Restart needed" -Kind "caution"))
        }
        [void]$text.Children.Add($title)
        [void]$text.Children.Add((New-WinToolText -Text ([string]$fix.description) -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 4, 16, 0))))
        [System.Windows.Controls.Grid]::SetColumn($text, 0)
        [void]$grid.Children.Add($text)
        $button = New-Object System.Windows.Controls.Button
        $button.Content = "Run"
        $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
        $button.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($button, 1)
        [void]$grid.Children.Add($button)
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Fixes: " + [string]$fix.name) -Data $fix -Action {
            param($source, $eventData, $boundFix)
            $null = $source, $eventData
            Invoke-WinToolFixClick -Fix $boundFix
        }
        Add-WinToolBusyControl -Control $button
        $card.Child = $grid
        [void]$hostPanel.Children.Add($card)
    }
}

function Invoke-WinToolFixClick {
    param(
        [Parameter(Mandatory = $true)]$Fix
    )
    $message = ([string]$Fix.name) + "?`n`n" + ([string]$Fix.description)
    $restart = [bool](Get-WinToolNote -Object $Fix -Name "restart" -Default $false)
    if ($restart) {
        $message += "`n`nRestart the PC when it finishes."
    }
    $ok = Request-WinToolConfirmation -Message $message -Title ([string]$Fix.name)
    if (-not $ok) {
        return
    }
    $done = ([string]$Fix.name) + " finished."
    if ($restart) {
        $done += " Restart the PC to complete it."
    }
    Invoke-WinToolPlanAsync -Step @(Get-WinToolFixPlan -Fix $Fix) -DoneMessage $done
}
