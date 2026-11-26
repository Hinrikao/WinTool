# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Invoke-WinToolUnattended {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    Write-WinToolLog -Message (Get-WinToolText "msg.wintool-unattended-profile-n" $Path) -Level "info"
    $toolProfile = Read-WinToolProfile -Path $Path
    $resolved = Resolve-WinToolProfileSelection -Profile $toolProfile
    foreach ($id in @($resolved.UnknownApps)) {
        Write-WinToolLog -Message (Get-WinToolText "msg.unknown-app-id-n-in-the-profile" $id) -Level "warn"
    }
    foreach ($id in @($resolved.UnknownTweaks)) {
        Write-WinToolLog -Message (Get-WinToolText "msg.unknown-tweak-id-n-in-the-profile" $id) -Level "warn"
    }

    $tweakRecords = @($resolved.TweakRecords)
    if ($tweakRecords.Count -gt 0) {
        Write-WinToolLog -Message (Get-WinToolText "msg.creating-a-restore-point-before-tweaks") -Level "info"
        Invoke-WinToolRestorePoint -Description (Get-WinToolText "msg.wintool-unattended-tweaks")
        Write-WinToolLog -Message (Get-WinToolText "drivers.restore.created") -Level "ok"
        Invoke-WinToolTweakChange -Tweak $tweakRecords -Direction "Apply" -RestartExplorer $true
    }

    $terminal = Get-WinToolNote -Object $toolProfile -Name "terminal"
    $terminalEnabled = $false
    if ($null -ne $terminal) {
        $terminalEnabled = [bool](Get-WinToolNote -Object $terminal -Name "enabled" -Default $false)
    }
    if ($terminalEnabled) {
        $terminalPlan = @(Get-WinToolTerminalPlan -Selection $terminal)
        Invoke-WinToolPlan -Step $terminalPlan
    }

    $appRecords = @($resolved.AppRecords)
    if ($appRecords.Count -gt 0) {
        $appPlan = @(Get-WinToolAppPlan -App $appRecords)
        Invoke-WinToolPlan -Step $appPlan
    }
    Write-WinToolLog -Message (Get-WinToolText "msg.unattended-setup-finished") -Level "ok"
}

function Start-WinTool {
    try {
        if ($null -eq $script:WinToolStartupStamp) {
            $script:WinToolStartupStamp = [System.Diagnostics.Stopwatch]::StartNew()
        }
        $t0 = [string]$env:WINTOOL_LAUNCH_T0
        if (-not [string]::IsNullOrWhiteSpace($t0)) {
            try {
                $started = [datetime]::SpecifyKind((New-Object datetime ([int64]$t0)), [datetimekind]::Utc)
                Write-WinToolStartupMark -Name "parseMs" -Started $started.ToLocalTime()
            }
            catch {
                $null = $_.Exception.Message
            }
        }
        if ($env:WINTOOL_HELPER -eq "1") {
            Invoke-WinToolElevatedHelperHost
            return
        }
        if (-not (Test-WinToolWindows)) {
            throw (Get-WinToolText "error.windows11")
        }
        if (-not (Test-WinToolIsPowerShell7)) {
            Invoke-WinToolPowerShell7Handoff
            return
        }
        if (-not $script:WinToolUnattended -and (Test-WinToolAlreadyRunning)) {
            Write-Host (Get-WinToolText "error.alreadyOpen")
            # A hidden second launch must not leave its console to appear as
            # this process exits. A console the user can see stays as it is.
            if ((Get-WinToolCurrentConsoleMode) -eq "hide" -and -not (Test-WinToolConsoleIsVisible)) {
                Remove-WinToolHiddenConsole
            }
            Exit-WinToolOwnedHost
            return
        }
        if ((Test-WinToolElevateAtStart) -and -not (Test-WinToolAdministrator)) {
            Request-WinToolAdministrator
            return
        }

        $apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        if ($apartment -ne "STA" -and -not $script:WinToolUnattended) {
            if ($env:WINTOOL_STA_RELAUNCHED -eq "1") {
                throw (Get-WinToolText "error.staUnavailable")
            }
            $env:WINTOOL_STA_RELAUNCHED = "1"
            Request-WinToolStaHost
            return
        }

        if (Test-WinToolCurrentShouldDetachHost) {
            # Open the window in a detached hidden console and give this
            # terminal back immediately. No UAC at start unless requested.
            Start-WinToolRelaunch
            return
        }

        if ($script:WinToolUnattended) {
            if ([string]::IsNullOrWhiteSpace($script:WinToolApplyProfile)) {
                throw (Get-WinToolText "error.unattendedProfile")
            }
            Invoke-WinToolUnattended -Path $script:WinToolApplyProfile
            return
        }

        # Hide the console before the catalogs and XAML load, so it does not
        # stay on screen while the window is built. Errors bring it back.
        if ((Get-WinToolCurrentConsoleMode) -eq "hide") {
            Hide-WinToolConsole
        }
        Show-WinToolWindow
    }
    catch {
        Show-WinToolFailure -ErrorRecord $_
    }
}
