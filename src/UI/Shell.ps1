# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Request-WinToolConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Title
    )
    # UI tests answer "no" without a modal dialog, so a click cannot hang the dispatcher.
    if ($script:WinToolUiQuiet) {
        return $false
    }
    $answer = [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    return ($answer -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-WinToolViewName {
    return @("Home", "Install", "Tweaks", "Terminal", "Drivers", "Updates", "Fixes", "Features", "Config")
}

function Add-WinToolBusyControl {
    param(
        [Parameter(Mandatory = $true)]$Control
    )
    if ($null -eq $script:WinToolState.BusyControls) {
        $script:WinToolState.BusyControls = New-Object System.Collections.Generic.List[object]
    }
    $script:WinToolState.BusyControls.Add($Control)
}

function Start-WinToolSlide {
    # Opacity and a horizontal render transform only. Nothing in the layout moves.
    param(
        $Element,
        [double]$FromX,
        [double]$ToX,
        [int]$Milliseconds
    )
    if ($null -eq $Element) { return }
    $shift = $Element.RenderTransform
    if ($shift -isnot [System.Windows.Media.TranslateTransform]) {
        $shift = New-Object System.Windows.Media.TranslateTransform
        $Element.RenderTransform = $shift
    }
    $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $Element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    if ((Test-WinToolHomeReduceMotion)) {
        $shift.X = $ToX
        $Element.Opacity = 1
        return
    }
    $shift.X = $FromX
    $Element.Opacity = 0
    $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($Milliseconds))
    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation($FromX, $ToX, $duration)
    $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 1, $duration)
    $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slide)
    $Element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
}

function Update-WinToolNavPill {
    param([bool]$Animate = $true)
    $list = Get-WinToolUi -Name "NavList"
    $shift = Get-WinToolUi -Name "NavPillShift"
    if ($null -eq $list -or $null -eq $shift) { return }
    $radio = $null
    foreach ($view in @(Get-WinToolViewName)) {
        $candidate = Get-WinToolUi -Name ("Nav" + $view)
        if ($null -ne $candidate -and $candidate.IsChecked -eq $true) {
            $radio = $candidate
            break
        }
    }
    if ($null -eq $radio -or $radio.ActualHeight -le 0) { return }
    $point = $radio.TranslatePoint([System.Windows.Point]::new(0, 0), $list)
    $target = $point.Y
    if (-not $Animate -or (Test-WinToolHomeReduceMotion)) {
        $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
        $shift.Y = $target
        return
    }
    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation($shift.Y, $target, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(180)))
    $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $slide)
}

function Sync-WinToolProgressShimmer {
    param([bool]$Busy)
    $shim = Get-WinToolUi -Name "ProgressShimmer"
    $shift = Get-WinToolUi -Name "ProgressShimmerShift"
    if ($null -eq $shim -or $null -eq $shift) { return }
    $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
    $shim.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
    if (-not $Busy -or (Test-WinToolHomeReduceMotion)) {
        $shim.Opacity = 0
        $shift.X = -80
        return
    }
    $shim.Opacity = 0.9
    $slide = New-Object System.Windows.Media.Animation.DoubleAnimation(-80, 720, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(1400)))
    $slide.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
    $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $slide)
}

function Complete-WinToolMotion {
    # Leaves every storyboard on its resting frame so a screenshot taken on
    # the same tick shows the settled screen, then real motion can start again.
    # Pages that stay measured (opacity 0) must not be faded back in, or every
    # tab would paint on top of the one the screenshot is of.
    $active = "Home"
    if ($null -ne $script:WinToolState -and -not [string]::IsNullOrWhiteSpace([string]$script:WinToolState.ActiveView)) {
        $active = [string]$script:WinToolState.ActiveView
    }
    $shown = @()
    if ($null -ne $script:WinToolState) { $shown = @($script:WinToolState.ViewShown) }
    foreach ($view in @(Get-WinToolViewName)) {
        $element = Get-WinToolUi -Name ("View" + $view)
        if ($null -eq $element) { continue }
        $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
        $shift = $element.RenderTransform
        if ($shift -is [System.Windows.Media.TranslateTransform]) {
            $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
            $shift.X = 0
        }
        if ($view -eq $active) {
            $element.Visibility = "Visible"
            $element.Opacity = 1
            $element.IsHitTestVisible = $true
            [System.Windows.Controls.Panel]::SetZIndex($element, 2)
        }
        elseif ($shown -contains $view) {
            $element.Visibility = "Visible"
            $element.Opacity = 0
            $element.IsHitTestVisible = $false
            [System.Windows.Controls.Panel]::SetZIndex($element, 0)
        }
        else {
            $element.Opacity = 0
            $element.IsHitTestVisible = $false
            $element.Visibility = "Collapsed"
        }
    }
    Update-WinToolNavPill -Animate $false
    $root = $script:WinToolWindow
    if ($null -eq $root) { return }
    $queue = New-Object System.Collections.Generic.Queue[object]
    if ($root.Content -is [System.Windows.Media.Visual]) { $queue.Enqueue($root.Content) }
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($node -is [System.Windows.UIElement]) {
            $motion = $node.RenderTransform
            if ($motion -is [System.Windows.Media.TranslateTransform] -and [string]$node.Name -ne "NavPill") {
                $motion.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
                $motion.Y = 0
            }
        }
        if ($node -is [System.Windows.Controls.CheckBox]) {
            $template = $node.Template
            if ($null -ne $template) {
                $fill = $template.FindName("Fill", $node)
                $mark = $template.FindName("Mark", $node)
                $dash = $template.FindName("Dash", $node)
                $knobShift = $template.FindName("KnobShift", $node)
                $knob = $template.FindName("Knob", $node)
                if ($null -ne $fill) {
                    $fill.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                    $fill.Opacity = 0
                }
                if ($null -ne $mark) {
                    $mark.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                    $mark.Opacity = 0
                }
                if ($null -ne $dash) {
                    $dash.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
                    $dash.Opacity = 0
                }
                if ($node.IsChecked -eq $true) {
                    if ($null -ne $fill) { $fill.Opacity = 1 }
                    if ($null -ne $mark) { $mark.Opacity = 1 }
                }
                elseif ($null -eq $node.IsChecked) {
                    if ($null -ne $fill) { $fill.Opacity = 1 }
                    if ($null -ne $dash) { $dash.Opacity = 1 }
                }
                if ($null -ne $knobShift) {
                    $travel = 20.0
                    if ($null -ne $knob -and $knob.Width -lt 13) { $travel = 15.0 }
                    $knobShift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
                    if ($node.IsChecked -eq $true) { $knobShift.X = $travel } else { $knobShift.X = 0 }
                }
            }
        }
        if ($node -isnot [System.Windows.Media.Visual]) { continue }
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
        for ($index = 0; $index -lt $count; $index++) {
            $queue.Enqueue([System.Windows.Media.VisualTreeHelper]::GetChild($node, $index))
        }
    }
}

