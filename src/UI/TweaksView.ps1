# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolTweakView {
    $catalog = Get-WinToolTweakCatalog
    $presetPanel = Get-WinToolUi -Name "TweakPresets"
    $presetPanel.Children.Clear()
    foreach ($preset in @(Get-WinToolNote -Object $catalog -Name "presets" -Default @())) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = [string]$preset.name
        $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $button.ToolTip = [string](Get-WinToolNote -Object $preset -Name "description" -Default "")
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name "Tweaks: preset" -Data $preset -Action {
            param($source, $eventData, $boundPreset)
            $null = $source, $eventData
            Select-WinToolPreset -Preset $boundPreset
        }
        [void]$presetPanel.Children.Add($button)
    }

    $hostPanel = Get-WinToolUi -Name "TweakCategories"
    $hostPanel.Children.Clear()
    $script:WinToolState.TweakRows = @()
    $script:WinToolState.TweakGroups = @()
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
        $card = New-WinToolCard
        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add((New-WinToolText -Text $categoryName -Size 18 -Weight "SemiBold" -Margin ([System.Windows.Thickness]::new(0, 0, 0, 10))))
        $rows = @()
        $tweaksInCategory = $groups[$categoryName].ToArray()
        foreach ($tweak in $tweaksInCategory) {
            $row = New-WinToolTweakRow -Tweak $tweak -CategoryName $categoryName
            [void]$stack.Children.Add($row.Panel)
            $rows += $row
            $script:WinToolState.TweakRows += $row
        }
        $card.Child = $stack
        [void]$hostPanel.Children.Add($card)
        $script:WinToolState.TweakGroups += [pscustomobject]@{
            Name = $categoryName
            Card = $card
            Rows = $rows
        }
    }

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakSearch") -EventName "TextChanged" -Name "Tweaks: search" -Action {
        Sync-WinToolSearchHint -BoxName "TweakSearch" -HintName "TweakSearchHint"
        Update-WinToolTweakFilter
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakClear") -EventName "Click" -Name "Tweaks: clear" -Action {
        Sync-WinToolTweakCheck -Id @() -OnlyThese
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakApply") -EventName "Click" -Name "Tweaks: apply selected" -Action {
        Invoke-WinToolTweakClick -Direction "Apply"
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TweakUndo") -EventName "Click" -Name "Tweaks: undo selected" -Action {
        Invoke-WinToolTweakClick -Direction "Undo"
    }
}

function New-WinToolTweakRow {
    param(
        $Tweak,
        [string]$CategoryName
    )
    $panel = New-Object System.Windows.Controls.Grid
    $panel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $panel.ColumnDefinitions.Add((New-WinToolColumn))

    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.VerticalAlignment = "Top"
    $checkbox.Margin = [System.Windows.Thickness]::new(0, 3, 10, 0)
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
    [void]$panel.Children.Add($checkbox)

    $text = New-Object System.Windows.Controls.StackPanel
    $title = New-Object System.Windows.Controls.StackPanel
    $title.Orientation = "Horizontal"
    [void]$title.Children.Add((New-WinToolText -Text ([string]$Tweak.name) -Weight "SemiBold"))
    $risk = [string](Get-WinToolNote -Object $Tweak -Name "risk" -Default "safe")
    $badgeText = "Safe"
    if ($risk -eq "caution") {
        $badgeText = "Caution"
    }
    [void]$title.Children.Add((New-WinToolBadge -Text $badgeText -Kind $risk))
    [void]$text.Children.Add($title)
    [void]$text.Children.Add((New-WinToolText -Text ([string]$Tweak.description) -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 4, 0, 0))))
    [System.Windows.Controls.Grid]::SetColumn($text, 1)
    [void]$panel.Children.Add($text)

    $search = (@([string]$Tweak.name, [string]$Tweak.description, [string]$Tweak.id, $CategoryName) -join " ")
    return [pscustomobject]@{
        Id = [string]$Tweak.id
        SearchText = $search
        Panel = $panel
        Checkbox = $checkbox
        Tweak = $Tweak
    }
}

