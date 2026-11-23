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

function Build-WinToolSimpleTerminalCard {
    $hostPanel = Get-WinToolUi -Name "TerminalSimpleHost"
    $hostPanel.Children.Clear()
    $card = New-WinToolCard
    $stack = New-Object System.Windows.Controls.StackPanel
    [void]$stack.Children.Add((New-WinToolText -Text "Recommended setup" -Weight "Bold"))
    [void]$stack.Children.Add((New-WinToolText -Text "Windows Terminal, PowerShell 7, Oh My Posh with the Jan De Dobbeleer theme, a Nerd Font, file icons, and history suggestions. You can change any of this in Advanced." -Brush "BrushMuted" -Wrap -Margin ([System.Windows.Thickness]::new(0, 6, 0, 8))))
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
$part = $path + ".part"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $folder = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing -TimeoutSec 10
    if (-not (Test-Path -LiteralPath $part) -or (Get-Item -LiteralPath $part).Length -le 2) {
        throw "Downloaded preview theme was empty."
    }
    Move-Item -LiteralPath $part -Destination $path -Force
    $sync.Ok = $true
}
catch {
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
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

function New-WinToolTerminalPreview {
    param($Segments)
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(12)
    $border.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushLog")
    $text = New-Object System.Windows.Controls.TextBlock
    $text.FontFamily = "Consolas"
    $text.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
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
    if ($null -ne $script:WinToolState.CatalogJob) {
        return
    }
    Write-WinToolLog -Message "Refreshing Nerd Fonts and Oh My Posh themes from GitHub." -Level "info"
    $refreshButton = Get-WinToolUi -Name "TerminalRefresh"
    if ($null -ne $refreshButton) {
        $refreshButton.IsEnabled = $false
    }
    $scriptText = @'
param($sync)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "WinTool"; "Accept" = "application/vnd.github+json" }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" -Headers $headers -TimeoutSec 15
    $themes = Invoke-RestMethod -Uri "https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/contents/themes?ref=main" -Headers $headers -TimeoutSec 15
    $sync.Release = $release
    $sync.Themes = $themes
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
        $job = Start-WinToolScriptJob -ScriptText $scriptText -Argument @()
        $script:WinToolState.CatalogJob = [pscustomobject]@{ Job = $job; Started = [datetime]::UtcNow }
    }
    catch {
        if ($null -ne $refreshButton -and -not $script:WinToolState.Busy) {
            $refreshButton.IsEnabled = $true
        }
        Write-WinToolLog -Message ("Could not refresh the catalogs. The built-in lists are still available. " + $_.Exception.Message) -Level "warn"
    }
}

