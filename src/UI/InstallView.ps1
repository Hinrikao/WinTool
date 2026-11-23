# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolInstallView {
    $catalog = Get-WinToolAppCatalog
    $hostPanel = Get-WinToolUi -Name "AppCategories"
    $hostPanel.Children.Clear()
    $script:WinToolState.AppRows = @()
    $script:WinToolState.CategoryRows = @()

    foreach ($category in @(Get-WinToolNote -Object $catalog -Name "categories" -Default @())) {
        $card = New-WinToolCard
        $stack = New-Object System.Windows.Controls.StackPanel
        $header = New-Object System.Windows.Controls.Grid
        $header.ColumnDefinitions.Add((New-WinToolColumn))
        $header.ColumnDefinitions.Add((New-WinToolColumn -Auto))

        $titleStack = New-Object System.Windows.Controls.StackPanel
        [void]$titleStack.Children.Add((New-WinToolText -Text ([string]$category.name) -Size 18 -Weight "SemiBold"))
        $description = [string](Get-WinToolNote -Object $category -Name "description" -Default "")
        [void]$titleStack.Children.Add((New-WinToolText -Text $description -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 4, 16, 0))))
        [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
        [void]$header.Children.Add($titleStack)

        $selectAll = New-Object System.Windows.Controls.CheckBox
        $selectAll.Content = "Select all"
        $selectAll.VerticalAlignment = "Center"
        $selectAll.IsThreeState = $true
        [System.Windows.Controls.Grid]::SetColumn($selectAll, 1)
        [void]$header.Children.Add($selectAll)
        [void]$stack.Children.Add($header)

        $appsPanel = New-Object System.Windows.Controls.StackPanel
        $appsPanel.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
        $appRows = @()
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $row = New-WinToolAppRow -App $app -CategoryName ([string]$category.name)
            [void]$appsPanel.Children.Add($row.Panel)
            $appRows += $row
        }
        [void]$stack.Children.Add($appsPanel)
        $card.Child = $stack
        [void]$hostPanel.Children.Add($card)

        $categoryRow = [pscustomobject]@{
            Id = [string]$category.id
            Card = $card
            SelectAll = $selectAll
            Apps = $appRows
            Updating = $false
        }
        $script:WinToolState.CategoryRows += $categoryRow
        foreach ($row in $appRows) {
            $script:WinToolState.AppRows += $row
        }

        Register-WinToolUiEvent -Control $selectAll -EventName "Click" -Name "Install: select all in category" -Data $categoryRow -Action {
            param($source, $eventData, $boundCategory)
            $null = $source, $eventData
            Sync-WinToolCategoryFromHeader -CategoryRow $boundCategory
        }
        foreach ($row in $appRows) {
            foreach ($eventName in @("Checked", "Unchecked")) {
                Register-WinToolUiEvent -Control $row.Checkbox -EventName $eventName -Name "Install: tick an app" -Data $categoryRow -Action {
                    param($source, $eventData, $boundCategory)
                    $null = $source, $eventData
                    Sync-WinToolAppToggle -CategoryRow $boundCategory
                }
            }
        }
    }

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppSearch") -EventName "TextChanged" -Name "Install: search" -Action {
        Sync-WinToolSearchHint -BoxName "AppSearch" -HintName "AppSearchHint"
        Update-WinToolAppFilter
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppSelectVisible") -EventName "Click" -Name "Install: select visible" -Action {
        foreach ($row in @($script:WinToolState.AppRows)) {
            if ($row.Panel.Visibility -eq "Visible") {
                $row.Checkbox.IsChecked = $true
            }
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppClear") -EventName "Click" -Name "Install: clear" -Action {
        Sync-WinToolAppCheck -Id @() -OnlyThese
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppInstall") -EventName "Click" -Name "Install: install selected" -Action {
        Invoke-WinToolInstallClick
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppSelectInstalled") -EventName "Click" -Name "Install: select installed" -Action {
        Select-WinToolInstalledApp
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppRefreshInstalled") -EventName "Click" -Name "Install: check installed" -Action {
        Start-WinToolAppDetection
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppUpdate") -EventName "Click" -Name "Install: update selected" -Action {
        Invoke-WinToolAppAction -App @(Get-WinToolCheckedApp) -Action "upgrade"
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppUninstall") -EventName "Click" -Name "Install: uninstall selected" -Action {
        Invoke-WinToolAppAction -App @(Get-WinToolCheckedApp) -Action "uninstall"
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppUpgradeAll") -EventName "Click" -Name "Install: update all" -Action {
        Invoke-WinToolUpgradeAllClick
    }
    Sync-WinToolAppCount
}

