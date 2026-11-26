# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Select-WinToolFolder {
    param(
        [string]$Description = "Choose a folder"
    )
    if ($script:WinToolUiQuiet) {
        return $null
    }
    try {
        $null = [System.Windows.Forms.FolderBrowserDialog]
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
    }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }
    $path = [string]$dialog.SelectedPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }
    return $path
}

function Test-WinToolDriverAdminReady {
    if (Test-WinToolAdministrator) {
        return $true
    }
    Write-WinToolLog -Message "This action needs administrator approval. WinTool will ask Windows to reopen the window elevated." -Level "warn"
    Request-WinToolAdministrator
    return $false
}

function Initialize-WinToolDriverView {
    $script:WinToolState.DriverRows = @()
    $script:WinToolState.DriverDevices = @()
    $script:WinToolState.DriverUpdates = @()
    $script:WinToolState.DriverDisplays = @()
    $script:WinToolState.DriverTools = @{}
    $script:WinToolState.DriverScanned = $false
    $script:WinToolState.DriverCurrentBuilt = $false
    $script:WinToolState.DriverHvci = $false
    $script:WinToolState.DriverInfo = $null
    $script:WinToolState.DriverPending = $null
    $script:WinToolState.DriverToolKind = ""
    $script:WinToolState.DriverSyncing = $false

    (Get-WinToolUi -Name "DriversStart").Visibility = "Visible"
    (Get-WinToolUi -Name "DriversResult").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversHeader").Text = ""
    (Get-WinToolUi -Name "DriversInfoText").Text = "Hardware details appear here after this page is opened."

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversScan") -EventName "Click" -Name "Drivers: scan" -Action { Invoke-WinToolDriverScanClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversScanAgain") -EventName "Click" -Name "Drivers: scan again" -Action { Invoke-WinToolDriverScanClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversUpdate") -EventName "Click" -Name "Drivers: update now" -Action { Invoke-WinToolDriverUpdateClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversBackup") -EventName "Click" -Name "Drivers: back up" -Action { Invoke-WinToolDriverBackupClick }

    foreach ($name in @("DriversScan", "DriversScanAgain", "DriversUpdate", "DriversBackup")) {
        Add-WinToolBusyControl -Control (Get-WinToolUi -Name $name)
    }

    Initialize-WinToolDriverToolList
}

function Initialize-WinToolDriverToolList {
    $hostPanel = Get-WinToolUi -Name "DriversToolList"
    $hostPanel.Children.Clear()
    $tools = @(
        [pscustomobject]@{ Id = "backup"; Glyph = [char]0xE8C8; Name = "Back up and restore drivers"; Description = "Export the drivers now on this PC, or install from a folder you backed up earlier."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "audio"; Glyph = [char]0xE767; Name = "Repair audio"; Description = "Restart the Windows audio services, re-enable disabled playback devices, and open the audio troubleshooter."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "problem"; Glyph = [char]0xE7BA; Name = "Fix devices with a problem code"; Description = "List devices that Windows has marked with a problem code, rescan the hardware, or disable and enable them."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "ghost"; Glyph = [char]0xE74D; Name = "Remove leftover device entries"; Description = "Remove device entries that are no longer present. This asks first and creates a restore point when it can."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "network"; Glyph = [char]0xE774; Name = "Repair the network"; Description = "Reset Winsock and the TCP/IP stack, flush DNS, renew the address, and restart adapters. The PC needs a restart afterwards."; Badge = "Restart needed"; Restart = $true }
        [pscustomobject]@{ Id = "display"; Glyph = [char]0xE7F4; Name = "Check display resolution"; Description = "Show the current display and recommend the preferred resolution and an official graphics driver update when one would help."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "runtime"; Glyph = [char]0xE7FC; Name = "Repair game runtimes"; Description = "Install or repair Visual C++ redistributables, the DirectX runtime, XNA, and OpenAL with winget."; Badge = ""; Restart = $false }
        [pscustomobject]@{ Id = "incompatible"; Glyph = [char]0xE730; Name = "Review incompatible drivers"; Description = "Flag drivers that failed to load or that Memory Integrity may have blocked."; Badge = ""; Restart = $false }
    )
    $index = 0
    $map = @{}
    foreach ($tool in $tools) {
        $card = New-WinToolCard
        $card.CornerRadius = [System.Windows.CornerRadius]::new(16)
        $card.Padding = [System.Windows.Thickness]::new(18)
        $card.MinHeight = 180
        $gapLeft = 0
        $gapTop = 0
        if (($index % 2) -ne 0) { $gapLeft = 14 }
        if ($index -ge 2) { $gapTop = 14 }
        $card.Margin = [System.Windows.Thickness]::new($gapLeft, $gapTop, 0, 0)
        $grid = New-Object System.Windows.Controls.Grid
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(32) }))
        $titleRow = New-Object System.Windows.Controls.DockPanel
        $glyph = New-WinToolText -Text ([string]$tool.Glyph) -Weight "Normal"
        $glyph.FontFamily = (New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets"))
        $glyph.FontSize = 18
        $glyph.VerticalAlignment = "Center"
        $glyph.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        [System.Windows.Controls.DockPanel]::SetDock($glyph, "Left")
        [void]$titleRow.Children.Add($glyph)
        $badgeHost = New-Object System.Windows.Controls.StackPanel
        $badgeHost.Orientation = "Horizontal"
        $badgeHost.VerticalAlignment = "Center"
        [System.Windows.Controls.DockPanel]::SetDock($badgeHost, "Right")
        [void]$titleRow.Children.Add($badgeHost)
        $title = New-WinToolText -Text ([string]$tool.Name) -Weight "Bold"
        $title.VerticalAlignment = "Center"
        $title.TextWrapping = "Wrap"
        [void]$titleRow.Children.Add($title)
        [void]$grid.Children.Add($titleRow)
        $description = New-WinToolText -Text ([string]$tool.Description) -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 8, 0, 8))
        [System.Windows.Controls.Grid]::SetRow($description, 1)
        [void]$grid.Children.Add($description)
        $foot = New-Object System.Windows.Controls.StackPanel
        $foot.Orientation = "Horizontal"
        $foot.HorizontalAlignment = "Right"
        [System.Windows.Controls.Grid]::SetRow($foot, 2)
        $buttons = Get-WinToolDriverToolButton -Id ([string]$tool.Id)
        foreach ($entry in @($buttons)) {
            $button = New-Object System.Windows.Controls.Button
            $button.Content = [string]$entry.Label
            $button.MinWidth = 96
            $button.Height = 32
            $button.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
            $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
            $button.VerticalAlignment = "Center"
            $actionId = [string]$entry.Action
            Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: " + [string]$entry.Label) -Data $actionId -Action {
                param($source, $eventData, $boundAction)
                $null = $source, $eventData
                Invoke-WinToolDriverToolClick -Action $boundAction
            }
            Add-WinToolBusyControl -Control $button
            [void]$foot.Children.Add($button)
        }
        [void]$grid.Children.Add($foot)
        $card.Child = $grid
        [void]$hostPanel.Children.Add($card)
        $map[[string]$tool.Id] = [pscustomobject]@{
            Card        = $card
            Description = $description
            BadgeHost   = $badgeHost
            Restart     = [bool]$tool.Restart
        }
        $index++
    }
    $script:WinToolState.DriverTools = $map
}

