# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolActiveFont {
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())) {
        $rows.Add($item)
        $seen[[string]$item.id] = $true
    }
    foreach ($item in @($script:WinToolExtraFont)) {
        if (-not $seen.ContainsKey([string]$item.id)) {
            $rows.Add($item)
        }
    }
    return $rows.ToArray()
}

function Get-WinToolActiveOhMyPoshTheme {
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @())) {
        $rows.Add($item)
        $seen[[string]$item.id] = $true
    }
    foreach ($item in @($script:WinToolExtraOhMyPoshTheme)) {
        if (-not $seen.ContainsKey([string]$item.id)) {
            $rows.Add($item)
        }
    }
    return $rows.ToArray()
}

function Initialize-WinToolTerminalView {
    $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    $script:WinToolTerminalMode = "simple"
    $script:WinToolExtraFont = @()
    $script:WinToolExtraOhMyPoshTheme = @()
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeSimple") -EventName "Checked" -Name "Terminal: Simple mode" -Action {
        $script:WinToolTerminalMode = "simple"
        (Get-WinToolUi -Name "TerminalAdvancedHost").Visibility = "Collapsed"
        (Get-WinToolUi -Name "TerminalSimpleHost").Visibility = "Visible"
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
        Update-WinToolTerminalSummary
        Update-WinToolTerminalPreview
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeAdvanced") -EventName "Checked" -Name "Terminal: Advanced mode" -Action {
        $script:WinToolTerminalMode = "advanced"
        (Get-WinToolUi -Name "TerminalSimpleHost").Visibility = "Collapsed"
        (Get-WinToolUi -Name "TerminalAdvancedHost").Visibility = "Visible"
        Update-WinToolTerminalSummary
        Update-WinToolPromptSelection
        Update-WinToolSchemeSelection
        Update-WinToolTerminalPreview
        Show-WinToolTerminalSelection
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontSearch") -EventName "TextChanged" -Name "Terminal: font search" -Action {
        Sync-WinToolSearchHint -BoxName "TerminalFontSearch" -HintName "TerminalFontSearchHint"
        Update-WinToolFontList
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontNerdOnly") -EventName "Click" -Name "Terminal: Nerd Fonts only" -Action { Update-WinToolFontList }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalThemeSearch") -EventName "TextChanged" -Name "Terminal: theme search" -Action {
        Sync-WinToolSearchHint -BoxName "TerminalThemeSearch" -HintName "TerminalThemeSearchHint"
        Update-WinToolPromptStyleList
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalRefresh") -EventName "Click" -Name "Terminal: refresh lists" -Action { Update-WinToolTerminalCatalogOnline }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalSetup") -EventName "Click" -Name "Terminal: apply setup" -Action { Invoke-WinToolTerminalClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontList") -EventName "SelectionChanged" -Name "Terminal: choose font" -Action {
        Update-WinToolFontSample
        Update-WinToolTerminalSummary
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalStyleList") -EventName "SelectionChanged" -Name "Terminal: choose prompt style" -Action {
        Update-WinToolTerminalSummary
        Update-WinToolTerminalPreview
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ViewTerminal") -EventName "SizeChanged" -Name "Terminal: layout" -Action {
        Update-WinToolTerminalLayout -Width ((Get-WinToolUi -Name "ViewTerminal").ActualWidth - 40)
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "NavTerminal") -EventName "Checked" -Name "Terminal: show the selection" -Action {
        Show-WinToolTerminalSelection
    }
    Build-WinToolSimpleTerminalCard
    Build-WinToolPromptCard
    Build-WinToolExtraToggle
    Build-WinToolSchemeCard
    Update-WinToolFontList
    Update-WinToolPromptStyleList
    Update-WinToolTerminalSummary
    Update-WinToolTerminalPreview
}

