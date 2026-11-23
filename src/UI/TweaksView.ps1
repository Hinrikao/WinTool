# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolTweakView {
    $catalog = Get-WinToolTweakCatalog
    $presetPanel = Get-WinToolUi -Name "TweakPresets"
    $presetPanel.Children.Clear()
    foreach ($preset in @(Get-WinToolNote -Object $catalog -Name "presets" -Default @())) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = [string]$preset.name
        $button.Style = $script:WinToolWindow.FindResource("ChipButton")
        $button.ToolTip = [string](Get-WinToolNote -Object $preset -Name "description" -Default "")
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name "Tweaks: preset" -Data $preset -Action {
            param($source, $eventData, $boundPreset)
            $null = $source, $eventData
            Select-WinToolPreset -Preset $boundPreset
        }
        Add-WinToolBusyControl -Control $button
        [void]$presetPanel.Children.Add($button)
    }

    $hostPanel = Get-WinToolUi -Name "TweakCategories"
    foreach ($column in @($hostPanel.Children)) { $column.Children.Clear() }
    $hostPanel.Children.Clear()
    $hostPanel.ColumnDefinitions.Clear()
    $script:WinToolState.TweakRows = @()
    $script:WinToolState.TweakGroups = @()
    $script:WinToolState.TweakStateRead = $false
    $script:WinToolState.TweakQueue = $null
    $groups = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in @(Get-WinToolNote -Object $catalog -Name "tweaks" -Default @())) {
        $categoryName = [string](Get-WinToolNote -Object $tweak -Name "category" -Default "Other")
        if ([string]::IsNullOrWhiteSpace($categoryName)) {
            $categoryName = "Other"
        }
        if (-not $groups.ContainsKey($categoryName)) {
            $groups[$categoryName] = New-Object System.Collections.Generic.List[object]
            [void]$order.Add($categoryName)
        }
        [void]$groups[$categoryName].Add($tweak)
    }

    # ToArray() keeps this on object[], which Windows PowerShell 5.1 can enumerate.
    # @() around a generic list throws "Argument types do not match" on 5.1.
    foreach ($categoryName in $order.ToArray()) {
        $card = New-Object System.Windows.Controls.Border
        $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushCard")
        $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        $card.BorderThickness = [System.Windows.Thickness]::new(1)
        $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $card.Padding = [System.Windows.Thickness]::new(10, 0, 10, 12)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $stack = New-Object System.Windows.Controls.StackPanel
        $header = New-Object System.Windows.Controls.Grid
        $header.Height = 36
        $header.ColumnDefinitions.Add((New-WinToolColumn))
        $header.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $title = New-WinToolText -Text $categoryName -Size 12.5 -Weight "Bold"
        $title.VerticalAlignment = "Center"
        $title.Margin = [System.Windows.Thickness]::new(2, 0, 0, 0)
        [void]$header.Children.Add($title)
        $count = New-WinToolText -Text " " -Size 9.5 -Brush "BrushMuted"
        $count.VerticalAlignment = "Center"
        $count.Margin = [System.Windows.Thickness]::new(0, 0, 2, 0)
        [System.Windows.Controls.Grid]::SetColumn($count, 1)
        [void]$header.Children.Add($count)
        [void]$stack.Children.Add($header)
        $rows = @()
        foreach ($tweak in $groups[$categoryName].ToArray()) {
            $row = New-WinToolTweakRow -Tweak $tweak -CategoryName $categoryName
            [void]$stack.Children.Add($row.Panel)
            $rows += $row
            $script:WinToolState.TweakRows += $row
        }
        $card.Child = $stack
        $script:WinToolState.TweakGroups += [pscustomobject]@{
            Name = $categoryName
            Card = $card
            Count = $count
            Rows = $rows
        }
    }
    Update-WinToolTweakCount
    Update-WinToolTweakLayout -Width 992

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakSearch") -EventName "TextChanged" -Name "Tweaks: search" -Action {
        Sync-WinToolSearchHint -BoxName "TweakSearch" -HintName "TweakSearchHint"
        Update-WinToolTweakFilter
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ViewTweaks") -EventName "SizeChanged" -Name "Tweaks: layout" -Action {
        Update-WinToolTweakLayout -Width (Get-WinToolTweakWidth)
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakScroll") -EventName "SizeChanged" -Name "Tweaks: layout (list)" -Action {
        Update-WinToolTweakLayout -Width (Get-WinToolTweakWidth)
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "NavTweaks") -EventName "Checked" -Name "Tweaks: read current state" -Action {
        if (-not $script:WinToolState.TweakStateRead) {
            Update-WinToolTweakState
        }
    }
}