function Get-WinToolDriverToolButton {
    param([string]$Id)
    switch ($Id) {
        "backup" { return @(
                [pscustomobject]@{ Label = "Back up"; Action = "backup" },
                [pscustomobject]@{ Label = "Install from folder"; Action = "offline" }
            ) }
        "audio" { return @([pscustomobject]@{ Label = "Repair audio"; Action = "audio" }) }
        "problem" { return @(
                [pscustomobject]@{ Label = "Enable"; Action = "enable" },
                [pscustomobject]@{ Label = "Disable"; Action = "disable" },
                [pscustomobject]@{ Label = "Rescan"; Action = "rescan" }
            ) }
        "ghost" { return @([pscustomobject]@{ Label = "Remove entries"; Action = "ghost" }) }
        "network" { return @([pscustomobject]@{ Label = "Repair network"; Action = "network" }) }
        "display" { return @([pscustomobject]@{ Label = "Check display"; Action = "display" }) }
        "runtime" { return @([pscustomobject]@{ Label = "Repair runtimes"; Action = "runtime" }) }
        "incompatible" { return @([pscustomobject]@{ Label = "Show details"; Action = "incompatible" }) }
    }
    return @()
}

function Set-WinToolDriverToolBadge {
    param(
        [string]$Id,
        [string]$Text,
        [string]$Kind = "ok"
    )
    $map = $script:WinToolState.DriverTools
    if ($null -eq $map -or -not $map.ContainsKey($Id)) {
        return
    }
    $hostPanel = $map[$Id].BadgeHost
    $hostPanel.Children.Clear()
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }
    $badge = New-WinToolBadge -Text $Text -Kind $Kind
    $badge.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [void]$hostPanel.Children.Add($badge)
}

function Sync-WinToolDriverToolCount {
    $scanned = [bool]$script:WinToolState.DriverScanned
    $devices = @($script:WinToolState.DriverDevices)
    $map = $script:WinToolState.DriverTools
    if ($null -eq $map) { return }

    if ($scanned) {
        $problem = @(Get-WinToolDriverProblemDevice -Device $devices)
        $ghost = @(Get-WinToolDriverGhostDevice -Device $devices)
        $incompatible = @(Get-WinToolDriverIncompatibleDevice -Device $devices -MemoryIntegrity ([bool]$script:WinToolState.DriverHvci))
        $problemText = "0 devices"
        if ($problem.Count -eq 1) { $problemText = "1 device" }
        elseif ($problem.Count -gt 1) { $problemText = ("{0} devices" -f $problem.Count) }
        Set-WinToolDriverToolBadge -Id "problem" -Text $problemText -Kind $(if ($problem.Count -gt 0) { "caution" } else { "ok" })
        $ghostText = "0 entries"
        if ($ghost.Count -eq 1) { $ghostText = "1 entry" }
        elseif ($ghost.Count -gt 1) { $ghostText = ("{0} entries" -f $ghost.Count) }
        Set-WinToolDriverToolBadge -Id "ghost" -Text $ghostText -Kind $(if ($ghost.Count -gt 0) { "caution" } else { "ok" })
        $incompatText = "0 drivers"
        if ($incompatible.Count -eq 1) { $incompatText = "1 driver" }
        elseif ($incompatible.Count -gt 1) { $incompatText = ("{0} drivers" -f $incompatible.Count) }
        Set-WinToolDriverToolBadge -Id "incompatible" -Text $incompatText -Kind $(if ($incompatible.Count -gt 0) { "caution" } else { "ok" })
        $runtimeNeed = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime" })
        if (@($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime-pending" }).Count -gt 0) {
            Set-WinToolDriverToolBadge -Id "runtime" -Text "" -Kind "ok"
        }
        else {
            $runtimeText = "0 needed"
            if ($runtimeNeed.Count -eq 1) { $runtimeText = "1 needed" }
            elseif ($runtimeNeed.Count -gt 1) { $runtimeText = ("{0} needed" -f $runtimeNeed.Count) }
            Set-WinToolDriverToolBadge -Id "runtime" -Text $runtimeText -Kind $(if ($runtimeNeed.Count -gt 0) { "caution" } else { "ok" })
        }
        $displays = @($script:WinToolState.DriverDisplays)
        if ($displays.Count -eq 1) {
            $item = $displays[0]
            $width = [int](Get-WinToolNote -Object $item -Name "Width" -Default 0)
            $height = [int](Get-WinToolNote -Object $item -Name "Height" -Default 0)
            if ($width -gt 0 -and $height -gt 0) {
                Set-WinToolDriverToolBadge -Id "display" -Text ("{0} x {1}" -f $width, $height) -Kind "ok"
            }
        }
        elseif ($displays.Count -gt 1) {
            Set-WinToolDriverToolBadge -Id "display" -Text ("{0} displays" -f $displays.Count) -Kind "ok"
        }
    }

    if ($map.ContainsKey("network") -and [bool]$map["network"].Restart) {
        Set-WinToolDriverToolBadge -Id "network" -Text "Restart needed" -Kind "caution"
    }

    if ($null -ne $script:WinToolState.DriverInfo) {
        (Get-WinToolUi -Name "DriversInfoText").Text = (Format-WinToolMachineSummary -Info $script:WinToolState.DriverInfo)
    }
}

function Start-WinToolDriverInfoJob {
    if ($script:WinToolShuttingDown) { return }
    if ($null -ne $script:WinToolState.DriverInfoJob) { return }
    if ($null -ne $script:WinToolState.DriverInfo) { return }
    $script:WinToolState.DriverInfoJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverInfoScript)
}