function New-WinToolAppRow {
    param(
        $App,
        [string]$CategoryName
    )
    $tags = @(Get-WinToolNote -Object $App -Name "tags" -Default @()) -join " "
    $panel = New-Object System.Windows.Controls.Grid
    $panel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $panel.ColumnDefinitions.Add((New-WinToolColumn))

    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.VerticalAlignment = "Top"
    $checkbox.Margin = [System.Windows.Thickness]::new(0, 2, 10, 0)
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 0)
    [void]$panel.Children.Add($checkbox)

    $text = New-Object System.Windows.Controls.StackPanel
    $titleLine = New-Object System.Windows.Controls.StackPanel
    $titleLine.Orientation = "Horizontal"
    [void]$titleLine.Children.Add((New-WinToolText -Text ([string]$App.name) -Weight "SemiBold"))
    $installedBadge = New-WinToolBadge -Text "Installed" -Kind "ok"
    $installedBadge.Visibility = "Collapsed"
    [void]$titleLine.Children.Add($installedBadge)
    $updateBadge = New-WinToolBadge -Text "Update available" -Kind "caution"
    $updateBadge.Visibility = "Collapsed"
    [void]$titleLine.Children.Add($updateBadge)
    [void]$text.Children.Add($titleLine)
    [void]$text.Children.Add((New-WinToolText -Text ([string]$App.description) -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 2, 0, 0))))
    [void]$text.Children.Add((New-WinToolText -Text ("winget: " + [string]$App.wingetId) -Size 12 -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 2, 0, 0))))
    [System.Windows.Controls.Grid]::SetColumn($text, 1)
    [void]$panel.Children.Add($text)

    $search = (@([string]$App.name, [string]$App.description, [string]$App.wingetId, [string]$App.id, $tags, $CategoryName) -join " ")
    $row = [pscustomobject]@{
        Id = [string]$App.id
        Name = [string]$App.name
        WingetId = [string]$App.wingetId
        DetectNames = @(Get-WinToolNote -Object $App -Name "detectNames" -Default @())
        Scope = [string](Get-WinToolNote -Object $App -Name "scope" -Default "")
        SearchText = $search
        Panel = $panel
        Checkbox = $checkbox
        InstalledBadge = $installedBadge
        UpdateBadge = $updateBadge
        Installed = $false
        UpdateAvailable = $false
    }

    # Right-click an app for a one-off update or uninstall.
    $menu = New-Object System.Windows.Controls.ContextMenu
    foreach ($choice in @(
            [pscustomobject]@{ Header = "Update this app"; Action = "upgrade"; Name = "Install: update one app" },
            [pscustomobject]@{ Header = "Uninstall this app"; Action = "uninstall"; Name = "Install: uninstall one app" }
        )) {
        $item = New-Object System.Windows.Controls.MenuItem
        $item.Header = $choice.Header
        Register-WinToolUiEvent -Control $item -EventName "Click" -Name $choice.Name -Data ([pscustomobject]@{ Row = $row; Action = $choice.Action }) -Action {
            param($source, $eventData, $target)
            $null = $source, $eventData
            Invoke-WinToolAppAction -App @($target.Row) -Action $target.Action
        }
        [void]$menu.Items.Add($item)
    }
    $panel.ContextMenu = $menu
    $panel.Background = [System.Windows.Media.Brushes]::Transparent
    return $row
}

