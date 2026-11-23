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
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeAdvanced") -EventName "Checked" -Name "Terminal: Advanced mode" -Action {
        $script:WinToolTerminalMode = "advanced"
        (Get-WinToolUi -Name "TerminalSimpleHost").Visibility = "Collapsed"
        (Get-WinToolUi -Name "TerminalAdvancedHost").Visibility = "Visible"
        Update-WinToolTerminalSummary
        Update-WinToolPromptSelection
        Update-WinToolSchemeSelection
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
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ViewTerminal") -EventName "SizeChanged" -Name "Terminal: layout" -Action {
        Update-WinToolTerminalLayout -Width ((Get-WinToolUi -Name "ViewTerminal").ActualWidth - 48)
    }
    Build-WinToolSimpleTerminalCard
    Build-WinToolPromptCard
    Build-WinToolExtraToggle
    Build-WinToolSchemeCard
    Update-WinToolFontList
    Update-WinToolPromptStyleList
    Update-WinToolTerminalSummary
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
    $tile.Padding = [System.Windows.Thickness]::new(10, 6, 10, 6)
    $tile.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
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
        $label = New-WinToolText -Text ([string]$prompt.name) -Size 13
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
    $list.Items.Clear()
    $prompt = [string]$script:WinToolTerminalChoice.prompt
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
        if ($prompt -eq "oh-my-posh" -or $prompt -eq "oh-my-zsh") {
            $note.Text = "No themes match the search."
        }
    }
    else {
        $note.Visibility = "Collapsed"
    }
}

function Build-WinToolExtraToggle {
    $hostPanel = Get-WinToolUi -Name "TerminalExtrasHost"
    $hostPanel.Children.Clear()
    foreach ($extra in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "extras" -Default @())) {
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Content = [string]$extra.name
        $box.ToolTip = [string]$extra.description
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 12, 10)
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
        $card.Padding = [System.Windows.Thickness]::new(8)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $card.Tag = [string]$scheme.id
        $swatch = New-Object System.Windows.Controls.Border
        $swatch.Height = 40
        $swatch.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $swatchColor = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString([string]$scheme.background))
        $swatch.Background = [System.Windows.Media.SolidColorBrush]::new($swatchColor)
        $swatch.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $stack = New-Object System.Windows.Controls.StackPanel
        [void]$stack.Children.Add((New-WinToolText -Text ([string]$scheme.name) -Size 12))
        [void]$stack.Children.Add($swatch)
        $card.Child = $stack
        Register-WinToolUiEvent -Control $card -EventName "MouseLeftButtonUp" -Name "Terminal: choose color scheme" -Data ([string]$scheme.id) -Action {
            param($source, $eventData, $schemeId)
            $null = $source, $eventData
            Set-WinToolTerminalChoiceValue -Name "schemeId" -Value $schemeId
            Update-WinToolTerminalSummary
            Update-WinToolSchemeSelection
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
        $right.MinWidth = 340
        $right.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $gap.Width = [System.Windows.GridLength]::new(16)
        $left.MinWidth = 340
    }
    $columns = 3
    if ($narrow -and $Width -lt 560) { $columns = 2 }
    (Get-WinToolUi -Name "TerminalSummaryHost").Columns = $columns
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
}

function Update-WinToolFontSample {
    $sample = Get-WinToolUi -Name "TerminalFontSample"
    $fontId = [string]$script:WinToolTerminalChoice.fontId
    $list = Get-WinToolUi -Name "TerminalFontList"
    if ($null -ne $list.SelectedItem) {
        $fontId = [string]$list.SelectedItem.Tag
        $script:WinToolTerminalChoice.fontId = $fontId
    }
    $font = $null
    foreach ($item in @(Get-WinToolActiveFont)) {
        if ([string]$item.id -eq $fontId) { $font = $item; break }
    }
    if ($null -eq $font) {
        $sample.Text = "Select a font to preview it."
        return
    }
    $sample.FontFamily = [string]$font.face
    $text = [string](Get-WinToolNote -Object $font -Name "sample" -Default "The quick brown fox jumps over the lazy dog.")
    $sample.Text = $text + "`n" + [string]$font.face
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
        if ($null -ne $list.SelectedItem) {
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
        $summaryHost.Children.Clear()
        foreach ($line in $lines) {
            $text = New-WinToolText -Text ([string]$line) -Size 12 -Brush "BrushMuted" -Margin ([System.Windows.Thickness]::new(0, 0, 12, 4))
            $text.TextTrimming = "CharacterEllipsis"
            $text.ToolTip = [string]$line
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