function Complete-WinToolDriverInfo {
    $job = $script:WinToolState.DriverInfoJob
    if ($null -eq $job) { return }
    $ok = [bool]$job.Sync.Ok
    $info = $job.Sync.Info
    Stop-WinToolThread -Job $job
    $script:WinToolState.DriverInfoJob = $null
    if ($ok -and $null -ne $info) {
        $script:WinToolState.DriverInfo = $info
        (Get-WinToolUi -Name "DriversInfoText").Text = (Format-WinToolMachineSummary -Info $info)
    }
    elseif (-not $ok) {
        (Get-WinToolUi -Name "DriversInfoText").Text = "Could not read system information."
    }
}

function Invoke-WinToolDriverScanClick {
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Scanning drivers" -Indeterminate $true
    Write-WinToolLog -Message "Scanning devices and Windows Update for drivers. This can take a few minutes." -Level "info"
    $script:WinToolState.DriverScanJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverScanScript)
}

function Complete-WinToolDriverScan {
    $job = $script:WinToolState.DriverScanJob
    $ok = $false
    $errorMessage = ""
    $warning = ""
    $deviceJson = "[]"
    $updateJson = "[]"
    $displayJson = "[]"
    $hvci = $false
    if ($null -ne $job) {
        $ok = [bool]$job.Sync.Ok
        $errorMessage = [string]$job.Sync.Error
        if ($null -ne $job.Sync.Warning) { $warning = [string]$job.Sync.Warning }
        if ($null -ne $job.Sync.DeviceJson) { $deviceJson = [string]$job.Sync.DeviceJson }
        if ($null -ne $job.Sync.UpdateJson) { $updateJson = [string]$job.Sync.UpdateJson }
        if ($null -ne $job.Sync.DisplayJson) { $displayJson = [string]$job.Sync.DisplayJson }
        if ($null -ne $job.Sync.Hvci) { $hvci = [bool]$job.Sync.Hvci }
        Stop-WinToolThread -Job $job
    }
    $script:WinToolState.DriverScanJob = $null
    if (-not $ok) {
        Sync-WinToolBusyState -Busy $false
        Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
        Write-WinToolLog -Message ("Driver scan failed. {0}" -f $errorMessage) -Level "error"
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($warning)) {
        Write-WinToolLog -Message ("Windows Update scan warning: {0}" -f $warning) -Level "warn"
    }
    $parsed = ConvertFrom-WinToolDriverScan -DeviceJson $deviceJson -UpdateJson $updateJson
    $script:WinToolState.DriverDevices = @($parsed.Device)
    $script:WinToolState.DriverUpdates = @($parsed.Update)
    $script:WinToolState.DriverDisplays = @(ConvertFrom-WinToolJsonArray -Text $displayJson)
    $script:WinToolState.DriverHvci = $hvci
    $script:WinToolState.DriverScanned = $true
    $gpus = New-Object System.Collections.Generic.List[string]
    foreach ($display in @($script:WinToolState.DriverDisplays)) {
        $name = [string](Get-WinToolNote -Object $display -Name "Gpu" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-WinToolNote -Object $display -Name "Name" -Default "") }
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $gpus.Contains($name)) { $gpus.Add($name) | Out-Null }
    }
    $script:WinToolState.DriverRows = @(Group-WinToolDriverRow -Device $parsed.Device -Update $parsed.Update -GpuName $gpus.ToArray())
    $script:WinToolState.DriverCurrentBuilt = $false
    Show-WinToolDriverResult
    Sync-WinToolDriverToolCount
    $outdated = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "outdated" }).Count
    $missing = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "missing" }).Count
    $runtime = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime" }).Count
    Write-WinToolLog -Message (Format-WinToolDriverHeader -Outdated $outdated -Missing $missing -Runtime $runtime) -Level "ok"
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 100 -Text "Scan finished" -Indeterminate $false
}

function Update-WinToolDriverRuntimeRow {
    if (-not [bool]$script:WinToolState.DriverScanned) { return }
    if ($null -eq $script:WinToolWindow) { return }
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($script:WinToolState.DriverRows)) {
        if ([string]$row.Kind -eq "runtime" -or [string]$row.Kind -eq "gpu") { continue }
        $kept.Add($row) | Out-Null
    }
    $gpus = New-Object System.Collections.Generic.List[string]
    foreach ($display in @($script:WinToolState.DriverDisplays)) {
        $name = [string](Get-WinToolNote -Object $display -Name "Gpu" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-WinToolNote -Object $display -Name "Name" -Default "") }
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $gpus.Contains($name)) { $gpus.Add($name) | Out-Null }
    }
    foreach ($row in @(Group-WinToolDriverRow -Device @() -Update @() -GpuName $gpus.ToArray())) {
        $kept.Add($row) | Out-Null
    }
    $script:WinToolState.DriverRows = $kept.ToArray()
    Show-WinToolDriverResult
    Sync-WinToolDriverToolCount
}

