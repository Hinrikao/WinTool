# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Request-WinToolConfirmation {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Title
    )
    $answer = [System.Windows.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question)
    return ($answer -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-WinToolViewName {
    return @("Install", "Tweaks", "Terminal", "Updates", "Fixes", "Features", "Config")
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

function Switch-WinToolView {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    foreach ($view in @(Get-WinToolViewName)) {
        $element = Get-WinToolUi -Name ("View" + $view)
        if ($view -eq $Name) {
            $element.Visibility = "Visible"
        }
        else {
            $element.Visibility = "Collapsed"
        }
    }
    if ($Name -eq "Config") {
        Update-WinToolProfileSummary
        if (-not $script:WinToolState.SystemChecked) {
            $script:WinToolState.SystemChecked = $true
            Update-WinToolSystemView
        }
    }
    if ($Name -eq "Features" -and -not $script:WinToolState.FeaturesChecked) {
        $script:WinToolState.FeaturesChecked = $true
        Start-WinToolFeatureDetection
    }
}

function Sync-WinToolStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )
    (Get-WinToolUi -Name "StatusText").Text = $Text
}

function Sync-WinToolProgress {
    param(
        [int]$Value,
        [string]$Text,
        [bool]$Indeterminate = $false
    )
    $bar = Get-WinToolUi -Name "MainProgress"
    $bar.IsIndeterminate = $Indeterminate
    if (-not $Indeterminate) {
        $bar.Value = $Value
    }
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        Sync-WinToolStatus -Text $Text
    }
}

function Sync-WinToolLogPanel {
    $expanded = $false
    if ($script:WinToolState.LogExpanded) {
        $expanded = $true
    }
    $busy = $false
    if ($script:WinToolState.Busy) {
        $busy = $true
    }
    $log = Get-WinToolUi -Name "LogPanel"
    $bar = Get-WinToolUi -Name "MainProgress"
    $toggle = Get-WinToolUi -Name "ToggleLogButton"
    $clear = Get-WinToolUi -Name "ClearLogButton"
    if ($expanded) {
        $log.Visibility = "Visible"
        $toggle.Content = "Hide log"
        $clear.Visibility = "Visible"
    }
    else {
        $log.Visibility = "Collapsed"
        $toggle.Content = "Show log"
        $clear.Visibility = "Collapsed"
    }
    if ($busy) {
        $bar.Visibility = "Visible"
    }
    else {
        $bar.Visibility = "Collapsed"
        $bar.IsIndeterminate = $false
    }
}

function Switch-WinToolLogPanel {
    if ($script:WinToolState.LogExpanded) {
        $script:WinToolState.LogExpanded = $false
        $script:WinToolState.LogPinned = $false
    }
    else {
        $script:WinToolState.LogExpanded = $true
        $script:WinToolState.LogPinned = $true
    }
    Sync-WinToolLogPanel
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
    if ($Busy -and -not $wasBusy) {
        $script:WinToolState.LogExpanded = $true
    }
    elseif (-not $Busy -and $wasBusy -and -not $script:WinToolState.LogPinned) {
        $script:WinToolState.LogExpanded = $false
    }
    Sync-WinToolLogPanel
    $names = @(
        "AppInstall", "AppClear",
        "AppRefreshInstalled", "AppUpdate", "AppUninstall", "AppUpgradeAll",
        "FeatureApply",
        "TerminalSetup", "ScanDrivers",
        "SaveProfile", "LoadProfile", "ExportWinget", "ImportWinget"
    )
    foreach ($name in $names) {
        (Get-WinToolUi -Name $name).IsEnabled = -not $Busy
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
        [string]$AfterDone
    )
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
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
    }
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
        Complete-WinToolPlan -Message "Cancelled."
        return
    }
    $run.Index = [int]$run.Index + 1
    $steps = @($run.Steps)
    if ($run.Index -ge $steps.Count) {
        Complete-WinToolPlan -Message ([string]$run.DoneMessage)
        return
    }
    $step = $steps[$run.Index]
    $total = $steps.Count
    $percent = 0
    if ($total -gt 0) {
        $percent = [int]((100.0 * $run.Index) / $total)
    }
    Sync-WinToolProgress -Value $percent -Text ("{0} ({1} of {2})" -f [string]$step.Label, ($run.Index + 1), $total) -Indeterminate $false
    Write-WinToolLog -Message ([string]$step.Label) -Level "info"

    if ([string]$step.Type -eq "wsl-shell" -and $run.SkipZsh) {
        Write-WinToolLog -Message "Zsh setup is waiting on a reboot. Run terminal setup again after Windows restarts." -Level "warn"
        Move-WinToolPlanForward
        return
    }

    $command = Get-WinToolPlanCommand -Step $step
    if ($null -eq $command) {
        try {
            Invoke-WinToolLocalStep -Step $step
        }
        catch {
            Write-WinToolLog -Message ("{0} failed. {1}" -f [string]$step.Label, $_.Exception.Message) -Level "error"
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
        Complete-WinToolPlan -Message "Cancelled."
        return
    }
    if ([string]$step.Type -eq "winget") {
        $result = ConvertTo-WinToolWingetResult -ExitCode $code -Output $output
        if ($result.Status -eq "Failed") {
            Write-WinToolLog -Message ("{0} failed (exit {1})." -f [string]$step.Label, $code) -Level "error"
        }
        elseif ($result.Status -eq "AlreadyInstalled") {
            Write-WinToolLog -Message ("{0}: {1}." -f [string]$step.Label, (Get-WinToolWingetOutcomeText -Action (Get-WinToolWingetStepAction -Step $step) -Status $result.Status)) -Level "ok"
        }
        else {
            Write-WinToolLog -Message ("{0}: done." -f [string]$step.Label) -Level "ok"
        }
    }
    elseif (-not (Test-WinToolStepSuccess -Step $step -ExitCode $code)) {
        Write-WinToolLog -Message ("{0} exited with code {1}." -f [string]$step.Label, $code) -Level "error"
    }
    else {
        Write-WinToolLog -Message ("{0}: done." -f [string]$step.Label) -Level "ok"
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
    if ($Message -eq "Cancelled.") {
        Sync-WinToolProgress -Value 0 -Text "Cancelled" -Indeterminate $false
        Write-WinToolLog -Message $Message -Level "warn"
    }
    else {
        Sync-WinToolProgress -Value 100 -Text "Ready" -Indeterminate $false
        Write-WinToolLog -Message $Message -Level "ok"
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
                if (-not $run.Process.HasExited) {
                    $run.Process.Kill()
                }
            }
            catch {
                Complete-WinToolPlan -Message "Cancelled."
            }
        }
        else {
            Complete-WinToolPlan -Message "Cancelled."
        }
        return
    }
    foreach ($name in @("RestoreJob", "UpdateJob", "InstallJob")) {
        $job = $script:WinToolState[$name]
        if ($null -ne $job) {
            Stop-WinToolThread -Job $job
            $script:WinToolState[$name] = $null
        }
    }
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text "Cancelled" -Indeterminate $false
    Write-WinToolLog -Message "Cancelled." -Level "warn"
}