function Build-WinToolSimpleTerminalCard {
    $hostPanel = Get-WinToolUi -Name "TerminalSimpleHost"
    $hostPanel.Children.Clear()
    $card = New-WinToolCard
    $stack = New-Object System.Windows.Controls.StackPanel
    [void]$stack.Children.Add((New-WinToolText -Text "Recommended setup" -Size 18 -Weight "SemiBold"))
    [void]$stack.Children.Add((New-WinToolText -Text "Windows Terminal, PowerShell 7, Oh My Posh with the Jan De Dobbeleer theme, a Nerd Font, file icons, and history suggestions. You can change any of this in Advanced." -Size 13 -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 6, 0, 8))))
    [void]$stack.Children.Add((New-WinToolTerminalPreview -Segments @(
        [pscustomobject]@{ text = "~/src "; color = "#6C9BFF" },
        [pscustomobject]@{ text = "main "; color = "#3DDC97" },
        [pscustomobject]@{ text = ">"; color = "#E8EDF7" }
    )))
    $card.Child = $stack
    [void]$hostPanel.Children.Add($card)
}

function New-WinToolTerminalTile {
    $tile = New-Object System.Windows.Controls.Border
    $tile.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushNavHover")
    $tile.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    $tile.BorderThickness = [System.Windows.Thickness]::new(1)
    $tile.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $tile.Padding = [System.Windows.Thickness]::new(9, 0, 9, 0)
    $tile.Margin = [System.Windows.Thickness]::new(0, 0, 8, 6)
    $tile.Cursor = [System.Windows.Input.Cursors]::Hand
    return $tile
}

function Build-WinToolPromptCard {
    $hostPanel = Get-WinToolUi -Name "TerminalPromptHost"
    $hostPanel.Children.Clear()
    $catalog = Get-WinToolTerminalCatalog
    foreach ($prompt in @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @())) {
        # Compact tile, three per row; the details move to the tooltip.
        $card = New-WinToolTerminalTile
        $card.Height = 44
        $card.Tag = [string]$prompt.id
        $installs = @($prompt.installs) -join ", "
        $card.ToolTip = ([string]$prompt.summary) + "`nInstalls: " + $installs
        $label = New-WinToolText -Text ([string]$prompt.name) -Size 11
        $label.VerticalAlignment = "Center"
        $label.TextTrimming = "CharacterEllipsis"
        $card.Child = $label
        Register-WinToolUiEvent -Control $card -EventName "MouseLeftButtonUp" -Name "Terminal: choose prompt" -Data ([string]$prompt.id) -Action {
            param($source, $eventData, $promptId)
            $null = $source, $eventData
            Set-WinToolTerminalChoiceValue -Name "prompt" -Value $promptId
            Update-WinToolPromptStyleList
            Update-WinToolTerminalSummary
            Update-WinToolPromptSelection
            Update-WinToolTerminalPreview
            Show-WinToolTerminalSelection
        }
        [void]$hostPanel.Children.Add($card)
    }
    Update-WinToolPromptSelection
}

function Set-WinToolTerminalChoiceValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )
    if ($null -eq $script:WinToolTerminalChoice) {
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    }
    $script:WinToolTerminalChoice.$Name = $Value
}

function Update-WinToolPromptSelection {
    $selected = [string]$script:WinToolTerminalChoice.prompt
    $hostPanel = Get-WinToolUi -Name "TerminalPromptHost"
    for ($index = 0; $index -lt $hostPanel.Children.Count; $index++) {
        $card = $hostPanel.Children[$index]
        if ([string]$card.Tag -eq $selected) {
            $card.BorderThickness = [System.Windows.Thickness]::new(2)
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushAccent")
        }
        else {
            $card.BorderThickness = [System.Windows.Thickness]::new(1)
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        }
    }
}

