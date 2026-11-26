# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolActivityView {
    Initialize-WinToolActivityState
    $script:WinToolState.LogExpanded = $false
    $script:WinToolState.LogPinned = $false
    $script:WinToolState.ActivityDirty = $true
    $script:WinToolState.ToastTimer = $null

    $toggle = Get-WinToolUi -Name "ToggleLogButton"
    $toggle.ToolTip = (Get-WinToolText "activity.show")
    [System.Windows.Automation.AutomationProperties]::SetName($toggle, (Get-WinToolText "activity.show"))
    (Get-WinToolUi -Name "ActivityToggleText").Text = (Get-WinToolText "activity.show")
    (Get-WinToolUi -Name "ActivityTitle").Text = (Get-WinToolText "activity.title")
    (Get-WinToolUi -Name "ActivityFilterAll").Content = (Get-WinToolText "activity.filter.all")
    (Get-WinToolUi -Name "ActivityFilterWarnings").Content = (Get-WinToolText "activity.filter.warnings")
    (Get-WinToolUi -Name "ActivityFilterErrors").Content = (Get-WinToolText "activity.filter.errors")
    (Get-WinToolUi -Name "ActivityCopy").Content = (Get-WinToolText "activity.copy")
    (Get-WinToolUi -Name "ActivitySave").Content = (Get-WinToolText "activity.save")
    (Get-WinToolUi -Name "CancelRun").Content = (Get-WinToolText "button.cancel")
    (Get-WinToolUi -Name "StatusText").Text = (Get-WinToolText "status.ready")
    (Get-WinToolUi -Name "ToastDismiss").ToolTip = (Get-WinToolText "toast.dismiss")
    [System.Windows.Automation.AutomationProperties]::SetName((Get-WinToolUi -Name "ToastDismiss"), (Get-WinToolText "toast.dismiss"))

    Register-WinToolUiEvent -Control $toggle -EventName "Click" -Name "Activity" -Action { Switch-WinToolLogPanel }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ActivityCopy") -EventName "Click" -Name "Copy activity" -Action { Copy-WinToolActivityReport }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ActivitySave") -EventName "Click" -Name "Save activity" -Action { Save-WinToolActivityReport }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ToastDismiss") -EventName "Click" -Name "Dismiss toast" -Action { Hide-WinToolToast }
    foreach ($pair in @(
            , @("ActivityFilterAll", "all")
            , @("ActivityFilterWarnings", "warnings")
            , @("ActivityFilterErrors", "errors")
        )) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name $pair[0]) -EventName "Checked" -Name ("Activity filter " + $pair[1]) -Data $pair[1] -Action {
            param($source, $eventData, $boundFilter)
            $null = $source, $eventData
            Set-WinToolActivityFilter -Filter ([string]$boundFilter)
        }
    }
    Sync-WinToolLogPanel
}

function Set-WinToolActivityFilter {
    param([string]$Filter = "all")
    Initialize-WinToolActivityState
    $script:WinToolState.ActivityFilter = $Filter
    $script:WinToolState.ActivityDirty = $true
    Update-WinToolActivityList
}

function Sync-WinToolStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Summary
    )
    $status = Get-WinToolUi -Name "StatusText"
    if ($null -ne $status) {
        $status.Text = $Text
    }
    $summaryBox = Get-WinToolUi -Name "StatusSummary"
    if ($null -ne $summaryBox -and $PSBoundParameters.ContainsKey("Summary")) {
        if ([string]::IsNullOrWhiteSpace($Summary)) {
            $summaryBox.Text = ""
            $summaryBox.Visibility = "Collapsed"
        }
        else {
            $summaryBox.Text = ("- " + $Summary)
            $summaryBox.Visibility = "Visible"
        }
    }
    $dot = Get-WinToolUi -Name "StatusDot"
    if ($null -ne $dot) {
        $brush = "BrushOk"
        if ($script:WinToolState.Busy) { $brush = "BrushAccent" }
        elseif ($Text -match 'fail|error|cancel') { $brush = "BrushBad" }
        elseif ($Text -match 'warn') { $brush = "BrushWarn" }
        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $brush)
    }
}