function Complete-WinToolTerminalCatalogOnline {
    $catalogJob = $script:WinToolState.CatalogJob
    $script:WinToolState.CatalogJob = $null
    if ($null -eq $catalogJob) {
        return
    }
    $ok = [bool]$catalogJob.Job.Sync.Ok
    $errText = [string]$catalogJob.Job.Sync.Error
    $release = $catalogJob.Job.Sync.Release
    $themes = $catalogJob.Job.Sync.Themes
    Stop-WinToolThread -Job $catalogJob.Job
    $refreshButton = Get-WinToolUi -Name "TerminalRefresh"
    if ($null -ne $refreshButton -and -not $script:WinToolState.Busy) {
        $refreshButton.IsEnabled = $true
    }
    if (-not $ok) {
        Write-WinToolLog -Message ("Could not refresh the catalogs. The built-in lists are still available. " + $errText) -Level "warn"
        return
    }
    try {
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
        Build-WinToolPromptCard
        Update-WinToolPromptSelection
        Update-WinToolFontList
        Update-WinToolPromptStyleList
        Write-WinToolLog -Message ("Catalog refresh added " + @($added.ToArray()).Count + " fonts and " + @($extraThemes.ToArray()).Count + " themes.") -Level "ok"
    }
    catch {
        Write-WinToolLog -Message ("Could not apply the refreshed catalogs. " + $_.Exception.Message) -Level "warn"
    }
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

function Initialize-WinToolTerminalView {
    $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    $script:WinToolTerminalMode = "simple"
    $script:WinToolTerminalFilter = "all"
    $script:WinToolTerminalSyncing = $false
    $script:WinToolExtraFont = @()
    $script:WinToolExtraOhMyPoshTheme = @()
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeSimple") -EventName "Checked" -Name "Terminal: Simple mode" -Action {
        $script:WinToolTerminalMode = "simple"
        Set-WinToolTerminalModeView
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
        Update-WinToolTerminalSummary
        Update-WinToolTerminalPreview
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeAdvanced") -EventName "Checked" -Name "Terminal: Advanced mode" -Action {
        $script:WinToolTerminalMode = "advanced"
        Set-WinToolTerminalModeView
        Update-WinToolExtraToggle
        # Simple resets the choice to the recommended setup, so the theme list,
        # fonts, and sizes are rebuilt for that choice here, before anything
        # reads them. Without this the theme list kept the last engine's rows.
        Update-WinToolFontSizeSelection
        Update-WinToolFontList
        Update-WinToolPromptStyleList
        Update-WinToolTerminalSummary
        Update-WinToolPromptSelection
        Update-WinToolSchemeSelection
        Update-WinToolTerminalPreview
        Show-WinToolTerminalSelection
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontNerdOnly") -EventName "Click" -Name "Terminal: Nerd Fonts only" -Action { Update-WinToolFontList }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalThemeSearch") -EventName "TextChanged" -Name "Terminal: theme search" -Action {
        Sync-WinToolSearchHint -BoxName "TerminalThemeSearch" -HintName "TerminalThemeSearchHint"
        Update-WinToolPromptStyleList
        Update-WinToolTerminalSummary
        Update-WinToolTerminalPreview
    }
    foreach ($filterName in @("TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd")) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name $filterName) -EventName "Checked" -Name "Terminal: theme filter" -Action {
            param($source, $eventData)
            $null = $eventData
            $script:WinToolTerminalFilter = [string]$source.Tag
            Update-WinToolPromptStyleList
            Update-WinToolTerminalSummary
            Update-WinToolTerminalPreview
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalRefresh") -EventName "Click" -Name "Terminal: refresh lists" -Action { Update-WinToolTerminalCatalogOnline }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalSetup") -EventName "Click" -Name "Terminal: apply setup" -Action { Invoke-WinToolTerminalClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontList") -EventName "SelectionChanged" -Name "Terminal: choose font" -Action {
        Update-WinToolFontSample
        Update-WinToolTerminalSummary
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontSize") -EventName "SelectionChanged" -Name "Terminal: choose font size" -Action {
        $sizeBox = Get-WinToolUi -Name "TerminalFontSize"
        if ($null -ne $sizeBox.SelectedItem -and -not $script:WinToolTerminalSyncing) {
            Set-WinToolTerminalChoiceValue -Name "fontSize" -Value ([int]$sizeBox.SelectedItem.Tag)
            Update-WinToolTerminalSummary
            Update-WinToolTerminalPreview
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalStyleList") -EventName "SelectionChanged" -Name "Terminal: choose prompt style" -Action {
        # While the list is rebuilt for another engine, its selection changes
        # are not clicks: they must not copy other controls into the choice.
        if ($script:WinToolTerminalSyncing) { return }
        Update-WinToolTerminalSummary
        Update-WinToolTerminalPreview
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalPromptList") -EventName "SelectionChanged" -Name "Terminal: choose prompt" -Action {
        $list = Get-WinToolUi -Name "TerminalPromptList"
        if ($script:WinToolTerminalSyncing -or $null -eq $list.SelectedItem) { return }
        $promptId = [string]$list.SelectedItem.Tag
        if ([string]::IsNullOrWhiteSpace($promptId) -or $promptId -eq [string]$script:WinToolTerminalChoice.prompt) { return }
        Select-WinToolTerminalPrompt -PromptId $promptId
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalBodyScroll") -EventName "SizeChanged" -Name "Terminal: layout" -Action {
        $bodyScroll = Get-WinToolUi -Name "TerminalBodyScroll"
        Update-WinToolTerminalLayout -Width $bodyScroll.ActualWidth -Height $bodyScroll.ActualHeight
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalSummaryScroll") -EventName "PreviewMouseWheel" -Name "Terminal: scroll the summary" -Action {
        param($source, $eventData)
        # One line of chips; the wheel moves it sideways when it is longer than the bar.
        if ($null -ne $eventData -and $source.ScrollableWidth -gt 0) {
            $source.ScrollToHorizontalOffset($source.HorizontalOffset - [double]$eventData.Delta / 2.0)
            $eventData.Handled = $true
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "NavTerminal") -EventName "Checked" -Name "Terminal: show the selection" -Action {
        $script:WinToolTerminalScrollPending = $true
    }
    Build-WinToolSimpleTerminalCard
    Build-WinToolPromptCard
    Build-WinToolExtraToggle
    Build-WinToolSchemeCard
    Build-WinToolFontSizeList
    Update-WinToolFontList
    Update-WinToolPromptStyleList
    Update-WinToolTerminalSummary
    Update-WinToolTerminalPreview
}

function Set-WinToolTerminalModeView {
    $advanced = ($script:WinToolTerminalMode -eq "advanced")
    $body = Get-WinToolUi -Name "TerminalBodyScroll"
    $simple = Get-WinToolUi -Name "TerminalSimpleScroll"
    $subtitle = Get-WinToolUi -Name "TerminalSubtitle"
    if ($advanced) {
        $simple.Visibility = "Collapsed"
        $body.Visibility = "Visible"
        $subtitle.Text = "Pick a prompt, a theme, a font and a color scheme. The preview updates as you click."
    }
    else {
        $body.Visibility = "Collapsed"
        $simple.Visibility = "Visible"
        $subtitle.Text = "A recommended setup in one click. Switch to Advanced to choose each part."
    }
}

function Select-WinToolTerminalPrompt {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId
    )
    Set-WinToolTerminalChoiceValue -Name "prompt" -Value $PromptId
    # A new engine starts on All, so a filter never leaves its list empty.
    $script:WinToolTerminalFilter = "all"
    $allChip = Get-WinToolUi -Name "TerminalFilterAll"
    if ($null -ne $allChip -and $allChip.IsChecked -ne $true) { $allChip.IsChecked = $true }
    Update-WinToolPromptStyleList
    Update-WinToolTerminalSummary
    Update-WinToolPromptSelection
    Update-WinToolTerminalPreview
    Show-WinToolTerminalSelection
}

function New-WinToolTerminalLabel {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$Brush = "BrushInk",
        [string]$Weight = "Normal"
    )
    # Every label uses the shared FontSizeBody (14 px) text size.
    $block = New-WinToolText -Text $Text -Brush $Brush -Weight $Weight
    $block.TextTrimming = "CharacterEllipsis"
    return $block
}

function Build-WinToolPromptCard {
    # The engines as one list, grouped by the shell they run in.
    $list = Get-WinToolUi -Name "TerminalPromptList"
    $rowStyle = $list.FindResource("TerminalRow")
    $script:WinToolPromptCheck = @{}
    $script:WinToolTerminalSyncing = $true
    try {
        $list.Items.Clear()
        $prompts = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())
        $ompCount = @(Get-WinToolActiveOhMyPoshTheme).Count
        $infos = @($prompts | ForEach-Object { Get-WinToolPromptEngineInfo -Prompt $_ -OhMyPoshCount $ompCount })
        foreach ($group in @("PowerShell", "WSL Ubuntu")) {
            $header = New-Object System.Windows.Controls.ListBoxItem
            $header.Style = $rowStyle
            $header.IsEnabled = $false
            $header.Focusable = $false
            $header.Padding = [System.Windows.Thickness]::new(8, 6, 8, 2)
            $header.Content = New-WinToolTerminalLabel -Text $group.ToUpperInvariant() -Brush "BrushHint" -Weight "SemiBold"
            [void]$list.Items.Add($header)
            for ($index = 0; $index -lt $prompts.Count; $index++) {
                $prompt = $prompts[$index]
                $info = $infos[$index]
                if ($info.Group -ne $group) { continue }
                [void]$list.Items.Add((New-WinToolPromptRow -Prompt $prompt -Info $info -Style $rowStyle))
            }
        }
        (Get-WinToolUi -Name "TerminalPromptCount").Text = ([string]$prompts.Count + " engines")
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
    Update-WinToolPromptSelection
}