function Sync-WinToolAppBadge {
    param($Row)
    if ($Row.Installed) {
        $Row.InstalledBadge.Visibility = "Visible"
    }
    else {
        $Row.InstalledBadge.Visibility = "Collapsed"
    }
    if ($Row.UpdateAvailable) {
        $Row.UpdateBadge.Visibility = "Visible"
    }
    else {
        $Row.UpdateBadge.Visibility = "Collapsed"
    }
}

$script:WinToolDetectTimeoutSeconds = 300

function Start-WinToolAppDetection {
    if ($null -ne $script:WinToolState.DetectJob) {
        return
    }
    $status = Get-WinToolUi -Name "AppInstalledStatus"
    $candidates = @(Get-WinToolWingetCandidate)
    if ($candidates.Count -eq 0) {
        $status.Text = "winget not found, so installed apps cannot be checked."
        Write-WinToolLog -Message "Installed apps: winget.exe was not found on this PC." -Level "warn" -Diagnostic
        return
    }
    $status.Text = "Checking installed apps..."
    Write-WinToolLog -Message ("Installed apps: checking with winget. Candidates: " + ($candidates -join "; ")) -Level "info" -Diagnostic
    $exportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-installed-" + [guid]::NewGuid().ToString("N") + ".json")
    $job = Start-WinToolScriptJob -ScriptText (Get-WinToolAppDetectionScript) -Argument @($candidates, $exportPath)
    $job | Add-Member -NotePropertyName Started -NotePropertyValue ([DateTime]::UtcNow)
    $script:WinToolState.DetectJob = $job
}

function Test-WinToolAppDetectionTimeout {
    $job = $script:WinToolState.DetectJob
    if ($null -eq $job -or $job.Sync.Done) {
        return
    }
    if (([DateTime]::UtcNow - $job.Started).TotalSeconds -lt $script:WinToolDetectTimeoutSeconds) {
        return
    }
    Write-WinToolDetectionLog -Job $job
    Stop-WinToolThread -Job $job
    $script:WinToolState.DetectJob = $null
    (Get-WinToolUi -Name "AppInstalledStatus").Text = "Checking installed apps took too long. Press Refresh to try again."
    Write-WinToolLog -Message ("Installed apps: winget did not finish in {0} seconds, so the check was stopped." -f $script:WinToolDetectTimeoutSeconds) -Level "warn" -Diagnostic
}

function Write-WinToolDetectionLog {
    param($Job)
    if ($null -eq $Job -or $null -eq $Job.Sync.Log) {
        return
    }
    foreach ($line in @($Job.Sync.Log.ToArray())) {
        Write-WinToolLog -Message ("Installed apps: " + [string]$line) -Level "info" -Diagnostic
    }
}

function Complete-WinToolAppDetection {
    $job = $script:WinToolState.DetectJob
    if ($null -eq $job) {
        return
    }
    $ok = [bool]$job.Sync.Ok
    $errorMessage = [string]$job.Sync.Error
    $exportText = [string]$job.Sync.ExportText
    $listText = [string]$job.Sync.ListText
    $upgradeText = [string]$job.Sync.UpgradeText
    $winget = [string]$job.Sync.Winget
    $displayNames = @()
    if ($null -ne $job.Sync.DisplayNames) {
        $displayNames = [string[]]$job.Sync.DisplayNames
    }
    Write-WinToolDetectionLog -Job $job
    Stop-WinToolThread -Job $job
    $script:WinToolState.DetectJob = $null
    $status = Get-WinToolUi -Name "AppInstalledStatus"
    if (-not $ok) {
        $status.Text = "Could not check installed apps. See the log."
        Write-WinToolLog -Message ("Could not check installed apps. {0}" -f $errorMessage) -Level "warn" -Diagnostic
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($winget)) {
        $script:WinToolWingetWorking = $winget
    }
    $installedIds = @()
    try {
        $installedIds = @(ConvertFrom-WinToolWingetExport -Text $exportText)
    }
    catch {
        Write-WinToolLog -Message ("Installed apps: could not read the winget export file. {0}" -f $_.Exception.Message) -Level "warn" -Diagnostic
    }
    Write-WinToolLog -Message ("Installed apps: winget export listed {0} packages." -f $installedIds.Count) -Level "info" -Diagnostic
    $counts = Set-WinToolAppState -InstalledId $installedIds -UpgradeText $upgradeText -ListText $listText -DisplayName $displayNames
    if (@($counts.ByName).Count -gt 0) {
        Write-WinToolLog -Message ("Installed apps: found by name, outside winget: " + (@($counts.ByName) -join ", ")) -Level "info" -Diagnostic
    }
    Write-WinToolLog -Message ("Installed apps: {0} catalog apps installed, {1} with an update." -f $counts.Installed, $counts.Updates) -Level "ok" -Diagnostic
    if ($counts.Installed -eq 0 -and $installedIds.Count -eq 0 -and [string]::IsNullOrWhiteSpace($listText)) {
        $status.Text = "winget returned nothing. See the log."
    }
}