function Update-WinToolPromptStyleList {
    $list = Get-WinToolUi -Name "TerminalStyleList"
    $prompt = [string]$script:WinToolTerminalChoice.prompt
    # The list remembers which prompt it was built for, so an old selection
    # never overwrites the style of a newly picked prompt.
    $list.Tag = $null
    $list.Items.Clear()
    $query = [string](Get-WinToolUi -Name "TerminalThemeSearch").Text
    $note = Get-WinToolUi -Name "TerminalStyleNote"
    if ($prompt -eq "oh-my-posh") {
        $note.Text = "Official Oh My Posh themes. Search to narrow the gallery."
        foreach ($theme in @(Get-WinToolActiveOhMyPoshTheme)) {
            $hay = ([string]$theme.name) + " " + ([string]$theme.file)
            if (-not (Test-WinToolTextMatch -Haystack $hay -Query $query)) { continue }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [string]$theme.name
            $item.Tag = [string]$theme.id
            [void]$list.Items.Add($item)
            if ([string]$theme.id -eq [string]$script:WinToolTerminalChoice.promptStyle) {
                $list.SelectedItem = $item
            }
        }
    }
    elseif ($prompt -eq "starship") {
        $note.Text = "Starship presets."
        foreach ($preset in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "starshipPresets" -Default @())) {
            if (-not (Test-WinToolTextMatch -Haystack ([string]$preset.name + " " + [string]$preset.id) -Query $query)) { continue }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [string]$preset.name
            $item.Tag = [string]$preset.id
            [void]$list.Items.Add($item)
            if ([string]$preset.id -eq [string]$script:WinToolTerminalChoice.promptStyle) {
                $list.SelectedItem = $item
            }
        }
    }
    elseif ($prompt -eq "oh-my-zsh") {
        $note.Text = "Themes that ship with Oh My Zsh."
        foreach ($name in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "omzThemes" -Default @())) {
            if (-not (Test-WinToolTextMatch -Haystack ([string]$name) -Query $query)) { continue }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [string]$name
            $item.Tag = [string]$name
            [void]$list.Items.Add($item)
            if ([string]$name -eq [string]$script:WinToolTerminalChoice.promptStyle) {
                $list.SelectedItem = $item
            }
        }
    }
    elseif (@(Get-WinToolPromptVariantList -PromptId $prompt).Count -gt 0) {
        $note.Text = "Styles for this prompt. The preview shows the one you pick."
        foreach ($variant in @(Get-WinToolPromptVariantList -PromptId $prompt)) {
            $about = [string](Get-WinToolNote -Object $variant -Name "description" -Default "")
            if (-not (Test-WinToolTextMatch -Haystack ([string]$variant.name + " " + $about) -Query $query)) { continue }
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = [string]$variant.name
            $item.Tag = [string]$variant.id
            if (-not [string]::IsNullOrWhiteSpace($about)) { $item.ToolTip = $about }
            [void]$list.Items.Add($item)
            if ([string]$variant.id -eq [string]$script:WinToolTerminalChoice.promptStyle) {
                $list.SelectedItem = $item
            }
        }
    }
    else {
        $note.Text = "This prompt has its own default look. The font and extras below still apply."
    }
    if ($null -eq $list.SelectedItem -and $list.Items.Count -gt 0) {
        $list.SelectedIndex = 0
    }
    # The note only shows inside an empty list, so the card stays as in the
    # approved layout; it is kept as a tooltip on the list otherwise.
    $list.ToolTip = $note.Text
    if ($list.Items.Count -eq 0) {
        $note.Visibility = "Visible"
        if ($prompt -eq "oh-my-posh" -or $prompt -eq "oh-my-zsh" -or $prompt -eq "starship" -or @(Get-WinToolPromptVariantList -PromptId $prompt).Count -gt 0) {
            $note.Text = "No themes match the search."
        }
    }
    else {
        $note.Visibility = "Collapsed"
    }
    $list.Tag = $prompt
    if ($null -ne $list.SelectedItem) {
        $script:WinToolTerminalChoice.promptStyle = [string]$list.SelectedItem.Tag
    }
    Show-WinToolTerminalSelection
}

function Build-WinToolExtraToggle {
    $hostPanel = Get-WinToolUi -Name "TerminalExtrasHost"
    $hostPanel.Children.Clear()
    foreach ($extra in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "extras" -Default @())) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = [string]$extra.name
        $box.ToolTip = [string]$extra.description
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 12, 10)
        $box.FontSize = 12
        $box.Height = 18
        $box.Tag = [string]$extra.id
        $box.IsChecked = $false
        if ([string]$extra.id -eq "terminal-icons" -or [string]$extra.id -eq "psreadline") {
            $box.IsChecked = $true
        }
        Register-WinToolUiEvent -Control $box -EventName "Click" -Name "Terminal: extras" -Action { Update-WinToolTerminalSummary }
        [void]$hostPanel.Children.Add($box)
    }
}

