# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Select-WinToolFolder {
    param(
        [string]$Description = (Get-WinToolText "drivers.folder.backup")
    )
    if ($null -ne $script:WinToolUiFolder) {
        return [string]$script:WinToolUiFolder
    }
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
    Write-WinToolLog -Message (Get-WinToolText "drivers.admin") -Level "info"
    return (Request-WinToolElevatedHelper)
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
    $script:WinToolState.DriverMode = "simple"
    $script:WinToolState.DriverCategory = "outdated"
    $script:WinToolState.DriverSelected = $null
    $script:WinToolState.DriverPhase = ""

    Set-WinToolDriverUiText
    Add-WinToolAdminBadgeNear -Name "DriversBackup" -Place "Before" | Out-Null
    Add-WinToolAdminBadgeNear -Name "DriversUpdate" -Place "Before" | Out-Null
    Show-WinToolDriverHome
    Initialize-WinToolDriverStepList
    Update-WinToolDriverPcChip

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversScan") -EventName "Click" -Name "Drivers: scan" -Action { Invoke-WinToolDriverScanClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversScanAgain") -EventName "Click" -Name "Drivers: scan again" -Action { Invoke-WinToolDriverScanClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversUpdate") -EventName "Click" -Name "Drivers: update now" -Action { Invoke-WinToolDriverUpdateClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversBackup") -EventName "Click" -Name "Drivers: back up" -Action { Invoke-WinToolDriverBackupClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DriversScanCancel") -EventName "Click" -Name "Drivers: cancel scan" -Action { Stop-WinToolRun }

    foreach ($pair in @(
            , @("DriversModeSimple", "simple")
            , @("DriversModeAdvanced", "advanced")
            , @("DriversModeTools", "tools")
        )) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name $pair[0]) -EventName "Checked" -Name ("Drivers mode " + $pair[1]) -Data $pair[1] -Action {
            param($source, $eventData, $boundMode)
            $null = $eventData
            if ($source -is [System.Windows.Controls.RadioButton] -and $source.IsChecked -ne $true) { return }
            Set-WinToolDriverMode -Mode ([string]$boundMode)
        }
    }

    foreach ($name in @("DriversScan", "DriversScanAgain", "DriversUpdate", "DriversBackup", "DriversModeSimple", "DriversModeAdvanced", "DriversModeTools")) {
        Add-WinToolBusyControl -Control (Get-WinToolUi -Name $name)
    }

    Initialize-WinToolDriverToolList
    Show-WinToolDriverMode
}

function Set-WinToolDriverUiText {
    $map = @{
        DriversTitle = "drivers.title"
        DriversSubtitle = "drivers.subtitle"
        DriversHeroTitle = "drivers.hero.title"
        DriversHeroBody = "drivers.hero.body"
        DriversPcLabel = "drivers.pcLabel"
        DriversAdvancedSub = "drivers.advanced.subtitle"
        DriversCategoryTitle = "drivers.advanced.categories"
        DriversDetailTitle = "drivers.advanced.details"
        DriversScanningTitle = "status.scanningDrivers"
        DriversInfoTitle = "drivers.tool.info.name"
        DriversInfoText = "drivers.info.waiting"
    }
    foreach ($name in @($map.Keys)) {
        $control = Get-WinToolUi -Name $name
        if ($null -ne $control) { $control.Text = Get-WinToolText ([string]$map[$name]) }
    }
    $buttonMap = @{
        DriversScan = "button.scanDrivers"
        DriversBackup = "button.backUpDrivers"
        DriversScanAgain = "button.scanAgain"
        DriversUpdate = "button.updateAll"
        DriversScanCancel = "button.cancel"
        DriversModeSimple = "drivers.mode.simple"
        DriversModeAdvanced = "drivers.mode.advanced"
        DriversModeTools = "drivers.mode.tools"
    }
    foreach ($name in @($buttonMap.Keys)) {
        $control = Get-WinToolUi -Name $name
        if ($null -ne $control) { $control.Content = Get-WinToolText ([string]$buttonMap[$name]) }
    }
    $tips = @{
        DriversScan = "drivers.hero.scan.tip"
        DriversBackup = "drivers.backup.tip"
        DriversUpdate = "drivers.update.tip"
        DriversModeSimple = "drivers.mode.simple.tip"
        DriversModeAdvanced = "drivers.mode.advanced.tip"
        DriversModeTools = "drivers.mode.tools.tip"
    }
    foreach ($name in @($tips.Keys)) {
        $control = Get-WinToolUi -Name $name
        if ($null -ne $control) {
            $text = Get-WinToolText ([string]$tips[$name])
            $control.ToolTip = $text
            [System.Windows.Automation.AutomationProperties]::SetName($control, $text)
        }
    }
    (Get-WinToolUi -Name "DriversScan").ToolTip = Get-WinToolText "drivers.hero.scan.tip"
    [System.Windows.Automation.AutomationProperties]::SetName((Get-WinToolUi -Name "DriversScan"), (Get-WinToolText "button.scanDrivers"))
    [System.Windows.Automation.AutomationProperties]::SetName((Get-WinToolUi -Name "DriversBackup"), (Get-WinToolText "button.backUpDrivers"))
    [System.Windows.Automation.AutomationProperties]::SetName((Get-WinToolUi -Name "DriversScanAgain"), (Get-WinToolText "button.scanAgain"))
    [System.Windows.Automation.AutomationProperties]::SetName((Get-WinToolUi -Name "DriversUpdate"), (Get-WinToolText "button.updateAll"))
}

function Set-WinToolDriverMode {
    param([string]$Mode)
    $script:WinToolState.DriverMode = $Mode
    Show-WinToolDriverMode
}

function Show-WinToolDriverHome {
    (Get-WinToolUi -Name "DriversStart").Visibility = "Visible"
    (Get-WinToolUi -Name "DriversResult").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversScanning").Visibility = "Collapsed"
}

function Show-WinToolDriverMode {
    $mode = [string]$script:WinToolState.DriverMode
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "simple" }
    $scanning = ($null -ne $script:WinToolState.DriverScanJob)
    (Get-WinToolUi -Name "DriversSimpleScroll").Visibility = $(if ($mode -eq "simple") { "Visible" } else { "Collapsed" })
    (Get-WinToolUi -Name "DriversAdvanced").Visibility = $(if ($mode -eq "advanced") { "Visible" } else { "Collapsed" })
    (Get-WinToolUi -Name "DriversToolsScroll").Visibility = $(if ($mode -eq "tools") { "Visible" } else { "Collapsed" })
    if ($mode -eq "simple") {
        if ($scanning) {
            (Get-WinToolUi -Name "DriversStart").Visibility = "Collapsed"
            (Get-WinToolUi -Name "DriversResult").Visibility = "Collapsed"
            (Get-WinToolUi -Name "DriversScanning").Visibility = "Visible"
        }
        elseif ([bool]$script:WinToolState.DriverScanned) {
            (Get-WinToolUi -Name "DriversStart").Visibility = "Collapsed"
            (Get-WinToolUi -Name "DriversResult").Visibility = "Visible"
            (Get-WinToolUi -Name "DriversScanning").Visibility = "Collapsed"
        }
        else {
            Show-WinToolDriverHome
        }
        Sync-WinToolScrollFill -ScrollName "DriversSimpleScroll" -BodyName "DriversBody"
    }
    elseif ($mode -eq "advanced") {
        Update-WinToolDriverAdvanced
    }
    else {
        Sync-WinToolScrollFill -ScrollName "DriversToolsScroll" -BodyName "DriversToolsBody"
    }
}

