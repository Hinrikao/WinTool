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
        $titleStack.Children.Add((New-WinToolText -Text ([string]$category.name) -Size 18 -Weight "SemiBold"))
        $description = [string](Get-WinToolNote -Object $category -Name "description" -Default "")
        $titleStack.Children.Add((New-WinToolText -Text $description -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 4, 16, 0))))
        [System.Windows.Controls.Grid]::SetColumn($titleStack, 0)
        $header.Children.Add($titleStack)

        $selectAll = New-Object System.Windows.Controls.CheckBox
        $selectAll.Content = "Select all"
        $selectAll.VerticalAlignment = "Center"
        $selectAll.IsThreeState = $true
        [System.Windows.Controls.Grid]::SetColumn($selectAll, 1)
        $header.Children.Add($selectAll)
        $stack.Children.Add($header)

        $appsPanel = New-Object System.Windows.Controls.StackPanel
        $appsPanel.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
        $appRows = @()
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $row = New-WinToolAppRow -App $app -CategoryName ([string]$category.name)
            $appsPanel.Children.Add($row.Panel)
            $appRows += $row
        }
        $stack.Children.Add($appsPanel)
        $card.Child = $stack
        $hostPanel.Children.Add($card)

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

        $boundCategory = $categoryRow
        $selectAll.Add_Click({
            Sync-WinToolCategoryFromHeader -CategoryRow $boundCategory
        }.GetNewClosure())
        foreach ($row in $appRows) {
            $boundRowCategory = $categoryRow
            $row.Checkbox.Add_Checked({
                Sync-WinToolAppToggle -CategoryRow $boundRowCategory
            }.GetNewClosure())
            $row.Checkbox.Add_Unchecked({
                Sync-WinToolAppToggle -CategoryRow $boundRowCategory
            }.GetNewClosure())
        }
    }

    (Get-WinToolUi -Name "AppSearch").Add_TextChanged({
        Sync-WinToolSearchHint -BoxName "AppSearch" -HintName "AppSearchHint"
        Update-WinToolAppFilter
    })
    (Get-WinToolUi -Name "AppSelectVisible").Add_Click({
        foreach ($row in @($script:WinToolState.AppRows)) {
            if ($row.Panel.Visibility -eq "Visible") {
                $row.Checkbox.IsChecked = $true
            }
        }
    })
    (Get-WinToolUi -Name "AppClear").Add_Click({
        Sync-WinToolAppCheck -Id @() -OnlyThese
    })
    (Get-WinToolUi -Name "AppInstall").Add_Click({
        Invoke-WinToolInstallClick
    })
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
    $panel.Children.Add($checkbox)

    $text = New-Object System.Windows.Controls.StackPanel
    $text.Children.Add((New-WinToolText -Text ([string]$App.name) -Weight "SemiBold"))
    $text.Children.Add((New-WinToolText -Text ([string]$App.description) -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 2, 0, 0))))
    $text.Children.Add((New-WinToolText -Text ("winget: " + [string]$App.wingetId) -Size 12 -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 2, 0, 0))))
    [System.Windows.Controls.Grid]::SetColumn($text, 1)
    $panel.Children.Add($text)

    $search = (@([string]$App.name, [string]$App.description, [string]$App.wingetId, [string]$App.id, $tags, $CategoryName) -join " ")
    return [pscustomobject]@{
        Id = [string]$App.id
        Name = [string]$App.name
        WingetId = [string]$App.wingetId
        Scope = [string](Get-WinToolNote -Object $App -Name "scope" -Default "")
        SearchText = $search
        Panel = $panel
        Checkbox = $checkbox
    }
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
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "App install finished. Open a new terminal if a command is not on PATH yet."
}