function Update-WinToolLogPump {
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

    $featureJob = $script:WinToolState.FeatureJob
    if ($null -ne $featureJob -and $featureJob.Sync.Done) {
        Complete-WinToolFeatureDetection
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

    if ($script:WinToolTerminalScrollPending -and (Get-WinToolUi -Name "ViewTerminal").IsVisible) {
        Show-WinToolTerminalSelection
    }

    $preview = $script:WinToolState.PreviewJob
    if ($null -ne $preview -and $preview.Job.Sync.Done) {
        Complete-WinToolPreviewThemeDownload
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
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ClearLogButton") -EventName "Click" -Name "Clear log" -Action {
        (Get-WinToolUi -Name "LogBox").Clear()
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ToggleLogButton") -EventName "Click" -Name "Show log" -Action {
        Switch-WinToolLogPanel
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
            if ((Get-WinToolUi -Name "ViewInstall").Visibility -eq "Visible") {
                (Get-WinToolUi -Name "AppSearch").Focus() | Out-Null
            }
            elseif ((Get-WinToolUi -Name "ViewTweaks").Visibility -eq "Visible") {
                (Get-WinToolUi -Name "TweakSearch").Focus() | Out-Null
            }
            $uiEvent.Handled = $true
        }
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Closing" -Name "Close WinTool" -Action {
        $uiEvent = $args[1]
        if ($script:WinToolState.Busy) {
            $ok = Request-WinToolConfirmation -Message "A task is still running. Stop it and close WinTool?" -Title "WinTool is busy"
            if (-not $ok) {
                $uiEvent.Cancel = $true
                return
            }
            Stop-WinToolRun
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
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Loaded" -Name "Check installed apps" -Action {
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
        UpdateMode = ""
        UpdateModeCurrent = ""
        UpdateModeRadios = @()
        DnsAdapters = @()
        SystemChecked = $false
        Run = $null
        Pump = $null
        RestoreJob = $null
        UpdateJob = $null
        InstallJob = $null
        DetectJob = $null
        PreviewJob = $null
        BusyControls = $null
        FeatureJob = $null
        FeatureRows = @()
        TweakQueue = $null
        TweakStateRead = $false
        TweakTwoColumns = $true
        TweakColumns = 3
        TweakWidth = 0
        AppColumns = 5
        RestorePointDone = $false
        AppFilter = "all"
        AppStartApps = @()
        AppCardAction = $null
        LogExpanded = $false
        LogPinned = $false
    }

    $xaml = Get-WinToolPayloadText -Name "Xaml"
    [xml]$document = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $document
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:WinToolWindow = $window
    $script:WinToolLogBox = $window.FindName("LogBox")

    Initialize-WinToolAppearance
    Initialize-WinToolInstallView
    Initialize-WinToolTweakView
    Initialize-WinToolTerminalView
    Initialize-WinToolUpdateView
    Initialize-WinToolFixView
    Initialize-WinToolFeatureView
    Initialize-WinToolConfigView
    Initialize-WinToolShellEvent
    Sync-WinToolLogPanel
    Register-WinToolUiEvent -Control $window -EventName "Activated" -Name "Follow the Windows theme" -Action {
        if ($null -eq $script:WinToolSetting) { return }
        if ([string]$script:WinToolSetting.theme -ne "system") { return }
        $want = "dark"
        if (Test-WinToolSystemLightTheme) { $want = "light" }
        if ([string]$script:WinToolResolvedTheme -ne $want) {
            Set-WinToolTheme -Theme "system" -Accent ([string]$script:WinToolSetting.accent)
        }
    }

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
    if ($null -ne $script:WinToolState.Pump) {
        try { $script:WinToolState.Pump.Stop() } catch { $null = $_.Exception.Message }
        $script:WinToolState.Pump = $null
    }
    $run = $script:WinToolState.Run
    if ($null -ne $run -and $null -ne $run.Process) {
        try { if (-not $run.Process.HasExited) { $run.Process.Kill() } } catch { $null = $_.Exception.Message }
    }
    $script:WinToolState.Run = $null
    foreach ($key in @($script:WinToolState.Keys)) {
        $value = $script:WinToolState[$key]
        if ($null -ne $value -and $null -ne $value.PSObject -and $null -ne $value.PSObject.Properties["Runspace"]) {
            # Asynchronous stop: a runspace still waiting on winget must not
            # hold the window open while it closes.
            try { $null = $value.PowerShell.BeginStop($null, $null) } catch { $null = $_.Exception.Message }
            try { $value.Runspace.CloseAsync() } catch { $null = $_.Exception.Message }
            $script:WinToolState[$key] = $null
        }
    }
    try { Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue } catch { $null = $_.Exception.Message }
}

function Stop-WinToolChildProcess {
    # Ends what this process started (winget, installers, helpers), children
    # first. conhost.exe is the console itself and is left alone.
    param([int]$ParentId = $PID)
    $children = @()
    try { $children = @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = {0}" -f $ParentId) -ErrorAction Stop) }
    catch { return }
    foreach ($child in $children) {
        if ([string]$child.Name -eq "conhost.exe") { continue }
        Stop-WinToolChildProcess -ParentId ([int]$child.ProcessId)
        try { Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction Stop } catch { $null = $_.Exception.Message }
    }
}

function Enter-WinToolSingleInstance {
    # One WinTool window per session. A second launch brings the first window
    # to the front and leaves.
    $created = $false
    try {
        $script:WinToolMutex = [System.Threading.Mutex]::new($true, "Local\WinTool.Hinrikao.Window", [ref]$created)
    }
    catch {
        $script:WinToolMutex = $null
        $created = $false
    }
    if ($created) { return $true }
    if ($null -ne $script:WinToolMutex) {
        $script:WinToolMutex.Dispose()
        $script:WinToolMutex = $null
    }
    if (Initialize-WinToolConsoleApi) {
        try {
            $handle = [WinToolConsoleApi]::FindWindow($null, "WinTool")
            if ($handle -ne [IntPtr]::Zero) {
                $null = [WinToolConsoleApi]::ShowWindow($handle, 9)
                $null = [WinToolConsoleApi]::SetForegroundWindow($handle)
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    Write-Host "WinTool is already open. Its window was brought to the front."
    return $false
}

function Exit-WinToolSingleInstance {
    if ($null -eq $script:WinToolMutex) { return }
    try { $script:WinToolMutex.ReleaseMutex() } catch { $null = $_.Exception.Message }
    try { $script:WinToolMutex.Dispose() } catch { $null = $_.Exception.Message }
    $script:WinToolMutex = $null
}

function Show-WinToolWindow {
    if (-not (Enter-WinToolSingleInstance)) {
        Exit-WinToolOwnedHost
        return
    }
    $closedNormally = $false
    try {
        $window = New-WinToolWindow
        Enable-WinToolLogPump
        Register-WinToolUiEvent -Control $window -EventName "ContentRendered" -Name "Hide the console" -Action { Hide-WinToolConsole }
        $null = $window.ShowDialog()
        $closedNormally = $true
    }
    finally {
        Stop-WinToolBackgroundWork
        Exit-WinToolSingleInstance
        # Give a console the user opened back to them. A hidden relaunch is
        # WinTool's own process: end it and everything it started, so no
        # hidden powershell.exe is left behind.
        # After a startup error the failure screen runs first and exits itself.
        if ($closedNormally -and (Test-WinToolOwnedHost)) {
            Stop-WinToolChildProcess
            [Environment]::Exit(0)
        }
        if ($script:WinToolConsoleHidden) {
            $null = Set-WinToolConsoleVisible -Visible $true
        }
    }
}
