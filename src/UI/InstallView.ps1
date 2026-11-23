# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolInstallView {
    $catalog = Get-WinToolAppCatalog
    $hostPanel = Get-WinToolUi -Name "AppCategories"
    $hostPanel.Children.Clear()
    $script:WinToolState.AppRows = @()
    $script:WinToolState.CategoryRows = @()
    $script:WinToolState.AppFilter = "all"
    $script:WinToolState.AppStartApps = @()
    $script:WinToolState.AppCardAction = $null

    $filters = Get-WinToolUi -Name "AppFilters"
    $filters.Children.Clear()
    $chips = New-Object System.Collections.Generic.List[object]
    $chips.Add([pscustomobject]@{ Tag = "all"; Text = "All" })
    $chips.Add([pscustomobject]@{ Tag = "installed"; Text = "Installed (0)" })
    $chips.Add([pscustomobject]@{ Tag = "updates"; Text = "Updates (0)" })

    $first = $true
    foreach ($category in @(Get-WinToolNote -Object $catalog -Name "categories" -Default @())) {
        $chipText = [string](Get-WinToolNote -Object $category -Name "chip" -Default ([string]$category.name))
        $chips.Add([pscustomobject]@{ Tag = ("category:" + [string]$category.id); Text = $chipText })

        $section = New-Object System.Windows.Controls.StackPanel
        $headerMargin = [System.Windows.Thickness]::new(0, 6, 0, 6)
        if ($first) { $headerMargin = [System.Windows.Thickness]::new(0, 0, 0, 6) }
        $first = $false
        $header = New-WinToolText -Text ([string]$category.name) -Size 13 -Weight "Bold" -Margin $headerMargin
        $header.ToolTip = [string](Get-WinToolNote -Object $category -Name "description" -Default "")
        [void]$section.Children.Add($header)
        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 5
        $grid.Margin = [System.Windows.Thickness]::new(0, 0, -10, 0)
        $appRows = @()
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $row = New-WinToolAppRow -App $app -CategoryName ([string]$category.name)
            $row | Add-Member -NotePropertyName CategoryId -NotePropertyValue ([string]$category.id)
            [void]$grid.Children.Add($row.Panel)
            $appRows += $row
        }
        [void]$section.Children.Add($grid)
        [void]$hostPanel.Children.Add($section)
        $script:WinToolState.CategoryRows += [pscustomobject]@{
            Id = [string]$category.id
            Card = $section
            Grid = $grid
            Apps = $appRows
        }
        foreach ($row in $appRows) {
            $script:WinToolState.AppRows += $row
            foreach ($eventName in @("Checked", "Unchecked")) {
                Register-WinToolUiEvent -Control $row.Checkbox -EventName $eventName -Name "Install: tick an app" -Action { Sync-WinToolAppCount }
            }
        }
    }

    foreach ($chip in $chips.ToArray()) {
        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.Style = $script:WinToolWindow.FindResource("ChipRadio")
        $radio.GroupName = "AppFilter"
        $radio.Content = [string]$chip.Text
        $radio.Tag = [string]$chip.Tag
        if ($chip.Tag -eq "all") { $radio.IsChecked = $true }
        Register-WinToolUiEvent -Control $radio -EventName "Checked" -Name "Install: filter" -Data ([string]$chip.Tag) -Action {
            param($source, $eventData, $tag)
            $null = $source, $eventData
            $script:WinToolState.AppFilter = $tag
            Update-WinToolAppFilter
        }
        [void]$filters.Children.Add($radio)
    }

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppSearch") -EventName "TextChanged" -Name "Install: search" -Action {
        Sync-WinToolSearchHint -BoxName "AppSearch" -HintName "AppSearchHint"
        Update-WinToolAppFilter
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppClear") -EventName "Click" -Name "Install: clear" -Action {
        Sync-WinToolAppCheck -Id @() -OnlyThese
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppInstall") -EventName "Click" -Name "Install: install selected" -Action {
        Invoke-WinToolInstallClick
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
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ViewInstall") -EventName "SizeChanged" -Name "Install: layout" -Action {
        Update-WinToolInstallLayout -Width (Get-WinToolInstallWidth)
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppScroll") -EventName "SizeChanged" -Name "Install: layout (list)" -Action {
        Update-WinToolInstallLayout -Width (Get-WinToolInstallWidth)
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppFilterScroll") -EventName "PreviewMouseWheel" -Name "Install: scroll the chips" -Action {
        param($source, $eventData)
        # The chip row never wraps; the mouse wheel moves it sideways.
        if ($null -ne $eventData -and $source.ScrollableWidth -gt 0) {
            $source.ScrollToHorizontalOffset($source.HorizontalOffset - $eventData.Delta / 2)
            $eventData.Handled = $true
        }
    }
    Update-WinToolAppChip
    Sync-WinToolAppCount
}