function Set-WinToolAppState {
    param(
        [string[]]$InstalledId,
        [AllowEmptyString()][string]$UpgradeText,
        [AllowEmptyString()][string]$ListText,
        [string[]]$DisplayName = @()
    )
    $catalogIds = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.AppRows)) {
        $catalogIds.Add([string]$row.WingetId)
    }
    $state = Resolve-WinToolAppState -CatalogId $catalogIds.ToArray() -InstalledId $InstalledId -UpgradeText $UpgradeText -ListText $ListText
    $byName = New-Object System.Collections.Generic.List[string]
    foreach ($id in @(Find-WinToolAppByName -DisplayName $DisplayName -App @($script:WinToolState.AppRows))) {
        if (-not $state.Installed.ContainsKey($id)) {
            $state.Installed[$id] = $true
            $byName.Add($id)
        }
    }
    $installedCount = 0
    $updateCount = 0
    foreach ($row in @($script:WinToolState.AppRows)) {
        $row.Installed = $state.Installed.ContainsKey([string]$row.WingetId)
        $row.UpdateAvailable = $state.Updates.ContainsKey([string]$row.WingetId)
        if ($row.Installed) { $installedCount++ }
        if ($row.UpdateAvailable) { $updateCount++ }
        Sync-WinToolAppBadge -Row $row
    }
    (Get-WinToolUi -Name "AppInstalledStatus").Text = ("{0} installed, {1} with an update." -f $installedCount, $updateCount)
    return [pscustomobject]@{ Installed = $installedCount; Updates = $updateCount; ByName = $byName.ToArray() }
}

function Select-WinToolInstalledApp {
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.AppRows)) {
        if ($row.Installed) {
            $ids.Add([string]$row.Id)
        }
    }
    if ($ids.Count -eq 0) {
        Write-WinToolLog -Message "No installed catalog apps were found yet. Press Check installed first." -Level "warn"
    }
    Sync-WinToolAppCheck -Id $ids.ToArray() -OnlyThese
}

function Invoke-WinToolAppAction {
    param(
        $App,
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "uninstall")][string]$Action
    )
    $apps = @($App)
    if ($apps.Count -eq 0) {
        Write-WinToolLog -Message "Select at least one app first." -Level "warn"
        return
    }
    $verb = "Update"
    if ($Action -eq "uninstall") {
        $verb = "Uninstall"
    }
    $names = @($apps | Select-Object -First 8 | ForEach-Object { [string]$_.Name }) -join ", "
    if ($apps.Count -gt 8) {
        $names += ", ..."
    }
    $ok = Request-WinToolConfirmation -Message ("{0} {1} app(s) with winget?`n`n{2}" -f $verb, $apps.Count, $names) -Title ($verb + " apps")
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolAppPlan -App $apps -Action $Action)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage ("{0} finished." -f $verb) -AfterDone "Start-WinToolAppDetection"
}

function Invoke-WinToolUpgradeAllClick {
    $ok = Request-WinToolConfirmation -Message "Update every app that winget can update, including apps that are not in this list?" -Title "Update all apps"
    if (-not $ok) {
        return
    }
    Invoke-WinToolPlanAsync -Step @(Get-WinToolUpgradeAllPlan) -DoneMessage "Update all finished." -AfterDone "Start-WinToolAppDetection"
}