function New-WinToolPromptRow {
    param($Prompt, $Info, $Style)
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Style = $Style
    $item.Tag = [string]$Prompt.id
    $item.BorderThickness = [System.Windows.Thickness]::new(1)
    $item.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $item.ToolTip = ([string]$Prompt.name + " (" + [string]$Info.Sub + ")`n" + [string]$Prompt.summary)
    [System.Windows.Automation.AutomationProperties]::SetName($item, [string]$Prompt.name)
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @(34, -1, 22)) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -lt 0) { $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = [System.Windows.GridLength]::new($width) }
        $grid.ColumnDefinitions.Add($column)
    }
    $icon = New-Object System.Windows.Controls.Border
    $icon.Width = 24
    $icon.Height = 24
    $icon.CornerRadius = [System.Windows.CornerRadius]::new(6)
    $icon.HorizontalAlignment = "Left"
    $fill = ConvertTo-WinToolPreviewBrush -Color ([string]$Info.Color)
    if ($null -ne $fill) { $icon.Background = $fill }
    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.Text = [string][char]0xE756
    $glyph.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $glyph.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
    $glyph.Foreground = [System.Windows.Media.Brushes]::White
    $glyph.HorizontalAlignment = "Center"
    $glyph.VerticalAlignment = "Center"
    $icon.Child = $glyph
    [void]$grid.Children.Add($icon)
    $names = New-Object System.Windows.Controls.StackPanel
    $names.VerticalAlignment = "Center"
    [void]$names.Children.Add((New-WinToolTerminalLabel -Text ([string]$Prompt.name)))
    [System.Windows.Controls.Grid]::SetColumn($names, 1)
    [void]$grid.Children.Add($names)
    $check = New-WinToolTerminalLabel -Text ([string][char]0xE73E) -Brush "BrushAccent"
    $check.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $check.VerticalAlignment = "Center"
    $check.HorizontalAlignment = "Right"
    $check.Visibility = "Collapsed"
    [System.Windows.Controls.Grid]::SetColumn($check, 2)
    [void]$grid.Children.Add($check)
    $script:WinToolPromptCheck[[string]$Prompt.id] = $check
    $item.Content = $grid
    return $item
}

function Update-WinToolPromptSelection {
    $selected = [string]$script:WinToolTerminalChoice.prompt
    $list = Get-WinToolUi -Name "TerminalPromptList"
    $script:WinToolTerminalSyncing = $true
    try {
        for ($index = 0; $index -lt $list.Items.Count; $index++) {
            $item = $list.Items[$index]
            if ([string]$item.Tag -eq $selected -and -not [string]::IsNullOrWhiteSpace($selected)) {
                if (-not [object]::ReferenceEquals($list.SelectedItem, $item)) { $list.SelectedItem = $item }
            }
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
    # Card 2 always shows the list of the checked engine.
    $styleList = Get-WinToolUi -Name "TerminalStyleList"
    if ($null -ne $styleList -and [string]$styleList.Tag -ne $selected -and -not [string]::IsNullOrWhiteSpace($selected)) {
        Update-WinToolPromptStyleList
    }
    if ($null -ne $script:WinToolPromptCheck) {
        foreach ($key in $script:WinToolPromptCheck.Keys) {
            if ($key -eq $selected) { $script:WinToolPromptCheck[$key].Visibility = "Visible" }
            else { $script:WinToolPromptCheck[$key].Visibility = "Collapsed" }
        }
    }
    # The short note under the list: what the engine is and what it installs.
    $prompt = $null
    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())) {
        if ([string]$item.id -eq $selected) { $prompt = $item; break }
    }
    $nameBlock = Get-WinToolUi -Name "TerminalPromptName"
    $aboutBlock = Get-WinToolUi -Name "TerminalPromptAbout"
    if ($null -eq $nameBlock -or $null -eq $aboutBlock) { return }
    if ($null -eq $prompt) {
        $nameBlock.Text = ""
        $aboutBlock.Text = ""
        return
    }
    $info = Get-WinToolPromptEngineInfo -Prompt $prompt -OhMyPoshCount (@(Get-WinToolActiveOhMyPoshTheme).Count)
    $nameBlock.Text = [string]$prompt.name
    # What it installs is listed in the action bar, so the note stays short.
    $aboutBlock.Text = ([string]$info.Sub + ". " + [string]$prompt.summary).Trim()
    $aboutBlock.ToolTip = ($aboutBlock.Text + "`n`nInstalls: " + (@($prompt.installs) -join ", ") + "`n" + [string]$info.Runs).Trim()
}

function New-WinToolTerminalChip {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [string]$Background = "BrushNavHover",
        [string]$Foreground = "BrushInk"
    )
    # A 32 px pill, like the shared chips.
    $chip = New-Object System.Windows.Controls.Border
    $chip.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $chip.Height = 32
    $chip.Padding = [System.Windows.Thickness]::new(12, 0, 12, 0)
    $chip.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $chip.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $Background)
    $label = New-WinToolTerminalLabel -Text $Text -Brush $Foreground
    $label.TextTrimming = "None"
    $label.VerticalAlignment = "Center"
    $chip.Child = $label
    return $chip
}