function Get-WinToolInstallWidth {
    # ActualWidth is current inside SizeChanged; ViewportWidth can still hold
    # the size from before the window was maximized, which left too few
    # columns. Room for the 10 px scroll bar is always kept.
    $scroll = Get-WinToolUi -Name "AppScroll"
    if ($null -ne $scroll -and $scroll.ActualWidth -gt 0) {
        return ([double]$scroll.ActualWidth - 10)
    }
    return ((Get-WinToolUi -Name "ViewInstall").ActualWidth - 50)
}

function Get-WinToolColumnCount {
    param(
        [double]$Width,
        [double]$MinWidth,
        [double]$Gap
    )
    # As many columns as fit at the minimum card width; the cards then
    # stretch to fill the row, so a wider window never leaves empty space.
    if ($Width -le 0 -or $MinWidth -le 0) { return 1 }
    $count = [int][Math]::Floor(($Width + $Gap) / ($MinWidth + $Gap))
    if ($count -lt 1) { $count = 1 }
    return $count
}

function Update-WinToolInstallLayout {
    param(
        [double]$Width
    )
    # Cards at least 185 px wide: 5 per row at 1280, 8 at 1920.
    if ($Width -le 0) {
        return
    }
    $columns = Get-WinToolColumnCount -Width $Width -MinWidth 185 -Gap 10
    $script:WinToolState.AppColumns = $columns
    foreach ($category in @($script:WinToolState.CategoryRows)) {
        if ($category.Grid.Columns -ne $columns) {
            $category.Grid.Columns = $columns
        }
    }
}

function New-WinToolCardButton {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Glyph,
        [ValidateSet("primary", "neutral", "danger", "warn")][string]$Kind = "neutral"
    )
    $button = New-Object System.Windows.Controls.Button
    $button.Style = $script:WinToolWindow.FindResource("CardButton")
    $button.Width = [double]::NaN
    $button.Height = 28
    $button.FontSize = 12.5
    $button.Padding = [System.Windows.Thickness]::new(4, 0, 4, 0)
    $button.Margin = [System.Windows.Thickness]::new(2, 0, 2, 0)
    switch ($Kind) {
        "primary" {
            $button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushAccent")
            $button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "BrushOnAccent")
            $button.FontWeight = [System.Windows.FontWeights]::Bold
        }
        "danger" {
            $button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushBadSoft")
            $button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "BrushBad")
        }
        "warn" {
            $button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushWarnStrong")
            $button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "BrushOnWarn")
            $button.FontWeight = [System.Windows.FontWeights]::Bold
        }
        default {
            $button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushNavHover")
            $button.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "BrushInk")
        }
    }
    Set-WinToolCardButtonText -Button $button -Text $Text -Glyph $Glyph
    return $button
}

function Set-WinToolCardButtonText {
    param(
        [Parameter(Mandatory = $true)]$Button,
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Glyph
    )
    if ([string]::IsNullOrEmpty($Glyph)) {
        $Button.Content = $Text
        return
    }
    $line = New-Object System.Windows.Controls.StackPanel
    $line.Orientation = "Horizontal"
    $icon = New-Object System.Windows.Controls.TextBlock
    $icon.Text = $Glyph
    $icon.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $icon.FontSize = 12
    $icon.VerticalAlignment = "Center"
    $icon.Margin = [System.Windows.Thickness]::new(0, 1, 6, 0)
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Text
    $label.VerticalAlignment = "Center"
    [void]$line.Children.Add($icon)
    [void]$line.Children.Add($label)
    $Button.Content = $line
}