function Build-WinToolSchemeCard {
    $hostPanel = Get-WinToolUi -Name "TerminalSchemeHost"
    $hostPanel.Children.Clear()
    foreach ($scheme in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
        $card = New-WinToolTerminalTile
        $card.Padding = [System.Windows.Thickness]::new(9, 6, 9, 0)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $card.Height = 90
        $card.Tag = [string]$scheme.id
        $swatch = New-Object System.Windows.Controls.Border
        $swatch.Height = 50
        $swatch.CornerRadius = [System.Windows.CornerRadius]::new(5)
        $swatchColor = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString([string]$scheme.background))
        $swatch.Background = [System.Windows.Media.SolidColorBrush]::new($swatchColor)
        $swatch.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
        $stack = New-Object System.Windows.Controls.StackPanel
        $schemeName = New-WinToolText -Text ([string]$scheme.name) -Size 11
        $schemeName.Height = 16
        $schemeName.TextTrimming = "CharacterEllipsis"
        [void]$stack.Children.Add($schemeName)
        [void]$stack.Children.Add($swatch)
        $card.Child = $stack
        Register-WinToolUiEvent -Control $card -EventName "MouseLeftButtonUp" -Name "Terminal: choose color scheme" -Data ([string]$scheme.id) -Action {
            param($source, $eventData, $schemeId)
            $null = $source, $eventData
            Set-WinToolTerminalChoiceValue -Name "schemeId" -Value $schemeId
            Update-WinToolTerminalSummary
            Update-WinToolSchemeSelection
            Update-WinToolTerminalPreview
        }
        [void]$hostPanel.Children.Add($card)
    }
    Update-WinToolSchemeSelection
}

function Update-WinToolSchemeSelection {
    $selected = [string]$script:WinToolTerminalChoice.schemeId
    $hostPanel = Get-WinToolUi -Name "TerminalSchemeHost"
    for ($index = 0; $index -lt $hostPanel.Children.Count; $index++) {
        $card = $hostPanel.Children[$index]
        if ([string]$card.Tag -eq $selected) {
            $card.BorderThickness = [System.Windows.Thickness]::new(2)
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushAccent")
        }
        else {
            $card.BorderThickness = [System.Windows.Thickness]::new(1)
            $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        }
    }
}

function Update-WinToolTerminalLayout {
    param(
        [double]$Width
    )
    # Two columns as in the approved layout; one column when the content
    # area is narrower than 800 px (a window under about 1100 px).
    $grid = Get-WinToolUi -Name "TerminalAdvancedHost"
    if ($null -eq $grid -or $Width -le 0) {
        return
    }
    $narrow = ($Width -lt 800)
    if ($narrow -eq [bool]$script:WinToolTerminalNarrow -and $null -ne $script:WinToolTerminalNarrow) {
        return
    }
    $script:WinToolTerminalNarrow = $narrow
    $places = [ordered]@{
        TerminalCardPrompt = @(0, 0, 0)
        TerminalCardFont = @(0, 2, 1)
        TerminalCardExtras = @(1, 0, 2)
        TerminalCardScheme = @(1, 2, 3)
    }
    foreach ($name in $places.Keys) {
        $card = Get-WinToolUi -Name $name
        if ($null -eq $card) { continue }
        $place = $places[$name]
        if ($narrow) {
            [System.Windows.Controls.Grid]::SetRow($card, $place[2])
            [System.Windows.Controls.Grid]::SetColumn($card, 0)
            [System.Windows.Controls.Grid]::SetColumnSpan($card, 3)
        }
        else {
            [System.Windows.Controls.Grid]::SetRow($card, $place[0])
            [System.Windows.Controls.Grid]::SetColumn($card, $place[1])
            [System.Windows.Controls.Grid]::SetColumnSpan($card, 1)
        }
    }
    $right = Get-WinToolUi -Name "TerminalColumnRight"
    $gap = Get-WinToolUi -Name "TerminalColumnGap"
    $left = Get-WinToolUi -Name "TerminalColumnLeft"
    if ($narrow) {
        $right.MinWidth = 0
        $right.Width = [System.Windows.GridLength]::new(0)
        $gap.Width = [System.Windows.GridLength]::new(0)
        $left.MinWidth = 0
    }
    else {
        $right.MinWidth = 330
        $right.Width = [System.Windows.GridLength]::new(540, [System.Windows.GridUnitType]::Star)
        $gap.Width = [System.Windows.GridLength]::new(15)
        $left.MinWidth = 330
    }
}

