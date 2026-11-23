# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolFeatureView {
    $hostPanel = Get-WinToolUi -Name "FeatureList"
    $hostPanel.Children.Clear()
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($feature in @(Get-WinToolNote -Object (Get-WinToolFeatureCatalog) -Name "features" -Default @())) {
        $panel = New-Object System.Windows.Controls.Grid
        $panel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $panel.ColumnDefinitions.Add((New-WinToolColumn))
        $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
        $checkbox = New-Object System.Windows.Controls.CheckBox
        $checkbox.VerticalAlignment = "Top"
        $checkbox.Margin = [System.Windows.Thickness]::new(0, 2, 10, 0)
        $checkbox.IsEnabled = $false
        [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
        [void]$panel.Children.Add($checkbox)
        $text = New-Object System.Windows.Controls.StackPanel
        [void]$text.Children.Add((New-WinToolText -Text ([string]$feature.name) -Weight "SemiBold"))
        [void]$text.Children.Add((New-WinToolText -Text ([string]$feature.description) -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 2, 16, 0))))
        [System.Windows.Controls.Grid]::SetColumn($text, 1)
        [void]$panel.Children.Add($text)
        $state = New-WinToolText -Text "Checking..." -Brush "BrushMuted"
        $state.VerticalAlignment = "Top"
        [System.Windows.Controls.Grid]::SetColumn($state, 2)
        [void]$panel.Children.Add($state)
        [void]$hostPanel.Children.Add($panel)
        $rows.Add([pscustomobject]@{
            Feature = $feature
            Checkbox = $checkbox
            StateText = $state
            Status = "Unknown"
        })
    }
    $script:WinToolState.FeatureRows = $rows.ToArray()
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "FeatureRefresh") -EventName "Click" -Name "Features: refresh state" -Action {
        Start-WinToolFeatureDetection
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "FeatureApply") -EventName "Click" -Name "Features: apply changes" -Action {
        Invoke-WinToolFeatureApplyClick
    }
}

function Start-WinToolFeatureDetection {
    if ($null -ne $script:WinToolState.FeatureJob) {
        return
    }
    if (-not (Test-WinToolWindows)) {
        return
    }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.FeatureRows)) {
        $row.StateText.Text = "Checking..."
        $row.Checkbox.IsEnabled = $false
        foreach ($name in @($row.Feature.names)) {
            $names.Add([string]$name)
        }
    }
    (Get-WinToolUi -Name "FeatureStatus").Text = "Reading the current state..."
    $script:WinToolState.FeatureJob = Start-WinToolScriptJob -ScriptText (Get-WinToolFeatureStateScript) -Argument @(, $names.ToArray())
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
    if (-not $ok) {
        (Get-WinToolUi -Name "FeatureStatus").Text = "Could not read the Windows features."
        Write-WinToolLog -Message ("Could not read the Windows features. {0}" -f $errorMessage) -Level "warn"
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
            "On" { $row.StateText.Text = "On"; $on++ }
            "Off" { $row.StateText.Text = "Off" }
            "Partial" { $row.StateText.Text = "Partly on" }
            default { $row.StateText.Text = "Not available on this PC" }
        }
        $row.Checkbox.IsEnabled = ($status -ne "Unavailable")
        $row.Checkbox.IsChecked = ($status -eq "On")
    }
    (Get-WinToolUi -Name "FeatureStatus").Text = ("{0} of these features are on. Tick or untick, then apply." -f $on)
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
    $change = Get-WinToolFeatureChange
    $total = @($change.Enable).Count + @($change.Disable).Count
    if ($total -eq 0) {
        Write-WinToolLog -Message "No Windows feature changes to apply." -Level "warn"
        return
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($feature in @($change.Enable)) { $lines.Add("Turn on: " + [string]$feature.name) }
    foreach ($feature in @($change.Disable)) { $lines.Add("Turn off: " + [string]$feature.name) }
    $ok = Request-WinToolConfirmation -Message ("Change these Windows features?`n`n" + ($lines -join "`n") + "`n`nWindows needs a restart to finish.") -Title "Windows features"
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolFeaturePlan -Enable $change.Enable -Disable $change.Disable)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "Windows features changed. Restart the PC to finish." -AfterDone "Start-WinToolFeatureDetection"
}
