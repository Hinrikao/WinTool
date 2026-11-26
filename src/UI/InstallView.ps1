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
    $script:WinToolState.AppsDetected = $false

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
        $header = New-WinToolText -Text ([string]$category.name) -Weight "Bold" -Margin $headerMargin
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
            $surface = "Install filter"
            if ($tag -eq "all") { $surface = "Install filter all" }
            elseif ($tag -eq "installed") { $surface = "Install installed" }
            elseif ($tag -eq "updates") { $surface = "Install updates" }
            elseif ($tag.StartsWith("category:")) { $surface = "Install category" }
            Start-WinToolSurfaceTiming -Name $surface
            $script:WinToolState.AppFilter = $tag
            Update-WinToolAppFilter
        }
        [void]$filters.Children.Add($radio)
    }

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppSearch") -EventName "TextChanged" -Name "Install: search" -Action {
        Start-WinToolSurfaceTiming -Name "Install search"
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
        $checked = @(Get-WinToolCheckedApp)
        if ($script:WinToolState.AppsDetected -and $checked.Count -gt 0) {
            $checked = @($checked | Where-Object { $_.Installed })
            if ($checked.Count -eq 0) {
                Write-WinToolLog -Message (Get-WinToolText "msg.none-of-the-selected-apps-are-marked-as-installed") -Level "warn"
                return
            }
        }
        Invoke-WinToolAppAction -App $checked -Action "upgrade"
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AppUninstall") -EventName "Click" -Name "Install: uninstall selected" -Action {
        $checked = @(Get-WinToolCheckedApp)
        if ($script:WinToolState.AppsDetected -and $checked.Count -gt 0) {
            $checked = @($checked | Where-Object { $_.Installed })
            if ($checked.Count -eq 0) {
                Write-WinToolLog -Message (Get-WinToolText "msg.none-of-the-selected-apps-are-marked-as-installed") -Level "warn"
                return
            }
        }
        Invoke-WinToolAppAction -App $checked -Action "uninstall"
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
    if ($null -ne $script:WinToolWindow -and $script:WinToolWindow.IsLoaded -and -not [bool]$script:WinToolState.AppsDetected -and $null -eq $script:WinToolState.DetectJob) {
        Update-WinToolLocalPackageCache | Out-Null
        Start-WinToolAppDetection
    }
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
    $button.Height = 32
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
    $icon.VerticalAlignment = "Center"
    $icon.Margin = [System.Windows.Thickness]::new(0, 1, 6, 0)
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Text
    $label.VerticalAlignment = "Center"
    [void]$line.Children.Add($icon)
    [void]$line.Children.Add($label)
    $Button.Content = $line
}

$script:WinToolIconBackplate = "#F3F5F8"
$script:WinToolIconCache = @{}

function Get-WinToolCachedAppIcon {
    # Decode each file once. The frozen bitmap is shared by every card that
    # uses it, including a later visit to Install.
    param(
        [Parameter(Mandatory = $true)][string]$FileName
    )
    $key = $FileName.ToLowerInvariant()
    if ($script:WinToolIconCache.ContainsKey($key)) {
        return $script:WinToolIconCache[$key]
    }
    $bitmap = $null
    $data = Get-WinToolAppIconData -FileName $FileName
    if ($null -ne $data -and $data.Length -ge 8 -and $data[0] -eq 137 -and $data[1] -eq 80 -and $data[2] -eq 78 -and $data[3] -eq 71) {
        try {
            $stream = [System.IO.MemoryStream]::new($data)
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.StreamSource = $stream
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.DecodePixelWidth = 64
            $bitmap.EndInit()
            $bitmap.Freeze()
            $stream.Dispose()
        }
        catch {
            $bitmap = $null
        }
    }
    $script:WinToolIconCache[$key] = $bitmap
    return $bitmap
}