function Initialize-WinToolDriverStepList {
    $hostPanel = Get-WinToolUi -Name "DriversStepList"
    if ($null -eq $hostPanel) { return }
    $hostPanel.Children.Clear()
    $steps = @(
        , @("drivers.step1.title", "drivers.step1.body")
        , @("drivers.step2.title", "drivers.step2.body")
        , @("drivers.step3.title", "drivers.step3.body")
    )
    $n = 1
    foreach ($step in $steps) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
        $badge = New-Object System.Windows.Controls.Border
        $badge.Width = 24
        $badge.Height = 24
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $badge.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $badge.VerticalAlignment = "Top"
        $badge.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushAccentSoft")
        $num = New-WinToolText -Text ([string]$n) -Weight "SemiBold" -Brush "BrushAccent"
        $num.HorizontalAlignment = "Center"
        $num.VerticalAlignment = "Center"
        $badge.Child = $num
        [System.Windows.Controls.DockPanel]::SetDock($badge, "Left")
        [void]$row.Children.Add($badge)
        $text = New-Object System.Windows.Controls.StackPanel
        [void]$text.Children.Add((New-WinToolText -Text (Get-WinToolText $step[0]) -Weight "SemiBold"))
        $body = New-WinToolText -Text (Get-WinToolText $step[1]) -Brush "BrushMuted" -Wrap
        $body.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$text.Children.Add($body)
        [void]$row.Children.Add($text)
        [void]$hostPanel.Children.Add($row)
        $n++
    }
}

function Update-WinToolDriverPcChip {
    $hostPanel = Get-WinToolUi -Name "DriversChipHost"
    if ($null -eq $hostPanel) { return }
    $hostPanel.Children.Clear()
    $chips = @(Get-WinToolDriverPcChip -Info $script:WinToolState.DriverInfo -Display $script:WinToolState.DriverDisplays -Device $script:WinToolState.DriverDevices)
    if ($chips.Count -eq 0) {
        $chip = New-WinToolBadge -Text (Get-WinToolText "drivers.chip.reading") -Kind "ok"
        $chip.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        [void]$hostPanel.Children.Add($chip)
        return
    }
    foreach ($item in $chips) {
        $border = New-WinToolCard
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $stack = New-Object System.Windows.Controls.StackPanel
        $label = New-WinToolText -Text ([string]$item.Label) -Brush "BrushMuted"
        $value = New-WinToolText -Text ([string]$item.Value) -Weight "SemiBold"
        $value.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$stack.Children.Add($label)
        [void]$stack.Children.Add($value)
        $border.Child = $stack
        [void]$hostPanel.Children.Add($border)
    }
}