function Stop-WinToolMotion {
    Complete-WinToolMotion
    Sync-WinToolProgressShimmer -Busy $false
    if ($null -eq $script:WinToolState -or $null -eq $script:WinToolState.Home) { return }
    $rows = $script:WinToolState.Home.Rows
    if ($null -eq $rows) { return }
    foreach ($row in @($rows.Values)) {
        try {
            $row.Spinner.RenderTransform.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
        }
        catch { $null = $_.Exception.Message }
    }
}

function Complete-WinToolNavTiming {
    # Runs after the render pass that paints the new page, so the number is
    # the time from the click to the first frame. The pill moves here, after
    # that frame: measuring it inside the click forced a full layout first.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$Stamp
    )
    if ($script:WinToolShuttingDown) { return }
    if ([int64]$script:WinToolState.NavStamp -ne [int64]$Stamp) { return }
    Update-WinToolNavPill -Animate $true
    if ($Name -eq "Config") {
        Update-WinToolProfileSummary
    }
    $elapsed = ([System.Diagnostics.Stopwatch]::GetTimestamp() - [int64]$Stamp) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
    $ms = [int][Math]::Round($elapsed)
    if ($ms -lt 0) { $ms = 0 }
    $script:WinToolState.NavMilliseconds = $ms
    Write-WinToolLog -Message ("Nav: {0} shown in {1}ms" -f $Name, $ms) -Level "info" -Diagnostic
    $safe = ($Name -replace "[^A-Za-z]", "")
    $follow = [scriptblock]::Create(("Complete-WinToolNavFollowUp -Name '{0}'" -f $safe))
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$follow)
}

function Start-WinToolSurfaceTiming {
    # Same clock as a sidebar switch: the click records a stamp, and the
    # Loaded pass (after the first frame) writes "Nav: {name} shown in Xms".
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($script:WinToolShuttingDown -or $null -eq $script:WinToolWindow -or $null -eq $script:WinToolState) { return }
    $stamp = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $script:WinToolState.NavStamp = [int64]$stamp
    $script:WinToolState.SurfaceName = $Name
    $callback = [scriptblock]::Create(("Complete-WinToolSurfaceTiming -Stamp {0}" -f [int64]$stamp))
    try {
        $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [System.Action]$callback)
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Complete-WinToolSurfaceTiming {
    param(
        [Parameter(Mandatory = $true)][long]$Stamp
    )
    if ($script:WinToolShuttingDown) { return }
    if ([int64]$script:WinToolState.NavStamp -ne [int64]$Stamp) { return }
    $elapsed = ([System.Diagnostics.Stopwatch]::GetTimestamp() - [int64]$Stamp) * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
    $ms = [int][Math]::Round($elapsed)
    if ($ms -lt 0) { $ms = 0 }
    $script:WinToolState.NavMilliseconds = $ms
    Write-WinToolLog -Message ("Nav: {0} shown in {1}ms" -f [string]$script:WinToolState.SurfaceName, $ms) -Level "info" -Diagnostic
}

function Sync-WinToolScrollFill {
    # A short page inside a scroll viewer otherwise leaves empty canvas under
    # it. MinHeight equal to the viewport lets star rows use that space, and
    # the top of every card stays where it is.
    param(
        [Parameter(Mandatory = $true)][string]$ScrollName,
        [Parameter(Mandatory = $true)][string]$BodyName
    )
    $scroll = Get-WinToolUi -Name $ScrollName
    $body = Get-WinToolUi -Name $BodyName
    if ($null -eq $scroll -or $null -eq $body) { return }
    $height = [double]$scroll.ViewportHeight
    if ($height -lt 1 -or [double]::IsNaN($height) -or [double]::IsInfinity($height)) { return }
    # Margin sits outside the element and inside the scroll content. Leave it
    # out of MinHeight so opening the log does not add a scrollbar.
    $margin = $body.Margin
    $target = $height - [double]$margin.Top - [double]$margin.Bottom
    if ($target -lt 1 -or [double]::IsNaN($target) -or [double]::IsInfinity($target)) { return }
    if ([Math]::Abs([double]$body.MinHeight - $target) -gt 0.5) {
        $body.MinHeight = $target
    }
}

function Complete-WinToolNavFollowUp {
    # Registry, DNS, and list scrolling stay off the click and off the first frame.
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($script:WinToolShuttingDown) { return }
    if ([string]$script:WinToolState.ActiveView -ne $Name) { return }
    if ($Name -eq "Tweaks" -or $Name -eq "Config") {
        Start-WinToolTweakStateRead
    }
    if ($Name -eq "Config") {
        Start-WinToolSystemProbe
    }
    if ($Name -eq "Terminal") {
        Show-WinToolTerminalSelection
    }
    if ($Name -eq "Features" -and -not $script:WinToolState.FeaturesChecked) {
        $script:WinToolState.FeaturesChecked = $true
        Start-WinToolFeatureDetection
    }
    if ($Name -eq "Drivers") {
        Start-WinToolDriverInfoJob
    }
}

function Start-WinToolNavWarmup {
    # Measures each page once while Home is on screen, so the first click
    # does not pay for building that page.
    $script:WinToolState.WarmViews = @("Install", "Tweaks", "Terminal", "Drivers", "Updates", "Fixes", "Features", "Config")
    $callback = [scriptblock]::Create("Invoke-WinToolNavWarmupStep")
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$callback)
}

function Invoke-WinToolNavWarmupStep {
    if ($script:WinToolShuttingDown) { return }
    $pending = @($script:WinToolState.WarmViews)
    if ($pending.Count -eq 0) { return }
    $name = [string]$pending[0]
    if ($pending.Count -le 1) { $script:WinToolState.WarmViews = @() }
    else { $script:WinToolState.WarmViews = @($pending | Select-Object -Skip 1) }
    if ([string]$script:WinToolState.ActiveView -ne $name) {
        $shown = @($script:WinToolState.ViewShown)
        $element = Get-WinToolUi -Name ("View" + $name)
        if ($null -ne $element -and $shown -notcontains $name) {
            $element.Opacity = 0
            $element.IsHitTestVisible = $false
            [System.Windows.Controls.Panel]::SetZIndex($element, 0)
            $element.Visibility = "Visible"
            $script:WinToolState.ViewShown = @($shown + $name)
        }
    }
    if (@($script:WinToolState.WarmViews).Count -gt 0) {
        $callback = [scriptblock]::Create("Invoke-WinToolNavWarmupStep")
        $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$callback)
    }
}