function New-WinToolTweakRow {
    param(
        $Tweak,
        [string]$CategoryName
    )
    # One 24 px line: a green (Safe) or amber (Caution) dot, the name, an
    # info mark with the details, and an on/off switch that changes Windows
    # right away.
    $panel = New-Object System.Windows.Controls.Border
    $panel.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0)
    $panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    $panel.Height = 24
    $panel.Background = [System.Windows.Media.Brushes]::Transparent
    $grid = New-Object System.Windows.Controls.Grid
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $grid.ColumnDefinitions.Add((New-WinToolColumn))
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))

    $risk = [string](Get-WinToolNote -Object $Tweak -Name "risk" -Default "safe")
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 6
    $dot.Height = 6
    $dot.VerticalAlignment = "Center"
    $dot.Margin = [System.Windows.Thickness]::new(3, 0, 7, 0)
    if ($risk -eq "caution") {
        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, "BrushWarn")
        $dot.ToolTip = "Caution: read the details before turning this on."
    }
    else {
        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, "BrushOk")
        $dot.ToolTip = "Safe"
    }
    [void]$grid.Children.Add($dot)

    $name = New-WinToolText -Text ([string]$Tweak.name) -Size 10.5
    $name.TextTrimming = "CharacterEllipsis"
    $name.VerticalAlignment = "Center"
    $name.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $name.ToolTip = [string]$Tweak.name
    [System.Windows.Controls.Grid]::SetColumn($name, 1)
    [void]$grid.Children.Add($name)

    $info = New-Object System.Windows.Controls.TextBlock
    $info.Text = [string][char]0xE946
    $info.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $info.FontSize = 10
    $info.VerticalAlignment = "Center"
    $info.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $info.Cursor = [System.Windows.Input.Cursors]::Help
    $info.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushHint")
    $info.ToolTip = [string]$Tweak.description
    [System.Windows.Controls.ToolTipService]::SetInitialShowDelay($info, 150)
    [System.Windows.Controls.Grid]::SetColumn($info, 2)
    [void]$grid.Children.Add($info)

    $toggle = New-Object System.Windows.Controls.CheckBox
    $toggle.Style = $script:WinToolWindow.FindResource("SwitchToggleSmall")
    $toggle.VerticalAlignment = "Center"
    $toggle.Margin = [System.Windows.Thickness]::new(0, 0, 2, 0)
    $toggle.IsChecked = $false
    $toggle.ToolTip = "Off"
    [System.Windows.Automation.AutomationProperties]::SetName($toggle, [string]$Tweak.name)
    [System.Windows.Controls.Grid]::SetColumn($toggle, 3)
    [void]$grid.Children.Add($toggle)
    $panel.Child = $grid

    $search = (@([string]$Tweak.name, [string]$Tweak.description, [string]$Tweak.id, $CategoryName) -join " ")
    $row = [pscustomobject]@{
        Id = [string]$Tweak.id
        SearchText = $search
        Panel = $panel
        Checkbox = $toggle
        Tweak = $Tweak
        State = "unknown"
    }
    Register-WinToolUiEvent -Control $toggle -EventName "Click" -Name "Tweaks: switch" -Data $row -Action {
        param($source, $eventData, $boundRow)
        $null = $source, $eventData
        Invoke-WinToolTweakToggle -Row $boundRow
    }
    Add-WinToolBusyControl -Control $toggle
    return $row
}