function Show-WinToolDriverResult {
    (Get-WinToolUi -Name "DriversStart").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversResult").Visibility = "Visible"
    $rows = @($script:WinToolState.DriverRows)
    $outdated = @($rows | Where-Object { $_.Group -eq "outdated" })
    $missing = @($rows | Where-Object { $_.Group -eq "missing" })
    $runtime = @($rows | Where-Object { $_.Group -eq "runtime" })
    $runtimePending = @($rows | Where-Object { $_.Group -eq "runtime-pending" -or $_.Group -eq "runtime-current" })
    $current = @($rows | Where-Object { $_.Group -eq "current" })
    $gpu = @($rows | Where-Object { $_.Group -eq "gpu" })
    $runtimeCount = $runtime.Count
    if ($runtimePending.Count -gt 0 -and $runtime.Count -eq 0) {
        # Cache is not ready, or every runtime is already current: do not invent a need count.
        if (@($rows | Where-Object { $_.Group -eq "runtime-pending" }).Count -gt 0) {
            $runtimeCount = 0
        }
    }
    (Get-WinToolUi -Name "DriversHeader").Text = (Format-WinToolDriverHeader -Outdated $outdated.Count -Missing $missing.Count -Runtime $runtimeCount)
    $hostPanel = Get-WinToolUi -Name "DriversGroupHost"
    $hostPanel.Children.Clear()
    $script:WinToolState.DriverCurrentBuilt = $false
    Add-WinToolDriverGroup -Host $hostPanel -Title "Outdated drivers" -Group "outdated" -Row $outdated -Expanded $( $outdated.Count -gt 0 )
    Add-WinToolDriverGroup -Host $hostPanel -Title "Missing drivers" -Group "missing" -Row $missing -Expanded $( $missing.Count -gt 0 )
    $runtimeRows = @($runtime + $runtimePending)
    $runtimeTitle = "Game runtimes"
    if (@($rows | Where-Object { $_.Group -eq "runtime-pending" }).Count -gt 0) {
        $runtimeTitle = "Game runtimes (checking installed versions)"
    }
    Add-WinToolDriverGroup -Host $hostPanel -Title $runtimeTitle -Group "runtime" -Row $runtimeRows -Expanded $( $runtime.Count -gt 0 )
    Add-WinToolDriverGroup -Host $hostPanel -Title "Official graphics app" -Group "gpu" -Row $gpu -Expanded $( $gpu.Count -gt 0 )
    Add-WinToolDriverGroup -Host $hostPanel -Title "Up to date" -Group "current" -Row $current -Expanded $false -Lazy
}

function Add-WinToolDriverGroup {
    param(
        $HostPanel,
        [string]$Title,
        [string]$Group,
        $Row = @(),
        [bool]$Expanded = $true,
        [switch]$Lazy
    )
    $items = @($Row)
    if ($items.Count -eq 0) {
        return
    }
    $expander = New-Object System.Windows.Controls.Expander
    $expander.IsExpanded = $Expanded
    $expander.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $expander.SetResourceReference([System.Windows.Controls.Expander]::ForegroundProperty, "BrushInk")
    $header = New-Object System.Windows.Controls.DockPanel
    $count = New-WinToolText -Text ("{0}" -f $items.Count) -Weight "SemiBold" -Brush "BrushMuted"
    $count.VerticalAlignment = "Center"
    $count.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($count, "Right")
    [void]$header.Children.Add($count)
    if ($Group -ne "current") {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $box.VerticalAlignment = "Center"
        $selected = @($items | Where-Object { [bool]$_.Selected }).Count
        $box.IsChecked = ($selected -eq $items.Count)
        if ($selected -gt 0 -and $selected -lt $items.Count) { $box.IsChecked = $null }
        Register-WinToolUiEvent -Control $box -EventName "Click" -Name ("Drivers: toggle " + $Group) -Data $Group -Action {
            param($source, $eventData, $boundGroup)
            $null = $eventData
            if ([bool]$script:WinToolState.DriverSyncing) { return }
            $state = $source.IsChecked
            if ($state -ne $true) { $state = $false }
            foreach ($row in @($script:WinToolState.DriverRows)) {
                $rowGroup = [string]$row.Group
                if ($boundGroup -eq "runtime" -and ($rowGroup -eq "runtime" -or $rowGroup -eq "runtime-pending" -or $rowGroup -eq "runtime-current")) {
                    $row.Selected = [bool]$state
                    if ($null -ne $row.Checkbox) { $row.Checkbox.IsChecked = [bool]$state }
                }
                elseif ($rowGroup -eq $boundGroup) {
                    $row.Selected = [bool]$state
                    if ($null -ne $row.Checkbox) { $row.Checkbox.IsChecked = [bool]$state }
                }
            }
        }
        [System.Windows.Controls.DockPanel]::SetDock($box, "Left")
        [void]$header.Children.Add($box)
    }
    $label = New-WinToolText -Text $Title -Weight "SemiBold"
    $label.VerticalAlignment = "Center"
    [void]$header.Children.Add($label)
    $expander.Header = $header
    $body = New-Object System.Windows.Controls.StackPanel
    $expander.Content = $body
    if ($Lazy) {
        $expander.Tag = $items
        Register-WinToolUiEvent -Control $expander -EventName "Expanded" -Name "Drivers: expand up to date" -Action {
            if ([bool]$script:WinToolState.DriverCurrentBuilt) { return }
            $control = Get-WinToolUi -Name "DriversGroupHost"
            foreach ($child in @($control.Children)) {
                if ($child -is [System.Windows.Controls.Expander] -and $null -ne $child.Tag) {
                    $panel = $child.Content
                    if ($panel -is [System.Windows.Controls.Panel] -and $panel.Children.Count -eq 0) {
                        foreach ($row in @($child.Tag)) {
                            [void]$panel.Children.Add((New-WinToolDriverRowControl -Row $row))
                        }
                    }
                }
            }
            $script:WinToolState.DriverCurrentBuilt = $true
        }
    }
    else {
        foreach ($row in $items) {
            [void]$body.Children.Add((New-WinToolDriverRowControl -Row $row))
        }
    }
    [void]$HostPanel.Children.Add($expander)
}