function Initialize-WinToolDriverToolList {
    $hostPanel = Get-WinToolUi -Name "DriversToolList"
    $hostPanel.Children.Clear()
    $tools = @(
        [pscustomobject]@{ Id = "backup"; Glyph = [char]0xE8C8; NameKey = "drivers.tool.backup.name"; BodyKey = "drivers.tool.backup.body"; Restart = $false }
        [pscustomobject]@{ Id = "offline"; Glyph = [char]0xE8B7; NameKey = "drivers.tool.offline.name"; BodyKey = "drivers.tool.offline.body"; Restart = $false }
        [pscustomobject]@{ Id = "audio"; Glyph = [char]0xE767; NameKey = "drivers.tool.audio.name"; BodyKey = "drivers.tool.audio.body"; Restart = $false }
        [pscustomobject]@{ Id = "problem"; Glyph = [char]0xE7BA; NameKey = "drivers.tool.problem.name"; BodyKey = "drivers.tool.problem.body"; Restart = $false }
        [pscustomobject]@{ Id = "ghost"; Glyph = [char]0xE74D; NameKey = "drivers.tool.ghost.name"; BodyKey = "drivers.tool.ghost.body"; Restart = $false }
        [pscustomobject]@{ Id = "network"; Glyph = [char]0xE774; NameKey = "drivers.tool.network.name"; BodyKey = "drivers.tool.network.body"; Restart = $false }
        [pscustomobject]@{ Id = "display"; Glyph = [char]0xE7F4; NameKey = "drivers.tool.display.name"; BodyKey = "drivers.tool.display.body"; Restart = $false }
        [pscustomobject]@{ Id = "runtime"; Glyph = [char]0xE7FC; NameKey = "drivers.tool.runtime.name"; BodyKey = "drivers.tool.runtime.body"; Restart = $false }
        [pscustomobject]@{ Id = "incompatible"; Glyph = [char]0xE730; NameKey = "drivers.tool.incompatible.name"; BodyKey = "drivers.tool.incompatible.body"; Restart = $false }
    )
    $index = 0
    $map = @{}
    foreach ($tool in $tools) {
        $card = New-WinToolCard
        $card.CornerRadius = [System.Windows.CornerRadius]::new(16)
        $card.Padding = [System.Windows.Thickness]::new(14)
        $card.MinHeight = 132
        $gapLeft = 0
        $gapTop = 0
        if (($index % 2) -ne 0) { $gapLeft = 14 }
        if ($index -ge 2) { $gapTop = 14 }
        $card.Margin = [System.Windows.Thickness]::new($gapLeft, $gapTop, 0, 0)
        $grid = New-Object System.Windows.Controls.Grid
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
        $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
        $footRow = New-Object System.Windows.Controls.RowDefinition
        $footRow.Height = [System.Windows.GridLength]::Auto
        $footRow.MinHeight = 36
        $grid.RowDefinitions.Add($footRow)
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
        $title = New-WinToolText -Text (Get-WinToolText ([string]$tool.NameKey)) -Weight "Bold"
        $title.VerticalAlignment = "Center"
        $title.TextWrapping = "Wrap"
        [void]$titleRow.Children.Add($title)
        [void]$grid.Children.Add($titleRow)
        $description = New-WinToolText -Text (Get-WinToolText ([string]$tool.BodyKey)) -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 8, 0, 8))
        [System.Windows.Controls.Grid]::SetRow($description, 1)
        [void]$grid.Children.Add($description)
        $foot = New-Object System.Windows.Controls.WrapPanel
        $foot.HorizontalAlignment = "Right"
        $foot.Orientation = "Horizontal"
        [System.Windows.Controls.Grid]::SetRow($foot, 2)
        $buttons = Get-WinToolDriverToolButton -Id ([string]$tool.Id)
        foreach ($entry in @($buttons)) {
            $button = New-Object System.Windows.Controls.Button
            $button.Content = [string]$entry.Label
            $button.Margin = [System.Windows.Thickness]::new(8, 4, 0, 0)
            $button.Style = $script:WinToolWindow.FindResource("SecondaryButton")
            $button.VerticalAlignment = "Center"
            Set-WinToolAutoButton -Button $button
            $actionId = [string]$entry.Action
            Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: " + [string]$entry.Label) -Data $actionId -Action {
                param($source, $eventData, $boundAction)
                $null = $source, $eventData
                Invoke-WinToolDriverToolClick -Action $boundAction
            }
            Add-WinToolBusyControl -Control $button
            [void]$foot.Children.Add($button)
        }
        $adminBadge = New-WinToolAdminBadge -Margin ([System.Windows.Thickness]::new(0, 4, 8, 0))
        $foot.Children.Insert(0, $adminBadge)
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
        "backup" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.backUp"); Action = "backup" }) }
        "offline" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.installFromFolder"); Action = "offline" }) }
        "audio" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.repairAudio"); Action = "audio" }) }
        "problem" { return @(
                [pscustomobject]@{ Label = (Get-WinToolText "button.enable"); Action = "enable" },
                [pscustomobject]@{ Label = (Get-WinToolText "button.disable"); Action = "disable" },
                [pscustomobject]@{ Label = (Get-WinToolText "button.rescan"); Action = "rescan" }
            ) }
        "ghost" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.removeEntries"); Action = "ghost" }) }
        "network" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.repairNetwork"); Action = "network" }) }
        "display" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.checkDisplay"); Action = "display" }) }
        "runtime" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.repairRuntimes"); Action = "runtime" }) }
        "incompatible" { return @([pscustomobject]@{ Label = (Get-WinToolText "button.showDetails"); Action = "incompatible" }) }
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
        $problemText = Get-WinToolCountText "drivers.badge.devices" $problem.Count
        if ($problem.Count -eq 0) { $problemText = Get-WinToolText "drivers.badge.devices.zero" }
        Set-WinToolDriverToolBadge -Id "problem" -Text $problemText -Kind $(if ($problem.Count -gt 0) { "caution" } else { "ok" })
        $ghostText = Get-WinToolCountText "drivers.badge.entries" $ghost.Count
        if ($ghost.Count -eq 0) { $ghostText = Get-WinToolText "drivers.badge.entries.zero" }
        Set-WinToolDriverToolBadge -Id "ghost" -Text $ghostText -Kind $(if ($ghost.Count -gt 0) { "caution" } else { "ok" })
        $incompatText = Get-WinToolCountText "drivers.badge.drivers" $incompatible.Count
        if ($incompatible.Count -eq 0) { $incompatText = Get-WinToolText "drivers.badge.drivers.zero" }
        Set-WinToolDriverToolBadge -Id "incompatible" -Text $incompatText -Kind $(if ($incompatible.Count -gt 0) { "caution" } else { "ok" })
        $runtimeNeed = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime" })
        if (@($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "runtime-pending" }).Count -gt 0) {
            Set-WinToolDriverToolBadge -Id "runtime" -Text "" -Kind "ok"
        }
        else {
            $runtimeNeed = @(Get-WinToolDriverAttentionRuntime -Row $script:WinToolState.DriverRows)
            $runtimeText = Get-WinToolCountText "drivers.badge.needed" $runtimeNeed.Count
            if ($runtimeNeed.Count -eq 0) { $runtimeText = Get-WinToolText "drivers.badge.needed.zero" }
            Set-WinToolDriverToolBadge -Id "runtime" -Text $runtimeText -Kind $(if ($runtimeNeed.Count -gt 0) { "caution" } else { "ok" })
        }
        $displays = @($script:WinToolState.DriverDisplays)
        if ($displays.Count -eq 1) {
            $item = $displays[0]
            $width = [int](Get-WinToolNote -Object $item -Name "Width" -Default 0)
            $height = [int](Get-WinToolNote -Object $item -Name "Height" -Default 0)
            if ($width -gt 0 -and $height -gt 0) {
                Set-WinToolDriverToolBadge -Id "display" -Text (Get-WinToolText "drivers.badge.resolution" $width $height) -Kind "ok"
            }
        }
        elseif ($displays.Count -gt 1) {
            Set-WinToolDriverToolBadge -Id "display" -Text (Get-WinToolText "drivers.badge.displays" $displays.Count) -Kind "ok"
        }
    }

    if ($map.ContainsKey("network") -and [bool]$map["network"].Restart) {
        Set-WinToolDriverToolBadge -Id "network" -Text (Get-WinToolText "drivers.badge.restart") -Kind "caution"
    }

    if ($null -ne $script:WinToolState.DriverInfo) {
        (Get-WinToolUi -Name "DriversInfoText").Text = (Format-WinToolMachineSummary -Info $script:WinToolState.DriverInfo)
    }
    Update-WinToolDriverPcChip
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
        Update-WinToolDriverPcChip
    }
    elseif (-not $ok) {
        (Get-WinToolUi -Name "DriversInfoText").Text = (Get-WinToolText "drivers.info.failed")
        Update-WinToolDriverPcChip
    }
}