function New-WinToolAppRow {
    param(
        $App,
        [string]$CategoryName
    )
    $tags = @(Get-WinToolNote -Object $App -Name "tags" -Default @()) -join " "
    # A compact card: icon, name, winget id, status dot, two lines of
    # description, the action buttons, and a checkbox for picking several.
    $panel = New-Object System.Windows.Controls.Border
    $panel.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushCard")
    $panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    $panel.BorderThickness = [System.Windows.Thickness]::new(1)
    $panel.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $panel.Padding = [System.Windows.Thickness]::new(10, 10, 10, 9)
    $panel.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
    $panel.Height = 130

    $layout = New-Object System.Windows.Controls.Grid
    foreach ($height in @(32, 0, 28)) {
        $rowDefinition = New-Object System.Windows.Controls.RowDefinition
        if ($height -gt 0) { $rowDefinition.Height = [System.Windows.GridLength]::new($height) }
        else { $rowDefinition.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        $layout.RowDefinitions.Add($rowDefinition)
    }

    $head = New-Object System.Windows.Controls.Grid
    $head.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $head.ColumnDefinitions.Add((New-WinToolColumn))
    $head.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $icon = New-Object System.Windows.Controls.Border
    $icon.Width = 32
    $icon.Height = 32
    $icon.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $iconColor = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString((Get-WinToolAppIconColor -Id ([string]$App.id))))
    $icon.Background = [System.Windows.Media.SolidColorBrush]::new($iconColor)
    $initial = New-Object System.Windows.Controls.TextBlock
    $initial.Text = Get-WinToolAppInitial -Name ([string]$App.name)
    $initial.FontSize = 15
    $initial.FontWeight = [System.Windows.FontWeights]::Bold
    $initial.Foreground = [System.Windows.Media.Brushes]::White
    $initial.HorizontalAlignment = "Center"
    $initial.VerticalAlignment = "Center"
    $icon.Child = $initial
    [void]$head.Children.Add($icon)

    $names = New-Object System.Windows.Controls.StackPanel
    $names.Margin = [System.Windows.Thickness]::new(8, 0, 6, 0)
    $names.VerticalAlignment = "Center"
    $title = New-WinToolText -Text ([string]$App.name) -Size 14 -Weight "SemiBold"
    $title.TextTrimming = "CharacterEllipsis"
    $title.ToolTip = [string]$App.name
    [void]$names.Children.Add($title)
    $idText = New-WinToolText -Text ([string]$App.wingetId) -Size 11.5 -Brush "BrushHint" -Margin ([System.Windows.Thickness]::new(0, 0, 0, 0))
    $idText.TextTrimming = "CharacterEllipsis"
    $idText.ToolTip = "winget: " + [string]$App.wingetId
    [void]$names.Children.Add($idText)
    [System.Windows.Controls.Grid]::SetColumn($names, 1)
    [void]$head.Children.Add($names)

    # The checkbox for picking several apps sits at the top right.
    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.VerticalAlignment = "Top"
    $checkbox.Margin = [System.Windows.Thickness]::new(0, 1, -4, 0)
    $checkbox.ToolTip = "Pick several apps and install, update, or uninstall them together."
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 2)
    [void]$head.Children.Add($checkbox)
    [void]$layout.Children.Add($head)

    $description = New-WinToolText -Text ([string]$App.description) -Size 12.5 -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 6, 0, 0))
    $description.TextWrapping = "Wrap"
    $description.TextTrimming = "CharacterEllipsis"
    $description.MaxHeight = 34
    $description.LineHeight = 17
    $description.LineStackingStrategy = "BlockLineHeight"
    $description.ToolTip = [string]$App.description
    [System.Windows.Controls.Grid]::SetRow($description, 1)
    [void]$layout.Children.Add($description)

    # The visible buttons share the full row evenly (collapsed ones take no room).
    $buttons = New-Object System.Windows.Controls.Primitives.UniformGrid
    $buttons.Rows = 1
    $buttons.Margin = [System.Windows.Thickness]::new(-2, 0, -2, 0)
    $installButton = New-WinToolCardButton -Text "Install" -Glyph ([string][char]0xE896) -Kind "primary"
    $updateButton = New-WinToolCardButton -Text "Update" -Glyph ([string][char]0xE72C) -Kind "warn"
    $openButton = New-WinToolCardButton -Text "Open" -Kind "neutral"
    $uninstallButton = New-WinToolCardButton -Text "Uninstall" -Kind "danger"
    foreach ($button in @($installButton, $updateButton, $openButton, $uninstallButton)) {
        [void]$buttons.Children.Add($button)
        Add-WinToolBusyControl -Control $button
    }
    [System.Windows.Controls.Grid]::SetRow($buttons, 2)
    [void]$layout.Children.Add($buttons)
    $panel.Child = $layout

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
        InstallButton = $installButton
        UpdateButton = $updateButton
        OpenButton = $openButton
        UninstallButton = $uninstallButton
        Installed = $false
        UpdateAvailable = $false
        LaunchId = $null
        Pending = $false
    }
    foreach ($choice in @(
            [pscustomobject]@{ Button = $installButton; Action = "install"; Name = "Install: install one app" },
            [pscustomobject]@{ Button = $updateButton; Action = "upgrade"; Name = "Install: update one app" },
            [pscustomobject]@{ Button = $uninstallButton; Action = "uninstall"; Name = "Install: uninstall one app" },
            [pscustomobject]@{ Button = $openButton; Action = "open"; Name = "Install: open app" }
        )) {
        Register-WinToolUiEvent -Control $choice.Button -EventName "Click" -Name $choice.Name -Data ([pscustomobject]@{ Row = $row; Action = $choice.Action }) -Action {
            param($source, $eventData, $target)
            $null = $source, $eventData
            Invoke-WinToolAppCardAction -Row $target.Row -Action $target.Action
        }
    }

    # The old right-click menu stays as a shortcut.
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
    Sync-WinToolAppBadge -Row $row
    return $row
}