function Get-WinToolCheckedTweak {
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($script:WinToolState.TweakRows)) {
        if ($row.Checkbox.IsChecked -eq $true) {
            $selected.Add($row.Tweak)
        }
    }
    return $selected.ToArray()
}

function Sync-WinToolTweakCheck {
    param(
        [string[]]$Id,
        [switch]$OnlyThese
    )
    $wanted = @{}
    foreach ($item in @($Id)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $wanted[$item] = $true
        }
    }
    foreach ($row in @($script:WinToolState.TweakRows)) {
        $shouldCheck = $wanted.ContainsKey([string]$row.Id)
        if ($OnlyThese -or $shouldCheck) {
            $row.Checkbox.IsChecked = $shouldCheck
        }
    }
}

function Select-WinToolPreset {
    param($Preset)
    $catalog = Get-WinToolTweakCatalog
    $matched = @(Get-WinToolPresetTweak -Catalog $catalog -PresetId ([string]$Preset.id))
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in $matched) {
        $ids.Add([string]$tweak.id)
    }
    Sync-WinToolTweakCheck -Id $ids.ToArray() -OnlyThese
    Write-WinToolLog -Message ("Selected the {0} preset ({1} tweaks)." -f [string]$Preset.name, $ids.Count) -Level "info"
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
    $empty = Get-WinToolUi -Name "TweakEmpty"
    if ($any) {
        $empty.Visibility = "Collapsed"
    }
    else {
        $empty.Visibility = "Visible"
    }
}

function Invoke-WinToolTweakClick {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Apply", "Undo")][string]$Direction
    )
    $tweaks = @(Get-WinToolCheckedTweak)
    if ($tweaks.Count -eq 0) {
        Write-WinToolLog -Message "Select at least one tweak first." -Level "warn"
        return
    }
    $verb = "Apply"
    if ($Direction -eq "Undo") {
        $verb = "Undo"
    }
    $ok = Request-WinToolConfirmation -Message ("{0} {1} tweak(s)? WinTool will create a restore point first." -f $verb, $tweaks.Count) -Title "Tweaks"
    if (-not $ok) {
        return
    }
    $script:WinToolState.PendingTweaks = $tweaks
    $script:WinToolState.PendingDirection = $Direction
    $script:WinToolState.PendingRestart = ((Get-WinToolUi -Name "TweakRestartExplorer").IsChecked -eq $true)
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Creating a restore point" -Indeterminate $true
    Write-WinToolLog -Message "Creating a restore point. This can take a minute." -Level "info"
    $description = "WinTool before tweaks"
    if ($Direction -eq "Undo") {
        $description = "WinTool before undo"
    }
    $script:WinToolState.RestoreJob = Start-WinToolRestorePointJob -Description $description
}

function Complete-WinToolRestorePoint {
    param(
        [bool]$Ok,
        [string]$ErrorMessage
    )
    if (-not $Ok) {
        $continue = Request-WinToolConfirmation -Message ("A restore point was not created.`n`n{0}`n`nContinue anyway?" -f $ErrorMessage) -Title "Restore point"
        if (-not $continue) {
            Sync-WinToolBusyState -Busy $false
            Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
            Write-WinToolLog -Message "Tweaks were not changed." -Level "warn"
            return
        }
        Write-WinToolLog -Message "Continuing without a restore point." -Level "warn"
    }
    else {
        Write-WinToolLog -Message "Restore point created." -Level "ok"
    }
    try {
        Invoke-WinToolTweakChange -Tweak $script:WinToolState.PendingTweaks -Direction $script:WinToolState.PendingDirection -RestartExplorer ([bool]$script:WinToolState.PendingRestart)
        Write-WinToolLog -Message "Tweaks finished." -Level "ok"
        Sync-WinToolProgress -Value 100 -Text "Tweaks finished" -Indeterminate $false
    }
    catch {
        Write-WinToolLog -Message ("Tweaks failed. {0}" -f $_.Exception.Message) -Level "error"
        Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
    }
    Sync-WinToolBusyState -Busy $false
}