function Switch-WinToolView {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($script:WinToolShuttingDown) { return }
    # The click only changes which page is on top. A page that has been shown
    # stays Visible at opacity 0, because collapsing it throws its layout away
    # and the next visit measures the whole tree inside the click.
    if ($null -eq $script:WinToolState.ViewShown) {
        $script:WinToolState.ViewShown = @("Home")
    }
    $stamp = [System.Diagnostics.Stopwatch]::GetTimestamp()
    $script:WinToolState.NavStamp = [int64]$stamp
    $script:WinToolState.ActiveView = $Name
    $shown = @($script:WinToolState.ViewShown)
    foreach ($view in @(Get-WinToolViewName)) {
        $element = Get-WinToolUi -Name ("View" + $view)
        if ($null -eq $element) { continue }
        if ($view -eq $Name) {
            $element.Visibility = "Visible"
            $element.IsHitTestVisible = $true
            [System.Windows.Controls.Panel]::SetZIndex($element, 2)
            Start-WinToolSlide -Element $element -FromX 8 -ToX 0 -Milliseconds 150
            if ($shown -notcontains $view) {
                $script:WinToolState.ViewShown = @($script:WinToolState.ViewShown) + $view
            }
        }
        elseif ($shown -contains $view) {
            $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
            $shift = $element.RenderTransform
            if ($shift -is [System.Windows.Media.TranslateTransform]) {
                $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $null)
                $shift.X = 0
            }
            $element.Opacity = 0
            $element.IsHitTestVisible = $false
            [System.Windows.Controls.Panel]::SetZIndex($element, 0)
            $element.Visibility = "Visible"
        }
        else {
            $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
            $element.Opacity = 0
            $element.IsHitTestVisible = $false
            [System.Windows.Controls.Panel]::SetZIndex($element, 0)
            $element.Visibility = "Collapsed"
        }
    }
    try { $null = $script:WinToolWindow.Focus() } catch { $null = $_.Exception.Message }
    $safe = ($Name -replace "[^A-Za-z]", "")
    $callback = [scriptblock]::Create(("Complete-WinToolNavTiming -Name '{0}' -Stamp {1}" -f $safe, [int64]$stamp))
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [System.Action]$callback)
}

function Sync-WinToolBusyState {
    param(
        [bool]$Busy
    )
    $wasBusy = $false
    if ($script:WinToolState.Busy) {
        $wasBusy = $true
    }
    $script:WinToolState.Busy = $Busy
    if (-not $Busy -and $wasBusy -and -not $script:WinToolState.ActivityPinned -and -not $script:WinToolState.LogPinned) {
        $script:WinToolState.ActivityExpanded = $false
        $script:WinToolState.LogExpanded = $false
    }
    Sync-WinToolLogPanel
    $names = @(
        "AppInstall", "AppClear",
        "AppRefreshInstalled", "AppUpdate", "AppUninstall", "AppUpgradeAll",
        "FeatureApply",
        "TerminalSetup", "TerminalUpdate", "ScanDrivers", "DriversScan", "DriversScanAgain", "DriversUpdate", "DriversBackup",
        "ApplyUpdateMode", "RevertUpdateMode",
        "ApplyDns", "RefreshDns", "AddUltimatePlan",
        "SaveProfile", "LoadProfile", "ExportWinget", "ImportWinget"
    )
    foreach ($name in $names) {
        (Get-WinToolUi -Name $name).IsEnabled = -not $Busy
    }
    (Get-WinToolUi -Name "TerminalRefresh").IsEnabled = (-not $Busy -and $null -eq $script:WinToolState.CatalogJob)
    (Get-WinToolUi -Name "FeatureRefresh").IsEnabled = (-not $Busy -and $null -eq $script:WinToolState.FeatureJob)
    (Get-WinToolUi -Name "RemoveUltimatePlan").IsEnabled = (-not $Busy -and [bool]$script:WinToolState.UltimatePlanAdded)
    foreach ($featureRow in @($script:WinToolState.FeatureRows)) {
        if ($Busy) {
            $featureRow.Checkbox.IsEnabled = $false
        }
        else {
            $featureRow.Checkbox.IsEnabled = ($featureRow.Status -ne "Unavailable" -and $featureRow.Status -ne "Unknown")
        }
    }
    if ($null -ne $script:WinToolState.BusyControls) {
        foreach ($control in $script:WinToolState.BusyControls.ToArray()) {
            $control.IsEnabled = -not $Busy
        }
    }
    $installUpdates = Get-WinToolUi -Name "InstallScannedUpdates"
    if ($Busy) {
        $installUpdates.IsEnabled = $false
    }
    else {
        $installUpdates.IsEnabled = (@($script:WinToolState.Updates).Count -gt 0)
    }
    $cancel = Get-WinToolUi -Name "CancelRun"
    if ($Busy) {
        $cancel.Visibility = "Visible"
    }
    else {
        $cancel.Visibility = "Collapsed"
    }
}

