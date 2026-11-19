# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Invoke-WinToolUnattended {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    Write-WinToolLog -Message "WinTool unattended profile: $Path" -Level "info"
    $toolProfile = Read-WinToolProfile -Path $Path
    $resolved = Resolve-WinToolProfileSelection -Profile $toolProfile
    foreach ($id in @($resolved.UnknownApps)) {
        Write-WinToolLog -Message "Unknown app id '$id' in the profile." -Level "warn"
    }
    foreach ($id in @($resolved.UnknownTweaks)) {
        Write-WinToolLog -Message "Unknown tweak id '$id' in the profile." -Level "warn"
    }

    $tweakRecords = @($resolved.TweakRecords)
    if ($tweakRecords.Count -gt 0) {
        Write-WinToolLog -Message "Creating a restore point before tweaks." -Level "info"
        Invoke-WinToolRestorePoint -Description "WinTool unattended tweaks"
        Write-WinToolLog -Message "Restore point created." -Level "ok"
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
    Write-WinToolLog -Message "Unattended setup finished." -Level "ok"
}

function Start-WinTool {
    if (-not (Test-WinToolWindows)) {
        throw "WinTool only runs on Windows 11."
    }
    if (-not (Test-WinToolAdministrator)) {
        Request-WinToolAdministrator
        return
    }

    $apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
    if ($apartment -ne "STA" -and -not $script:WinToolUnattended) {
        if ($env:WINTOOL_STA_RELAUNCHED -eq "1") {
            throw "WinTool could not start a window because STA mode was not available."
        }
        $env:WINTOOL_STA_RELAUNCHED = "1"
        Request-WinToolStaHost
        return
    }

    if ($script:WinToolUnattended) {
        if ([string]::IsNullOrWhiteSpace($script:WinToolApplyProfile)) {
            throw "Unattended mode needs -ApplyProfile with a path to a WinTool JSON profile."
        }
        Invoke-WinToolUnattended -Path $script:WinToolApplyProfile
        return
    }

    try {
        Show-WinToolWindow
    }
    catch {
        $message = $_.Exception.Message
        Write-Host "WinTool could not start: $message"
        try {
            Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
            [System.Windows.MessageBox]::Show($message, "WinTool") | Out-Null
        }
        catch {
            Write-Host $message
        }
        throw
    }
}