function Update-WinToolFontList {
    $list = Get-WinToolUi -Name "TerminalFontList"
    $list.Items.Clear()
    $query = [string](Get-WinToolUi -Name "TerminalFontSearch").Text
    $nerdOnly = ((Get-WinToolUi -Name "TerminalFontNerdOnly").IsChecked -eq $true)
    $fonts = @(Select-WinToolFont -Font (Get-WinToolActiveFont) -Query $query -NerdOnly $nerdOnly)
    foreach ($font in $fonts) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $badge = "Programming font"
        if ($font.nerd) { $badge = "Nerd Font" }
        $item.Content = [string]$font.name
        $item.ToolTip = $badge
        $item.Tag = [string]$font.id
        [void]$list.Items.Add($item)
        if ([string]$font.id -eq [string]$script:WinToolTerminalChoice.fontId) {
            $list.SelectedItem = $item
        }
    }
    if ($null -eq $list.SelectedItem -and $list.Items.Count -gt 0) {
        $list.SelectedIndex = 0
    }
    Update-WinToolFontSample
    Show-WinToolTerminalSelection
}

function Update-WinToolFontSample {
    $list = Get-WinToolUi -Name "TerminalFontList"
    if ($null -ne $list.SelectedItem) {
        $script:WinToolTerminalChoice.fontId = [string]$list.SelectedItem.Tag
    }
    Update-WinToolTerminalPreview
}

function Find-WinToolChildScrollViewer {
    param(
        $Element
    )
    if ($null -eq $Element) {
        return $null
    }
    $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element)
    for ($index = 0; $index -lt $count; $index++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Element, $index)
        if ($child -is [System.Windows.Controls.ScrollViewer]) {
            return $child
        }
        $found = Find-WinToolChildScrollViewer -Element $child
        if ($null -ne $found) {
            return $found
        }
    }
    return $null
}