function Enable-WinToolLogPump {
    if ($null -ne $script:WinToolState.Pump) {
        return
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    Register-WinToolUiEvent -Control $timer -EventName "Tick" -Name "Log refresh" -Action { Update-WinToolLogPump }
    $timer.Start()
    $script:WinToolState.Pump = $timer
}

function Invoke-WinToolPlanAsync {
    param(
        $Step,
        [Parameter(Mandatory = $true)][string]$DoneMessage,
        [string]$AfterDone,
        [switch]$Update
    )
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $script:WinToolState.Run = @{
        Steps = @($Step)
        Index = -1
        Process = $null
        Queue = $queue
        StepLog = New-Object System.Collections.Generic.List[string]
        ExitHandled = $false
        Cancel = $false
        DoneMessage = $DoneMessage
        AfterDone = $AfterDone
        SkipZsh = $false
        Update = [bool]$Update
        Tally = New-WinToolPlanTally
        Cache = Get-WinToolPackageCache
    }
    Start-WinToolActivity -Title $DoneMessage | Out-Null
    Sync-WinToolBusyState -Busy $true
    Enable-WinToolLogPump
    Move-WinToolPlanForward
}

function Move-WinToolPlanForward {
    $run = $script:WinToolState.Run
    if ($null -eq $run) {
        return
    }
    if ($run.Cancel) {
        Complete-WinToolPlan -Message (Get-WinToolText "activity.cancelled")
        return
    }
    $run.Index = [int]$run.Index + 1
    $steps = @($run.Steps)
    if ($run.Index -ge $steps.Count) {
        $message = [string]$run.DoneMessage
        if ($null -ne $run.Tally) {
            $summary = Format-WinToolPlanSummary -Tally $run.Tally
            if (-not [string]::IsNullOrWhiteSpace($summary)) {
                $message = $summary
            }
        }
        Complete-WinToolPlan -Message $message
        return
    }
    $step = $steps[$run.Index]
    $total = $steps.Count
    $percent = 0
    if ($total -gt 0) {
        $percent = [int]((100.0 * $run.Index) / $total)
    }
    Sync-WinToolProgress -Value $percent -Text (Get-WinToolText "status.summary.step" ([string]$step.Label) ($run.Index + 1) $total) -Indeterminate $false

    if ([string]$step.Type -eq "wsl-shell" -and $run.SkipZsh) {
        Write-WinToolLog -Message "Zsh setup is waiting on a reboot. Run terminal setup again after Windows restarts." -Level "warn"
        Move-WinToolPlanForward
        return
    }

    $cache = $run.Cache
    if ($null -eq $cache) { $cache = Get-WinToolPackageCache }
    $decision = Set-WinToolPlanStepDecision -Step $step -Cache $cache -Update:([bool]$run.Update)
    $run.Decision = $decision
    if (-not [bool]$decision.Run) {
        Write-WinToolLog -Message ([string]$step.Label + " (already installed, skipped)") -Level "ok"
        if ($null -ne $run.Tally) {
            Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome ([string]$decision.Outcome)
        }
        Move-WinToolPlanForward
        return
    }

    Write-WinToolLog -Message ([string]$step.Label) -Level "info"
    $command = Get-WinToolPlanCommand -Step $step
    if ($null -eq $command) {
        try {
            $changed = Invoke-WinToolLocalStep -Step $step
            if ($null -ne $run.Tally) {
                if ([string]$decision.Outcome -eq "config") {
                    if ($changed -eq $false) {
                        Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "config-unchanged"
                    }
                    else {
                        Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "config-changed"
                    }
                }
                else {
                    Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome ([string]$decision.Outcome)
                }
            }
        }
        catch {
            Write-WinToolLog -Message ("{0} failed. {1}" -f [string]$step.Label, $_.Exception.Message) -Level "error"
            if ($null -ne $run.Tally) {
                Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "failed"
            }
        }
        Move-WinToolPlanForward
        return
    }

    $filePath = [string]$command.FilePath
    if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -LiteralPath $filePath)) {
        Write-WinToolLog -Message ("Skipped {0} because the program was not found." -f [string]$step.Label) -Level "warn"
        if ([string]$step.Type -eq "winget") {
            Write-WinToolLog -Message "Install App Installer from the Microsoft Store, then try again." -Level "warn"
        }
        Move-WinToolPlanForward
        return
    }

    $run.StepLog = New-Object System.Collections.Generic.List[string]
    $run.ExitHandled = $false
    try {
        $run.Process = Start-WinToolAsyncProcess -FilePath $filePath -ArgumentList @($command.ArgumentList) -LineQueue $run.Queue
    }
    catch {
        Write-WinToolLog -Message ("Could not start {0}. {1}" -f [string]$step.Label, $_.Exception.Message) -Level "error"
        $run.Process = $null
        Move-WinToolPlanForward
    }
}

function Complete-WinToolPlanStep {
    $run = $script:WinToolState.Run
    if ($null -eq $run -or $null -eq $run.Process) {
        return
    }
    $code = -1
    try {
        $code = [int]$run.Process.ExitCode
    }
    catch {
        $code = -1
    }
    $output = ""
    if ($null -ne $run.StepLog -and $run.StepLog.Count -gt 0) {
        $output = ($run.StepLog -join "`n")
    }
    $steps = @($run.Steps)
    $step = $steps[$run.Index]
    $run.Process = $null
    if ($run.Cancel) {
        Complete-WinToolPlan -Message (Get-WinToolText "activity.cancelled")
        return
    }
    $decision = $run.Decision
    if ([string]$step.Type -eq "winget") {
        $result = ConvertTo-WinToolWingetResult -ExitCode $code -Output $output
        if ($result.Status -eq "Failed") {
            Write-WinToolLog -Message ("{0} failed (exit {1})." -f [string]$step.Label, $code) -Level "error"
            if ($null -ne $run.Tally) { Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "failed" }
        }
        elseif ($result.Status -eq "AlreadyInstalled") {
            Write-WinToolLog -Message ("{0}: {1}." -f [string]$step.Label, (Get-WinToolWingetOutcomeText -Action (Get-WinToolWingetStepAction -Step $step) -Status $result.Status)) -Level "ok"
            if ($null -ne $run.Tally) { Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "already-had" }
        }
        else {
            Write-WinToolLog -Message ("{0}: done." -f [string]$step.Label) -Level "ok"
            $bucket = "install"
            if ($null -ne $decision -and -not [string]::IsNullOrWhiteSpace([string]$decision.Outcome)) {
                $bucket = [string]$decision.Outcome
            }
            if ($null -ne $run.Tally) { Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome $bucket }
        }
    }
    elseif (-not (Test-WinToolStepSuccess -Step $step -ExitCode $code)) {
        Write-WinToolLog -Message ("{0} exited with code {1}." -f [string]$step.Label, $code) -Level "error"
        if ($null -ne $run.Tally) { Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome "failed" }
    }
    else {
        Write-WinToolLog -Message ("{0}: done." -f [string]$step.Label) -Level "ok"
        $bucket = "install"
        if ($null -ne $decision -and -not [string]::IsNullOrWhiteSpace([string]$decision.Outcome)) {
            $bucket = [string]$decision.Outcome
        }
        if ($null -ne $run.Tally) { Add-WinToolPlanStepOutcome -Tally $run.Tally -Step $step -Outcome $bucket }
    }
    if ([string]$step.Type -eq "wsl-install" -and $output -match "(?i)reboot") {
        $run.SkipZsh = $true
        Write-WinToolLog -Message "Windows asked for a reboot before WSL can finish." -Level "warn"
    }
    Move-WinToolPlanForward
}