function Sync-WinToolAppBadge {
    param($Row)
    # Border tint and buttons follow the detected state.
    $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    if ($Row.UpdateAvailable) {
        $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushWarnLine")
    }
    elseif ($Row.Installed) {
        $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushOkLine")
    }
    if ($Row.Pending) {
        return
    }
    $Row.InstallButton.Visibility = "Collapsed"
    $Row.UpdateButton.Visibility = "Collapsed"
    $Row.OpenButton.Visibility = "Collapsed"
    $Row.UninstallButton.Visibility = "Collapsed"
    if (-not $Row.Installed) {
        $Row.InstallButton.Visibility = "Visible"
        return
    }
    if ($Row.UpdateAvailable) {
        $Row.UpdateButton.Visibility = "Visible"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Row.LaunchId)) {
        $Row.OpenButton.Visibility = "Visible"
    }
    $Row.UninstallButton.Visibility = "Visible"
}

function Set-WinToolAppStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [bool]$Show = $true
    )
    $status = Get-WinToolUi -Name "AppInstalledStatus"
    $status.Text = $Text
    if ($Show) {
        $status.Visibility = "Visible"
    }
    else {
        $status.Visibility = "Collapsed"
    }
    (Get-WinToolUi -Name "AppRefreshInstalled").ToolTip = $Text + " Press to check again."
}

function Update-WinToolAppChip {
    $installed = 0
    $updates = 0
    foreach ($row in @($script:WinToolState.AppRows)) {
        if ($row.Installed) { $installed++ }
        if ($row.UpdateAvailable) { $updates++ }
    }
    foreach ($chip in @((Get-WinToolUi -Name "AppFilters").Children)) {
        if ([string]$chip.Tag -eq "installed") { $chip.Content = "Installed ($installed)" }
        if ([string]$chip.Tag -eq "updates") { $chip.Content = "Updates ($updates)" }
    }
    $upgradeAll = Get-WinToolUi -Name "AppUpgradeAll"
    if ($updates -gt 0) {
        $upgradeAll.Content = "Update all ($updates)"
    }
    else {
        $upgradeAll.Content = "Update all"
    }
}