function Sync-WinToolAppToggle {
    param($CategoryRow)
    if ($CategoryRow.Updating) {
        return
    }
    Sync-WinToolCategoryCheck -CategoryRow $CategoryRow
    Sync-WinToolAppCount
}

function Sync-WinToolCategoryFromHeader {
    param($CategoryRow)
    if ($CategoryRow.Updating) {
        return
    }
    $target = $false
    if ($CategoryRow.SelectAll.IsChecked -eq $true) {
        $target = $true
    }
    $CategoryRow.Updating = $true
    foreach ($app in @($CategoryRow.Apps)) {
        if ($app.Panel.Visibility -eq "Visible") {
            $app.Checkbox.IsChecked = $target
        }
    }
    $CategoryRow.Updating = $false
    Sync-WinToolAppCount
}

function Sync-WinToolCategoryCheck {
    param($CategoryRow)
    $visible = @($CategoryRow.Apps | Where-Object { $_.Panel.Visibility -eq "Visible" })
    $CategoryRow.Updating = $true
    if ($visible.Count -eq 0) {
        $CategoryRow.SelectAll.IsChecked = $false
    }
    else {
        $selected = @($visible | Where-Object { $_.Checkbox.IsChecked -eq $true })
        if ($selected.Count -eq 0) {
            $CategoryRow.SelectAll.IsChecked = $false
        }
        elseif ($selected.Count -eq $visible.Count) {
            $CategoryRow.SelectAll.IsChecked = $true
        }
        else {
            $CategoryRow.SelectAll.IsChecked = $null
        }
    }
    $CategoryRow.Updating = $false
}

function Sync-WinToolAppCount {
    $selected = @(Get-WinToolCheckedApp)
    (Get-WinToolUi -Name "AppCount").Text = "{0} selected" -f $selected.Count
}

function Update-WinToolAppFilter {
    $query = [string](Get-WinToolUi -Name "AppSearch").Text
    $any = $false
    foreach ($category in @($script:WinToolState.CategoryRows)) {
        $visible = 0
        foreach ($app in @($category.Apps)) {
            if (Test-WinToolTextMatch -Haystack $app.SearchText -Query $query) {
                $app.Panel.Visibility = "Visible"
                $visible++
                $any = $true
            }
            else {
                $app.Panel.Visibility = "Collapsed"
            }
        }
        if ($visible -eq 0) {
            $category.Card.Visibility = "Collapsed"
        }
        else {
            $category.Card.Visibility = "Visible"
            Sync-WinToolCategoryCheck -CategoryRow $category
        }
    }
    $empty = Get-WinToolUi -Name "AppEmpty"
    if ($any) {
        $empty.Visibility = "Collapsed"
    }
    else {
        $empty.Visibility = "Visible"
    }
}

function Get-WinToolCheckedApp {
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($script:WinToolState.AppRows)) {
        if ($row.Checkbox.IsChecked -eq $true) {
            $selected.Add($row)
        }
    }
    return $selected.ToArray()
}

function Sync-WinToolAppCheck {
    param(
        [string[]]$Id,
        [switch]$OnlyThese
    )
    $wanted = @{}
    foreach ($item in @($Id)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $wanted[$item] = $true
        }
    }
    foreach ($row in @($script:WinToolState.AppRows)) {
        $shouldCheck = $wanted.ContainsKey([string]$row.Id)
        if ($OnlyThese -or $shouldCheck) {
            $row.Checkbox.IsChecked = $shouldCheck
        }
    }
    foreach ($category in @($script:WinToolState.CategoryRows)) {
        Sync-WinToolCategoryCheck -CategoryRow $category
    }
    Sync-WinToolAppCount
}

function Invoke-WinToolInstallClick {
    $apps = @(Get-WinToolCheckedApp)
    if ($apps.Count -eq 0) {
        Write-WinToolLog -Message "Select at least one app first." -Level "warn"
        return
    }
    $ok = Request-WinToolConfirmation -Message ("Install {0} app(s) with winget? Each vendor's license is accepted for you by winget." -f $apps.Count) -Title "Install apps"
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolAppPlan -App $apps)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "App install finished. Open a new terminal if a command is not on PATH yet." -AfterDone "Start-WinToolAppDetection"
}