function Sync-WinToolProgress {
    param(
        [int]$Value,
        [string]$Text,
        [string]$Summary,
        [bool]$Indeterminate = $false
    )
    $bar = Get-WinToolUi -Name "MainProgress"
    if ($null -ne $bar) {
        $bar.IsIndeterminate = $Indeterminate
        if (-not $Indeterminate) {
            $bar.Value = $Value
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Text) -or $PSBoundParameters.ContainsKey("Summary")) {
        if ([string]::IsNullOrWhiteSpace($Text)) {
            $Text = [string](Get-WinToolUi -Name "StatusText").Text
        }
        if ($PSBoundParameters.ContainsKey("Summary")) {
            Sync-WinToolStatus -Text $Text -Summary $Summary
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Text)) {
            Sync-WinToolStatus -Text $Text
        }
    }
}

function Sync-WinToolLogPanel {
    Initialize-WinToolActivityState
    $expanded = [bool]$script:WinToolState.ActivityExpanded
    if ([bool]$script:WinToolState.LogExpanded) {
        $expanded = $true
        $script:WinToolState.ActivityExpanded = $true
    }
    $busy = [bool]$script:WinToolState.Busy
    $panel = Get-WinToolUi -Name "ActivityPanel"
    $bar = Get-WinToolUi -Name "MainProgress"
    $toggle = Get-WinToolUi -Name "ToggleLogButton"
    $toggleText = Get-WinToolUi -Name "ActivityToggleText"
    if ($expanded) {
        $panel.Visibility = "Visible"
        $label = Get-WinToolText "activity.hide"
        if ($null -ne $toggleText) { $toggleText.Text = $label }
        $toggle.ToolTip = $label
        [System.Windows.Automation.AutomationProperties]::SetName($toggle, $label)
        Update-WinToolActivityList
    }
    else {
        $panel.Visibility = "Collapsed"
        $label = Get-WinToolText "activity.show"
        if ($null -ne $toggleText) { $toggleText.Text = $label }
        $toggle.ToolTip = $label
        [System.Windows.Automation.AutomationProperties]::SetName($toggle, $label)
    }
    Sync-WinToolActivityBadge
    $clearance = 16
    if ($expanded) { $clearance = 376 }
    $homeBottom = $clearance
    $listBottom = 0
    $pageBottom = 12
    if ($expanded) {
        $listBottom = 368
        $pageBottom = 376
    }
    $homeBody = Get-WinToolUi -Name "HomeBody"
    if ($null -ne $homeBody) {
        $homeBody.Margin = [System.Windows.Thickness]::new(20, 0, 10, $homeBottom)
    }
    foreach ($listName in @("AppCategories", "TweakCategories")) {
        $list = Get-WinToolUi -Name $listName
        if ($null -ne $list) {
            $list.Margin = [System.Windows.Thickness]::new(0, 0, 0, $listBottom)
        }
    }
    foreach ($pageName in @("DriversBody", "DriversToolsBody", "UpdatesBody", "FixesBody", "FeaturesBody", "ConfigBody")) {
        $page = Get-WinToolUi -Name $pageName
        if ($null -ne $page) {
            $page.Margin = [System.Windows.Thickness]::new(20, 15, 20, $pageBottom)
        }
    }
    foreach ($fillPair in @(
            , @("DriversSimpleScroll", "DriversBody")
            , @("DriversToolsScroll", "DriversToolsBody")
            , @("ViewUpdates", "UpdatesBody")
            , @("ViewFixes", "FixesBody")
            , @("ViewFeatures", "FeaturesBody")
            , @("ViewConfig", "ConfigBody")
            , @("TerminalSimpleScroll", "TerminalSimpleHost")
        )) {
        if ($null -ne (Get-WinToolUi -Name $fillPair[0])) {
            Sync-WinToolScrollFill -ScrollName $fillPair[0] -BodyName $fillPair[1]
        }
    }
    if ($null -ne $bar) {
        if ($busy) {
            $bar.Visibility = "Visible"
        }
        else {
            $bar.Visibility = "Hidden"
            $bar.IsIndeterminate = $false
        }
    }
    Sync-WinToolProgressShimmer -Busy $busy
    Update-WinToolToastPlacement
}