function Update-WinToolPromptStyleList {
    $script:WinToolTerminalBodyKey = 0
    $list = Get-WinToolUi -Name "TerminalStyleList"
    $prompt = [string]$script:WinToolTerminalChoice.prompt
    # The list remembers which prompt it was built for, so an old selection
    # never overwrites the style of a newly picked prompt.
    $wasSyncing = [bool]$script:WinToolTerminalSyncing
    $script:WinToolTerminalSyncing = $true
    try {
        $list.Tag = $null
        $list.Items.Clear()
        $query = [string](Get-WinToolUi -Name "TerminalThemeSearch").Text
        $note = Get-WinToolUi -Name "TerminalStyleNote"
        $filter = [string]$script:WinToolTerminalFilter
        if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "all" }
        $titles = Get-WinToolThemeTitle -PromptId $prompt
        (Get-WinToolUi -Name "TerminalThemeTitle").Text = [string]$titles.Title
        (Get-WinToolUi -Name "TerminalThemeSearchHint").Text = ([string]$titles.Hint + [string][char]0x2026)
        $rows = @(Get-WinToolThemeRow -PromptId $prompt -OhMyPoshTheme @(Get-WinToolActiveOhMyPoshTheme))
        $script:WinToolTerminalRows = $rows
        $shown = @(Select-WinToolThemeRow -Row $rows -Query $query -Filter $filter)
        $rowStyle = $list.FindResource("TerminalRow")
        foreach ($row in $shown) {
            $item = New-WinToolThemeItem -Row $row -Style $rowStyle
            [void]$list.Items.Add($item)
            if ([string]$row.Id -eq [string]$script:WinToolTerminalChoice.promptStyle) {
                $list.SelectedItem = $item
            }
        }
        (Get-WinToolUi -Name "TerminalThemeCount").Text = ([string]$shown.Count + " of " + [string]$rows.Count)
        if ($null -eq $list.SelectedItem -and $list.Items.Count -gt 0) {
            $list.SelectedIndex = 0
        }
        if ($list.Items.Count -eq 0) {
            $note.Visibility = "Visible"
            if ($rows.Count -eq 0) { $note.Text = "This prompt has its own default look. The font and extras still apply." }
            else { $note.Text = "No " + [string]$titles.Noun + " match the search or filter." }
        }
        else {
            $note.Visibility = "Collapsed"
        }
        $list.Tag = $prompt
        if ($null -ne $list.SelectedItem) {
            $script:WinToolTerminalChoice.promptStyle = [string]$list.SelectedItem.Tag
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $wasSyncing
    }
    Show-WinToolTerminalSelection
}

function New-WinToolThemeItem {
    param($Row, $Style)
    # Name, a "Nerd Font" tag when the theme needs one, the id, and a sample
    # prompt line in the theme colors.
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Style = $Style
    $item.Tag = [string]$Row.Id
    $item.BorderThickness = [System.Windows.Thickness]::new(3, 0, 0, 0)
    $item.Padding = [System.Windows.Thickness]::new(8, 6, 8, 7)
    $item.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $tip = [string]$Row.Id
    if (-not [string]::IsNullOrWhiteSpace([string]$Row.Description)) { $tip = [string]$Row.Description + "`n" + $tip }
    $item.ToolTip = $tip
    [System.Windows.Automation.AutomationProperties]::SetName($item, [string]$Row.Name)
    $stack = New-Object System.Windows.Controls.StackPanel
    $top = New-Object System.Windows.Controls.DockPanel
    if ($Row.NerdFont -eq $true) {
        $tag = New-WinToolTerminalLabel -Text "Nerd Font" -Brush "BrushWarn"
        $tag.TextTrimming = "None"
        $tag.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $tag.VerticalAlignment = "Center"
        [System.Windows.Controls.DockPanel]::SetDock($tag, "Right")
        [void]$top.Children.Add($tag)
    }
    $nameLabel = New-WinToolTerminalLabel -Text ([string]$Row.Name)
    $nameLabel.TextTrimming = "None"
    $nameLabel.TextWrapping = "Wrap"
    [void]$top.Children.Add($nameLabel)
    [void]$stack.Children.Add($top)
    $segments = @($Row.Preview)
    if ($segments.Count -gt 0) {
        $sample = New-Object System.Windows.Controls.Border
        $sample.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $sample.Padding = [System.Windows.Thickness]::new(6, 3, 6, 3)
        $sample.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
        $sample.ClipToBounds = $true
        $sample.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushLog")
        $line = New-Object System.Windows.Controls.TextBlock
        # A sample prompt in the theme colors; it may run past the edge like a real terminal line.
        $line.Tag = "preview-content"
        $line.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
        $line.TextWrapping = "NoWrap"
        $line.SetResourceReference([System.Windows.Controls.TextBlock]::FontFamilyProperty, "TerminalPreviewFont")
        Set-WinToolLigatureTypography -Element $line
        $line.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushLogText")
        foreach ($segment in $segments) {
            [void]$line.Inlines.Add((New-WinToolPreviewRun -Segment $segment))
        }
        $sample.Child = $line
        [void]$stack.Children.Add($sample)
    }
    $item.Content = $stack
    return $item
}

function Set-WinToolLigatureTypography {
    param($Element)
    # Windows Terminal setup always turns ligatures on, so previews draw them too.
    if ($null -eq $Element) { return }
    [System.Windows.Documents.Typography]::SetStandardLigatures($Element, $true)
    [System.Windows.Documents.Typography]::SetContextualAlternates($Element, $true)
}

function New-WinToolPreviewRun {
    param($Segment)
    $run = New-Object System.Windows.Documents.Run -ArgumentList ([string]$Segment.Text)
    $brush = ConvertTo-WinToolPreviewBrush -Color ([string]$Segment.Foreground)
    if ($null -ne $brush) { $run.Foreground = $brush }
    $fill = ConvertTo-WinToolPreviewBrush -Color ([string]$Segment.Background)
    if ($null -ne $fill) { $run.Background = $fill }
    return $run
}