function Show-WinToolTerminalSelection {
    # Brings the chosen font and theme into view in their lists. When a list
    # is not laid out yet, the log pump calls this again a moment later.
    $script:WinToolTerminalScrollPending = $false
    foreach ($name in @("TerminalFontList", "TerminalStyleList")) {
        $list = Get-WinToolUi -Name $name
        if ($null -eq $list -or $null -eq $list.SelectedItem) { continue }
        try {
            $list.UpdateLayout()
            $list.ScrollIntoView($list.SelectedItem)
            # ScrollIntoView needs a later layout pass; moving the list's own
            # scroll viewer (item based) works right away.
            $viewer = Find-WinToolChildScrollViewer -Element $list
            if ($null -ne $viewer -and $list.SelectedIndex -ge 0) {
                $viewer.ScrollToVerticalOffset([Math]::Max(0, $list.SelectedIndex - 1))
                $list.UpdateLayout()
            }
            if ($list.ActualHeight -le 0 -and $script:WinToolTerminalMode -eq "advanced") {
                # Not laid out yet (hidden tab or mode); the log pump retries.
                $script:WinToolTerminalScrollPending = $true
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
}

function ConvertTo-WinToolPreviewBrush {
    param(
        [string]$Color
    )
    if ([string]::IsNullOrWhiteSpace($Color)) {
        return $null
    }
    try {
        $value = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($Color))
        $brush = [System.Windows.Media.SolidColorBrush]::new($value)
        $brush.Freeze()
        return $brush
    }
    catch {
        return $null
    }
}

function Get-WinToolPreviewTheme {
    # Returns the Oh My Posh theme JSON from memory or disk; when it is not
    # there yet, starts one background download and returns $null.
    param(
        [string]$ThemeId
    )
    $file = Get-WinToolOmpThemeFileName -ThemeId $ThemeId -Themes @(Get-WinToolActiveOhMyPoshTheme)
    $theme = Read-WinToolCachedOmpTheme -File $file
    if ($null -ne $theme) {
        return $theme
    }
    if ($null -eq $script:WinToolOmpPreviewFailed) {
        $script:WinToolOmpPreviewFailed = @{}
    }
    if ($script:WinToolOmpPreviewFailed.ContainsKey($file) -or $null -ne $script:WinToolState.PreviewJob) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or $file -notmatch '^[A-Za-z0-9._-]+$') {
        $script:WinToolOmpPreviewFailed[$file] = $true
        return $null
    }
    $path = Join-Path $env:LOCALAPPDATA ("WinTool\themes\" + $file)
    $url = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/" + [uri]::EscapeDataString($file)
    $scriptText = @'
param($sync, $url, $path)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $folder = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $part = $path + ".part"
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 10
    Move-Item -LiteralPath $part -Destination $path -Force
    $sync.Ok = $true
}
catch {
    $sync.Error = $_.Exception.Message
}
finally {
    $sync.Done = $true
}
'@
    try {
        $job = Start-WinToolScriptJob -ScriptText $scriptText -Argument @($url, $path)
        $script:WinToolState.PreviewJob = [pscustomobject]@{ Job = $job; File = $file; Started = [datetime]::UtcNow }
    }
    catch {
        $script:WinToolOmpPreviewFailed[$file] = $true
    }
    return $null
}

function Complete-WinToolPreviewThemeDownload {
    $preview = $script:WinToolState.PreviewJob
    $script:WinToolState.PreviewJob = $null
    if ($null -eq $preview) {
        return
    }
    $ok = [bool]$preview.Job.Sync.Ok
    Stop-WinToolThread -Job $preview.Job
    if (-not $ok) {
        if ($null -eq $script:WinToolOmpPreviewFailed) { $script:WinToolOmpPreviewFailed = @{} }
        $script:WinToolOmpPreviewFailed[[string]$preview.File] = $true
    }
    try {
        Update-WinToolTerminalPreview
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Update-WinToolTerminalPreview {
    # Draws the prompt line for the chosen prompt and theme, in the chosen
    # font, on the chosen color scheme. Never throws: a failure keeps the
    # last preview.
    $sample = Get-WinToolUi -Name "TerminalFontSample"
    $border = Get-WinToolUi -Name "TerminalFontPreview"
    if ($null -eq $sample -or $null -eq $border -or $null -eq $script:WinToolTerminalChoice) {
        return
    }
    try {
        $choice = $script:WinToolTerminalChoice
        $promptId = [string]$choice.prompt
        $style = [string]$choice.promptStyle
        $theme = $null
        $waiting = $false
        if ($promptId -eq "oh-my-posh") {
            $theme = Get-WinToolPreviewTheme -ThemeId $style
            $waiting = ($null -eq $theme -and $null -ne $script:WinToolState.PreviewJob)
        }
        $segments = @(Get-WinToolPromptPreview -PromptId $promptId -PromptStyle $style -Theme $theme)

        $schemeBackground = "#0F131C"
        $schemeForeground = "#D5DEEE"
        foreach ($scheme in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
            if ([string]$scheme.id -eq [string]$choice.schemeId) {
                $schemeBackground = [string]$scheme.background
                $schemeForeground = [string]$scheme.foreground
                break
            }
        }
        $foreground = ConvertTo-WinToolPreviewBrush -Color $schemeForeground
        $background = ConvertTo-WinToolPreviewBrush -Color $schemeBackground
        if ($null -ne $background) { $border.Background = $background }
        if ($null -ne $foreground) { $sample.Foreground = $foreground }

        $face = ""
        foreach ($font in @(Get-WinToolActiveFont)) {
            if ([string]$font.id -eq [string]$choice.fontId) { $face = [string]$font.face; break }
        }
        $families = "Cascadia Mono, Consolas"
        if (-not [string]::IsNullOrWhiteSpace($face)) { $families = $face + ", " + $families }
        $sample.FontFamily = [System.Windows.Media.FontFamily]::new($families)

        $sample.Inlines.Clear()
        foreach ($segment in $segments) {
            $run = New-Object System.Windows.Documents.Run -ArgumentList ([string]$segment.Text)
            $brush = ConvertTo-WinToolPreviewBrush -Color ([string]$segment.Foreground)
            if ($null -ne $brush) { $run.Foreground = $brush }
            $fill = ConvertTo-WinToolPreviewBrush -Color ([string]$segment.Background)
            if ($null -ne $fill) { $run.Background = $fill }
            $sample.Inlines.Add($run)
        }
        $sample.Inlines.Add((New-Object System.Windows.Documents.Run -ArgumentList " echo hello"))
        $sample.Inlines.Add((New-Object System.Windows.Documents.LineBreak))
        $answer = New-Object System.Windows.Documents.Run -ArgumentList "hello"
        $answer.FontSize = 12
        $sample.Inlines.Add($answer)

        $tip = "Font: " + $face
        if ($waiting) { $tip += "`nLoading the theme colors from GitHub..." }
        elseif ($promptId -eq "oh-my-posh" -and $null -eq $theme) { $tip += "`nTheme colors are approximate (theme file not available)." }
        $border.ToolTip = $tip
    }
    catch {
        $null = $_.Exception.Message
    }
}
function Read-WinToolExtraSelection {
    $hostPanel = Get-WinToolUi -Name "TerminalExtrasHost"
    $flags = @{ terminalIcons = $false; psReadLine = $false; zoxide = $false; fzf = $false }
    for ($index = 0; $index -lt $hostPanel.Children.Count; $index++) {
        $box = $hostPanel.Children[$index]
        $flags[[string]$box.Tag] = ($box.IsChecked -eq $true)
    }
    return $flags
}

function Update-WinToolTerminalSummary {
    if ($script:WinToolTerminalMode -eq "advanced") {
        $list = Get-WinToolUi -Name "TerminalStyleList"
        if ($null -ne $list.SelectedItem -and [string]$list.Tag -eq [string]$script:WinToolTerminalChoice.prompt) {
            $script:WinToolTerminalChoice.promptStyle = [string]$list.SelectedItem.Tag
        }
        $fonts = Get-WinToolUi -Name "TerminalFontList"
        if ($null -ne $fonts.SelectedItem) {
            $script:WinToolTerminalChoice.fontId = [string]$fonts.SelectedItem.Tag
        }
        $flags = Read-WinToolExtraSelection
        $script:WinToolTerminalChoice.terminalIcons = [bool]$flags["terminal-icons"]
        $script:WinToolTerminalChoice.psReadLine = [bool]$flags["psreadline"]
        $script:WinToolTerminalChoice.zoxide = [bool]$flags["zoxide"]
        $script:WinToolTerminalChoice.fzf = [bool]$flags["fzf"]
    }
    $lines = @(Get-WinToolTerminalSummary -Selection $script:WinToolTerminalChoice)
    (Get-WinToolUi -Name "TerminalSummary").Text = ($lines -join "`n")
    $summaryHost = Get-WinToolUi -Name "TerminalSummaryHost"
    if ($null -ne $summaryHost) {
        # Three short rows, as in the mockup; the full list is the tooltip.
        $summaryHost.Children.Clear()
        $rows = @(Get-WinToolSummaryRow -Line $lines -Count 3)
        foreach ($row in $rows) {
            $text = New-WinToolText -Text ([string]$row) -Size 11 -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 0, 12, 0))
            $text.Height = 18
            $text.TextTrimming = "CharacterEllipsis"
            $text.ToolTip = ($lines -join "`n")
            [void]$summaryHost.Children.Add($text)
        }
    }
}

function New-WinToolTerminalPreview {
    param($Segments)
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(12)
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushLog")
    $text = New-Object System.Windows.Controls.TextBlock
    $text.FontFamily = "Consolas"
    $text.FontSize = 13
    $text.TextWrapping = "Wrap"
    foreach ($segment in @($Segments)) {
        $run = New-Object System.Windows.Documents.Run
        $run.Text = [string]$segment.text
        $runColor = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString([string]$segment.color))
        $run.Foreground = [System.Windows.Media.SolidColorBrush]::new($runColor)
        [void]$text.Inlines.Add($run)
    }
    $border.Child = $text
    return $border
}