function New-WinToolDriverRowControl {
    param($Row)
    $border = New-Object System.Windows.Controls.Border
    $border.Padding = [System.Windows.Thickness]::new(4, 6, 4, 6)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $grid.ColumnDefinitions.Add((New-WinToolColumn))
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $grid.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $box = New-Object System.Windows.Controls.CheckBox
    $box.IsChecked = [bool]$Row.Selected
    $box.VerticalAlignment = "Center"
    $box.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
    if ([string]$Row.Group -eq "current") {
        $box.Visibility = "Collapsed"
    }
    else {
        Register-WinToolUiEvent -Control $box -EventName "Click" -Name "Drivers: toggle row" -Data $Row -Action {
            param($source, $eventData, $boundRow)
            $null = $eventData
            $boundRow.Selected = ($source.IsChecked -eq $true)
        }
    }
    $Row.Checkbox = $box
    [void]$grid.Children.Add($box)
    $textHost = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($textHost, 1)
    $name = New-WinToolText -Text ([string]$Row.Name) -Weight "SemiBold"
    $name.TextWrapping = "Wrap"
    [void]$textHost.Children.Add($name)
    $meta = [string]$Row.Class
    $problem = [int]$Row.Problem
    if ($problem -gt 0) {
        $label = Get-WinToolDriverProblemName -Code $problem
        if (-not [string]::IsNullOrWhiteSpace($label)) {
            if ([string]::IsNullOrWhiteSpace($meta)) { $meta = $label }
            else { $meta = $meta + " - " + $label }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($meta)) {
        $classBlock = New-WinToolText -Text $meta -Brush "BrushMuted"
        $classBlock.TextWrapping = "Wrap"
        [void]$textHost.Children.Add($classBlock)
    }
    [void]$grid.Children.Add($textHost)
    $detail = New-WinToolText -Text (Format-WinToolDriverDetail -Row $Row) -Brush "BrushMuted"
    $detail.VerticalAlignment = "Center"
    $detail.Margin = [System.Windows.Thickness]::new(12, 0, 12, 0)
    $detail.TextWrapping = "Wrap"
    [System.Windows.Controls.Grid]::SetColumn($detail, 2)
    [void]$grid.Children.Add($detail)
    $group = [string]$Row.Group
    if ($group -eq "outdated" -or $group -eq "missing" -or $group -eq "runtime" -or $group -eq "gpu") {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = "Update"
        $button.Width = 88
        $button.Height = 28
        $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
        $button.VerticalAlignment = "Center"
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: update " + [string]$Row.Name) -Data $Row -Action {
            param($source, $eventData, $boundRow)
            $null = $source, $eventData
            Invoke-WinToolDriverUpdateClick -Row $boundRow
        }
        Add-WinToolBusyControl -Control $button
        [System.Windows.Controls.Grid]::SetColumn($button, 3)
        [void]$grid.Children.Add($button)
    }
    $border.Child = $grid
    return $border
}

function Get-WinToolDriverSelectedRow {
    param($Row)
    if ($null -ne $Row) {
        return @($Row)
    }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($script:WinToolState.DriverRows)) {
        if ([bool]$item.Selected -and [string]$item.Group -ne "current" -and [string]$item.Group -ne "runtime-current") {
            $list.Add($item) | Out-Null
        }
    }
    return $list.ToArray()
}

function Invoke-WinToolDriverUpdateClick {
    param($Row)
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    $selected = @(Get-WinToolDriverSelectedRow -Row $Row)
    if ($selected.Count -eq 0) {
        Write-WinToolLog -Message "Tick at least one item to update." -Level "warn"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $wu = @($selected | Where-Object { [string]$_.Kind -eq "device" -and $null -ne $_.Offer -and -not [string]::IsNullOrWhiteSpace([string]$_.Title) })
    $packages = @($selected | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.WingetId) })
    $missingNoOffer = @($selected | Where-Object { [string]$_.Kind -eq "device" -and ($null -eq $_.Offer -or [string]::IsNullOrWhiteSpace([string]$_.Title)) })
    $parts = New-Object System.Collections.Generic.List[string]
    if ($wu.Count -gt 0) { $parts.Add(("{0} Windows Update driver(s)" -f $wu.Count)) | Out-Null }
    if ($packages.Count -gt 0) { $parts.Add(("{0} official package(s)" -f $packages.Count)) | Out-Null }
    if ($missingNoOffer.Count -gt 0) { $parts.Add(("{0} device(s) have no Windows Update driver yet" -f $missingNoOffer.Count)) | Out-Null }
    $message = "Install " + ($parts.ToArray() -join " and ") + "? A restore point is created first when System Protection is on. The PC may need a restart."
    $ok = Request-WinToolConfirmation -Message $message -Title "Update drivers"
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingInstall = [pscustomobject]@{
        Wu      = $wu
        Package = $packages
        Missing = $missingNoOffer
    }
    Start-WinToolDriverProtectedAction -Title "Update drivers" -Handler "Invoke-WinToolDriverSelectedInstall" -NeedsRestore
}