function Invoke-WinToolAppCardAction {
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][ValidateSet("install", "upgrade", "uninstall", "open")][string]$Action
    )
    if ($Action -eq "open") {
        Open-WinToolApp -Row $Row
        return
    }
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message "Wait for the current task to finish." -Level "warn"
        return
    }
    if ($Action -eq "uninstall") {
        $ok = Request-WinToolConfirmation -Message ("Uninstall {0} with winget?" -f [string]$Row.Name) -Title "Uninstall app"
        if (-not $ok) {
            return
        }
    }
    $button = $Row.InstallButton
    $busyText = "Installing" + [char]0x2026
    $verb = "Install"
    if ($Action -eq "upgrade") { $button = $Row.UpdateButton; $busyText = "Updating" + [char]0x2026; $verb = "Update" }
    if ($Action -eq "uninstall") { $button = $Row.UninstallButton; $busyText = "Removing" + [char]0x2026; $verb = "Uninstall" }
    $steps = @(Get-WinToolAppPlan -App @($Row) -Action $Action)
    $Row.Pending = $true
    $script:WinToolState.AppCardAction = [pscustomobject]@{ Row = $Row; Button = $button }
    Set-WinToolCardButtonText -Button $button -Text $busyText
    Write-WinToolLog -Message ("{0}: {1} ({2})." -f $verb, [string]$Row.Name, [string]$Row.WingetId) -Level "info"
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage ("{0} {1} finished." -f $verb, [string]$Row.Name) -AfterDone "Complete-WinToolAppCardAction"
    $button.IsEnabled = $false
}

function Complete-WinToolAppCardAction {
    # The card keeps a "Checking" label until the installed-app check is back.
    $action = $script:WinToolState.AppCardAction
    if ($null -ne $action) {
        Set-WinToolCardButtonText -Button $action.Button -Text ("Checking" + [char]0x2026)
        $action.Button.IsEnabled = $false
    }
    Start-WinToolAppDetection
    if ($null -eq $script:WinToolState.DetectJob) {
        Clear-WinToolAppCardAction
    }
}

function Clear-WinToolAppCardAction {
    $action = $script:WinToolState.AppCardAction
    $script:WinToolState.AppCardAction = $null
    if ($null -eq $action) {
        return
    }
    $action.Row.Pending = $false
    Set-WinToolCardButtonText -Button $action.Row.InstallButton -Text "Install" -Glyph ([string][char]0xE896)
    Set-WinToolCardButtonText -Button $action.Row.UpdateButton -Text "Update" -Glyph ([string][char]0xE72C)
    Set-WinToolCardButtonText -Button $action.Row.UninstallButton -Text "Uninstall"
    $action.Button.IsEnabled = (-not $script:WinToolState.Busy)
    Sync-WinToolAppBadge -Row $action.Row
}

function Open-WinToolApp {
    param(
        [Parameter(Mandatory = $true)]$Row
    )
    $launchId = [string]$Row.LaunchId
    if ([string]::IsNullOrWhiteSpace($launchId)) {
        Write-WinToolLog -Message ("WinTool could not find {0} in the Start menu." -f [string]$Row.Name) -Level "warn"
        return
    }
    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList ("shell:AppsFolder\" + $launchId)
        Write-WinToolLog -Message ("Opened {0}." -f [string]$Row.Name) -Level "info"
    }
    catch {
        Write-WinToolLog -Message ("Could not open {0}. {1}" -f [string]$Row.Name, $_.Exception.Message) -Level "warn"
    }
}

$script:WinToolDetectTimeoutSeconds = 300

