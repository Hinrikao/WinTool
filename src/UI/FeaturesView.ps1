# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolFeatureView {
    $hostPanel = Get-WinToolUi -Name "FeatureList"
    $hostPanel.Children.Clear()
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($feature in @(Get-WinToolNote -Object (Get-WinToolFeatureCatalog) -Name "features" -Default @())) {
        $panel = New-Object System.Windows.Controls.Grid
        $panel.Height = 72
        $panel.Margin = [System.Windows.Thickness]::new(10, 0, 10, 0)
        $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $panel.ColumnDefinitions.Add((New-WinToolColumn))
        $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.VerticalAlignment = "Center"
        $checkbox.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
        $checkbox.IsEnabled = $false
        [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
        [void]$panel.Children.Add($checkbox)
        $text = New-Object System.Windows.Controls.StackPanel
        $text.VerticalAlignment = "Center"
        $name = New-WinToolText -Text ([string]$feature.name) -Weight "SemiBold"
        $name.TextTrimming = "CharacterEllipsis"
        [void]$text.Children.Add($name)
        $about = New-WinToolText -Text ([string]$feature.description) -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 2, 12, 0))
        $about.TextTrimming = "CharacterEllipsis"
        [void]$text.Children.Add($about)
        [System.Windows.Controls.Grid]::SetColumn($text, 1)
        [void]$panel.Children.Add($text)
        $pill = New-Object System.Windows.Controls.Border
        $pill.Width = 176
        $pill.Height = 28
        $pill.CornerRadius = [System.Windows.CornerRadius]::new(14)
        $pill.VerticalAlignment = "Center"
        $pill.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushNavHover")
        $state = New-WinToolText -Text "Checking..." -Brush "BrushMuted"
        $state.Width = 160
        $state.TextAlignment = "Center"
        $state.HorizontalAlignment = "Center"
        $state.VerticalAlignment = "Center"
        $state.TextTrimming = "CharacterEllipsis"
        $pill.Child = $state
        [System.Windows.Controls.Grid]::SetColumn($pill, 2)
        [void]$panel.Children.Add($pill)
        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Height = 72
        $rowBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $rowBorder.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        $rowBorder.Child = $panel
        [void]$hostPanel.Children.Add($rowBorder)
        $rows.Add([pscustomobject]@{
            Feature = $feature
            Checkbox = $checkbox
            StateText = $state
            Pill = $pill
            Status = "Unknown"
        })
    }
    $script:WinToolState.FeatureRows = $rows.ToArray()
    Add-WinToolAdminBadgeNear -Name "FeatureApply" -Place "Before" | Out-Null
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "FeatureRefresh") -EventName "Click" -Name "Features: refresh state" -Action {
        Start-WinToolFeatureDetection
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "FeatureApply") -EventName "Click" -Name "Features: apply changes" -Action {
        Invoke-WinToolFeatureApplyClick
    }
}

$script:WinToolFeatureTimeoutSeconds = 120

function Start-WinToolFeatureDetection {
    if ($null -ne $script:WinToolState.FeatureJob -or $script:WinToolState.Busy) {
        return
    }
    if (-not (Test-WinToolWindows)) {
        return
    }
    (Get-WinToolUi -Name "FeatureRefresh").IsEnabled = $false
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.FeatureRows)) {
        $row.StateText.Text = (Get-WinToolText "msg.checking-ellipsis")
        $row.Checkbox.IsEnabled = $false
        foreach ($name in @($row.Feature.names)) {
            $names.Add([string]$name)
        }
    }
    (Get-WinToolUi -Name "FeatureStatus").Text = (Get-WinToolText "msg.reading-the-current-state")
    $job = Start-WinToolScriptJob -ScriptText (Get-WinToolFeatureStateScript) -Argument @(, $names.ToArray())
    $job | Add-Member -NotePropertyName Started -NotePropertyValue ([DateTime]::UtcNow)
    $script:WinToolState.FeatureJob = $job
}