function Get-WinToolTweakWidth {
    $scroll = Get-WinToolUi -Name "TweakScroll"
    if ($null -ne $scroll -and $scroll.ViewportWidth -gt 0) {
        return [double]$scroll.ViewportWidth
    }
    return ((Get-WinToolUi -Name "ViewTweaks").ActualWidth - 40)
}

function Update-WinToolTweakLayout {
    param(
        [double]$Width
    )
    # Masonry: as many columns as fit at 300 px (3 at 1280, more when wider),
    # each card goes into the shortest column so no column runs far longer.
    if ($Width -le 0) {
        return
    }
    $columns = Get-WinToolColumnCount -Width $Width -MinWidth 300 -Gap 12
    $script:WinToolState.TweakWidth = $Width
    $script:WinToolState.TweakColumns = $columns
    $script:WinToolState.TweakTwoColumns = ($columns -gt 1)
    $grid = Get-WinToolUi -Name "TweakCategories"
    foreach ($column in @($grid.Children)) { $column.Children.Clear() }
    $grid.Children.Clear()
    $grid.ColumnDefinitions.Clear()
    $panels = New-Object System.Collections.Generic.List[object]
    $heights = New-Object System.Collections.Generic.List[double]
    for ($index = 0; $index -lt $columns; $index++) {
        if ($index -gt 0) {
            $gap = New-Object System.Windows.Controls.ColumnDefinition
            $gap.Width = [System.Windows.GridLength]::new(12)
            $grid.ColumnDefinitions.Add($gap)
        }
        $grid.ColumnDefinitions.Add((New-WinToolColumn))
        $panel = New-Object System.Windows.Controls.StackPanel
        [System.Windows.Controls.Grid]::SetColumn($panel, $grid.ColumnDefinitions.Count - 1)
        [void]$grid.Children.Add($panel)
        $panels.Add($panel)
        $heights.Add(0)
    }
    foreach ($group in @($script:WinToolState.TweakGroups)) {
        if ($group.Card.Visibility -ne "Visible") { continue }
        $shortest = 0
        for ($index = 1; $index -lt $heights.Count; $index++) {
            if ($heights[$index] -lt $heights[$shortest]) { $shortest = $index }
        }
        [void]$panels[$shortest].Children.Add($group.Card)
        $rows = @($group.Rows | Where-Object { $_.Panel.Visibility -eq "Visible" }).Count
        $heights[$shortest] = $heights[$shortest] + 36 + 24 * $rows + 12 + 12
    }
}

function Get-WinToolTweakCardColumn {
    param($Group)
    # Which masonry column (0, 1, 2...) holds a category card.
    $parent = $Group.Card.Parent
    if ($null -eq $parent) { return -1 }
    return [int]([System.Windows.Controls.Grid]::GetColumn($parent) / 2)
}

function Update-WinToolTweakCount {
    foreach ($group in @($script:WinToolState.TweakGroups)) {
        $on = @($group.Rows | Where-Object { $_.Checkbox.IsChecked -eq $true }).Count
        $group.Count.Text = ("{0} of {1} on" -f $on, @($group.Rows).Count)
    }
}

function Sync-WinToolTweakToggleTip {
    param($Row)
    if ($Row.State -eq "unknown") {
        $Row.Checkbox.ToolTip = "WinTool cannot read this setting, so it shows as off. Turning it on applies it."
        $Row.Checkbox.Opacity = 0.6
    }
    elseif ($Row.Checkbox.IsChecked -eq $true) {
        $Row.Checkbox.ToolTip = "On. Turn off to undo."
        $Row.Checkbox.Opacity = 1
    }
    else {
        $Row.Checkbox.ToolTip = "Off. Turn on to apply."
        $Row.Checkbox.Opacity = 1
    }
}

function Update-WinToolTweakState {
    # Reads every tweak's current state from Windows and sets the switches.
    $script:WinToolState.TweakStateRead = $true
    $probe = Get-WinToolTweakProbe
    $unknown = 0
    foreach ($row in @($script:WinToolState.TweakRows)) {
        $state = "unknown"
        if (Test-WinToolWindows) {
            $state = Get-WinToolTweakState -Tweak $row.Tweak -Probe $probe
        }
        if ($state -eq "unknown") { $unknown++ }
        Set-WinToolTweakToggleState -Row $row -State $state
        Sync-WinToolTweakToggleTip -Row $row
    }
    Update-WinToolTweakCount
    Write-WinToolLog -Message ("Tweaks: read the current state of {0} tweaks ({1} could not be read)." -f @($script:WinToolState.TweakRows).Count, $unknown) -Level "info" -Diagnostic
}