function Switch-WinToolLogPanel {
    Initialize-WinToolActivityState
    $surface = Get-WinToolText "activity.show"
    if ($script:WinToolState.ActivityExpanded) { $surface = Get-WinToolText "activity.hide" }
    Start-WinToolSurfaceTiming -Name $surface
    if ($script:WinToolState.ActivityExpanded) {
        $script:WinToolState.ActivityExpanded = $false
        $script:WinToolState.ActivityPinned = $false
        $script:WinToolState.LogExpanded = $false
        $script:WinToolState.LogPinned = $false
    }
    else {
        $script:WinToolState.ActivityExpanded = $true
        $script:WinToolState.ActivityPinned = $true
        $script:WinToolState.LogExpanded = $true
        $script:WinToolState.LogPinned = $true
        $script:WinToolState.ActivityBadge = 0
    }
    Sync-WinToolLogPanel
}

function Sync-WinToolActivityBadge {
    $hostBadge = Get-WinToolUi -Name "ActivityBadgeHost"
    $label = Get-WinToolUi -Name "ActivityBadgeText"
    if ($null -eq $hostBadge) { return }
    $count = [int]$script:WinToolState.ActivityBadge
    if ($count -le 0 -or [bool]$script:WinToolState.ActivityExpanded) {
        $hostBadge.Visibility = "Collapsed"
        return
    }
    $text = [string]$count
    if ($count -gt 9) { $text = "9+" }
    if ($null -ne $label) { $label.Text = $text }
    $hostBadge.Visibility = "Visible"
}

function Update-WinToolActivityList {
    $hostPanel = Get-WinToolUi -Name "ActivityHost"
    if ($null -eq $hostPanel) { return }
    if (-not [bool]$script:WinToolState.ActivityExpanded -and -not [bool]$script:WinToolState.LogExpanded) {
        return
    }
    $filter = [string]$script:WinToolState.ActivityFilter
    if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "all" }
    $hostPanel.Children.Clear()
    $runs = @(Get-WinToolActivityRun | Where-Object { Test-WinToolActivityRunVisible -Run $_ -Filter $filter })
    if ($runs.Count -eq 0) {
        $emptyKey = "activity.empty"
        if ($filter -ne "all") { $emptyKey = "activity.emptyFilter" }
        $empty = New-WinToolText -Text (Get-WinToolText $emptyKey) -Brush "BrushMuted"
        $empty.Margin = [System.Windows.Thickness]::new(8, 12, 8, 8)
        [void]$hostPanel.Children.Add($empty)
        $script:WinToolState.ActivityDirty = $false
        return
    }
    $index = 0
    foreach ($run in $runs) {
        [void]$hostPanel.Children.Add((New-WinToolActivityRunCard -Run $run -Filter $filter -Latest ($index -eq 0)))
        $index++
    }
    $script:WinToolState.ActivityDirty = $false
}