function New-WinToolAppIconImage {
    # A 32 px image in the same slot as the letter tile. Uniform keeps the
    # picture's shape. The bitmap is decoded at 64 px; BitmapCache keeps that
    # scale so the page fade does not paint every icon in software again.
    param(
        [Parameter(Mandatory = $true)][string]$FileName
    )
    $bitmap = Get-WinToolCachedAppIcon -FileName $FileName
    if ($null -eq $bitmap) {
        return $null
    }
    $image = New-Object System.Windows.Controls.Image
    $image.Source = $bitmap
    $image.Width = 32
    $image.Height = 32
    $image.Stretch = [System.Windows.Media.Stretch]::Uniform
    $image.HorizontalAlignment = "Center"
    $image.VerticalAlignment = "Center"
    $image.IsHitTestVisible = $false
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    $image.CacheMode = New-Object System.Windows.Media.BitmapCache
    $image.Clip = New-Object System.Windows.Media.RectangleGeometry ([System.Windows.Rect]::new(0, 0, 32, 32), 8, 8)
    return $image
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
    $panel.Height = 156

    $layout = New-Object System.Windows.Controls.Grid
    foreach ($height in @(40, 0, 32)) {
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
    $initial.FontWeight = [System.Windows.FontWeights]::Bold
    $initial.Foreground = [System.Windows.Media.Brushes]::White
    $initial.HorizontalAlignment = "Center"
    $initial.VerticalAlignment = "Center"
    $icon.Child = $initial
    $iconImage = $null
    $iconFile = [string](Get-WinToolNote -Object $App -Name "icon" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($iconFile)) {
        $iconImage = New-WinToolAppIconImage -FileName $iconFile
    }
    if ($null -ne $iconImage) {
        # One light plate for every real icon, still exactly 32 px, so a dark
        # logo stays visible on the dark card without moving the row.
        $plate = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($script:WinToolIconBackplate))
        $icon.Background = [System.Windows.Media.SolidColorBrush]::new($plate)
        $icon.Child = $iconImage
    }
    [void]$head.Children.Add($icon)

    $names = New-Object System.Windows.Controls.StackPanel
    $names.Margin = [System.Windows.Thickness]::new(8, 0, 6, 0)
    $names.VerticalAlignment = "Center"
    $title = New-WinToolText -Text ([string]$App.name) -Weight "SemiBold"
    $title.TextTrimming = "CharacterEllipsis"
    $title.ToolTip = [string]$App.name
    [void]$names.Children.Add($title)
    $idText = New-WinToolText -Text ([string]$App.wingetId) -Brush "BrushHint" -Margin ([System.Windows.Thickness]::new(0, 0, 0, 0))
    $idText.TextTrimming = "CharacterEllipsis"
    $idText.ToolTip = "winget: " + [string]$App.wingetId
    [void]$names.Children.Add($idText)
    [System.Windows.Controls.Grid]::SetColumn($names, 1)
    [void]$head.Children.Add($names)

    # The checkbox for picking several apps sits at the top right.
    $checkbox = New-Object System.Windows.Controls.CheckBox
    $checkbox.VerticalAlignment = "Top"
    $checkbox.Margin = [System.Windows.Thickness]::new(0, 1, -4, 0)
    $checkbox.ToolTip = (Get-WinToolText "msg.pick-several-apps-and-install-update-or-uninstall-them-t")
    [System.Windows.Controls.Grid]::SetColumn($checkbox, 2)
    [void]$head.Children.Add($checkbox)
    [void]$layout.Children.Add($head)

    $description = New-WinToolText -Text ([string]$App.description) -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 6, 0, 0))
    $description.TextWrapping = "Wrap"
    $description.TextTrimming = "CharacterEllipsis"
    $description.MaxHeight = 40
    $description.LineHeight = 20
    $description.LineStackingStrategy = "BlockLineHeight"
    $description.ToolTip = [string]$App.description
    [System.Windows.Controls.Grid]::SetRow($description, 1)
    [void]$layout.Children.Add($description)

    # Two fixed slots: Install, Update, or Open on the left; Uninstall on the right.
    # An empty slot stays Hidden so the other button never grows or jumps.
    $buttons = New-Object System.Windows.Controls.Grid
    $buttons.Height = 32
    $buttons.ColumnDefinitions.Add((New-WinToolColumn))
    $buttons.ColumnDefinitions.Add((New-WinToolColumn))
    $primarySlot = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetColumn($primarySlot, 0)
    $installButton = New-WinToolCardButton -Text "Install" -Glyph ([string][char]0xE896) -Kind "primary"
    $updateButton = New-WinToolCardButton -Text "Update" -Glyph ([string][char]0xE72C) -Kind "warn"
    $openButton = New-WinToolCardButton -Text "Open" -Kind "neutral"
    $uninstallButton = New-WinToolCardButton -Text "Uninstall" -Kind "danger"
    foreach ($button in @($installButton, $updateButton, $openButton)) {
        $button.Margin = [System.Windows.Thickness]::new(0)
        $button.HorizontalAlignment = "Stretch"
        [void]$primarySlot.Children.Add($button)
        Add-WinToolBusyControl -Control $button
    }
    $uninstallButton.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $uninstallButton.HorizontalAlignment = "Stretch"
    [System.Windows.Controls.Grid]::SetColumn($uninstallButton, 1)
    [void]$buttons.Children.Add($primarySlot)
    [void]$buttons.Children.Add($uninstallButton)
    Add-WinToolBusyControl -Control $uninstallButton
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
        IconHost = $icon
        IconImage = $iconImage
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
            [pscustomobject]@{ Button = $installButton; Action = "install"; Name = (Get-WinToolText "msg.install-install-one-app") },
            [pscustomobject]@{ Button = $updateButton; Action = "upgrade"; Name = (Get-WinToolText "msg.install-update-one-app") },
            [pscustomobject]@{ Button = $uninstallButton; Action = "uninstall"; Name = (Get-WinToolText "msg.install-uninstall-one-app") },
            [pscustomobject]@{ Button = $openButton; Action = "open"; Name = (Get-WinToolText "msg.install-open-app") }
        )) {
        Register-WinToolUiEvent -Control $choice.Button -EventName "Click" -Name $choice.Name -Data ([pscustomobject]@{ Row = $row; Action = $choice.Action }) -Action {
            param($source, $eventData, $target)
            $null = $source, $eventData
            Invoke-WinToolAppCardAction -Row $target.Row -Action $target.Action
        }
    }

    # The old right-click menu stays as a shortcut.
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menuItems = New-Object System.Collections.Generic.List[object]
    foreach ($choice in @(
            [pscustomobject]@{ Header = (Get-WinToolText "msg.update-this-app"); Action = "upgrade"; Name = (Get-WinToolText "msg.install-update-one-app") },
            [pscustomobject]@{ Header = (Get-WinToolText "msg.uninstall-this-app"); Action = "uninstall"; Name = (Get-WinToolText "msg.install-uninstall-one-app") }
        )) {
        $item = New-Object System.Windows.Controls.MenuItem
        $item.Header = $choice.Header
        Register-WinToolUiEvent -Control $item -EventName "Click" -Name $choice.Name -Data ([pscustomobject]@{ Row = $row; Action = $choice.Action }) -Action {
            param($source, $eventData, $target)
            $null = $source, $eventData
            Invoke-WinToolAppAction -App @($target.Row) -Action $target.Action
        }
        [void]$menu.Items.Add($item)
        $menuItems.Add($item)
    }
    Register-WinToolUiEvent -Control $menu -EventName "Opened" -Name "Install: open app menu" -Data ([pscustomobject]@{ Row = $row; Items = $menuItems.ToArray() }) -Action {
        param($source, $eventData, $target)
        $null = $source, $eventData
        $canAct = (-not $script:WinToolState.Busy) -and ([bool]$target.Row.Installed -or -not $script:WinToolState.AppsDetected)
        foreach ($entry in @($target.Items)) {
            $entry.IsEnabled = $canAct
        }
    }
    $panel.ContextMenu = $menu
    $lift = New-Object System.Windows.Media.TranslateTransform
    $panel.RenderTransform = $lift
    Register-WinToolUiEvent -Control $panel -EventName "MouseEnter" -Name "Install: card hover" -Data $row -Action {
        param($source, $eventData, $card)
        $null = $eventData
        Set-WinToolAppCardBorder -Row $card -Hover
        $shift = $source.RenderTransform
        if ($shift -isnot [System.Windows.Media.TranslateTransform]) { return }
        if (Test-WinToolHomeReduceMotion) {
            $shift.Y = -2
            return
        }
        $rise = New-Object System.Windows.Media.Animation.DoubleAnimation($shift.Y, -2, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150)))
        $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $rise)
    }
    Register-WinToolUiEvent -Control $panel -EventName "MouseLeave" -Name "Install: card hover end" -Data $row -Action {
        param($source, $eventData, $card)
        $null = $eventData
        Set-WinToolAppCardBorder -Row $card
        $shift = $source.RenderTransform
        if ($shift -isnot [System.Windows.Media.TranslateTransform]) { return }
        if (Test-WinToolHomeReduceMotion) {
            $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $null)
            $shift.Y = 0
            return
        }
        $drop = New-Object System.Windows.Media.Animation.DoubleAnimation($shift.Y, 0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150)))
        $shift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $drop)
    }
    Sync-WinToolAppBadge -Row $row
    return $row
}

