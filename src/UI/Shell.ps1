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

function Switch-WinToolView {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    foreach ($view in @("Install", "Tweaks", "Terminal", "Updates", "Config")) {
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

function Sync-WinToolBusyState {
    param(
        [bool]$Busy
    )
    $script:WinToolState.Busy = $Busy
    $names = @(
        "AppInstall", "AppSelectVisible", "AppClear",
        "TweakApply", "TweakUndo", "TweakClear",
        "TerminalSetup", "ScanDrivers",
        "SaveProfile", "LoadProfile", "ExportWinget", "ImportWinget"
    )
    foreach ($name in $names) {
        (Get-WinToolUi -Name $name).IsEnabled = -not $Busy
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
    $timer.Add_Tick({ Update-WinToolLogPump })
    $timer.Start()
    $script:WinToolState.Pump = $timer
}

function Invoke-WinToolPlanAsync {
    param(
        $Step,
        [Parameter(Mandatory = $true)][string]$DoneMessage
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
            Write-WinToolLog -Message ("{0}: already installed." -f [string]$step.Label) -Level "ok"
        }
        else {
            Write-WinToolLog -Message ("{0}: done." -f [string]$step.Label) -Level "ok"
        }
    }
    elseif ($code -ne 0) {
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
                $clean = $line.Trim()
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

    $install = $script:WinToolState.InstallJob
    if ($null -ne $install -and $install.Sync.Done) {
        Complete-WinToolUpdateInstall
    }
}

function Initialize-WinToolShellEvent {
    (Get-WinToolUi -Name "VersionText").Text = "Version " + $script:WinToolVersion
    (Get-WinToolUi -Name "NavInstall").Add_Checked({ Switch-WinToolView -Name "Install" })
    (Get-WinToolUi -Name "NavTweaks").Add_Checked({ Switch-WinToolView -Name "Tweaks" })
    (Get-WinToolUi -Name "NavTerminal").Add_Checked({ Switch-WinToolView -Name "Terminal" })
    (Get-WinToolUi -Name "NavUpdates").Add_Checked({ Switch-WinToolView -Name "Updates" })
    (Get-WinToolUi -Name "NavConfig").Add_Checked({ Switch-WinToolView -Name "Config" })
    (Get-WinToolUi -Name "ClearLogButton").Add_Click({
        (Get-WinToolUi -Name "LogBox").Clear()
    })
    (Get-WinToolUi -Name "CancelRun").Add_Click({
        Stop-WinToolRun
    })
    (Get-WinToolUi -Name "ProjectLink").Add_RequestNavigate({
        $uiEvent = $args[1]
        if ($null -ne $uiEvent -and $null -ne $uiEvent.Uri) {
            Open-WinToolUri -Uri $uiEvent.Uri.AbsoluteUri
            $uiEvent.Handled = $true
        }
    })
    $script:WinToolWindow.Add_PreviewKeyDown({
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
    })
    $script:WinToolWindow.Add_Closing({
        $uiEvent = $args[1]
        if ($script:WinToolState.Busy) {
            $ok = Request-WinToolConfirmation -Message "A task is still running. Stop it and close WinTool?" -Title "WinTool is busy"
            if (-not $ok) {
                $uiEvent.Cancel = $true
                return
            }
            Stop-WinToolRun
        }
    })
    $script:WinToolWindow.Add_Closed({
        if ($null -ne $script:WinToolState.Pump) {
            $script:WinToolState.Pump.Stop()
        }
    })
    $script:WinToolWindow.Add_Loaded({
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
    })
}

function Show-WinToolWindow {
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
        Run = $null
        Pump = $null
        RestoreJob = $null
        UpdateJob = $null
        InstallJob = $null
        PendingTweaks = @()
        PendingDirection = "Apply"
        PendingRestart = $true
    }

    $xaml = Get-WinToolPayloadText -Name "Xaml"
    [xml]$document = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $document
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $script:WinToolWindow = $window
    $script:WinToolLogBox = $window.FindName("LogBox")

    Initialize-WinToolInstallView
    Initialize-WinToolTweakView
    Initialize-WinToolTerminalView
    Initialize-WinToolUpdateView
    Initialize-WinToolConfigView
    Initialize-WinToolShellEvent
    Enable-WinToolLogPump

    if (-not [string]::IsNullOrWhiteSpace($script:WinToolApplyProfile)) {
        try {
            Import-WinToolProfileToUi -Path $script:WinToolApplyProfile
        }
        catch {
            Write-WinToolLog -Message ("Could not load the profile. {0}" -f $_.Exception.Message) -Level "error"
        }
    }

    $null = $window.ShowDialog()
}