function Invoke-WinToolDriverSelectedInstall {
    $pending = $script:WinToolState.DriverPendingInstall
    $script:WinToolState.DriverPendingInstall = $null
    $Wu = @()
    $Package = @()
    $Missing = @()
    if ($null -ne $pending) {
        $Wu = @($pending.Wu)
        $Package = @($pending.Package)
        $Missing = @($pending.Missing)
    }
    foreach ($item in @($Missing)) {
        Write-WinToolLog -Message ("No Windows Update driver was matched for {0}." -f [string]$item.Name) -Level "warn"
    }
    if (@($Package).Count -gt 0) {
        $apps = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($Package)) {
            $apps.Add([pscustomobject]@{
                    name     = [string]$item.Name
                    wingetId = [string]$item.WingetId
                    scope    = [string]$item.Scope
                }) | Out-Null
        }
        $done = "Finished installing the selected packages."
        if (@($Wu).Count -gt 0) {
            $script:WinToolState.DriverPendingWu = @($Wu)
            Invoke-WinToolPlanAsync -Step (Get-WinToolAppPlan -App $apps.ToArray()) -DoneMessage $done -AfterDone "Start-WinToolDriverPendingWu"
            return
        }
        Invoke-WinToolPlanAsync -Step (Get-WinToolAppPlan -App $apps.ToArray()) -DoneMessage $done
        return
    }
    Start-WinToolDriverWuInstall -Row $Wu
}

function Start-WinToolDriverPendingWu {
    $rows = @($script:WinToolState.DriverPendingWu)
    $script:WinToolState.DriverPendingWu = $null
    if ($rows.Count -eq 0) { return }
    Start-WinToolDriverWuInstall -Row $rows
}

function Start-WinToolDriverWuInstall {
    param($Row)
    $titles = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Row)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item.Title)) {
            $titles.Add([string]$item.Title) | Out-Null
        }
    }
    if ($titles.Count -eq 0) {
        Write-WinToolLog -Message "Those devices had no Windows Update title to install." -Level "warn"
        return
    }
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Installing driver updates" -Indeterminate $true
    Write-WinToolLog -Message ("Downloading and installing {0} Windows Update driver(s)." -f $titles.Count) -Level "info"
    $script:WinToolState.DriverToolKind = "install"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolUpdateInstallScript) -Argument @("IsInstalled=0 and Type='Driver'", ($titles.ToArray() -join "`n"))
}

function Start-WinToolDriverProtectedAction {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Handler,
        [switch]$NeedsRestore
    )
    if ($NeedsRestore -and -not [bool]$script:WinToolState.RestorePointDone) {
        $script:WinToolState.DriverPending = $Handler
        Sync-WinToolBusyState -Busy $true
        Sync-WinToolProgress -Value 0 -Text "Creating a restore point" -Indeterminate $true
        Write-WinToolLog -Message ("Creating a restore point before {0}. This can take a minute." -f $Title) -Level "info"
        $script:WinToolState.RestoreJob = Start-WinToolRestorePointJob -Description "WinTool before driver changes"
        return
    }
    & $Handler
}

function Complete-WinToolDriverRestore {
    param(
        [bool]$Ok,
        [string]$ErrorMessage
    )
    $action = $script:WinToolState.DriverPending
    if (-not $Ok) {
        $continue = Request-WinToolConfirmation -Message ("A restore point was not created.`n`n{0}`n`nContinue anyway?" -f $ErrorMessage) -Title "Restore point"
        if (-not $continue) {
            $script:WinToolState.DriverPending = $null
            Sync-WinToolBusyState -Busy $false
            Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
            Write-WinToolLog -Message "The driver change was not applied." -Level "warn"
            return
        }
        Write-WinToolLog -Message "Continuing without a restore point." -Level "warn"
    }
    else {
        Write-WinToolLog -Message "Restore point created." -Level "ok"
        $script:WinToolState.RestorePointDone = $true
    }
    $script:WinToolState.DriverPending = $null
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
    if (-not [string]::IsNullOrWhiteSpace([string]$action)) {
        & ([string]$action)
    }
}

function Invoke-WinToolDriverBackupClick {
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $folder = Select-WinToolFolder -Description "Choose a folder for the driver backup"
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Backing up drivers" -Indeterminate $true
    Write-WinToolLog -Message ("Exporting drivers to {0}." -f $folder) -Level "info"
    $script:WinToolState.DriverToolKind = "backup"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverBackupScript) -Argument @($folder)
}

function Invoke-WinToolDriverToolClick {
    param([string]$Action)
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    switch ($Action) {
        "backup" { Invoke-WinToolDriverBackupClick }
        "offline" { Invoke-WinToolDriverOfflineClick }
        "audio" { Invoke-WinToolDriverAudioClick }
        "enable" { Invoke-WinToolDriverToggleClick -Enable $true }
        "disable" { Invoke-WinToolDriverToggleClick -Enable $false }
        "rescan" { Invoke-WinToolDriverRescanClick }
        "ghost" { Invoke-WinToolDriverGhostClick }
        "network" { Invoke-WinToolDriverNetworkClick }
        "display" { Invoke-WinToolDriverDisplayClick }
        "runtime" { Invoke-WinToolDriverRuntimeClick }
        "incompatible" { Invoke-WinToolDriverIncompatibleClick }
        default { Write-WinToolLog -Message ("Unknown driver tool: " + $Action) -Level "warn" }
    }
}

function Invoke-WinToolDriverOfflineClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $folder = Select-WinToolFolder -Description "Choose the folder that has the backed-up drivers"
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    $ok = Request-WinToolConfirmation -Message ("Install every driver found under {0}? A restore point is created first when System Protection is on. The PC may need a restart." -f $folder) -Title "Install drivers from a folder"
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingFolder = $folder
    Start-WinToolDriverProtectedAction -Title "Install drivers from a folder" -Handler "Invoke-WinToolDriverOfflineStart" -NeedsRestore
}