function Update-WinToolTerminalCatalogOnline {
    Write-WinToolLog -Message "Refreshing Nerd Fonts and Oh My Posh themes from GitHub." -Level "info"
    try {
        $headers = @{ "User-Agent" = "WinTool"; "Accept" = "application/vnd.github+json" }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" -Headers $headers
        $known = @{}
        foreach ($font in @(Get-WinToolActiveFont)) {
            $asset = [string](Get-WinToolNote -Object $font -Name "asset" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($asset)) { $known[$asset] = $true }
        }
        $added = New-Object System.Collections.Generic.List[object]
        foreach ($asset in @($release.assets)) {
            $name = [string]$asset.name
            if (-not $name.EndsWith(".zip")) { continue }
            if ($name -eq "FontPatcher.zip" -or $name -eq "NerdFontsSymbolsOnly.zip") { continue }
            if ($known.ContainsKey($name)) { continue }
            $stem = [IO.Path]::GetFileNameWithoutExtension($name)
            $added.Add([pscustomobject]@{
                id = ($stem.ToLower() + "-nf")
                name = ($stem + " Nerd Font")
                face = ($stem + " Nerd Font")
                match = $stem
                nerd = $true
                source = "nerd-fonts"
                release = [string]$release.tag_name
                asset = $name
                sample = "agnoster ~/src main"
            })
        }
        $script:WinToolExtraFont = @($script:WinToolExtraFont) + @($added.ToArray())
        $themes = Invoke-RestMethod -Uri "https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes?ref=main" -Headers $headers
        $knownThemes = @{}
        foreach ($theme in @(Get-WinToolActiveOhMyPoshTheme)) { $knownThemes[[string]$theme.file] = $true }
        $extraThemes = New-Object System.Collections.Generic.List[object]
        foreach ($theme in @($themes)) {
            $file = [string]$theme.name
            if (-not $file.EndsWith(".omp.json")) { continue }
            if ($knownThemes.ContainsKey($file)) { continue }
            $id = $file.Substring(0, $file.Length - 9)
            $extraThemes.Add([pscustomobject]@{ id = $id; file = $file; name = $id })
        }
        $script:WinToolExtraOhMyPoshTheme = @($script:WinToolExtraOhMyPoshTheme) + @($extraThemes.ToArray())
        Update-WinToolFontList
        Update-WinToolPromptStyleList
        Write-WinToolLog -Message ("Catalog refresh added " + @($added.ToArray()).Count + " fonts and " + @($extraThemes.ToArray()).Count + " themes.") -Level "ok"
    }
    catch {
        Write-WinToolLog -Message ("Could not refresh the catalogs. The built-in lists are still available. " + $_.Exception.Message) -Level "warn"
    }
}