function Set-WinToolAppCardBorder {
    param($Row, [switch]$Hover)
    if ($Hover -or $Row.Panel.IsMouseOver) {
        $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushAccent")
        return
    }
    $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    if ($Row.UpdateAvailable) {
        $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushWarnLine")
    }
    elseif ($Row.Installed) {
        $Row.Panel.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushOkLine")
    }
}

function Sync-WinToolAppBadge {
    param($Row)
    # Border tint and buttons follow the detected state. The right slot stays
    # Hidden (not Collapsed) when there is nothing to uninstall, so Install
    # keeps the same width as Update and Open.
    Set-WinToolAppCardBorder -Row $Row
    if ($Row.Pending) {
        return
    }
    $Row.InstallButton.Visibility = "Collapsed"
    $Row.UpdateButton.Visibility = "Collapsed"
    $Row.OpenButton.Visibility = "Collapsed"
    $Row.UninstallButton.Visibility = "Hidden"
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
        $status.Visibility = "Hidden"
    }
    (Get-WinToolUi -Name "AppRefreshInstalled").ToolTip = ($Text + (Get-WinToolText "msg.press-to-check-again"))
}

function Update-WinToolAppChip {
    $installed = 0
    $updates = 0
    foreach ($row in @($script:WinToolState.AppRows)) {
        if ($row.Installed) { $installed++ }
        if ($row.UpdateAvailable) { $updates++ }
    }
    foreach ($chip in @((Get-WinToolUi -Name "AppFilters").Children)) {
        if ([string]$chip.Tag -eq "installed") { $chip.Content = (Get-WinToolText "msg.installed-n" $installed) }
        if ([string]$chip.Tag -eq "updates") { $chip.Content = (Get-WinToolText "msg.updates-n" $updates) }
    }
    $upgradeAll = Get-WinToolUi -Name "AppUpgradeAll"
    if ($updates -gt 0) {
        $upgradeAll.Content = (Get-WinToolText "msg.update-all-n" $updates)
    }
    else {
        $upgradeAll.Content = (Get-WinToolText "button.updateAll")
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
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    if ($Action -eq "uninstall") {
        $ok = Request-WinToolConfirmation -Message ((Get-WinToolText "msg.uninstall-n-with-winget") -f [string]$Row.Name) -Title (Get-WinToolText "msg.uninstall-app")
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
        Write-WinToolLog -Message ((Get-WinToolText "msg.wintool-could-not-find-n-in-the-start-menu") -f [string]$Row.Name) -Level "warn"
        return
    }
    try {
        Start-Process -FilePath "explorer.exe" -ArgumentList ("shell:AppsFolder\" + $launchId)
        Write-WinToolLog -Message ((Get-WinToolText "msg.opened-n") -f [string]$Row.Name) -Level "info"
    }
    catch {
        Write-WinToolLog -Message ((Get-WinToolText "msg.could-not-open-n-n") -f [string]$Row.Name, $_.Exception.Message) -Level "warn"
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
        Write-WinToolLog -Message (Get-WinToolText "msg.installed-apps-winget-exe-was-not-found-on-this-pc") -Level "warn" -Diagnostic
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
    Write-WinToolLog -Message ((Get-WinToolText "msg.installed-apps-winget-did-not-finish-in-n-seconds-so-the") -f $script:WinToolDetectTimeoutSeconds) -Level "warn" -Diagnostic
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
        Write-WinToolLog -Message ((Get-WinToolText "msg.could-not-check-installed-apps-n") -f $errorMessage) -Level "warn" -Diagnostic
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
        Write-WinToolLog -Message ((Get-WinToolText "msg.installed-apps-could-not-read-the-winget-export-file-n") -f $_.Exception.Message) -Level "warn" -Diagnostic
    }
    Write-WinToolLog -Message ((Get-WinToolText "msg.installed-apps-winget-export-listed-n-packages") -f $installedIds.Count) -Level "info" -Diagnostic
    $counts = Set-WinToolAppState -InstalledId $installedIds -UpgradeText $upgradeText -ListText $listText -DisplayName $displayNames
    $known = @(Get-WinToolTerminalWingetId)
    $fromList = @()
    $fromUpgrade = @()
    if ($known.Count -gt 0) {
        $fromList = @(Find-WinToolWingetIdInText -Text $listText -KnownId $known)
        $fromUpgrade = @(Find-WinToolWingetIdInText -Text $upgradeText -KnownId $known)
    }
    $allInstalled = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($installedIds) + @($fromList) + @($fromUpgrade) + @($counts.InstalledIds)) {
        if (-not [string]::IsNullOrWhiteSpace($id)) { $allInstalled.Add($id) | Out-Null }
    }
    $allUpdates = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($fromUpgrade) + @($counts.UpdateIds)) {
        if (-not [string]::IsNullOrWhiteSpace($id)) { $allUpdates.Add($id) | Out-Null }
    }
    Set-WinToolWingetPackageCache -InstalledId $allInstalled.ToArray() -UpdateId $allUpdates.ToArray() | Out-Null
    Update-WinToolLocalPackageCache | Out-Null
    try { Update-WinToolTerminalSummary } catch { $null = $_.Exception.Message }
    try { Update-WinToolDriverRuntimeRow } catch { $null = $_.Exception.Message }
    if (@($counts.ByName).Count -gt 0) {
        Write-WinToolLog -Message ("Installed apps: found by name, outside winget: " + (@($counts.ByName) -join ", ")) -Level "info" -Diagnostic
    }
    Write-WinToolLog -Message ((Get-WinToolText "msg.installed-apps-n-catalog-apps-installed-n-with-an-update") -f $counts.Installed, $counts.Updates) -Level "ok" -Diagnostic
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
    $script:WinToolState.AppsDetected = $true
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
        Write-WinToolLog -Message (Get-WinToolText "msg.no-installed-catalog-apps-were-found-yet-press-refresh-f") -Level "warn"
    }
    Sync-WinToolAppCheck -Id $ids.ToArray() -OnlyThese
}