function Invoke-WinToolTweakToggle {
    param(
        [Parameter(Mandatory = $true)]$Row
    )
    $wantOn = ($Row.Checkbox.IsChecked -eq $true)
    if ($script:WinToolState.Busy -or $null -ne $script:WinToolState.TweakQueue) {
        $Row.Checkbox.IsChecked = (-not $wantOn)
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    $direction = "Apply"
    if (-not $wantOn) {
        $direction = "Undo"
        if ($null -eq (Get-WinToolNote -Object $Row.Tweak -Name "undo")) {
            $Row.Checkbox.IsChecked = $true
            Write-WinToolLog -Message ("{0} has no undo." -f [string]$Row.Tweak.name) -Level "warn"
            return
        }
    }
    Start-WinToolTweakQueue -Item @([pscustomobject]@{ Row = $Row; Direction = $direction; Previous = (-not $wantOn) })
}

function Start-WinToolTweakQueue {
    # Switches stay disabled while they run. The first change of the session
    # waits for a restore point.
    param(
        [object[]]$Item
    )
    $items = @($Item)
    if ($items.Count -eq 0) {
        return
    }
    foreach ($entry in $items) {
        $entry.Row.Checkbox.IsEnabled = $false
    }
    $script:WinToolState.TweakQueue = $items
    if ($script:WinToolState.RestorePointDone) {
        Complete-WinToolTweakQueue
        return
    }
    Sync-WinToolBusyState -Busy $true
    foreach ($entry in $items) {
        $entry.Row.Checkbox.IsEnabled = $false
    }
    Sync-WinToolProgress -Value 0 -Text "Creating a restore point" -Indeterminate $true
    Write-WinToolLog -Message "Creating a restore point before the first change. This can take a minute." -Level "info"
    $script:WinToolState.RestoreJob = Start-WinToolRestorePointJob -Description "WinTool before tweaks"
}

function Complete-WinToolRestorePoint {
    param(
        [bool]$Ok,
        [string]$ErrorMessage
    )
    if (-not $Ok) {
        $continue = Request-WinToolConfirmation -Message ("A restore point was not created.`n`n{0}`n`nContinue anyway?" -f $ErrorMessage) -Title "Restore point"
        if (-not $continue) {
            foreach ($entry in @($script:WinToolState.TweakQueue)) {
                $entry.Row.Checkbox.IsChecked = [bool]$entry.Previous
            }
            $script:WinToolState.TweakQueue = $null
            Sync-WinToolBusyState -Busy $false
            Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
            Update-WinToolTweakCount
            Write-WinToolLog -Message "Tweaks were not changed." -Level "warn"
            return
        }
        Write-WinToolLog -Message "Continuing without a restore point." -Level "warn"
    }
    else {
        Write-WinToolLog -Message "Restore point created." -Level "ok"
    }
    $script:WinToolState.RestorePointDone = $true
    Sync-WinToolBusyState -Busy $false
    Complete-WinToolTweakQueue
}

function Complete-WinToolTweakQueue {
    $items = @($script:WinToolState.TweakQueue)
    $script:WinToolState.TweakQueue = $null
    if ($items.Count -eq 0) {
        return
    }
    $needsExplorer = $false
    try {
        # Tests can swap in their own runner and probe.
        $probe = $script:WinToolTweakProbeOverride
        if ($null -eq $probe) { $probe = Get-WinToolTweakProbe }
        $needsExplorer = Invoke-WinToolTweakItem -Item $items -Probe $probe -Runner $script:WinToolTweakRunnerOverride
        if ($needsExplorer -and ((Get-WinToolUi -Name "TweakRestartExplorer").IsChecked -eq $true)) {
            Restart-WinToolExplorer
        }
        Sync-WinToolProgress -Value 100 -Text "Ready" -Indeterminate $false
    }
    catch {
        Write-WinToolLog -Message ("Tweaks failed. {0}" -f $_.Exception.Message) -Level "error"
        Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
    }
    foreach ($entry in $items) {
        $entry.Row.Checkbox.IsEnabled = $true
        Sync-WinToolTweakToggleTip -Row $entry.Row
    }
    Update-WinToolTweakCount
}

function Get-WinToolCheckedTweak {
    # The tweaks that are on now; a saved profile keeps these.
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($script:WinToolState.TweakRows)) {
        if ($row.Checkbox.IsChecked -eq $true) {
            $selected.Add($row.Tweak)
        }
    }
    return $selected.ToArray()
}