function Build-WinToolExtraToggle {
    # Each extra as the shared rounded checkbox with its name and a
    # description that wraps, in two columns.
    $hostPanel = Get-WinToolUi -Name "TerminalExtrasHost"
    $hostPanel.Children.Clear()
    $script:WinToolTerminalExtraBox = @()
    $extras = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "extras" -Default @())
    for ($index = 0; $index -lt $extras.Count; $index++) {
        $extra = $extras[$index]
        $cell = New-Object System.Windows.Controls.Border
        $cell.Margin = [System.Windows.Thickness]::new(0, 0, 16, 0)
        $cell.Padding = [System.Windows.Thickness]::new(0, 8, 0, 8)
        $cell.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
        if ($index -ge 2) { $cell.BorderThickness = [System.Windows.Thickness]::new(0, 1, 0, 0) }
        $grid = New-Object System.Windows.Controls.Grid
        $auto = New-Object System.Windows.Controls.ColumnDefinition
        $auto.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($auto)
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Tag = [string]$extra.id
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $box.VerticalAlignment = "Top"
        [System.Windows.Automation.AutomationProperties]::SetName($box, [string]$extra.name)
        [void]$grid.Children.Add($box)
        $text = New-Object System.Windows.Controls.StackPanel
        $name = New-WinToolTerminalLabel -Text ([string]$extra.name) -Weight "SemiBold"
        $name.TextTrimming = "None"
        $name.TextWrapping = "Wrap"
        [void]$text.Children.Add($name)
        $about = New-WinToolTerminalLabel -Text ([string]$extra.description) -Brush "BrushMuted"
        $about.TextTrimming = "None"
        $about.TextWrapping = "Wrap"
        [void]$text.Children.Add($about)
        [System.Windows.Controls.Grid]::SetColumn($text, 1)
        [void]$grid.Children.Add($text)
        Register-WinToolUiEvent -Control $box -EventName "Click" -Name "Terminal: extras" -Action {
            Update-WinToolTerminalSummary
            Update-WinToolTerminalPreview
        }
        $cell.Child = $grid
        [void]$hostPanel.Children.Add($cell)
        $script:WinToolTerminalExtraBox += $box
    }
    Update-WinToolExtraToggle
}

function Get-WinToolExtraChoiceName {
    param([string]$ExtraId)
    if ($ExtraId -eq "terminal-icons") { return "terminalIcons" }
    if ($ExtraId -eq "psreadline") { return "psReadLine" }
    return $ExtraId
}

function Update-WinToolExtraToggle {
    # The switches follow the current choice (Simple turns on the recommended ones).
    $boxes = $script:WinToolTerminalExtraBox
    if ($null -eq $boxes) { return }
    for ($index = 0; $index -lt $boxes.Count; $index++) {
        $toggle = $boxes[$index]
        if ($null -eq $toggle) { continue }
        $choiceName = Get-WinToolExtraChoiceName -ExtraId ([string]$toggle.Tag)
        $choiceValue = Get-WinToolNote -Object $script:WinToolTerminalChoice -Name $choiceName
        $toggle.IsChecked = [bool]($null -ne $choiceValue -and [bool]$choiceValue)
    }
}