function Invoke-WinToolDriverScanClick {
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    Start-WinToolActivity -Title (Get-WinToolText "button.scanDrivers") | Out-Null
    $script:WinToolState.DriverMode = "simple"
    (Get-WinToolUi -Name "DriversModeSimple").IsChecked = $true
    Show-WinToolDriverScanUi
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 5 -Text (Get-WinToolText "status.scanningDrivers") -Summary (Get-WinToolText "status.summary.phase" (Get-WinToolText "drivers.phase.devices") 1 3) -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.scan.log") -Level "info"
    $script:WinToolState.DriverPhase = "devices"
    $script:WinToolState.DriverScanJob = Start-WinToolScriptJob -ScriptText (Get-WinToolDriverScanScript)
    Enable-WinToolLogPump
    Update-WinToolDriverScanProgress
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
        $cancelled = ($errorMessage -eq "Cancelled" -or $errorMessage -eq (Get-WinToolText "status.cancelled") -or $errorMessage -eq (Get-WinToolText "activity.cancelled") -or [bool]$script:WinToolState.DriverScanCancel)
        Show-WinToolDriverScanEnd
        Sync-WinToolBusyState -Busy $false
        if ($cancelled) {
            Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.cancelled") -Summary "" -Indeterminate $false
            $run = Complete-WinToolActivity -Summary (Get-WinToolText "activity.cancelled") -Status "warn"
        }
        else {
            Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.ready") -Summary "" -Indeterminate $false
            Write-WinToolLog -Message (Get-WinToolText "drivers.scan.failed" $errorMessage) -Level "error"
            $run = Complete-WinToolActivity -Summary (Get-WinToolText "drivers.scan.failed" $errorMessage) -Status "error"
        }
        if ($null -ne $run) { Show-WinToolActivityToast -Run $run }
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($warning)) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.warning" $warning) -Level "warn"
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
    $outdated = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "outdated" }).Count
    $missing = @($script:WinToolState.DriverRows | Where-Object { $_.Group -eq "missing" }).Count
    $runtimeAttention = @(Get-WinToolDriverAttentionRuntime -Row $script:WinToolState.DriverRows)
    $deviceCount = @($parsed.Device).Count
    Write-WinToolLog -Message (Get-WinToolText "drivers.scan.listed" $deviceCount) -Level "ok"
    $updateCount = @($parsed.Update).Count
    if ($updateCount -gt 0) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.updates.some" $updateCount) -Level "ok"
    }
    else {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.updates.none") -Level "ok"
    }
    Write-WinToolLog -Message (Get-WinToolText "drivers.scan.runtimes") -Level "ok"
    if ($runtimeAttention.Count -gt 0) {
        $names = @($runtimeAttention | ForEach-Object { [string]$_.Name })
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.runtimesNeeded" $runtimeAttention.Count ($names -join ", ")) -Level "warn"
    }
    $header = Format-WinToolDriverHeader -Outdated $outdated -Missing $missing -Runtime $runtimeAttention.Count
    $summary = Format-WinToolDriverStatusSummary -Outdated $outdated -Missing $missing -Runtime $runtimeAttention.Count
    Write-WinToolLog -Message $header -Level "ok"
    Show-WinToolDriverResult
    Sync-WinToolDriverToolCount
    Show-WinToolDriverScanEnd
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 100 -Text (Get-WinToolText "status.scanFinished") -Summary $summary -Indeterminate $false
    $run = Complete-WinToolActivity -Summary $summary -Status $(if ($runtimeAttention.Count -gt 0 -or $outdated -gt 0 -or $missing -gt 0) { "ok" } else { "ok" })
    if ($null -ne $run) { Show-WinToolToast -Title (Get-WinToolText "toast.scan.title") -Body $header -Kind "ok" }
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
    $runtimePending = @($rows | Where-Object { $_.Group -eq "runtime-pending" })
    $current = @($rows | Where-Object { $_.Group -eq "current" })
    $attention = @(Get-WinToolDriverAttentionRuntime -Row $rows)
    $runtimeCount = $attention.Count
    if (@($rows | Where-Object { $_.Group -eq "runtime-pending" }).Count -gt 0) {
        $runtimeCount = 0
    }
    (Get-WinToolUi -Name "DriversHeader").Text = (Format-WinToolDriverHeader -Outdated $outdated.Count -Missing $missing.Count -Runtime $runtimeCount)
    $hostPanel = Get-WinToolUi -Name "DriversGroupHost"
    $hostPanel.Children.Clear()
    $script:WinToolState.DriverCurrentBuilt = $false
    Add-WinToolDriverGroup -HostPanel $hostPanel -Title (Get-WinToolText "drivers.group.outdated") -Group "outdated" -Row $outdated -Expanded $( $outdated.Count -gt 0 )
    Add-WinToolDriverGroup -HostPanel $hostPanel -Title (Get-WinToolText "drivers.group.missing") -Group "missing" -Row $missing -Expanded $( $missing.Count -gt 0 )
    $runtimeTitle = Get-WinToolText "drivers.group.runtime"
    if ($runtimePending.Count -gt 0) {
        $runtimeTitle = Get-WinToolText "drivers.group.runtimePending"
    }
    Add-WinToolDriverGroup -HostPanel $hostPanel -Title $runtimeTitle -Group "runtime" -Row $attention -Expanded $( $attention.Count -gt 0 )
    Add-WinToolDriverGroup -HostPanel $hostPanel -Title (Get-WinToolText "drivers.group.current") -Group "current" -Row $current -Expanded $false -Lazy
    Show-WinToolDriverMode
    Update-WinToolDriverAdvanced
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
    $null = Set-WinToolDriverRowCheckbox -Row $Row -Checkbox $box
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
        $button.Content = (Get-WinToolText "button.update")
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

function Start-WinToolDriverActivity {
    param(
        [Parameter(Mandatory = $true)][string]$Title
    )
    Initialize-WinToolActivityState
    if ($null -eq $script:WinToolState.ActivityCurrent) {
        Start-WinToolActivity -Title $Title | Out-Null
    }
}

function Invoke-WinToolDriverUpdateClick {
    param($Row)
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    $selected = @(Get-WinToolDriverSelectedRow -Row $Row)
    if ($selected.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.update.noneSelected") -Level "warn"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $wu = @($selected | Where-Object { [string]$_.Kind -eq "device" -and $null -ne $_.Offer -and -not [string]::IsNullOrWhiteSpace([string]$_.Title) })
    $packages = @($selected | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.WingetId) })
    $missingNoOffer = @($selected | Where-Object { [string]$_.Kind -eq "device" -and ($null -eq $_.Offer -or [string]::IsNullOrWhiteSpace([string]$_.Title)) })
    $parts = New-Object System.Collections.Generic.List[string]
    if ($wu.Count -gt 0) { $parts.Add((Get-WinToolCountText "drivers.update.part.wu" $wu.Count)) | Out-Null }
    if ($packages.Count -gt 0) { $parts.Add((Get-WinToolCountText "drivers.update.part.package" $packages.Count)) | Out-Null }
    if ($missingNoOffer.Count -gt 0) { $parts.Add((Get-WinToolCountText "drivers.update.part.noOffer" $missingNoOffer.Count)) | Out-Null }
    $message = Get-WinToolText "drivers.update.confirm" ($parts.ToArray() -join (Get-WinToolText "drivers.join"))
    $ok = Request-WinToolConfirmation -Message $message -Title (Get-WinToolText "drivers.update.title")
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingInstall = [pscustomobject]@{
        Wu      = $wu
        Package = $packages
        Missing = $missingNoOffer
    }
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "drivers.update.title") -Handler "Invoke-WinToolDriverSelectedInstall" -NeedsRestore
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
        Write-WinToolLog -Message (Get-WinToolText "drivers.update.noMatch" ([string]$item.Name)) -Level "warn"
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
        $done = Get-WinToolText "drivers.update.packagesDone"
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
        Write-WinToolLog -Message (Get-WinToolText "drivers.update.noTitle") -Level "warn"
        return
    }
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    Start-WinToolDriverActivity -Title (Get-WinToolText "drivers.update.title")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.update.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolCountText "drivers.update.downloading" $titles.Count) -Level "info"
    $script:WinToolState.DriverToolKind = "install"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolUpdateInstallScript" -Argument @("IsInstalled=0 and Type='Driver'", ($titles.ToArray() -join "`n"))
}

function Start-WinToolDriverProtectedAction {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Handler,
        [switch]$NeedsRestore
    )
    Start-WinToolDriverActivity -Title $Title
    if ($NeedsRestore -and -not [bool]$script:WinToolState.RestorePointDone) {
        $script:WinToolState.DriverPending = $Handler
        Sync-WinToolBusyState -Busy $true
        Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.restore.progress") -Indeterminate $true
        Write-WinToolLog -Message (Get-WinToolText "drivers.restore.log" $Title) -Level "info"
        $script:WinToolState.RestoreJob = Start-WinToolRestorePointJob -Description (Get-WinToolText "drivers.restore.description")
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
        $continue = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.restore.missing" $ErrorMessage) -Title (Get-WinToolText "drivers.restore.title")
        if (-not $continue) {
            $script:WinToolState.DriverPending = $null
            Sync-WinToolBusyState -Busy $false
            Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.ready") -Summary "" -Indeterminate $false
            Write-WinToolLog -Message (Get-WinToolText "drivers.restore.notApplied") -Level "warn"
            return
        }
        Write-WinToolLog -Message (Get-WinToolText "drivers.restore.continue") -Level "warn"
    }
    else {
        Write-WinToolLog -Message (Get-WinToolText "drivers.restore.created") -Level "ok"
        $script:WinToolState.RestorePointDone = $true
    }
    $script:WinToolState.DriverPending = $null
    Sync-WinToolBusyState -Busy $false
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.ready") -Summary "" -Indeterminate $false
    if (-not [string]::IsNullOrWhiteSpace([string]$action)) {
        & ([string]$action)
    }
}

function Invoke-WinToolDriverBackupClick {
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $folder = Select-WinToolFolder -Description (Get-WinToolText "drivers.folder.backup")
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    Start-WinToolActivity -Title (Get-WinToolText "button.backUpDrivers") | Out-Null
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.backup.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.backup.exporting" $folder) -Level "info"
    $script:WinToolState.DriverToolKind = "backup"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverBackupScript" -Argument @($folder)
}

function Invoke-WinToolDriverToolClick {
    param([string]$Action)
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
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
        default { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.unknown" $Action) -Level "warn" }
    }
}

function Invoke-WinToolDriverOfflineClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $folder = Select-WinToolFolder -Description (Get-WinToolText "drivers.folder.offline")
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.offline.confirm" $folder) -Title (Get-WinToolText "drivers.offline.title")
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingFolder = $folder
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "drivers.offline.title") -Handler "Invoke-WinToolDriverOfflineStart" -NeedsRestore
}

function Invoke-WinToolDriverOfflineStart {
    $folder = [string]$script:WinToolState.DriverPendingFolder
    if ([string]::IsNullOrWhiteSpace($folder)) { return }
    Start-WinToolDriverActivity -Title (Get-WinToolText "drivers.offline.title")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.offline.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.offline.installing" $folder) -Level "info"
    $script:WinToolState.DriverToolKind = "offline"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverOfflineScript" -Argument @($folder)
}

function Invoke-WinToolDriverAudioClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.audio.confirm") -Title (Get-WinToolText "button.repairAudio")
    if (-not $ok) { return }
    Start-WinToolDriverActivity -Title (Get-WinToolText "button.repairAudio")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.audio.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.audio.log") -Level "info"
    $script:WinToolState.DriverToolKind = "audio"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverAudioScript"
}

function Invoke-WinToolDriverToggleClick {
    param([bool]$Enable)
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scanFirst.problem") -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverProblemDevice -Device $script:WinToolState.DriverDevices)
    if ($devices.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.problem.none") -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $kind = "drivers.toggle.disable"
    $jobAction = "disable"
    if ($Enable) {
        $kind = "drivers.toggle.enable"
        $jobAction = "enable"
    }
    $title = Get-WinToolText ($kind + ".title")
    $names = @($devices | ForEach-Object { [string]$_.Name } | Select-Object -First 12)
    $extra = ""
    if ($devices.Count -gt $names.Count) { $extra = (Get-WinToolText "drivers.list.more" ($devices.Count - $names.Count)) }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolCountText ($kind + ".confirm") $devices.Count ($names -join "`n") $extra) -Title $title
    if (-not $ok) { return }
    $ids = ($devices | ForEach-Object { [string]$_.InstanceId }) -join "`n"
    $script:WinToolState.DriverPendingToggle = [pscustomobject]@{
        Ids    = $ids
        Action = $jobAction
        Title  = $title
    }
    if ($Enable) {
        Invoke-WinToolDriverToggleStart
    }
    else {
        Start-WinToolDriverProtectedAction -Title $title -Handler "Invoke-WinToolDriverToggleStart" -NeedsRestore
    }
}