function New-WinToolActivityRunCard {
    param(
        $Run,
        [string]$Filter = "all",
        [bool]$Latest = $false
    )
    $card = New-WinToolCard
    $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $card.Padding = [System.Windows.Thickness]::new(12, 8, 12, 9)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(12)
    $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushSidebar")
    $root = New-Object System.Windows.Controls.StackPanel
    $top = New-Object System.Windows.Controls.DockPanel
    if ($Latest) {
        $latest = New-WinToolText -Text (Get-WinToolText "activity.latest") -Brush "BrushMuted"
        $latest.VerticalAlignment = "Top"
        [System.Windows.Controls.DockPanel]::SetDock($latest, "Right")
        [void]$top.Children.Add($latest)
    }
    $titleBlock = New-Object System.Windows.Controls.StackPanel
    $title = New-WinToolText -Text ([string]$Run.Title) -Weight "SemiBold"
    [void]$titleBlock.Children.Add($title)
    $when = Format-WinToolActivityWhen -Started $Run.Started
    $duration = Format-WinToolActivityDuration -Started $Run.Started -Ended $Run.Ended
    $metaText = $when
    if (-not [string]::IsNullOrWhiteSpace($duration)) {
        $metaText = Get-WinToolText "activity.meta" $when $duration
    }
    $meta = New-WinToolText -Text $metaText -Brush "BrushHint"
    $meta.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    [void]$titleBlock.Children.Add($meta)
    $counts = New-Object System.Windows.Controls.WrapPanel
    $counts.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
    $okKind = "ok"
    if ([int]$Run.Errors -gt 0) { $okKind = "caution" }
    [void]$counts.Children.Add((New-WinToolBadge -Text (Get-WinToolCountText "activity.count.completed" ([int]$Run.Completed)) -Kind $okKind))
    if ([int]$Run.Warnings -gt 0) {
        [void]$counts.Children.Add((New-WinToolBadge -Text (Get-WinToolCountText "activity.count.warning" ([int]$Run.Warnings)) -Kind "caution"))
    }
    $errorKind = "ok"
    if ([int]$Run.Errors -gt 0) { $errorKind = "caution" }
    [void]$counts.Children.Add((New-WinToolBadge -Text (Get-WinToolCountText "activity.count.error" ([int]$Run.Errors)) -Kind $errorKind))
    [void]$titleBlock.Children.Add($counts)
    [void]$top.Children.Add($titleBlock)
    [void]$root.Children.Add($top)
    foreach ($step in $Run.Steps) {
        if (-not (Test-WinToolActivityStepVisible -Step $step -Filter $Filter)) { continue }
        [void]$root.Children.Add((New-WinToolActivityStepRow -Step $step))
    }
    $card.Child = $root
    return $card
}

function New-WinToolActivityStepRow {
    param($Step)
    $row = New-Object System.Windows.Controls.DockPanel
    $row.Margin = [System.Windows.Thickness]::new(0, 3, 0, 0)
    $status = [string]$Step.Status
    $icon = New-Object System.Windows.Controls.Border
    $icon.Width = 18
    $icon.Height = 18
    $icon.CornerRadius = [System.Windows.CornerRadius]::new(9)
    $icon.Margin = [System.Windows.Thickness]::new(0, 1, 8, 0)
    $icon.VerticalAlignment = "Top"
    $mark = New-Object System.Windows.Controls.TextBlock
    $mark.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $mark.FontSize = 10
    $mark.HorizontalAlignment = "Center"
    $mark.VerticalAlignment = "Center"
    $bg = "BrushOkSoft"
    $fg = "BrushOk"
    $glyph = [char]0xE73E
    if ($status -eq "warn") {
        $bg = "BrushWarnSoft"; $fg = "BrushWarn"; $glyph = [char]0xE7BA
    }
    elseif ($status -eq "error") {
        $bg = "BrushBadSoft"; $fg = "BrushBad"; $glyph = [char]0xE711
    }
    elseif ($status -eq "skipped") {
        $bg = "BrushAccentSoft"; $fg = "BrushMuted"; $glyph = [char]0xE73C
    }
    elseif ($status -eq "running") {
        $bg = "BrushAccentSoft"; $fg = "BrushAccent"; $glyph = [char]0xE895
    }
    $icon.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $bg)
    $mark.Text = [string]$glyph
    $mark.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $fg)
    $icon.Child = $mark
    [System.Windows.Controls.DockPanel]::SetDock($icon, "Left")
    [void]$row.Children.Add($icon)
    $message = [string]$Step.Message
    if (-not [string]::IsNullOrWhiteSpace([string]$Step.Detail)) {
        $message = $message + "  " + [string]$Step.Detail
    }
    $text = New-WinToolText -Text $message -Wrap
    $text.VerticalAlignment = "Top"
    [void]$row.Children.Add($text)
    return $row
}

