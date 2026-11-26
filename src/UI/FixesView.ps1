# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolFixView {
    $hostPanel = Get-WinToolUi -Name "FixList"
    $hostPanel.Children.Clear()
    $fixes = @(Get-WinToolNote -Object (Get-WinToolFixCatalog) -Name "fixes" -Default @())
    $index = 0
    foreach ($fix in $fixes) {
        $card = New-WinToolCard
        $card.CornerRadius = [System.Windows.CornerRadius]::new(16)
        $card.Padding = [System.Windows.Thickness]::new(18)
        $card.MinHeight = 0
        $gapLeft = 0
        $gapTop = 0
        if (($index % 2) -eq 0) { $gapLeft = 0 } else { $gapLeft = 14 }
        if ($index -ge 2) { $gapTop = 14 }
        $card.Margin = [System.Windows.Thickness]::new($gapLeft, $gapTop, 0, 0)
        $grid = New-Object System.Windows.Controls.Grid
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        $footRow = New-Object System.Windows.Controls.RowDefinition
        $footRow.Height = [System.Windows.GridLength]::Auto
        $footRow.MinHeight = 36
        $grid.RowDefinitions.Add($footRow)
        $title = New-WinToolText -Text ([string]$fix.name) -Weight "Bold"
        [void]$grid.Children.Add($title)
        $description = New-WinToolText -Text ([string]$fix.description) -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 8, 0, 8))
        [System.Windows.Controls.Grid]::SetRow($description, 1)
        [void]$grid.Children.Add($description)
        $foot = New-Object System.Windows.Controls.Grid
        $foot.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $foot.ColumnDefinitions.Add((New-WinToolColumn))
        $foot.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        [System.Windows.Controls.Grid]::SetRow($foot, 2)
        $restart = [bool](Get-WinToolNote -Object $fix -Name "restart" -Default $false)
        $badgeText = Get-WinToolText "msg.no-restart"
        $badgeKind = "ok"
        if ($restart) {
            $badgeText = Get-WinToolText "msg.restart-needed"
            $badgeKind = "caution"
        }
        $badge = New-WinToolBadge -Text $badgeText -Kind $badgeKind
        $badge.Margin = [System.Windows.Thickness]::new(0)
        [void]$foot.Children.Add($badge)
        $button = New-Object System.Windows.Controls.Button
        $button.Content = (Get-WinToolText "msg.run-fix")
        $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
        Set-WinToolAutoButton -Button $button
        $button.HorizontalAlignment = "Right"
        $button.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($button, 2)
        [void]$foot.Children.Add($button)
        [void]$grid.Children.Add($foot)
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Fixes: " + [string]$fix.name) -Data $fix -Action {
            param($source, $eventData, $boundFix)
            $null = $source, $eventData
            Invoke-WinToolFixClick -Fix $boundFix
        }
        Add-WinToolBusyControl -Control $button
        $card.Child = $grid
        [void]$hostPanel.Children.Add($card)
        $index++
    }
}

function Invoke-WinToolFixClick {
    param(
        [Parameter(Mandatory = $true)]$Fix
    )
    Start-WinToolSurfaceTiming -Name ("Fixes " + [string]$Fix.name)
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    $message = ([string]$Fix.name) + "?`n`n" + ([string]$Fix.description)
    $restart = [bool](Get-WinToolNote -Object $Fix -Name "restart" -Default $false)
    if ($restart) {
        $message += "`n`n" + (Get-WinToolText "msg.restart-the-pc-when-it-finishes")
    }
    $ok = Request-WinToolConfirmation -Message $message -Title ([string]$Fix.name)
    if (-not $ok) {
        return
    }
    $done = (Get-WinToolText "msg.fix-finished" ([string]$Fix.name))
    if ($restart) {
        $done += " " + (Get-WinToolText "msg.restart-the-pc-to-complete-it")
    }
    Invoke-WinToolPlanAsync -Step @(Get-WinToolFixPlan -Fix $Fix) -DoneMessage $done
}