function Invoke-WinToolDriverToggleStart {
    $pending = $script:WinToolState.DriverPendingToggle
    if ($null -eq $pending) { return }
    $title = [string]$pending.Title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = Get-WinToolText "drivers.toggle.disable.title" }
    Start-WinToolDriverActivity -Title $title
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text $title -Indeterminate $true
    $script:WinToolState.DriverToolKind = "toggle"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverToggleScript" -Argument @([string]$pending.Ids, [string]$pending.Action)
}

function Invoke-WinToolDriverRescanClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.rescan.confirm") -Title (Get-WinToolText "drivers.rescan.title")
    if (-not $ok) { return }
    Start-WinToolDriverActivity -Title (Get-WinToolText "drivers.rescan.title")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.rescan.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.rescan.log") -Level "info"
    $script:WinToolState.DriverToolKind = "rescan"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverRescanScript"
}

function Invoke-WinToolDriverGhostClick {
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scanFirst.ghost") -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverGhostDevice -Device $script:WinToolState.DriverDevices)
    if ($devices.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.ghost.none") -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $names = @($devices | ForEach-Object { [string]$_.Name } | Select-Object -First 12)
    $extra = ""
    if ($devices.Count -gt $names.Count) { $extra = (Get-WinToolText "drivers.list.more" ($devices.Count - $names.Count)) }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolCountText "drivers.ghost.confirm" $devices.Count ($names -join "`n") $extra) -Title (Get-WinToolText "drivers.tool.ghost.name")
    if (-not $ok) { return }
    $ids = ($devices | ForEach-Object { [string]$_.InstanceId }) -join "`n"
    $script:WinToolState.DriverPendingIds = $ids
    $script:WinToolState.DriverPendingCount = $devices.Count
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "drivers.tool.ghost.name") -Handler "Invoke-WinToolDriverGhostStart" -NeedsRestore
}

function Invoke-WinToolDriverGhostStart {
    $ids = [string]$script:WinToolState.DriverPendingIds
    $count = [int]$script:WinToolState.DriverPendingCount
    if ([string]::IsNullOrWhiteSpace($ids)) { return }
    Start-WinToolDriverActivity -Title (Get-WinToolText "drivers.tool.ghost.name")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.ghost.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolCountText "drivers.ghost.removing" $count) -Level "info"
    $script:WinToolState.DriverToolKind = "remove"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverRemoveScript" -Argument @($ids)
}

function Invoke-WinToolDriverNetworkClick {
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.network.confirm") -Title (Get-WinToolText "drivers.tool.network.name")
    if (-not $ok) { return }
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "drivers.tool.network.name") -Handler "Invoke-WinToolDriverNetworkStart" -NeedsRestore
}

function Invoke-WinToolDriverNetworkStart {
    Start-WinToolDriverActivity -Title (Get-WinToolText "drivers.tool.network.name")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "drivers.network.progress") -Indeterminate $true
    Write-WinToolLog -Message (Get-WinToolText "drivers.network.log") -Level "info"
    $script:WinToolState.DriverToolKind = "network"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverNetworkScript"
}

function Invoke-WinToolDriverDisplayClick {
    $displays = @($script:WinToolState.DriverDisplays)
    if (-not [bool]$script:WinToolState.DriverScanned -or $displays.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scanFirst.display") -Level "warn"
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
        Write-WinToolLog -Message (Get-WinToolText "drivers.runtime.checking") -Level "warn"
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
        Write-WinToolLog -Message (Get-WinToolText "drivers.runtime.none") -Level "ok"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolCountText "drivers.runtime.confirm" $rows.Count) -Title (Get-WinToolText "drivers.tool.runtime.name")
    if (-not $ok) { return }
    $script:WinToolState.DriverPendingApps = @($rows | ForEach-Object { [pscustomobject]@{ name = [string]$_.Name; wingetId = [string]$_.WingetId; scope = [string]$_.Scope } })
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "drivers.tool.runtime.name") -Handler "Invoke-WinToolDriverRuntimeStart" -NeedsRestore
}