function Start-WinToolAppDetection {
    if ($null -ne $script:WinToolState.DetectJob) {
        return
    }
    $candidates = @(Get-WinToolWingetCandidate)
    if ($candidates.Count -eq 0) {
        Set-WinToolAppStatus -Text "winget not found, so installed apps cannot be checked."
        Clear-WinToolAppCardAction
        Write-WinToolLog -Message "Installed apps: winget.exe was not found on this PC." -Level "warn" -Diagnostic
        return
    }
    Set-WinToolAppStatus -Text "Checking installed apps..."
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
    Set-WinToolAppStatus -Text "Checking installed apps took too long. Press Refresh to try again."
    Clear-WinToolAppCardAction
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
    if ($null -ne $job.Sync.StartApps) {
        $script:WinToolState.AppStartApps = [string[]]$job.Sync.StartApps
    }
    if (-not $ok) {
        Set-WinToolAppStatus -Text "Could not check installed apps. See the log."
        Clear-WinToolAppCardAction
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
    Write-WinToolLog -Message ("Installed apps: marked installed: " + (@($counts.InstalledIds) -join ", ")) -Level "info" -Diagnostic
    if (@($counts.UpdateIds).Count -gt 0) {
        Write-WinToolLog -Message ("Installed apps: update available: " + (@($counts.UpdateIds) -join ", ")) -Level "info" -Diagnostic
    }
    if ($counts.Installed -eq 0 -and $installedIds.Count -eq 0 -and [string]::IsNullOrWhiteSpace($listText)) {
        Set-WinToolAppStatus -Text "winget returned nothing. See the log."
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
    $startApps = @($script:WinToolState.AppStartApps)
    $installedCount = 0
    $updateCount = 0
    $installedIds = New-Object System.Collections.Generic.List[string]
    $updateIds = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.AppRows)) {
        $row.Installed = $state.Installed.ContainsKey([string]$row.WingetId)
        $row.UpdateAvailable = $state.Updates.ContainsKey([string]$row.WingetId)
        $row.LaunchId = $null
        if ($row.Installed -and $startApps.Count -gt 0) {
            $row.LaunchId = Resolve-WinToolAppLaunchId -Name ([string]$row.Name) -DetectName @($row.DetectNames) -StartApp $startApps
        }
        if ($row.Installed) { $installedCount++; $installedIds.Add([string]$row.WingetId) }
        if ($row.UpdateAvailable) { $updateCount++; $updateIds.Add([string]$row.WingetId) }
        Sync-WinToolAppBadge -Row $row
    }
    Set-WinToolAppStatus -Text ("{0} installed, {1} with an update." -f $installedCount, $updateCount) -Show $false
    Clear-WinToolAppCardAction
    Update-WinToolAppChip
    Update-WinToolAppFilter
    return [pscustomobject]@{ Installed = $installedCount; Updates = $updateCount; ByName = $byName.ToArray(); InstalledIds = $installedIds.ToArray(); UpdateIds = $updateIds.ToArray() }
}

function Select-WinToolInstalledApp {
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($script:WinToolState.AppRows)) {
        if ($row.Installed) {
            $ids.Add([string]$row.Id)
        }
    }
    if ($ids.Count -eq 0) {
        Write-WinToolLog -Message "No installed catalog apps were found yet. Press Refresh first." -Level "warn"
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

function Sync-WinToolAppCount {
    $selected = @(Get-WinToolCheckedApp)
    (Get-WinToolUi -Name "AppCount").Text = "{0} selected" -f $selected.Count
    $bar = Get-WinToolUi -Name "AppBulkBar"
    if ($selected.Count -gt 0) {
        $bar.Visibility = "Visible"
    }
    else {
        $bar.Visibility = "Collapsed"
    }
}

function Test-WinToolAppFilterMatch {
    param(
        $Row,
        [string]$Filter,
        [string]$Query
    )
    if (-not (Test-WinToolTextMatch -Haystack $Row.SearchText -Query $Query)) {
        return $false
    }
    if ($Filter -eq "installed") { return [bool]$Row.Installed }
    if ($Filter -eq "updates") { return [bool]$Row.UpdateAvailable }
    if ($Filter.StartsWith("category:")) { return ([string]$Row.CategoryId -eq $Filter.Substring(9)) }
    return $true
}

function Update-WinToolAppFilter {
    $query = [string](Get-WinToolUi -Name "AppSearch").Text
    $filter = [string]$script:WinToolState.AppFilter
    if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "all" }
    $any = $false
    foreach ($category in @($script:WinToolState.CategoryRows)) {
        $visible = 0
        foreach ($app in @($category.Apps)) {
            if (Test-WinToolAppFilterMatch -Row $app -Filter $filter -Query $query) {
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
        }
    }
    $empty = Get-WinToolUi -Name "AppEmpty"
    if ($any) {
        $empty.Visibility = "Collapsed"
    }
    else {
        $empty.Visibility = "Visible"
        $empty.Text = "No apps match this search or filter."
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