function Invoke-WinToolAppAction {
    param(
        $App,
        [Parameter(Mandatory = $true)][ValidateSet("upgrade", "uninstall")][string]$Action
    )
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    $apps = @($App)
    if ($apps.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "msg.select-at-least-one-app-first") -Level "warn"
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
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "msg.n-apps-with-winget-n" $verb $apps.Count $names) -Title (Get-WinToolText "msg.n-apps" $verb)
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolAppPlan -App $apps -Action $Action)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage ("{0} finished." -f $verb) -AfterDone "Start-WinToolAppDetection"
}

function Invoke-WinToolUpgradeAllClick {
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    $ok = Request-WinToolConfirmation -Message (Get-WinToolText "msg.update-every-app-that-winget-can-update-including-apps-t") -Title (Get-WinToolText "msg.update-all-apps")
    if (-not $ok) {
        return
    }
    Invoke-WinToolPlanAsync -Step @(Get-WinToolUpgradeAllPlan) -DoneMessage (Get-WinToolText "msg.update-all-finished") -AfterDone "Start-WinToolAppDetection"
}

function Sync-WinToolAppCount {
    $selected = @(Get-WinToolCheckedApp)
    (Get-WinToolUi -Name "AppCount").Text = (Get-WinToolText "msg.n-selected") -f $selected.Count
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
                if ($app.Panel.Visibility -ne "Visible") { $app.Panel.Visibility = "Visible" }
                $visible++
                $any = $true
            }
            else {
                if ($app.Panel.Visibility -ne "Collapsed") { $app.Panel.Visibility = "Collapsed" }
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
        $empty.Text = (Get-WinToolText "msg.no-apps-match-this-search-or-filter")
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
    if ($script:WinToolState.Busy) {
        Write-WinToolLog -Message (Get-WinToolText "drivers.scan.wait") -Level "warn"
        return
    }
    $apps = @(Get-WinToolCheckedApp)
    if ($apps.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "msg.select-at-least-one-app-first") -Level "warn"
        return
    }
    $detected = $false
    if ($null -ne $script:WinToolState -and [bool]$script:WinToolState.AppsDetected) {
        $detected = $true
    }
    $split = Select-WinToolInstallApp -App $apps -Detected $detected
    $pending = @($split.Pending)
    $already = @($split.Already)
    if ($pending.Count -eq 0) {
        Write-WinToolLog -Message (Get-WinToolText "msg.those-apps-are-already-installed-use-update-to-look-for-") -Level "info"
        return
    }
    if ($already.Count -gt 0) {
        Write-WinToolLog -Message ((Get-WinToolText "msg.skipped-n-already-installed-app-s-use-update-to-look-for") -f $already.Count) -Level "info"
    }
    $ok = Request-WinToolConfirmation -Message ((Get-WinToolText "msg.install-n-app-s-with-winget-each-vendor-s-license-is-acc") -f $pending.Count) -Title (Get-WinToolText "msg.install-apps")
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolAppPlan -App $pending)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "App install finished. Open a new terminal if a command is not on PATH yet." -AfterDone "Start-WinToolAppDetection"
}