function Invoke-WinToolDriverRuntimeStart {
    $apps = @($script:WinToolState.DriverPendingApps)
    $script:WinToolState.DriverPendingApps = $null
    if ($apps.Count -eq 0) { return }
    Invoke-WinToolPlanAsync -Step (Get-WinToolAppPlan -App $apps) -DoneMessage (Get-WinToolText "drivers.runtime.done")
}

function Invoke-WinToolDriverIncompatibleClick {
    if (-not [bool]$script:WinToolState.DriverScanned) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scanFirst.incompatible") -Level "warn"
        return
    }
    $devices = @(Get-WinToolDriverIncompatibleDevice -Device $script:WinToolState.DriverDevices -MemoryIntegrity ([bool]$script:WinToolState.DriverHvci))
    if ($devices.Count -eq 0) {
        if ([bool]$script:WinToolState.DriverHvci) {
            Write-WinToolLog -Message (Get-WinToolText "drivers.incompatible.noneHvci") -Level "ok"
        }
        else {
            Write-WinToolLog -Message (Get-WinToolText "drivers.incompatible.none") -Level "ok"
        }
        return
    }
    if ([bool]$script:WinToolState.DriverHvci) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.incompatible.hvci") -Level "info"
    }
    foreach ($item in $devices) {
        $label = Get-WinToolDriverProblemName -Code ([int]$item.Problem)
        Write-WinToolLog -Message (Get-WinToolText "drivers.incompatible.item" ([string]$item.Name) $label) -Level "warn"
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
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "status.ready") -Summary "" -Indeterminate $false
    foreach ($line in $log) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
            Write-WinToolLog -Message ([string]$line) -Level "info"
        }
    }
    if (-not $ok) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.tool.failed" $errorMessage) -Level "error"
        $failed = Complete-WinToolActivity -Summary (Get-WinToolText "drivers.tool.failed" $errorMessage) -Status "error"
        if ($null -ne $failed) { Show-WinToolActivityToast -Run $failed }
        return
    }
    switch ($kind) {
        "backup" { Write-WinToolLog -Message (Get-WinToolCountText "drivers.tool.backup.done" $count) -Level "ok" }
        "offline" { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.offline.done") -Level "ok" }
        "install" {
            if ($count -eq 0) {
                Write-WinToolLog -Message (Get-WinToolText "drivers.tool.install.none") -Level "warn"
            }
            else {
                Write-WinToolLog -Message (Get-WinToolCountText "drivers.tool.install.done" $count) -Level "ok"
            }
        }
        "audio" { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.audio.done") -Level "ok" }
        "network" { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.network.done") -Level "ok" }
        "remove" { Write-WinToolLog -Message (Get-WinToolCountText "drivers.tool.remove.done" $count) -Level "ok" }
        "rescan" { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.rescan.done") -Level "ok" }
        "toggle" { Write-WinToolLog -Message (Get-WinToolCountText "drivers.tool.toggle.done" $count) -Level "ok" }
        "rollback" { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.rollback.done") -Level "ok" }
        default { Write-WinToolLog -Message (Get-WinToolText "drivers.tool.finished") -Level "ok" }
    }
    if ($reboot) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.tool.reboot") -Level "warn"
    }
    $finished = Complete-WinToolActivity -Summary $(if ($ok) { Get-WinToolText "drivers.tool.finished" } else { $errorMessage })
    if ($null -ne $finished) { Show-WinToolActivityToast -Run $finished }
}


function Show-WinToolDriverScanUi {
    $script:WinToolState.DriverPhase = "devices"
    (Get-WinToolUi -Name "DriversStart").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversResult").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversScanning").Visibility = "Visible"
    (Get-WinToolUi -Name "DriversSimpleScroll").Visibility = "Visible"
    (Get-WinToolUi -Name "DriversAdvanced").Visibility = "Collapsed"
    (Get-WinToolUi -Name "DriversToolsScroll").Visibility = "Collapsed"
    $hostPanel = Get-WinToolUi -Name "DriversPhaseHost"
    $hostPanel.Children.Clear()
    $script:WinToolState.DriverPhaseRow = @{}
    foreach ($id in @("devices", "updates", "runtimes")) {
        $card = New-WinToolCard
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $card.Padding = [System.Windows.Thickness]::new(14, 12, 14, 12)
        $title = New-WinToolText -Text (Get-WinToolText ("drivers.phase." + $id)) -Weight "SemiBold"
        $sub = New-WinToolText -Text (Get-WinToolText ("drivers.phase." + $id + ".sub")) -Brush "BrushMuted" -Wrap
        $sub.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        $state = New-WinToolText -Text (Get-WinToolText "drivers.phase.pending") -Brush "BrushMuted"
        $state.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add($title)
        [void]$stack.Children.Add($sub)
        [void]$stack.Children.Add($state)
        $card.Child = $stack
        [void]$hostPanel.Children.Add($card)
        $script:WinToolState.DriverPhaseRow[$id] = [pscustomobject]@{ Card = $card; State = $state }
    }
}

function Update-WinToolDriverScanProgress {
    $job = $script:WinToolState.DriverScanJob
    if ($null -eq $job) { return }
    $phase = [string]$job.Sync.Phase
    if ([string]::IsNullOrWhiteSpace($phase)) { $phase = [string]$script:WinToolState.DriverPhase }
    if ([string]::IsNullOrWhiteSpace($phase)) { $phase = "devices" }
    $script:WinToolState.DriverPhase = $phase
    $order = @("devices", "updates", "runtimes")
    $index = [Math]::Max(0, [array]::IndexOf($order, $phase))
    $phaseName = Get-WinToolText ("drivers.phase." + $phase)
    Sync-WinToolProgress -Value (10 + ($index * 30)) -Text (Get-WinToolText "status.scanningDrivers") -Summary (Get-WinToolText "status.summary.phase" $phaseName ($index + 1) 3) -Indeterminate $true
    $rows = $script:WinToolState.DriverPhaseRow
    if ($null -eq $rows) { return }
    for ($i = 0; $i -lt $order.Count; $i++) {
        $id = $order[$i]
        if (-not $rows.ContainsKey($id)) { continue }
        $entry = $rows[$id]
        $state = $entry.State
        $card = $entry.Card
        if ($i -lt $index) {
            $state.Text = Get-WinToolText "drivers.phase.done"
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushOkLine")
        }
        elseif ($i -eq $index) {
            $state.Text = Get-WinToolText "drivers.phase.running"
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushAccent")
        }
        else {
            $state.Text = Get-WinToolText "drivers.phase.pending"
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        }
    }
}

function Show-WinToolDriverScanEnd {
    $script:WinToolState.DriverPhase = ""
    $script:WinToolState.DriverScanCancel = $false
    if ([bool]$script:WinToolState.DriverScanned) {
        (Get-WinToolUi -Name "DriversStart").Visibility = "Collapsed"
        (Get-WinToolUi -Name "DriversResult").Visibility = "Visible"
        (Get-WinToolUi -Name "DriversScanning").Visibility = "Collapsed"
    }
    else {
        Show-WinToolDriverHome
    }
    Show-WinToolDriverMode
}

function Complete-WinToolDriverScanCancel {
    $job = $script:WinToolState.DriverScanJob
    if ($null -eq $job) { return }
    $script:WinToolState.DriverScanCancel = $true
    try { $job.Sync.Cancel = $true } catch { $null = $_.Exception.Message }
}

function Get-WinToolDriverCategoryRow {
    param([string]$Group)
    $rows = @($script:WinToolState.DriverRows)
    $devices = @($script:WinToolState.DriverDevices)
    switch ($Group) {
        "outdated" { return @($rows | Where-Object { $_.Group -eq "outdated" }) }
        "missing" { return @($rows | Where-Object { $_.Group -eq "missing" }) }
        "runtime" { return @($rows | Where-Object { $_.Kind -eq "runtime" }) }
        "gpu" { return @($rows | Where-Object { $_.Group -eq "gpu" }) }
        "current" { return @($rows | Where-Object { $_.Group -eq "current" }) }
        "problem" {
            $items = @(Get-WinToolDriverProblemDevice -Device $devices)
            return @(foreach ($item in $items) { ConvertTo-WinToolDriverRow -Device $item -Group "problem" })
        }
        "ghost" {
            $items = @(Get-WinToolDriverGhostDevice -Device $devices)
            return @(foreach ($item in $items) { ConvertTo-WinToolDriverRow -Device $item -Group "ghost" })
        }
    }
    return @()
}

function Update-WinToolDriverAdvanced {
    if ([string]$script:WinToolState.DriverMode -ne "advanced") { return }
    $hostPanel = Get-WinToolUi -Name "DriversCategoryHost"
    if ($null -eq $hostPanel) { return }
    $hostPanel.Children.Clear()
    $groups = @(
        , @("outdated", "drivers.group.outdated")
        , @("missing", "drivers.group.missing")
        , @("runtime", "drivers.group.runtime")
        , @("gpu", "drivers.group.gpu")
        , @("current", "drivers.group.current")
        , @("problem", "drivers.group.problem")
        , @("ghost", "drivers.group.ghost")
    )
    $selected = [string]$script:WinToolState.DriverCategory
    if ([string]::IsNullOrWhiteSpace($selected)) { $selected = "outdated" }
    foreach ($entry in $groups) {
        $id = [string]$entry[0]
        $count = @(Get-WinToolDriverCategoryRow -Group $id).Count
        $button = New-Object System.Windows.Controls.Button
        $button.HorizontalContentAlignment = "Stretch"
        $button.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $button.Cursor = "Hand"
        $button.Style = $script:WinToolWindow.FindResource("QuietButton")
        if ($id -eq $selected) {
            $button.SetResourceReference([System.Windows.Controls.Button]::BackgroundProperty, "BrushAccentSoft")
        }
        $row = New-Object System.Windows.Controls.Grid
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto }))
        $name = New-WinToolText -Text (Get-WinToolText ([string]$entry[1])) -Weight "SemiBold"
        $name.VerticalAlignment = "Center"
        $name.HorizontalAlignment = "Left"
        $name.TextAlignment = "Left"
        $name.TextWrapping = "Wrap"
        $name.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        [void]$row.Children.Add($name)
        $badge = New-WinToolBadge -Text ([string]$count) -Kind "ok"
        $badge.VerticalAlignment = "Center"
        $badge.HorizontalAlignment = "Right"
        $badge.MinWidth = 28
        [System.Windows.Controls.Grid]::SetColumn($badge, 1)
        [void]$row.Children.Add($badge)
        $button.Content = $row
        $button.HorizontalContentAlignment = "Stretch"
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: category " + $id) -Data $id -Action {
            param($source, $eventData, $boundGroup)
            $null = $source, $eventData
            $script:WinToolState.DriverCategory = [string]$boundGroup
            $script:WinToolState.DriverSelected = $null
            Update-WinToolDriverAdvanced
        }
        [void]$hostPanel.Children.Add($button)
    }
    Update-WinToolDriverDeviceList
}