function Request-WinToolTweakOn {
    # Turns on the given tweaks that are off, after one confirmation.
    param(
        [string[]]$Id,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $wanted = @{}
    foreach ($item in @($Id)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) { $wanted[$item] = $true }
    }
    $rows = @($script:WinToolState.TweakRows | Where-Object { $wanted.ContainsKey([string]$_.Id) -and $_.Checkbox.IsChecked -ne $true })
    if ($rows.Count -eq 0) {
        Write-WinToolLog -Message ("Every tweak in {0} is already on." -f $Label) -Level "info"
        return
    }
    if ($script:WinToolState.Busy -or $null -ne $script:WinToolState.TweakQueue) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    $names = @($rows | Select-Object -First 10 | ForEach-Object { "- " + [string]$_.Tweak.name }) -join "`n"
    if ($rows.Count -gt 10) { $names += "`n- ..." }
    $ok = Request-WinToolConfirmation -Message ("Turn on {0} tweak(s) from {1}?`n`n{2}`n`nWinTool creates a restore point before the first change." -f $rows.Count, $Label, $names) -Title "Tweaks"
    if (-not $ok) {
        return
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $row.Checkbox.IsChecked = $true
        $items.Add([pscustomobject]@{ Row = $row; Direction = "Apply"; Previous = $false })
    }
    Write-WinToolLog -Message ("Turning on {0} tweak(s) from {1}." -f $rows.Count, $Label) -Level "info"
    Start-WinToolTweakQueue -Item $items.ToArray()
}

function Sync-WinToolTweakCheck {
    # Used when a profile is loaded: offers to turn its tweaks on.
    param(
        [string[]]$Id,
        [switch]$OnlyThese
    )
    $null = $OnlyThese
    if (@($Id).Count -eq 0) {
        return
    }
    Request-WinToolTweakOn -Id $Id -Label "the profile"
}

function Select-WinToolPreset {
    param($Preset)
    $catalog = Get-WinToolTweakCatalog
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in @(Get-WinToolPresetTweak -Catalog $catalog -PresetId ([string]$Preset.id))) {
        $ids.Add([string]$tweak.id)
    }
    Request-WinToolTweakOn -Id $ids.ToArray() -Label ("the " + [string]$Preset.name + " preset")
}

function Update-WinToolTweakFilter {
    $query = [string](Get-WinToolUi -Name "TweakSearch").Text
    $any = $false
    foreach ($group in @($script:WinToolState.TweakGroups)) {
        $visible = 0
        foreach ($row in @($group.Rows)) {
            if (Test-WinToolTextMatch -Haystack $row.SearchText -Query $query) {
                $row.Panel.Visibility = "Visible"
                $visible++
                $any = $true
            }
            else {
                $row.Panel.Visibility = "Collapsed"
            }
        }
        if ($visible -eq 0) {
            $group.Card.Visibility = "Collapsed"
        }
        else {
            $group.Card.Visibility = "Visible"
        }
    }
    $width = [double]$script:WinToolState.TweakWidth
    if ($width -le 0) { $width = Get-WinToolTweakWidth }
    if ($width -le 0) { $width = 992 }
    Update-WinToolTweakLayout -Width $width
    $empty = Get-WinToolUi -Name "TweakEmpty"
    if ($any) {
        $empty.Visibility = "Collapsed"
    }
    else {
        $empty.Visibility = "Visible"
    }
}
