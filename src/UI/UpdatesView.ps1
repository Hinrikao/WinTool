# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolUpdateView {
    $catalog = Get-WinToolUpdateCatalog
    $gpus = @(Get-WinToolGpuInfo)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($gpu in $gpus) {
        $vendor = Resolve-WinToolGpuVendor -Name ([string]$gpu.Name) -Vendor @(Get-WinToolNote -Object $catalog -Name "vendors" -Default @())
        $text = [string]$gpu.Name
        if (-not [string]::IsNullOrWhiteSpace([string]$gpu.DriverVersion)) {
            $text = "{0}  (driver {1})" -f $text, $gpu.DriverVersion
        }
        if ($null -ne $vendor) {
            $text = "{0}  -  {1}" -f $text, [string]$vendor.name
        }
        $lines.Add($text)
    }
    $summary = "Windows did not report a graphics adapter."
    if ($lines.Count -gt 0) {
        $summary = $lines -join [Environment]::NewLine
    }
    (Get-WinToolUi -Name "GpuSummary").Text = $summary

    $panel = Get-WinToolUi -Name "VendorLinks"
    $panel.Children.Clear()
    foreach ($vendor in @(Get-WinToolNote -Object $catalog -Name "vendors" -Default @())) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = [string]$vendor.name + " downloads"
        $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $button.Tag = [string]$vendor.url
        $button.ToolTip = [string](Get-WinToolNote -Object $vendor -Name "note" -Default "")
        $button.Add_Click({
            Open-WinToolUri -Uri ([string]$args[0].Tag)
        })
        [void]$panel.Children.Add($button)
    }

    (Get-WinToolUi -Name "ScanDrivers").Add_Click({ Invoke-WinToolScanClick })
    (Get-WinToolUi -Name "OpenWindowsUpdate").Add_Click({ Open-WinToolUri -Uri "ms-settings:windowsupdate" })
    (Get-WinToolUi -Name "OpenOptionalUpdates").Add_Click({ Open-WinToolUri -Uri "ms-settings:windowsupdate-optionalupdates" })
    (Get-WinToolUi -Name "InstallScannedUpdates").Add_Click({ Invoke-WinToolInstallUpdatesClick })
}

function Invoke-WinToolScanClick {
    $criteria = "IsInstalled=0 and Type='Driver'"
    if ((Get-WinToolUi -Name "IncludeSoftwareUpdates").IsChecked -eq $true) {
        $criteria = "IsInstalled=0"
    }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Scanning Windows Update" -Indeterminate $true
    Write-WinToolLog -Message "Scanning Windows Update. This can take a few minutes." -Level "info"
    $script:WinToolState.UpdateJob = Start-WinToolScriptJob -ScriptText (Get-WinToolUpdateSearchScript) -Argument @($criteria)
}

function Complete-WinToolUpdateScan {
    $job = $script:WinToolState.UpdateJob
    $ok = $false
    $errorMessage = ""
    $lines = @()
    if ($null -ne $job) {
        $ok = [bool]$job.Sync.Ok
        $errorMessage = [string]$job.Sync.Error
        $lines = @($job.Sync.Lines)
        Stop-WinToolThread -Job $job
    }
    $script:WinToolState.UpdateJob = $null
    if (-not $ok) {
        Sync-WinToolBusyState -Busy $false
        Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
        Write-WinToolLog -Message ("Windows Update scan failed. {0}" -f $errorMessage) -Level "error"
        return
    }

    $list = Get-WinToolUi -Name "UpdateList"
    $list.Items.Clear()
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
        $text = [string]$line
        $index = $text.IndexOf("`t")
        if ($index -lt 1) {
            continue
        }
        $kind = $text.Substring(0, $index)
        $title = $text.Substring($index + 1)
        $records.Add([pscustomobject]@{
            Kind = $kind
            Title = $title
        })
        [void]$list.Items.Add(("{0}   {1}" -f $kind, $title))
    }
    $script:WinToolState.Updates = $records.ToArray()
    $empty = Get-WinToolUi -Name "UpdateEmpty"
    if ($records.Count -eq 0) {
        $empty.Text = "Windows Update did not offer anything for this scan."
        $empty.Visibility = "Visible"
        Write-WinToolLog -Message "Scan finished. No updates were offered." -Level "ok"
    }
    else {
        $empty.Visibility = "Collapsed"
        Write-WinToolLog -Message ("Scan finished. {0} update(s) listed." -f $records.Count) -Level "ok"
    }
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 100 -Text "Scan finished" -Indeterminate $false
}

function Invoke-WinToolInstallUpdatesClick {
    $updates = @($script:WinToolState.Updates)
    if ($updates.Count -eq 0) {
        Write-WinToolLog -Message "Scan for updates before installing them." -Level "warn"
        return
    }
    $ok = Request-WinToolConfirmation -Message ("Download and install {0} Windows Update item(s)? The PC may need a restart." -f $updates.Count) -Title "Install updates"
    if (-not $ok) {
        return
    }
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($item in $updates) {
        $titles.Add([string]$item.Title)
    }
    $criteria = "IsInstalled=0 and Type='Driver'"
    if ((Get-WinToolUi -Name "IncludeSoftwareUpdates").IsChecked -eq $true) {
        $criteria = "IsInstalled=0"
    }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Installing Windows updates" -Indeterminate $true
    Write-WinToolLog -Message "Downloading and installing the scanned updates." -Level "info"
    $script:WinToolState.InstallJob = Start-WinToolScriptJob -ScriptText (Get-WinToolUpdateInstallScript) -Argument @($criteria, ($titles -join "`n"))
}

function Complete-WinToolUpdateInstall {
    $job = $script:WinToolState.InstallJob
    $ok = $false
    $errorMessage = ""
    $count = 0
    $reboot = $false
    if ($null -ne $job) {
        $ok = [bool]$job.Sync.Ok
        $errorMessage = [string]$job.Sync.Error
        if ($null -ne $job.Sync.Count) { $count = [int]$job.Sync.Count }
        if ($null -ne $job.Sync.Reboot) { $reboot = [bool]$job.Sync.Reboot }
        Stop-WinToolThread -Job $job
    }
    $script:WinToolState.InstallJob = $null
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
    if (-not $ok) {
        Write-WinToolLog -Message ("Update install failed. {0}" -f $errorMessage) -Level "error"
        return
    }
    if ($count -eq 0) {
        Write-WinToolLog -Message "Those updates were no longer offered when the install started." -Level "warn"
        return
    }
    Write-WinToolLog -Message ("Finished installing {0} update(s)." -f $count) -Level "ok"
    if ($reboot) {
        Write-WinToolLog -Message "Windows asked for a restart to finish the updates." -Level "warn"
    }
}