function Update-WinToolDriverDeviceList {
    $group = [string]$script:WinToolState.DriverCategory
    if ([string]::IsNullOrWhiteSpace($group)) { $group = "outdated" }
    $titleKey = "drivers.group." + $group
    (Get-WinToolUi -Name "DriversDeviceTitle").Text = (Get-WinToolText $titleKey)
    $hostPanel = Get-WinToolUi -Name "DriversDeviceHost"
    $hostPanel.Children.Clear()
    $items = @(Get-WinToolDriverCategoryRow -Group $group)
    if ($items.Count -eq 0) {
        $empty = New-WinToolText -Text (Get-WinToolText "drivers.advanced.emptyList") -Brush "BrushMuted" -Wrap
        $empty.Margin = [System.Windows.Thickness]::new(6, 8, 6, 8)
        [void]$hostPanel.Children.Add($empty)
        $script:WinToolState.DriverSelected = $null
        Update-WinToolDriverDetail
        return
    }
    $selected = $script:WinToolState.DriverSelected
    if ($null -eq $selected -or @($items | Where-Object { [string]$_.Id -eq [string]$selected.Id }).Count -eq 0) {
        $selected = $items[0]
        $script:WinToolState.DriverSelected = $selected
    }
    foreach ($item in $items) {
        $button = New-Object System.Windows.Controls.Button
        $button.HorizontalContentAlignment = "Stretch"
        $button.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $button.Cursor = "Hand"
        $button.Style = $script:WinToolWindow.FindResource("QuietButton")
        if ([string]$item.Id -eq [string]$selected.Id) {
            $button.SetResourceReference([System.Windows.Controls.Button]::BackgroundProperty, "BrushAccentSoft")
        }
        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add((New-WinToolText -Text ([string]$item.Name) -Weight "SemiBold" -Wrap))
        $source = Get-WinToolText "drivers.source.none"
        if ($null -ne $item.Offer) { $source = Get-WinToolText "drivers.source.wu" }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item.WingetId)) { $source = Get-WinToolText "drivers.source.winget" }
        $src = New-WinToolText -Text $source -Brush "BrushMuted"
        $src.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$stack.Children.Add($src)
        $cls = New-WinToolText -Text ([string]$item.Class) -Brush "BrushMuted"
        [void]$stack.Children.Add($cls)
        $ver = New-WinToolText -Text (Format-WinToolDriverDetail -Row $item) -Brush "BrushMuted" -Wrap
        $ver.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        [void]$stack.Children.Add($ver)
        $button.Content = $stack
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: select " + [string]$item.Name) -Data $item -Action {
            param($source, $eventData, $boundRow)
            $null = $source, $eventData
            $script:WinToolState.DriverSelected = $boundRow
            Update-WinToolDriverDeviceList
        }
        [void]$hostPanel.Children.Add($button)
    }
    Update-WinToolDriverDetail
}