function Get-WinToolTerminalChoice {
    if ($null -eq $script:WinToolTerminalChoice) {
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    }
    $enabled = $true
    $enabledBox = $script:WinToolWindow.FindName("TerminalEnabled")
    if ($null -ne $enabledBox) {
        $enabled = ($enabledBox.IsChecked -eq $true)
    }
    $choice = $script:WinToolTerminalChoice
    return [pscustomobject]@{
        enabled = $enabled
        prompt = [string]$choice.prompt
        promptStyle = [string]$choice.promptStyle
        fontId = [string]$choice.fontId
        schemeId = [string]$choice.schemeId
        terminalIcons = [bool]$choice.terminalIcons
        psReadLine = [bool]$choice.psReadLine
        zoxide = [bool]$choice.zoxide
        fzf = [bool]$choice.fzf
    }
}

function Sync-WinToolTerminalChoice {
    param($Selection)
    if ($null -eq $Selection) { return }
    if ($null -eq $script:WinToolTerminalChoice) {
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    }
    $prompt = [string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($prompt)) { $script:WinToolTerminalChoice.prompt = $prompt }
    $style = [string](Get-WinToolNote -Object $Selection -Name "promptStyle" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($style)) { $script:WinToolTerminalChoice.promptStyle = $style }
    $fontId = [string](Get-WinToolNote -Object $Selection -Name "fontId" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($fontId)) { $script:WinToolTerminalChoice.fontId = $fontId }
    $icons = Get-WinToolNote -Object $Selection -Name "terminalIcons"
    if ($null -ne $icons) { $script:WinToolTerminalChoice.terminalIcons = [bool]$icons }
    (Get-WinToolUi -Name "TerminalModeAdvanced").IsChecked = $true
    Update-WinToolFontList
    Update-WinToolPromptStyleList
    Update-WinToolPromptSelection
    Update-WinToolTerminalSummary
}

function Invoke-WinToolTerminalClick {
    $choice = Get-WinToolTerminalChoice
    $summary = @(Get-WinToolTerminalSummary -Selection $choice)
    $preview = ($summary -join "`n")
    $ok = Request-WinToolConfirmation -Message ("Apply this terminal setup?`n`n" + $preview) -Title "Terminal"
    if (-not $ok) { return }
    $steps = @(Get-WinToolTerminalPlan -Selection $choice)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "Terminal setup finished. Open a new terminal window to see the prompt."
}