function Invoke-WinToolDriverOfflineStart {
    $folder = [string]$script:WinToolState.DriverPendingFolder
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Installing drivers from a folder" -Indeterminate $true
    Write-WinToolLog -Message ("Installing drivers from {0}." -f $folder) -Level "info"
    $script:WinToolState.DriverToolKind = "offline"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverOfflineScript) -Argument @($folder)
}

function Invoke-WinToolDriverAudioClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message "Restart the Windows audio services, re-enable disabled playback devices, and open the audio troubleshooter?" -Title "Repair audio"
    if (-not $ok) { return }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Repairing audio" -Indeterminate $true
    Write-WinToolLog -Message "Restarting audio services and checking playback devices." -Level "info"
    $script:WinToolState.DriverToolKind = "audio"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverAudioScript)
}

function Invoke-WinToolDriverToggleClick {
    param([bool]$Enable)
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message "Scan drivers first so WinTool can list devices with a problem code." -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverProblemDevice -Device $script:WinToolState.DriverDevices)
    if ($devices.Count -eq 0) {
        Write-WinToolLog -Message "No devices with a problem code were found in the last scan." -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $verb = "Disable"
    $jobAction = "disable"
    if ($Enable) {
        $verb = "Enable"
        $jobAction = "enable"
    }
    $names = @($devices | ForEach-Object { [string]$_.Name } | Select-Object -First 12)
    $extra = ""
    if ($devices.Count -gt $names.Count) { $extra = ("`n`nand {0} more." -f ($devices.Count - $names.Count)) }
    $ok = Request-WinToolConfirmation -Message ("{0} {1} device(s) with a problem code?`n`n{2}{3}" -f $verb, $devices.Count, ($names -join "`n"), $extra) -Title ("{0} devices" -f $verb)
    if (-not $ok) { return }
    $ids = ($devices | ForEach-Object { [string]$_.InstanceId }) -join "`n"
    $script:WinToolState.DriverPendingToggle = [pscustomobject]@{
        Ids    = $ids
        Action = $jobAction
        Verb   = $verb
    }
    if ($Enable) {
        Invoke-WinToolDriverToggleStart
    }
    else {
        Start-WinToolDriverProtectedAction -Title "Disable devices" -Handler "Invoke-WinToolDriverToggleStart" -NeedsRestore
    }
}

function Invoke-WinToolDriverToggleStart {
    $pending = $script:WinToolState.DriverPendingToggle
    if ($null -eq $pending) { return }
    $verb = [string]$pending.Verb
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text ($verb + " devices") -Indeterminate $true
    $script:WinToolState.DriverToolKind = "toggle"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverToggleScript) -Argument @([string]$pending.Ids, [string]$pending.Action)
}

function Invoke-WinToolDriverRescanClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message "Ask Windows to rescan for hardware changes?" -Title "Rescan devices"
    if (-not $ok) { return }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Rescanning devices" -Indeterminate $true
    Write-WinToolLog -Message "Asking Windows to rescan for hardware changes." -Level "info"
    $script:WinToolState.DriverToolKind = "rescan"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverRescanScript)
}

function Invoke-WinToolDriverGhostClick {
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message "Scan drivers first so WinTool can count leftover device entries." -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverGhostDevice -Device $script:WinToolState.DriverDevices)
    if ($devices.Count -eq 0) {
        Write-WinToolLog -Message "No leftover device entries were found in the last scan." -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $names = @($devices | ForEach-Object { [string]$_.Name } | Select-Object -First 12)
    $extra = ""
    if ($devices.Count -gt $names.Count) { $extra = ("`n`nand {0} more." -f ($devices.Count - $names.Count)) }
    $ok = Request-WinToolConfirmation -Message ("Remove {0} leftover device entr(y/ies)? This cannot be undone except by a restore point or by replugging the hardware.`n`n{1}{2}" -f $devices.Count, ($names -join "`n"), $extra) -Title "Remove leftover device entries"
    if (-not $ok) { return }
    $ids = ($devices | ForEach-Object { [string]$_.InstanceId }) -join "`n"
    $script:WinToolState.DriverPendingIds = $ids
    $script:WinToolState.DriverPendingCount = $devices.Count
    Start-WinToolDriverProtectedAction -Title "Remove leftover device entries" -Handler "Invoke-WinToolDriverGhostStart" -NeedsRestore
}

function Invoke-WinToolDriverGhostStart {
    $ids = [string]$script:WinToolState.DriverPendingIds
    $count = [int]$script:WinToolState.DriverPendingCount
    if ([string]::IsNullOrWhiteSpace($ids)) { return }
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Removing leftover devices" -Indeterminate $true
    Write-WinToolLog -Message ("Removing {0} leftover device entries." -f $count) -Level "info"
    $script:WinToolState.DriverToolKind = "remove"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverRemoveScript) -Argument @($ids)
}

function Invoke-WinToolDriverNetworkClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message "Reset Winsock and the TCP/IP stack, flush DNS, renew the address, and restart network adapters? You will need to restart the PC when it finishes." -Title "Repair the network"
    if (-not $ok) { return }
    Start-WinToolDriverProtectedAction -Title "Repair the network" -Handler "Invoke-WinToolDriverNetworkStart" -NeedsRestore
}

function Invoke-WinToolDriverNetworkStart {
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text "Repairing the network" -Indeterminate $true
    Write-WinToolLog -Message "Resetting the network stack. Restart the PC when this finishes." -Level "info"
    $script:WinToolState.DriverToolKind = "network"
    $script:WinToolState.DriverToolJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverNetworkScript)
}