function Update-WinToolDriverDetail {
    $hostPanel = Get-WinToolUi -Name "DriversDetailHost"
    $hostPanel.Children.Clear()
    $row = $script:WinToolState.DriverSelected
    if ($null -eq $row) {
        [void]$hostPanel.Children.Add((New-WinToolText -Text (Get-WinToolText "drivers.advanced.emptyDetail") -Brush "BrushMuted" -Wrap))
        return
    }
    [void]$hostPanel.Children.Add((New-WinToolText -Text ([string]$row.Name) -Weight "Bold" -Wrap))
    $problem = [int]$row.Problem
    $kind = [string]$row.Class
    if ($problem -gt 0) {
        $kind = Get-WinToolText "drivers.kind.problem" $row.Class (Get-WinToolDriverProblemName -Code $problem)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($kind)) {
        $kind = Get-WinToolText "drivers.kind.working" $row.Class
    }
    $kindBlock = New-WinToolText -Text $kind -Brush "BrushMuted" -Wrap
    $kindBlock.Margin = [System.Windows.Thickness]::new(0, 4, 0, 12)
    [void]$hostPanel.Children.Add($kindBlock)

    $device = $row.Device
    $inf = [string](Get-WinToolNote -Object $device -Name "Inf" -Default "")
    $hardware = @()
    if ($null -ne $device) { $hardware = @(Get-WinToolNote -Object $device -Name "HardwareId" -Default @()) }
    $hardwareText = ($hardware | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace([string]$hardwareText)) { $hardwareText = Get-WinToolText "drivers.source.none" }
    $statusText = Get-WinToolText "drivers.status.ok"
    if ($problem -gt 0) {
        $statusText = Get-WinToolText "drivers.status.code" (Get-WinToolDriverProblemName -Code $problem) $problem
    }
    $source = Get-WinToolText "drivers.source.none"
    if ($null -ne $row.Offer) { $source = Get-WinToolText "drivers.source.wu" }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$row.WingetId)) { $source = Get-WinToolText "drivers.source.winget" }
    $current = [string]$row.Version
    $currentDate = Format-WinToolDriverDate -Value $row.Date
    if (-not [string]::IsNullOrWhiteSpace($current) -and -not [string]::IsNullOrWhiteSpace($currentDate)) {
        $current = $current + " - " + $currentDate
    }
    $available = [string]$row.AvailableVersion
    $availableDate = Format-WinToolDriverDate -Value $row.AvailableDate
    if (-not [string]::IsNullOrWhiteSpace($available) -and -not [string]::IsNullOrWhiteSpace($availableDate)) {
        $available = $available + " - " + $availableDate
    }
    $fields = @(
        , @("drivers.field.provider", [string]$row.Provider)
        , @("drivers.field.hardwareId", [string]$hardwareText)
        , @("drivers.field.inf", $(if ([string]::IsNullOrWhiteSpace($inf)) { Get-WinToolText "drivers.source.none" } else { $inf }))
        , @("drivers.field.status", $statusText)
        , @("drivers.field.current", $(if ([string]::IsNullOrWhiteSpace($current)) { Get-WinToolText "drivers.source.none" } else { $current }))
        , @("drivers.field.available", $(if ([string]::IsNullOrWhiteSpace($available)) { Get-WinToolText "drivers.source.none" } else { $available }))
        , @("drivers.field.source", $source)
        , @("drivers.field.instanceId", [string]$row.Id)
    )
    foreach ($field in $fields) {
        $label = New-WinToolText -Text (Get-WinToolText ([string]$field[0])) -Brush "BrushMuted"
        $value = New-WinToolText -Text ([string]$field[1]) -Wrap
        $value.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        if ([string]$field[0] -eq "drivers.field.hardwareId" -or [string]$field[0] -eq "drivers.field.instanceId") {
            $value.FontFamily = [System.Windows.Media.FontFamily]::new("Consolas")
        }
        [void]$hostPanel.Children.Add($label)
        [void]$hostPanel.Children.Add($value)
    }

    $actions = New-Object System.Windows.Controls.WrapPanel
    $actions.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
    $group = [string]$row.Group
    $buttons = New-Object System.Collections.Generic.List[object]
    if ($group -eq "outdated" -or $group -eq "missing" -or $group -eq "runtime" -or $group -eq "gpu") {
        $buttons.Add(@((Get-WinToolText "button.update"), "update", $true)) | Out-Null
    }
    if ([string]$row.Kind -eq "device") {
        $buttons.Add(@((Get-WinToolText "button.rollback"), "rollback", $false)) | Out-Null
        $buttons.Add(@((Get-WinToolText "button.disable"), "disable", $false)) | Out-Null
        $buttons.Add(@((Get-WinToolText "button.uninstall"), "uninstall", $false)) | Out-Null
        $buttons.Add(@((Get-WinToolText "button.openDeviceManager"), "devmgmt", $false)) | Out-Null
    }
    foreach ($entry in $buttons) {
        $button = New-Object System.Windows.Controls.Button
        $button.Content = [string]$entry[0]
        $button.Height = 32
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $button.Padding = [System.Windows.Thickness]::new(14, 0, 14, 0)
        if ([bool]$entry[2]) { $button.Style = $script:WinToolWindow.FindResource("PrimaryButton") }
        else { $button.Style = $script:WinToolWindow.FindResource("SecondaryButton") }
        $action = [string]$entry[1]
        Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Drivers: detail " + $action) -Data $action -Action {
            param($source, $eventData, $boundAction)
            $null = $source, $eventData
            Invoke-WinToolDriverDetailAction -Action $boundAction
        }
        Add-WinToolBusyControl -Control $button
        [void]$actions.Children.Add($button)
    }
    [void]$hostPanel.Children.Add($actions)
}

function Invoke-WinToolDriverDetailAction {
    param([string]$Action)
    $row = $script:WinToolState.DriverSelected
    if ($null -eq $row) { return }
    switch ($Action) {
        "update" { Invoke-WinToolDriverUpdateClick -Row $row }
        "disable" { Invoke-WinToolDriverToolClick -Action "disable" }
        "uninstall" { Invoke-WinToolDriverToolClick -Action "ghost" }
        "rollback" { Invoke-WinToolDriverRollbackClick }
        "devmgmt" { Invoke-WinToolDriverDeviceManager }
    }
}

function Invoke-WinToolDriverRollbackClick {
    $row = $script:WinToolState.DriverSelected
    if ($null -eq $row) { return }
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "status.wait") -Level "warn"
        return
    }
    if (-not (Test-WinToolDriverAdminReady)) { return }
    $inf = [string](Get-WinToolNote -Object $row.Device -Name "Inf" -Default "")
    if ([string]::IsNullOrWhiteSpace($inf)) {
        Invoke-WinToolDriverDeviceManager
        return
    }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "drivers.rollback.confirm" ([string]$row.Name)) -Title (Get-WinToolText "button.rollback")
    if (-not $ok) { return }
    Start-WinToolActivity -Title (Get-WinToolText "button.rollback") | Out-Null
    Start-WinToolDriverProtectedAction -Title (Get-WinToolText "button.rollback") -Handler "Start-WinToolDriverRollbackJob" -NeedsRestore
}

function Start-WinToolDriverRollbackJob {
    $row = $script:WinToolState.DriverSelected
    $inf = [string](Get-WinToolNote -Object $row.Device -Name "Inf" -Default "")
    Sync-WinToolBusyState -Busy $true
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "button.rollback") -Indeterminate $true
    $script:WinToolState.DriverToolKind = "rollback"
    $script:WinToolState.DriverToolJob = Start-WinToolPrivilegedScriptJob -Factory "Get-WinToolDriverRollbackScript" -Argument @($inf)
}

function Invoke-WinToolDriverDeviceManager {
    try {
        Start-Process -FilePath "devmgmt.msc" | Out-Null
    }
    catch {
        Write-WinToolLog -Message $_.Exception.Message -Level "warn"
    }
}