function Test-WinToolFeatureDetectionTimeout {
    $job = $script:WinToolState.FeatureJob
    if ($null -eq $job -or $job.Sync.Done) {
        return
    }
    if (([DateTime]::UtcNow - $job.Started).TotalSeconds -lt $script:WinToolFeatureTimeoutSeconds) {
        return
    }
    Stop-WinToolThread -Job $job
    $script:WinToolState.FeatureJob = $null
    (Get-WinToolUi -Name "FeatureRefresh").IsEnabled = (-not $script:WinToolState.Busy)
    (Get-WinToolUi -Name "FeatureStatus").Text = (Get-WinToolText "msg.reading-windows-features-took-too-long-press-refresh-to-")
    Write-WinToolLog -Message (Get-WinToolText "msg.windows-features-check-timed-out-press-refresh-to-try-ag") -Level "warn"
}

function Complete-WinToolFeatureDetection {
    $job = $script:WinToolState.FeatureJob
    if ($null -eq $job) {
        return
    }
    $ok = [bool]$job.Sync.Ok
    $errorMessage = [string]$job.Sync.Error
    $states = $job.Sync.States
    Stop-WinToolThread -Job $job
    $script:WinToolState.FeatureJob = $null
    (Get-WinToolUi -Name "FeatureRefresh").IsEnabled = (-not $script:WinToolState.Busy)
    if (-not $ok) {
        (Get-WinToolUi -Name "FeatureStatus").Text = (Get-WinToolText "msg.could-not-read-the-windows-features")
        Write-WinToolLog -Message ((Get-WinToolText "msg.could-not-read-the-windows-features-n") -f $errorMessage) -Level "warn"
        return
    }
    Set-WinToolFeatureState -State $states
}

function Set-WinToolFeatureState {
    param([hashtable]$State)
    $on = 0
    foreach ($row in @($script:WinToolState.FeatureRows)) {
        $status = Get-WinToolFeatureStatus -Feature $row.Feature -State $State
        $row.Status = $status
        switch ($status) {
            "On" { $row.StateText.Text = (Get-WinToolText "msg.on"); $on++ }
            "Off" { $row.StateText.Text = (Get-WinToolText "msg.off") }
            "Partial" { $row.StateText.Text = (Get-WinToolText "msg.partly-on") }
            default { $row.StateText.Text = (Get-WinToolText "msg.not-available-on-this-pc") }
        }
        $row.Checkbox.IsEnabled = ($status -ne "Unavailable")
        $row.Checkbox.IsChecked = ($status -eq "On")
        if ($null -ne $row.Pill) {
            $tone = switch ($status) {
                "On" { @("BrushOkSoft", "BrushOk") }
                "Partial" { @("BrushWarnSoft", "BrushWarn") }
                default { @("BrushNavHover", "BrushMuted") }
            }
            $row.Pill.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $tone[0])
            $row.StateText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $tone[1])
        }
    }
    (Get-WinToolUi -Name "FeatureStatus").Text = (Get-WinToolCountText "msg.n-of-these-features-are-on-tick-or-untick-then-apply" $on)
}

function Get-WinToolFeatureChange {
    $enable = New-Object System.Collections.Generic.List[object]
    $disable = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($script:WinToolState.FeatureRows)) {
        if ($row.Status -eq "Unavailable" -or $row.Status -eq "Unknown") {
            continue
        }
        $wanted = ($row.Checkbox.IsChecked -eq $true)
        if ($wanted -and $row.Status -ne "On") {
            $enable.Add($row.Feature)
        }
        elseif (-not $wanted -and $row.Status -ne "Off") {
            $disable.Add($row.Feature)
        }
    }
    return [pscustomobject]@{
        Enable = $enable.ToArray()
        Disable = $disable.ToArray()
    }
}

function Invoke-WinToolFeatureApplyClick {
    Start-WinToolSurfaceTiming -Name "Features apply"
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    $change = Get-WinToolFeatureChange
    $total = @($change.Enable).Count + @($change.Disable).Count
    if ($total -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "msg.no-windows-feature-changes-to-apply") -Level "warn"
        return
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($feature in @($change.Enable)) { $lines.Add("Turn on: " + [string]$feature.name) }
    foreach ($feature in @($change.Disable)) { $lines.Add("Turn off: " + [string]$feature.name) }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "msg.change-these-windows-features-n" ($lines -join "`n")) -Title (Get-WinToolText "msg.windows-features")
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolFeaturePlan -Enable $change.Enable -Disable $change.Disable)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "Windows features changed. Restart the PC to finish." -AfterDone "Start-WinToolFeatureDetection"
}