function Invoke-WinToolDriverDisplayClick {
    $displays = @($script:WinToolState.DriverDisplays)
    if (-not [bool]$script:WinToolState.DriverScanned -or $displays.Count -eq 0) {
        Write-WinToolLog -Message "Scan drivers first so WinTool can read the current display." -Level "warn"
        if ($displays.Count -eq 0) {
            Write-WinToolLog -Message (Format-WinToolDisplayAdvice -Display $null) -Level "info"
        }
        return
    }
    foreach ($item in $displays) {
        Write-WinToolLog -Message (Format-WinToolDisplayAdvice -Display $item) -Level "info"
    }
}

function Invoke-WinToolDriverRuntimeClick {
    $cache = Get-WinToolPackageCache
    if (-not [bool]$cache.WingetReady) {
        Write-WinToolLog -Message "WinTool is still checking which runtimes are already installed. Try again in a moment, or scan first." -Level "warn"
        return
    }
    $rows = @()
    if ([bool]$script:WinToolState.DriverScanned) {
        $rows = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime" })
    }
    else {
        foreach ($item in @(Get-WinToolNote -Object (Get-WinToolDriverCatalog) -Name "runtimes" -Default @())) {
            $row = Get-WinToolDriverRuntimeRow -Runtime $item -Cache $cache
            if ([string]$row.Group -eq "runtime") { $rows += $row }
        }
    }
    if ($rows.Count -eq 0) {
        Write-WinToolLog -Message "No missing or outdated game runtimes were found." -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message ("Install or repair {0} game runtime(s) with winget? A restore point is created first when System Protection is on." -f $rows.Count) -Title "Repair game runtimes"
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingApps = @($rows | ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; wingetId = [string]$_.WingetId; scope = [string]$_.Scope } })
    Start-WinToolDriverProtectedAction -Title "Repair game runtimes" -Handler "Invoke-WinToolDriverRuntimeStart" -NeedsRestore
}

function Invoke-WinToolDriverRuntimeStart {
    $apps = @($script:WinToolState.DriverPendingApps)
    $script:WinToolState.DriverPendingApps = $null
    if ($apps.Count -eq 0) { return }
    Invoke-WinToolPlanAsync -Step (Get-WinToolAppPlan -App $apps) -DoneMessage "Finished repairing game runtimes."
}

function Invoke-WinToolDriverIncompatibleClick {
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message "Scan drivers first so WinTool can review incompatible drivers." -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverIncompatibleDevice -Device $script:WinToolState.DriverDevices -MemoryIntegrity ([bool]$script:WinToolState.DriverHvci))
    if ($devices.Count -eq 0) {
        $extra = ""
        if ([bool]$script:WinToolState.DriverHvci) {
            $extra = " Memory Integrity is on, and no blocked drivers were listed."
        }
        Write-WinToolLog -Message ("No incompatible drivers were found in the last scan." + $extra) -Level "ok"
        return
    }
    if ([bool]$script:WinToolState.DriverHvci) {
        Write-WinToolLog -Message "Memory Integrity is on. Unsigned or blocked drivers can fail to load." -Level "info"
    }
    foreach ($item in $devices) {
        $label = Get-WinToolDriverProblemName -Code ([int]$item.Problem)
        Write-WinToolLog -Message ("{0}  ({1})" -f [string]$item.Name, $label) -Level "warn"
    }
}

function Complete-WinToolDriverTool {
    $job = $script:WinToolState.DriverToolJob
    $kind = [string]$script:WinToolState.DriverToolKind
    $ok = $false
    $errorMessage = ""
    $count = 0
    $reboot = $false
    $log = @()
    if ($null -ne $job) {
        $ok = [bool]$job.Sync.Ok
        $errorMessage = [string]$job.Sync.Error
        if ($null -ne $job.Sync.Count) { $count = [int]$job.Sync.Count }
        if ($null -ne $job.Sync.Removed) { $count = [int]$job.Sync.Removed }
        if ($null -ne $job.Sync.Reboot) { $reboot = [bool]$job.Sync.Reboot }
        if ($null -ne $job.Sync.Log) { $log = @($job.Sync.Log) }
        Stop-WinToolThread -Job $job
    }
    $script:WinToolState.DriverToolJob = $null
    $script:WinToolState.DriverToolKind = ""
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text "Ready" -Indeterminate $false
    foreach ($line in $log) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-WinToolLog -Message ([string]$line) -Level "info"
        }
    }
    if (-not $ok) {
        Write-WinToolLog -Message ("Driver tool failed. {0}" -f $errorMessage) -Level "error"
        return
    }
    switch ($kind) {
        "backup" { Write-WinToolLog -Message ("Driver backup finished. {0} INF file(s) were written." -f $count) -Level "ok" }
        "offline" { Write-WinToolLog -Message "Drivers from the backup folder were installed." -Level "ok" }
        "install" {
            if ($count -eq 0) {
                Write-WinToolLog -Message "Those updates were no longer offered when the install started." -Level "warn"
            }
            else {
                Write-WinToolLog -Message ("Finished installing {0} Windows Update driver(s)." -f $count) -Level "ok"
            }
        }
        "audio" { Write-WinToolLog -Message "Audio repair finished." -Level "ok" }
        "network" { Write-WinToolLog -Message "Network repair finished. Restart the PC to complete it." -Level "ok" }
        "remove" { Write-WinToolLog -Message ("Removed leftover device entries ({0}). Scan again to refresh the list." -f $count) -Level "ok" }
        "rescan" { Write-WinToolLog -Message "Hardware rescan finished. Scan drivers again to refresh the list." -Level "ok" }
        "toggle" { Write-WinToolLog -Message ("Changed {0} device(s). Scan again to refresh the list." -f $count) -Level "ok" }
        default { Write-WinToolLog -Message "Driver tool finished." -Level "ok" }
    }
    if ($reboot) {
        Write-WinToolLog -Message "Restart the PC to finish applying the change." -Level "warn"
    }
}