function Build-WinToolSchemeCard {
    $hostPanel = Get-WinToolUi -Name "TerminalSchemeHost"
    $hostPanel.Children.Clear()
    foreach ($scheme in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
        $card = New-WinToolTerminalTile
        # Each tile is drawn in its own colors: the scheme background with
        # the name in its text color, so no extra swatch or hex line is needed.
        $card.Padding = [System.Windows.Thickness]::new(4, 0, 4, 0)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $card.Height = 36
        $card.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $card.Tag = [string]$scheme.id
        $card.ToolTip = [string]$scheme.name + " " + [string]$scheme.background
        [System.Windows.Automation.AutomationProperties]::SetName($card, [string]$scheme.name)
        $tileFill = ConvertTo-WinToolPreviewBrush -Color ([string]$scheme.background)
        if ($null -ne $tileFill) { $card.Background = $tileFill }
        $palette = Get-WinToolNote -Object $scheme -Name "palette"
        $mark = New-Object System.Windows.Controls.TextBlock
        $mark.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
        $mark.VerticalAlignment = "Center"
        $mark.HorizontalAlignment = "Center"
        $mark.Inlines.Add((New-WinToolPreviewRun -Segment ([pscustomobject]@{ Text = ([string][char]0x276F + " "); Foreground = [string](Get-WinToolNote -Object $palette -Name "green" -Default ([string]$scheme.cursor)); Background = $null })))
        $mark.Inlines.Add((New-WinToolPreviewRun -Segment ([pscustomobject]@{ Text = [string]$scheme.name; Foreground = [string]$scheme.foreground; Background = $null })))
        $grid = $mark
        $card.Child = $grid
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

function Build-WinToolFontSizeList {
    $box = Get-WinToolUi -Name "TerminalFontSize"
    $script:WinToolTerminalSyncing = $true
    try {
        $box.Items.Clear()
        foreach ($size in @(9, 10, 11, 12, 13, 14, 15, 16, 18, 20)) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = ([string]$size + " pt")
            $item.Tag = $size
            [void]$box.Items.Add($item)
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
    Update-WinToolFontSizeSelection
}

function Update-WinToolFontSizeSelection {
    $box = Get-WinToolUi -Name "TerminalFontSize"
    if ($null -eq $box) { return }
    $wanted = 12
    $value = Get-WinToolNote -Object $script:WinToolTerminalChoice -Name "fontSize"
    if ($null -ne $value) { $wanted = [int]$value }
    $script:WinToolTerminalSyncing = $true
    try {
        for ($index = 0; $index -lt $box.Items.Count; $index++) {
            $item = $box.Items[$index]
            if ([int]$item.Tag -eq $wanted) { $box.SelectedItem = $item }
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
}

function Update-WinToolTerminalLayout {
    param(
        [double]$Width,
        [double]$Height = -1
    )
    # Wide: prompt engines | themes | preview, with font and extras inside the
    # preview column. Below 760 px of content (a window under about 1050 px)
    # that whole column moves under the lists.
    # When the body is shorter than the cards need at 14 px text, it gets a
    # fixed height and scrolls instead of squeezing or clipping the cards.
    $grid = Get-WinToolUi -Name "TerminalAdvancedHost"
    $scroll = Get-WinToolUi -Name "TerminalBodyScroll"
    if ($null -eq $grid -or $null -eq $scroll) {
        return
    }
    if ($Width -le 0) { $Width = $scroll.ActualWidth }
    if ($Height -lt 0) { $Height = $scroll.ActualHeight }
    if ([double]::IsNaN($Height) -or [double]::IsInfinity($Height) -or $Height -lt 0) { $Height = 0 }
    if ($Width -le 0 -or [double]::IsNaN($Width) -or [double]::IsInfinity($Width)) { return }
    $narrow = ($Width -lt 760)
    $side = Get-WinToolUi -Name "TerminalSideColumn"
    $prompt = Get-WinToolUi -Name "TerminalCardPrompt"
    $right = Get-WinToolUi -Name "TerminalColumnRight"
    $gap = Get-WinToolUi -Name "TerminalColumnGap"
    $mainRow = Get-WinToolUi -Name "TerminalRowMain"
    $previewRow = Get-WinToolUi -Name "TerminalRowPreview"
    if ($narrow -ne [bool]$script:WinToolTerminalNarrow -or $null -eq $script:WinToolTerminalNarrow) {
        $script:WinToolTerminalNarrow = $narrow
        if ($narrow) {
            [System.Windows.Controls.Grid]::SetRow($side, 1)
            [System.Windows.Controls.Grid]::SetColumn($side, 0)
            [System.Windows.Controls.Grid]::SetColumnSpan($side, 5)
            $side.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
            [System.Windows.Controls.Grid]::SetRowSpan($prompt, 1)
            $right.Width = [System.Windows.GridLength]::new(0)
            $gap.Width = [System.Windows.GridLength]::new(0)
            $mainRow.Height = [System.Windows.GridLength]::new(520)
            $previewRow.Height = [System.Windows.GridLength]::new(160)
        }
        else {
            # Prompt, theme, and preview (with font and extras inside) share one row.
            [System.Windows.Controls.Grid]::SetRow($side, 0)
            [System.Windows.Controls.Grid]::SetColumn($side, 4)
            [System.Windows.Controls.Grid]::SetColumnSpan($side, 1)
            $side.Margin = [System.Windows.Thickness]::new(0)
            [System.Windows.Controls.Grid]::SetRowSpan($prompt, 1)
            $right.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $gap.Width = [System.Windows.GridLength]::new(12)
            $mainRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $previewRow.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        }
    }
    if ($narrow) {
        # The lists get a row tall enough for every engine; the body scrolls.
        $promptCard = Get-WinToolUi -Name "TerminalCardPrompt"
        $promptCard.Measure([System.Windows.Size]::new(230.0, [double]::PositiveInfinity))
        $mainRow.Height = [System.Windows.GridLength]::new([Math]::Max(520.0, [Math]::Ceiling($promptCard.DesiredSize.Height)))
        $grid.Height = [double]::NaN
        return
    }
    # Wide: fill the body, but never go below what the cards need.
    $need = Get-WinToolTerminalBodyMinHeight -Width $Width
    if ($Height -gt 0 -and $Height -ge $need) {
        $grid.Height = $Height
    }
    else {
        $grid.Height = $need
    }
}

function Get-WinToolTerminalBodyMinHeight {
    param([double]$Width)
    # The tallest of the three aligned cards. Extras live inside the preview column.
    # Measuring the theme list with infinite height builds every row, so a width
    # that was already measured keeps that height.
    $widthKey = 0
    if (-not [double]::IsNaN($Width) -and -not [double]::IsInfinity($Width) -and $Width -gt 0) {
        $widthKey = [int][Math]::Round($Width)
    }
    if ($widthKey -gt 0 -and $widthKey -eq [int]$script:WinToolTerminalBodyKey -and [double]$script:WinToolTerminalBodyNeed -gt 0) {
        return [double]$script:WinToolTerminalBodyNeed
    }
    $prompt = Get-WinToolUi -Name "TerminalCardPrompt"
    $side = Get-WinToolUi -Name "TerminalSideColumn"
    $infinite = [double]::PositiveInfinity
    $promptWidth = 230.0
    $restWidth = [Math]::Max(200.0, ($Width - $promptWidth - 24.0) / 2.0)
    $prompt.Measure([System.Windows.Size]::new($promptWidth, $infinite))
    $side.Measure([System.Windows.Size]::new($restWidth, $infinite))
    $promptNeed = $prompt.DesiredSize.Height
    $themeNeed = 260.0
    $restNeed = [Math]::Max($side.DesiredSize.Height, $themeNeed)
    $need = [Math]::Ceiling([Math]::Max([Math]::Max($promptNeed, $restNeed), 420.0))
    $script:WinToolTerminalBodyKey = $widthKey
    $script:WinToolTerminalBodyNeed = $need
    return $need
}

function Update-WinToolFontList {
    $list = Get-WinToolUi -Name "TerminalFontList"
    $nerdOnly = ((Get-WinToolUi -Name "TerminalFontNerdOnly").IsChecked -eq $true)
    $allFonts = @(Get-WinToolActiveFont)
    $fonts = @(Select-WinToolFont -Font $allFonts -Query "" -NerdOnly $nerdOnly)
    $script:WinToolTerminalSyncing = $true
    try {
        $list.Items.Clear()
        foreach ($font in $fonts) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
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
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
    if ($null -eq $list.SelectedItem -and $list.Items.Count -gt 0) {
        $list.SelectedIndex = 0
    }
    $nerdCount = @($allFonts | Where-Object { $_.nerd }).Count
    $schemeCount = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @()).Count
    $dot = " " + [string][char]0x00B7 + " "
    $countBlock = Get-WinToolUi -Name "TerminalFontCount"
    if ($null -ne $countBlock) {
        $countBlock.Text = ([string]$allFonts.Count + " fonts" + $dot + $nerdCount + " Nerd Fonts" + $dot + $schemeCount + " schemes")
    }
    Update-WinToolFontSizeSelection
    Update-WinToolFontSample
}

function Show-WinToolTerminalSelection {
    # Brings the chosen engine and theme into view in their lists. When a list
    # is not laid out yet, the log pump calls this again a moment later.
    $script:WinToolTerminalScrollPending = $false
    foreach ($name in @("TerminalPromptList", "TerminalStyleList")) {
        $list = Get-WinToolUi -Name $name
        if ($null -eq $list -or $null -eq $list.SelectedItem) { continue }
        try {
            $list.UpdateLayout()
            $list.ScrollIntoView($list.SelectedItem)
            # ScrollIntoView needs a later layout pass; moving the list's own
            # scroll viewer (item based) works right away.
            $viewer = Find-WinToolChildScrollViewer -Element $list
            if ($null -ne $viewer -and $list.SelectedIndex -ge 0 -and $viewer.ViewportHeight -gt 0) {
                $target = [Math]::Max(0, $list.SelectedIndex - 1)
                if ($list.SelectedIndex -lt $viewer.VerticalOffset -or $list.SelectedIndex -ge ($viewer.VerticalOffset + $viewer.ViewportHeight)) {
                    $viewer.ScrollToVerticalOffset($target)
                    $list.UpdateLayout()
                }
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

function Get-WinToolTerminalScheme {
    $fallback = [pscustomobject]@{ id = ""; name = "Default"; background = "#0F131C"; foreground = "#D5DEEE"; cursor = "#6C9BFF"; palette = $null }
    if ($null -eq $script:WinToolTerminalChoice) { return $fallback }
    foreach ($scheme in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
        if ([string]$scheme.id -eq [string]$script:WinToolTerminalChoice.schemeId) { return $scheme }
    }
    return $fallback
}

function Update-WinToolTerminalPreview {
    # Draws a short terminal session with the chosen prompt and theme, in the
    # chosen font and size, on the chosen color scheme. Never throws: a
    # failure keeps the last preview.
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

        $scheme = Get-WinToolTerminalScheme
        $palette = Get-WinToolNote -Object $scheme -Name "palette"
        $background = ConvertTo-WinToolPreviewBrush -Color ([string]$scheme.background)
        $foreground = ConvertTo-WinToolPreviewBrush -Color ([string]$scheme.foreground)
        if ($null -ne $background) {
            $border.Background = $background
            $tab = Get-WinToolUi -Name "TerminalPreviewTab"
            if ($null -ne $tab) { $tab.Background = $background }
        }
        if ($null -ne $foreground) { $sample.Foreground = $foreground }

        $face = ""
        $fontName = ""
        foreach ($font in @(Get-WinToolActiveFont)) {
            if ([string]$font.id -eq [string]$choice.fontId) { $face = [string]$font.face; $fontName = [string]$font.name; break }
        }
        $families = "Cascadia Mono, Consolas"
        if (-not [string]::IsNullOrWhiteSpace($face)) { $families = $face + ", " + $families }
        $family = [System.Windows.Media.FontFamily]::new($families)
        $sample.FontFamily = $family
        Set-WinToolLigatureTypography -Element $sample
        $styleList = Get-WinToolUi -Name "TerminalStyleList"
        if ($null -ne $styleList) { $styleList.Resources["TerminalPreviewFont"] = $family }
        $size = 12
        $sizeValue = Get-WinToolNote -Object $choice -Name "fontSize"
        if ($null -ne $sizeValue -and [int]$sizeValue -gt 0) { $size = [int]$sizeValue }
        $sample.FontSize = [Math]::Round($size * 1.1, 1)
        $sample.LineHeight = [Math]::Round($sample.FontSize * 1.5)

        $info = $null
        $promptName = $promptId
        foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())) {
            if ([string]$item.id -eq $promptId) { $info = Get-WinToolPromptEngineInfo -Prompt $item -OhMyPoshCount 0; $promptName = [string]$item.name; break }
        }
        $wsl = ($null -ne $info -and $info.Wsl)
        $tabText = Get-WinToolUi -Name "TerminalPreviewTabText"
        if ($null -ne $tabText) {
            if ($wsl) { $tabText.Text = "Ubuntu" } else { $tabText.Text = "PowerShell" }
        }

        $red = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "red" -Default "#F07178")) -Palette $null
        $yellow = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "yellow" -Default "#EED49F")) -Palette $null
        $blue = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "blue" -Default "#6C9BFF")) -Palette $null
        $dim = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "brightBlack" -Default "#5B6680")) -Palette $null

        $sample.Inlines.Clear()
        $addLine = {
            param([object[]]$Parts)
            if ($sample.Inlines.Count -gt 0) { $sample.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
            foreach ($part in @($Parts)) { $sample.Inlines.Add((New-WinToolPreviewRun -Segment $part)) }
        }
        $text = { param([string]$Value, [string]$Color) New-WinToolPreviewSegment -Text $Value -Foreground $Color }
        $header = "PowerShell 7"
        if ($wsl) {
            $header = "Ubuntu on WSL " + [string][char]0x00B7 + " zsh"
            if ($promptId -eq "tide") { $header = "Ubuntu on WSL " + [string][char]0x00B7 + " fish" }
        }
        & $addLine @((& $text $header $dim))
        & $addLine @((& $text " " ""))
        & $addLine (@($segments) + @((& $text " git status" "")))
        & $addLine @((& $text "On branch main" ""))
        & $addLine @((& $text "Changes not staged for commit:" ""))
        & $addLine @((& $text "        modified:   src/app.ts" $red))
        & $addLine @((& $text " " ""))
        & $addLine (@($segments) + @((& $text " head -1 src/app.ts" "")))
        & $addLine @((& $text "const same = (a, b) => a === b || a >= b;" ""))
        & $addLine @((& $text " " ""))
        $jump = " cd wintool"
        if ([bool]$choice.zoxide) { $jump = " z wintool" }
        & $addLine (@($segments) + @((& $text $jump "")))
        & $addLine (@($segments) + @((& $text " ls" "")))
        $folder = ""
        $file = ""
        if ([bool]$choice.terminalIcons -and -not $wsl) {
            $folder = [string][char]0xF07B + " "
            $file = [string][char]0xF489 + " "
        }
        $listing = ""
        foreach ($name in @("assets", "build", "data", "src")) { $listing += $folder + $name + "   " }
        & $addLine @((& $text $listing $blue), (& $text ($file + "wintool.ps1") $yellow))
        $last = @($segments) + @((& $text " git s" ""), (New-WinToolPreviewSegment -Text " " -Background ([string]$scheme.cursor)))
        if ([bool]$choice.psReadLine -and -not $wsl) { $last += (& $text "tatus" $dim) }
        & $addLine $last

        $themeName = $style
        foreach ($row in @($script:WinToolTerminalRows)) {
            if ($null -ne $row -and [string]$row.Id -eq $style) { $themeName = [string]$row.Name; break }
        }
        $dot = " " + [string][char]0x00B7 + " "
        $infoBlock = Get-WinToolUi -Name "TerminalPreviewInfo"
        if ($null -ne $infoBlock) {
            $parts = @($promptName, $themeName, ($fontName + " " + $size), [string]$scheme.name) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $infoBlock.Text = ($parts -join $dot)
            $infoBlock.ToolTip = $infoBlock.Text
        }
        $tip = "Font: " + $face
        if ($waiting) { $tip += "`nLoading the theme colors from GitHub..." }
        elseif ($promptId -eq "oh-my-posh" -and $null -eq $theme) { $tip += "`nTheme colors come from the WinTool catalog sample." }
        $border.ToolTip = $tip
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Read-WinToolExtraSelection {
    $flags = @{ "terminal-icons" = $false; psreadline = $false; zoxide = $false; fzf = $false }
    $boxes = $script:WinToolTerminalExtraBox
    if ($null -eq $boxes) { return $flags }
    for ($index = 0; $index -lt $boxes.Count; $index++) {
        $toggle = $boxes[$index]
        if ($null -eq $toggle) { continue }
        $flags[[string]$toggle.Tag] = ($toggle.IsChecked -eq $true)
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
        if ($null -ne $script:WinToolTerminalExtraBox -and $script:WinToolTerminalExtraBox.Count -gt 0) {
            $flags = Read-WinToolExtraSelection
            $script:WinToolTerminalChoice.terminalIcons = [bool]$flags["terminal-icons"]
            $script:WinToolTerminalChoice.psReadLine = [bool]$flags["psreadline"]
            $script:WinToolTerminalChoice.zoxide = [bool]$flags["zoxide"]
            $script:WinToolTerminalChoice.fzf = [bool]$flags["fzf"]
        }
    }
    $steps = @(Get-WinToolTerminalPlan -Selection $script:WinToolTerminalChoice)
    $lines = @($steps | ForEach-Object { [string]$_.Label })
    (Get-WinToolUi -Name "TerminalSummary").Text = ($lines -join "`n")
    $extrasCount = Get-WinToolUi -Name "TerminalExtrasCount"
    if ($null -ne $extrasCount) {
        $flags = Read-WinToolExtraSelection
        $on = 0
        foreach ($flagKey in $flags.Keys) { if ($flags[$flagKey]) { $on++ } }
        $extrasCount.Text = ([string]$on + " of " + [string]$flags.Count + " on")
    }
    $summaryHost = Get-WinToolUi -Name "TerminalSummaryHost"
    if ($null -eq $summaryHost) { return }
    # One wrapping row of chips: what gets installed (+), then what gets changed (~).
    $summaryHost.Children.Clear()
    $summaryHost.ToolTip = ($lines -join "`n")
    $chips = @(Get-WinToolSummaryChip -Step $steps)
    foreach ($kind in @("add", "change")) {
        foreach ($chip in @($chips | Where-Object { $_.Kind -eq $kind })) {
            if ($kind -eq "add") {
                $element = New-WinToolTerminalChip -Text ("+ " + [string]$chip.Text) -Background "BrushOkSoft" -Foreground "BrushOk"
            }
            else {
                $element = New-WinToolTerminalChip -Text ([string][char]0x007E + " " + [string]$chip.Text) -Background "BrushWarnSoft" -Foreground "BrushWarn"
            }
            $element.Tag = [string]$kind
            [void]$summaryHost.Children.Add($element)
        }
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
    $fontSize = 12
    $sizeValue = Get-WinToolNote -Object $choice -Name "fontSize"
    if ($null -ne $sizeValue) { $fontSize = [int]$sizeValue }
    return [pscustomobject]@{
        enabled = $enabled
        prompt = [string]$choice.prompt
        promptStyle = [string]$choice.promptStyle
        fontId = [string]$choice.fontId
        fontSize = $fontSize
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
    foreach ($name in @("prompt", "promptStyle", "fontId", "schemeId")) {
        $text = [string](Get-WinToolNote -Object $Selection -Name $name -Default "")
        if (-not [string]::IsNullOrWhiteSpace($text)) { $script:WinToolTerminalChoice.$name = $text }
    }
    $size = Get-WinToolNote -Object $Selection -Name "fontSize"
    if ($null -ne $size -and [int]$size -ge 6 -and [int]$size -le 48) { $script:WinToolTerminalChoice.fontSize = [int]$size }
    foreach ($name in @("terminalIcons", "psReadLine", "zoxide", "fzf")) {
        $flag = Get-WinToolNote -Object $Selection -Name $name
        if ($null -ne $flag) { $script:WinToolTerminalChoice.$name = [bool]$flag }
    }
    $enabledFlag = Get-WinToolNote -Object $Selection -Name "enabled"
    $enabledBox = Get-WinToolUi -Name "TerminalEnabled"
    if ($null -ne $enabledFlag -and $null -ne $enabledBox) {
        $enabledBox.IsChecked = [bool]$enabledFlag
    }
    (Get-WinToolUi -Name "TerminalModeAdvanced").IsChecked = $true
    Update-WinToolExtraToggle
    Update-WinToolFontSizeSelection
    Update-WinToolFontList
    Update-WinToolPromptStyleList
    Update-WinToolPromptSelection
    Update-WinToolSchemeSelection
    Update-WinToolTerminalSummary
    Update-WinToolTerminalPreview
}