function Copy-WinToolActivityReport {
    $text = Format-WinToolActivityReport -Filter ([string]$script:WinToolState.ActivityFilter)
    try {
        [System.Windows.Clipboard]::SetText($text)
        Write-WinToolLog -Message (Get-WinToolText "activity.copied") -Level "ok"
    }
    catch {
        Write-WinToolLog -Message (Get-WinToolText "activity.copyFailed") -Level "warn"
    }
}

function Save-WinToolActivityReport {
    if ($script:WinToolUiQuiet) { return }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = Get-WinToolText "activity.saveTitle"
    $dialog.Filter = Get-WinToolText "activity.saveFilter"
    $dialog.FileName = "wintool-activity.txt"
    $dialog.AddExtension = $true
    $dialog.DefaultExt = ".txt"
    if ($dialog.ShowDialog() -ne $true) { return }
    try {
        [System.IO.File]::WriteAllText($dialog.FileName, (Format-WinToolActivityReport -Filter ([string]$script:WinToolState.ActivityFilter)), [System.Text.UTF8Encoding]::new($false))
        Write-WinToolLog -Message (Get-WinToolText "activity.saved") -Level "ok"
    }
    catch {
        Write-WinToolLog -Message (Get-WinToolText "activity.saveFailed") -Level "warn"
    }
}

function Show-WinToolToast {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Body = "",
        [string]$Kind = "ok"
    )
    $panel = Get-WinToolUi -Name "ToastPanel"
    if ($null -eq $panel) { return }
    (Get-WinToolUi -Name "ToastTitle").Text = $Title
    (Get-WinToolUi -Name "ToastBody").Text = $Body
    $accent = Get-WinToolUi -Name "ToastAccent"
    $iconBg = Get-WinToolUi -Name "ToastIcon"
    $iconMark = Get-WinToolUi -Name "ToastIconMark"
    $brush = "BrushOk"
    $soft = "BrushOkSoft"
    $glyph = [char]0xE73E
    if ($Kind -eq "warn") { $brush = "BrushWarn"; $soft = "BrushWarnSoft"; $glyph = [char]0xE7BA }
    elseif ($Kind -eq "error") { $brush = "BrushBad"; $soft = "BrushBadSoft"; $glyph = [char]0xE711 }
    if ($null -ne $accent) { $accent.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $brush) }
    if ($null -ne $iconBg) { $iconBg.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $soft) }
    if ($null -ne $iconMark) {
        $iconMark.Text = [string]$glyph
        $iconMark.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $brush)
    }
    $panel.Visibility = "Visible"
    Update-WinToolToastPlacement
    $timer = $script:WinToolState.ToastTimer
    if ($null -ne $timer) {
        try { $timer.Stop() } catch { $null = $_.Exception.Message }
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(5)
    Register-WinToolUiEvent -Control $timer -EventName "Tick" -Name "Hide toast" -Action { Hide-WinToolToast }
    $timer.Start()
    $script:WinToolState.ToastTimer = $timer
}

function Hide-WinToolToast {
    $timer = $script:WinToolState.ToastTimer
    if ($null -ne $timer) {
        try { $timer.Stop() } catch { $null = $_.Exception.Message }
        $script:WinToolState.ToastTimer = $null
    }
    $panel = Get-WinToolUi -Name "ToastPanel"
    if ($null -ne $panel) { $panel.Visibility = "Collapsed" }
}

function Update-WinToolToastPlacement {
    $panel = Get-WinToolUi -Name "ToastPanel"
    if ($null -eq $panel) { return }
    $bottom = 8
    if ([bool]$script:WinToolState.ActivityExpanded -or [bool]$script:WinToolState.LogExpanded) {
        $bottom = 376
    }
    $panel.Margin = [System.Windows.Thickness]::new(0, 0, 28, $bottom)
}

function Show-WinToolActivityToast {
    param($Run)
    if ($null -eq $Run) { return }
    $kind = [string]$Run.Status
    if ($kind -eq "ok" -or [string]::IsNullOrWhiteSpace($kind) -or $kind -eq "running") { $kind = "ok" }
    $body = [string]$Run.Summary
    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = Format-WinToolActivityCount -Run $Run
    }
    Show-WinToolToast -Title ([string]$Run.Title) -Body $body -Kind $kind
}