function Complete-WinToolPlan {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )
    $run = $script:WinToolState.Run
    if ($null -ne $run -and $null -ne $run.Process) {
        try {
            if (-not $run.Process.HasExited) {
                $run.Process.Kill()
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    $afterDone = $null
    if ($null -ne $run) {
        $afterDone = [string]$run.AfterDone
    }
    $script:WinToolState.Run = $null
    Sync-WinToolBusyState -Busy $false
    if ($Message -eq "Cancelled." -or $Message -eq (Get-WinToolText "activity.cancelled")) {
        Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.cancelled") -Summary $Message -Indeterminate $false
        Write-WinToolLog -Message $Message -Level "warn"
        $finished = Complete-WinToolActivity -Summary $Message -Status "warn"
    }
    else {
        Sync-WinToolProgress -Value 100 -Text (Get-WinToolText "status.ready") -Summary $Message -Indeterminate $false
        Write-WinToolLog -Message $Message -Level "ok"
        $finished = Complete-WinToolActivity -Summary $Message -Status "ok"
    }
    if ($null -ne $finished) {
        Show-WinToolActivityToast -Run $finished
    }
    if (-not [string]::IsNullOrWhiteSpace($afterDone)) {
        try {
            & $afterDone
        }
        catch {
            Write-WinToolLog -Message ("Follow-up step failed. {0}" -f $_.Exception.Message) -Level "warn"
        }
    }
}

function Stop-WinToolRun {
    $run = $script:WinToolState.Run
    if ($null -ne $run) {
        $run.Cancel = $true
        if ($null -ne $run.Process) {
            try {
                Stop-WinToolChildProcess -ParentId ([int]$run.Process.Id)
                if (-not $run.Process.HasExited) {
                    $run.Process.Kill()
                }
            }
            catch {
                Complete-WinToolPlan -Message (Get-WinToolText "activity.cancelled")
            }
        }
        else {
            Complete-WinToolPlan -Message (Get-WinToolText "activity.cancelled")
        }
        return
    }
    foreach ($name in @("RestoreJob", "UpdateJob", "InstallJob", "DriverScanJob", "DriverToolJob")) {
        $job = $script:WinToolState[$name]
        if ($null -ne $job) {
            Stop-WinToolThread -Job $job
            $script:WinToolState[$name] = $null
        }
    }
    $queuedTweaks = $script:WinToolState.TweakQueue
    $script:WinToolState.TweakQueue = $null
    if ($null -ne $queuedTweaks) {
        $script:WinToolState.TweakRequestStarted = $true
        try {
            foreach ($entry in @($queuedTweaks.ToArray())) {
                $entry.Row.Checkbox.IsChecked = [bool]$entry.Previous
                $entry.Row.Checkbox.IsEnabled = $true
                Sync-WinToolTweakToggleTip -Row $entry.Row
            }
        }
        finally {
            $script:WinToolState.TweakRequestStarted = $false
        }
        Update-WinToolTweakCount
        Sync-WinToolHomeTweakRow
    }
    if (Get-Command Complete-WinToolDriverScanCancel -ErrorAction SilentlyContinue) {
        Complete-WinToolDriverScanCancel
    }
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.cancelled") -Indeterminate $false
    Write-WinToolLog -Message (Get-WinToolText "activity.cancelled") -Level "warn"
    $run = Complete-WinToolActivity -Summary (Get-WinToolText "activity.cancelled") -Status "warn"
    if ($null -ne $run) { Show-WinToolActivityToast -Run $run }
}

function Update-WinToolLogPump {
    # A tick already queued when the window closes must not activate it again.
    if ($script:WinToolShuttingDown) { return }
    if ($null -ne $script:WinToolActivateEvent) {
        try {
            if ($script:WinToolActivateEvent.WaitOne(0) -and $null -ne $script:WinToolWindow) {
                if ($script:WinToolWindow.WindowState -eq "Minimized") {
                    $script:WinToolWindow.WindowState = "Normal"
                }
                $null = $script:WinToolWindow.Activate()
                $script:WinToolWindow.Topmost = $true
                $script:WinToolWindow.Topmost = $false
                $null = $script:WinToolWindow.Focus()
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }

    $run = $script:WinToolState.Run
    if ($null -ne $run -and $null -ne $run.Queue) {
        $line = $null
        while ($run.Queue.TryDequeue([ref]$line)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                # sfc.exe writes UTF-16, which arrives with NUL characters.
                $clean = $line.Replace([string][char]0, "").Trim()
                if ($null -ne $run.StepLog) {
                    $run.StepLog.Add($clean)
                }
                Add-WinToolLogLine -Line ("           " + $clean)
            }
        }
        if ($null -ne $run.Process -and $run.Process.HasExited -and -not $run.ExitHandled) {
            $run.ExitHandled = $true
            Complete-WinToolPlanStep
        }
    }

    $restore = $script:WinToolState.RestoreJob
    if ($null -ne $restore -and $restore.Sync.Done) {
        $ok = [bool]$restore.Sync.Ok
        $errorMessage = [string]$restore.Sync.Error
        Stop-WinToolThread -Job $restore
        $script:WinToolState.RestoreJob = $null
        Complete-WinToolRestorePoint -Ok $ok -ErrorMessage $errorMessage
    }

    $update = $script:WinToolState.UpdateJob
    if ($null -ne $update -and $update.Sync.Done) {
        Complete-WinToolUpdateScan
    }

    $driverScan = $script:WinToolState.DriverScanJob
    if ($null -ne $driverScan -and $driverScan.Sync.Done) {
        Complete-WinToolDriverScan
    }
    elseif ($null -ne $driverScan) {
        Update-WinToolDriverScanProgress
    }

    $driverTool = $script:WinToolState.DriverToolJob
    if ($null -ne $driverTool -and $driverTool.Sync.Done) {
        Complete-WinToolDriverTool
    }

    $driverInfo = $script:WinToolState.DriverInfoJob
    if ($null -ne $driverInfo -and $driverInfo.Sync.Done) {
        Complete-WinToolDriverInfo
    }

    $featureJob = $script:WinToolState.FeatureJob
    if ($null -ne $featureJob -and $featureJob.Sync.Done) {
        Complete-WinToolFeatureDetection
    }
    else {
        Test-WinToolFeatureDetectionTimeout
    }

    $detect = $script:WinToolState.DetectJob
    if ($null -ne $detect -and $detect.Sync.Done) {
        Complete-WinToolAppDetection
    }
    else {
        Test-WinToolAppDetectionTimeout
    }

    $install = $script:WinToolState.InstallJob
    if ($null -ne $install -and $install.Sync.Done) {
        Complete-WinToolUpdateInstall
    }

    if ($script:WinToolTerminalScrollPending -and [string]$script:WinToolState.ActiveView -eq "Terminal") {
        Show-WinToolTerminalSelection
    }

    $tweakStateJob = $script:WinToolState.TweakStateJob
    if ($null -ne $tweakStateJob -and $tweakStateJob.Sync.Done) {
        Complete-WinToolTweakStateRead
    }

    $systemJob = $script:WinToolState.SystemJob
    if ($null -ne $systemJob -and $systemJob.Sync.Done) {
        Complete-WinToolSystemProbe
    }

    $preview = $script:WinToolState.PreviewJob
    if ($null -ne $preview) {
        if ($preview.Job.Sync.Done) {
            Complete-WinToolPreviewThemeDownload
        }
        elseif (([DateTime]::UtcNow - $preview.Started).TotalSeconds -gt 15) {
            Complete-WinToolPreviewThemeDownload
        }
    }

    $catalogJob = $script:WinToolState.CatalogJob
    if ($null -ne $catalogJob) {
        if ($catalogJob.Job.Sync.Done) {
            Complete-WinToolTerminalCatalogOnline
        }
        elseif (([DateTime]::UtcNow - $catalogJob.Started).TotalSeconds -gt 25) {
            $catalogJob.Job.Sync.Error = "Request timed out."
            Complete-WinToolTerminalCatalogOnline
        }
    }

    if ([bool]$script:WinToolState.ActivityDirty -and ([bool]$script:WinToolState.ActivityExpanded -or [bool]$script:WinToolState.LogExpanded)) {
        Update-WinToolActivityList
    }
}

function Initialize-WinToolShellEvent {
    (Get-WinToolUi -Name "VersionText").Text = "Version " + $script:WinToolVersion
    foreach ($view in @(Get-WinToolViewName)) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name ("Nav" + $view)) -EventName "Checked" -Name ("Open the " + $view + " tab") -Data $view -Action {
            param($source, $eventData, $viewName)
            $null = $source, $eventData
            Switch-WinToolView -Name $viewName
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "NavList") -EventName "SizeChanged" -Name "Place the sidebar pill" -Action {
        Update-WinToolNavPill -Animate $false
    }
    Update-WinToolNavPill -Animate $false
    foreach ($fillPair in @(
            , @("DriversSimpleScroll", "DriversBody")
            , @("DriversToolsScroll", "DriversToolsBody")
            , @("ViewUpdates", "UpdatesBody")
            , @("ViewFixes", "FixesBody")
            , @("ViewFeatures", "FeaturesBody")
            , @("ViewConfig", "ConfigBody")
            , @("TerminalSimpleScroll", "TerminalSimpleHost")
        )) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name $fillPair[0]) -EventName "SizeChanged" -Name ("Fill " + $fillPair[1]) -Data @($fillPair[0], $fillPair[1]) -Action {
            param($source, $eventData, $boundPair)
            $null = $source, $eventData
            Sync-WinToolScrollFill -ScrollName ([string]$boundPair[0]) -BodyName ([string]$boundPair[1])
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "CancelRun") -EventName "Click" -Name "Cancel" -Action {
        Stop-WinToolRun
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ProjectLink") -EventName "RequestNavigate" -Name "Open project link" -Action {
        $uiEvent = $args[1]
        if ($null -ne $uiEvent -and $null -ne $uiEvent.Uri) {
            Open-WinToolUri -Uri $uiEvent.Uri.AbsoluteUri
            $uiEvent.Handled = $true
        }
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "PreviewKeyDown" -Name "Keyboard shortcut" -Action {
        $uiEvent = $args[1]
        $modifiers = [System.Windows.Input.Keyboard]::Modifiers
        $control = [System.Windows.Input.ModifierKeys]::Control
        if (($modifiers -band $control) -eq $control -and $uiEvent.Key -eq "F") {
            $activeView = [string]$script:WinToolState.ActiveView
            if ($activeView -eq "Install") {
                (Get-WinToolUi -Name "AppSearch").Focus() | Out-Null
            }
            elseif ($activeView -eq "Tweaks") {
                (Get-WinToolUi -Name "TweakSearch").Focus() | Out-Null
            }
            elseif ($activeView -eq "Terminal" -and $script:WinToolTerminalMode -eq "advanced") {
                (Get-WinToolUi -Name "TerminalThemeSearch").Focus() | Out-Null
            }
            $uiEvent.Handled = $true
        }
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Closing" -Name "Close WinTool" -Action {
        $uiEvent = $args[1]
        try {
            if ($script:WinToolState.Busy) {
                $ok = Request-WinToolConfirmation -Message (Get-WinToolText "shell.close.busy") -Title (Get-WinToolText "shell.close.title")
                if (-not $ok) {
                    $uiEvent.Cancel = $true
                    return
                }
                Stop-WinToolRun
            }
            $script:WinToolShuttingDown = $true
            Stop-WinToolBackgroundWork
            # The window test closes a window it built itself. Leave that
            # process, and a console the user was using, alone.
            if (-not $script:WinToolSessionExit) { return }
            if (Test-WinToolConsoleShouldRestore) { return }
            if ((Get-WinToolCurrentConsoleMode) -eq "show") { return }
            # Kill tracked children and detach the hidden console before this
            # window is destroyed. Otherwise Windows shows the console, then
            # the process exits and the taskbar button disappears again.
            Stop-WinToolChildProcess
            Remove-WinToolHiddenConsole
            Exit-WinToolSingleInstance
            [Environment]::Exit(0)
        }
        catch {
            $null = $_.Exception.Message
            if ($script:WinToolSessionExit -and -not (Test-WinToolConsoleShouldRestore) -and (Get-WinToolCurrentConsoleMode) -ne "show") {
                try { [Environment]::Exit(1) } catch { $null = $_.Exception.Message }
            }
        }
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Closed" -Name "Window closed" -Action {
        Stop-WinToolBackgroundWork
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Loaded" -Name "Window loaded" -Action {
        Write-WinToolLog -Message "Welcome to WinTool. Choose what you want, then run it when you are ready." -Level "info"
        $winget = Get-WinToolWingetPath
        if ([string]::IsNullOrWhiteSpace($winget)) {
            Write-WinToolLog -Message "winget was not found. Install App Installer from the Microsoft Store before installing apps." -Level "warn"
            Sync-WinToolStatus -Text "winget not found"
        }
        else {
            Write-WinToolLog -Message "winget is available." -Level "ok"
            Sync-WinToolStatus -Text "Ready"
        }
        Start-WinToolTweakStateRead
        Start-WinToolNavWarmup
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Loaded" -Name "Check installed apps" -Action {
        Update-WinToolLocalPackageCache | Out-Null
        Start-WinToolAppDetection
    }
}

function New-WinToolWindow {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $script:WinToolState = @{
        Busy = $false
        AppRows = @()
        CategoryRows = @()
        TweakRows = @()
        TweakGroups = @()
        Updates = @()
        UpdateCriteria = ""
        UpdateMode = ""
        UpdateModeCurrent = ""
        UpdateModeRadios = @()
        DnsAdapters = @()
        UltimatePlanAdded = $false
        SystemChecked = $false
        Run = $null
        Pump = $null
        RestoreJob = $null
        UpdateJob = $null
        InstallJob = $null
        DriverScanJob = $null
        DriverToolJob = $null
        DriverInfoJob = $null
        DriverPending = $null
        DriverPendingWu = $null
        DriverRows = @()
        DriverDevices = @()
        DriverUpdates = @()
        DriverDisplays = @()
        DriverTools = $null
        DriverScanned = $false
        DriverCurrentBuilt = $false
        DriverHvci = $false
        DriverInfo = $null
        DriverToolKind = ""
        DriverSyncing = $false
        DetectJob = $null
        PreviewJob = $null
        CatalogJob = $null
        BusyControls = $null
        FeatureJob = $null
        FeatureRows = @()
        TweakQueue = $null
        ActiveView = "Home"
        ViewShown = @("Home")
        NavStamp = [int64]0
        NavMilliseconds = -1
        WarmViews = @()
        TweakStateRead = $false
        TweakStateJob = $null
        TweakStateGeneration = 0
        TweakLayoutSignature = ""
        SystemJob = $null
        SystemGeneration = 0
        TweakTwoColumns = $true
        TweakColumns = 3
        TweakWidth = 0
        AppColumns = 5
        RestorePointDone = $false
        AppFilter = "all"
        AppStartApps = @()
        AppCardAction = $null
        AppsDetected = $false
        LogExpanded = $false
        LogPinned = $false
        ActivityExpanded = $false
        ActivityPinned = $false
        ActivityRuns = New-Object System.Collections.Generic.List[object]
        ActivityCurrent = $null
        ActivityFilter = "all"
        ActivityBadge = 0
        ActivityDirty = $true
        ToastTimer = $null
        Home = $null
        HomeTimer = $null
        HomeAnimTimer = $null
        HomeSampler = $null
        HomeInfoJob = $null
        HomeCleanJob = $null
        TweakRequestStarted = $false
    }
    $script:WinToolShuttingDown = $false
    $script:WinToolSessionExit = $false

    $xaml = Get-WinToolPayloadText -Name "Xaml"
    [xml]$document = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $document
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:WinToolWindow = $window
    $script:WinToolLogBox = $null

    Initialize-WinToolAppearance
    Initialize-WinToolActivityView
    Initialize-WinToolHomeView
    Initialize-WinToolInstallView
    Initialize-WinToolTweakView
    Initialize-WinToolTerminalView
    Initialize-WinToolDriverView
    Initialize-WinToolUpdateView
    Initialize-WinToolFixView
    Initialize-WinToolFeatureView
    Initialize-WinToolConfigView
    Initialize-WinToolShellEvent
    Sync-WinToolLogPanel

    if (-not [string]::IsNullOrWhiteSpace($script:WinToolApplyProfile)) {
        try {
            Import-WinToolProfileToUi -Path $script:WinToolApplyProfile
        }
        catch {
            Write-WinToolLog -Message ("Could not load the profile. {0}" -f $_.Exception.Message) -Level "error"
        }
    }

    return $window
}

function Stop-WinToolBackgroundWork {
    # Stops the log timer, a running plan, and every background runspace, so
    # nothing keeps powershell.exe alive after the window is gone.
    if ($null -eq $script:WinToolState) { return }
    try { Stop-WinToolMotion } catch { $null = $_.Exception.Message }
    if ($null -ne $script:WinToolState.Pump) {
        try { $script:WinToolState.Pump.Stop() } catch { $null = $_.Exception.Message }
        $script:WinToolState.Pump = $null
    }
    foreach ($timerKey in @("HomeTimer", "HomeAnimTimer")) {
        if ($null -ne $script:WinToolState[$timerKey]) {
            try { $script:WinToolState[$timerKey].Stop() } catch { $null = $_.Exception.Message }
            $script:WinToolState[$timerKey] = $null
        }
    }
    if ($null -ne $script:WinToolState.HomeSampler) {
        # Lets the sampler loop end on its own as well.
        try { $script:WinToolState.HomeSampler.Sync.Stop = $true } catch { $null = $_.Exception.Message }
    }
    $run = $script:WinToolState.Run
    if ($null -ne $run -and $null -ne $run.Process) {
        try { if (-not $run.Process.HasExited) { $run.Process.Kill() } } catch { $null = $_.Exception.Message }
    }
    $script:WinToolState.Run = $null
    foreach ($key in @($script:WinToolState.Keys)) {
        $value = $script:WinToolState[$key]
        if ($null -eq $value -or $null -eq $value.PSObject) { continue }
        $target = $value
        if ($null -ne $value.PSObject.Properties["Job"] -and $null -ne $value.Job) {
            $target = $value.Job
        }
        if ($null -ne $target -and $null -ne $target.PSObject -and $null -ne $target.PSObject.Properties["Runspace"]) {
            # Asynchronous stop: a runspace still waiting on winget must not
            # hold the window open while it closes.
            try { $null = $target.PowerShell.BeginStop($null, $null) } catch { $null = $_.Exception.Message }
            try { $null = $target.Runspace.CloseAsync() } catch { $null = $_.Exception.Message }
            $script:WinToolState[$key] = $null
        }
    }
    try { Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue } catch { $null = $_.Exception.Message }
}

$script:WinToolKeepProcesses = @("conhost.exe", "openconsole.exe", "explorer.exe", "taskmgr.exe", "mmc.exe", "systemsettings.exe", "applicationframehost.exe")

function Stop-WinToolChildProcess {
    # Ends what this process started (winget, installers, helpers), children
    # first. Console hosts and desktop tools opened for the user stay open.
    param([int]$ParentId = $PID)
    $children = @()
    try { $children = @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = {0}" -f $ParentId) -ErrorAction Stop) }
    catch { return }
    foreach ($child in $children) {
        $childName = ([string]$child.Name).ToLowerInvariant()
        if ($script:WinToolKeepProcesses -contains $childName) { continue }
        Stop-WinToolChildProcess -ParentId ([int]$child.ProcessId)
        try { Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction Stop } catch { $null = $_.Exception.Message }
    }
}

$script:WinToolMutexName = "Local\WinTool.Hinrikao.Window"
$script:WinToolActivateEventName = "Local\WinTool.Hinrikao.Activate"

function New-WinToolSingleInstanceMutex {
    if (Test-WinToolWindows) {
        try {
            $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $security = New-Object System.Security.AccessControl.MutexSecurity
            $rule = New-Object System.Security.AccessControl.MutexAccessRule($sid, [System.Security.AccessControl.MutexRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
            $security.AddAccessRule($rule)
            $createdNew = $false
            return New-Object System.Threading.Mutex($false, $script:WinToolMutexName, [ref]$createdNew, $security)
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    return [System.Threading.Mutex]::new($false, $script:WinToolMutexName)
}

function New-WinToolActivateEvent {
    if (Test-WinToolWindows) {
        try {
            $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $security = New-Object System.Security.AccessControl.EventWaitHandleSecurity
            $rule = New-Object System.Security.AccessControl.EventWaitHandleAccessRule($sid, [System.Security.AccessControl.EventWaitHandleRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
            $security.AddAccessRule($rule)
            $createdNew = $false
            return New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:WinToolActivateEventName, [ref]$createdNew, $security)
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    return New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:WinToolActivateEventName)
}

function Send-WinToolActivateSignal {
    $focused = $false
    if (Initialize-WinToolConsoleApi) {
        try { $null = [WinToolConsoleApi]::AllowSetForegroundWindow(-1) } catch { $null = $_.Exception.Message }
    }
    try {
        $signal = [System.Threading.EventWaitHandle]::OpenExisting($script:WinToolActivateEventName)
        try {
            $null = $signal.Set()
        }
        finally {
            $signal.Dispose()
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    if (Initialize-WinToolConsoleApi) {
        try {
            $focused = [WinToolConsoleApi]::FocusWinToolWindow()
        }
        catch {
            $focused = $false
        }
    }
    return $focused
}

function Test-WinToolAlreadyRunning {
    $existing = $null
    try {
        $existing = [System.Threading.Mutex]::OpenExisting($script:WinToolMutexName)
    }
    catch [System.Threading.WaitHandleCannotBeOpenedException] {
        return $false
    }
    catch [System.UnauthorizedAccessException] {
        $null = Send-WinToolActivateSignal
        return $true
    }
    catch {
        return $false
    }
    try {
        $free = $false
        try {
            $free = $existing.WaitOne(0)
        }
        catch [System.Threading.AbandonedMutexException] {
            $free = $true
        }
        if ($free) {
            try { $existing.ReleaseMutex() } catch { $null = $_.Exception.Message }
            return $false
        }
        $null = Send-WinToolActivateSignal
        return $true
    }
    finally {
        $existing.Dispose()
    }
}

function Enter-WinToolSingleInstance {
    # One WinTool window per session. A second launch signals the open window
    # to bring itself to the front and leaves. If the first copy is closing,
    # this instance waits briefly to take over instead of leaving zero windows.
    $mutex = $null
    try {
        $mutex = New-WinToolSingleInstanceMutex
    }
    catch [System.UnauthorizedAccessException] {
        $null = Send-WinToolActivateSignal
        Write-Host "WinTool is already open. Its window was brought to the front."
        return $false
    }
    catch {
        $script:WinToolMutex = $null
        $script:WinToolMutexOwned = $false
        return $true
    }
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not $acquired) {
        $focused = Send-WinToolActivateSignal
        if (-not $focused) {
            try {
                $acquired = $mutex.WaitOne(2000)
            }
            catch [System.Threading.AbandonedMutexException] {
                $acquired = $true
            }
        }
        if (-not $acquired) {
            $null = Send-WinToolActivateSignal
            try { $mutex.Dispose() } catch { $null = $_.Exception.Message }
            Write-Host "WinTool is already open. Its window was brought to the front."
            return $false
        }
    }
    $script:WinToolMutex = $mutex
    $script:WinToolMutexOwned = $true
    try {
        $script:WinToolActivateEvent = New-WinToolActivateEvent
    }
    catch {
        $script:WinToolActivateEvent = $null
    }
    return $true
}

function Exit-WinToolSingleInstance {
    if ($null -ne $script:WinToolActivateEvent) {
        try { $script:WinToolActivateEvent.Dispose() } catch { $null = $_.Exception.Message }
        $script:WinToolActivateEvent = $null
    }
    if ($null -eq $script:WinToolMutex) { return }
    if ($script:WinToolMutexOwned) {
        try { $script:WinToolMutex.ReleaseMutex() } catch { $null = $_.Exception.Message }
    }
    try { $script:WinToolMutex.Dispose() } catch { $null = $_.Exception.Message }
    $script:WinToolMutex = $null
    $script:WinToolMutexOwned = $false
}

function Show-WinToolWindow {
    # Hide before the window exists, including when a test host calls this
    # directly. A second hide later does not forget a console that was visible.
    if ((Get-WinToolCurrentConsoleMode) -eq "hide") {
        Hide-WinToolConsole
    }
    if (-not (Enter-WinToolSingleInstance)) {
        if (Test-WinToolConsoleShouldRestore) {
            $null = Set-WinToolConsoleVisible -Visible $true
        }
        else {
            Remove-WinToolHiddenConsole
        }
        Exit-WinToolOwnedHost
        return
    }
    $closedNormally = $false
    try {
        $window = New-WinToolWindow
        $script:WinToolSessionExit = $true
        Enable-WinToolLogPump
        Register-WinToolUiEvent -Control $window -EventName "ContentRendered" -Name "Hide the console" -Action { Hide-WinToolConsole }
        $null = $window.ShowDialog()
        $closedNormally = $true
    }
    finally {
        Stop-WinToolBackgroundWork
        Exit-WinToolSingleInstance
        # Closing already detached a hidden console and ended that process.
        # This runs when the console belongs to the user, or when Closing did
        # not exit. Never show a console that was hidden before WinTool opened.
        if ($closedNormally -and (Test-WinToolConsoleShouldRestore)) {
            $null = Set-WinToolConsoleVisible -Visible $true
        }
        elseif ($closedNormally -and (Get-WinToolCurrentConsoleMode) -ne "show") {
            Remove-WinToolHiddenConsole
            [Environment]::Exit(0)
        }
    }
}
