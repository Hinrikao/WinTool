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
    $extra = @($script:WinToolExtraOhMyPoshTheme).Count
    if ($null -ne $script:WinToolActiveOhMyPoshTheme -and [int]$script:WinToolActiveOhMyPoshCount -eq $extra) {
        return @($script:WinToolActiveOhMyPoshTheme)
    }
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
    $script:WinToolActiveOhMyPoshTheme = $rows.ToArray()
    $script:WinToolActiveOhMyPoshCount = $extra
    return @($script:WinToolActiveOhMyPoshTheme)
}

function New-WinToolSimpleIncludedRow {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $true)][string]$Badge,
        [string]$IconFile = "",
        [int]$Glyph = 0
    )
    $row = New-Object System.Windows.Controls.Grid
    $row.Height = 56
    $row.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $row.ColumnDefinitions.Add((New-WinToolColumn))
    $row.ColumnDefinitions.Add((New-WinToolColumn -Auto))
    $slot = New-Object System.Windows.Controls.Border
    $slot.Width = 32
    $slot.Height = 32
    $slot.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $slot.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
    $slot.VerticalAlignment = "Center"
    $image = $null
    if (-not [string]::IsNullOrWhiteSpace($IconFile)) {
        $image = New-WinToolAppIconImage -FileName $IconFile
    }
    if ($null -ne $image) {
        $plate = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($script:WinToolIconBackplate))
        $brush = [System.Windows.Media.SolidColorBrush]::new($plate)
        $brush.Freeze()
        $slot.Background = $brush
        $slot.Child = $image
    }
    else {
        $slot.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushAccentSoft")
        $mark = New-Object System.Windows.Controls.TextBlock
        if ($Glyph -ne 0) { $mark.Text = [string][char]$Glyph }
        $mark.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
        $mark.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
        $mark.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushAccent")
        $mark.HorizontalAlignment = "Center"
        $mark.VerticalAlignment = "Center"
        $slot.Child = $mark
    }
    [void]$row.Children.Add($slot)
    $text = New-Object System.Windows.Controls.StackPanel
    $text.VerticalAlignment = "Center"
    $titleBlock = New-WinToolText -Text $Title -Weight "SemiBold"
    $titleBlock.TextTrimming = "CharacterEllipsis"
    [void]$text.Children.Add($titleBlock)
    $detailBlock = New-WinToolText -Text $Detail -Brush "BrushMuted"
    $detailBlock.TextTrimming = "CharacterEllipsis"
    [void]$text.Children.Add($detailBlock)
    [System.Windows.Controls.Grid]::SetColumn($text, 1)
    [void]$row.Children.Add($text)
    # $Badge is the [string] parameter. PowerShell names are case-insensitive,
    # so the pill cannot be stored in $badge or the Border becomes that string.
    $pill = New-WinToolBadge -Text $Badge -Kind "ok"
    [System.Windows.Controls.Grid]::SetColumn($pill, 2)
    [void]$row.Children.Add($pill)
    return $row
}

function Build-WinToolSimpleTerminalCard {
    $list = Get-WinToolUi -Name "TerminalSimpleIncludedList"
    if ($null -eq $list) { return }
    $list.Children.Clear()
    $choice = Get-WinToolSimpleTerminalChoice
    $fontName = (Get-WinToolText "ui.t.nerd-font.Text")
    foreach ($font in @(Get-WinToolActiveFont)) {
        if ([string]$font.id -eq [string]$choice.fontId) { $fontName = [string]$font.name; break }
    }
    $themeName = [string]$choice.promptStyle
    foreach ($theme in @(Get-WinToolActiveOhMyPoshTheme)) {
        if ([string]$theme.id -eq [string]$choice.promptStyle) { $themeName = [string]$theme.name; break }
    }
    [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title (Get-WinToolText "msg.windows-terminal") -Detail (Get-WinToolText "msg.the-window-this-prompt-opens-in") -Badge "App" -IconFile "terminal.png" -Glyph 0xE756))
    [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title (Get-WinToolText "msg.powershell-7") -Detail (Get-WinToolText "msg.the-shell-wintool-configures") -Badge "Shell" -IconFile "powershell.png" -Glyph 0xE756))
    [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title "Oh My Posh" -Detail (Get-WinToolText "msg.n-theme" $themeName) -Badge (Get-WinToolText "ui.t.prompt.Text") -IconFile "posh.png" -Glyph 0xE756))
    [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title $fontName -Detail (Get-WinToolText "msg.icons-in-the-prompt-line") -Badge "Font" -Glyph 0xE8D2))
    if ([bool]$choice.terminalIcons) {
        [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title "Terminal-Icons" -Detail (Get-WinToolText "msg.folder-and-file-icons-in-listings") -Badge "Icons" -Glyph 0xE8B9))
    }
    if ([bool]$choice.psReadLine) {
        [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title "PSReadLine" -Detail (Get-WinToolText "msg.history-suggestions-as-you-type") -Badge "Suggestions" -Glyph 0xE81C))
    }
    if (Test-WinToolHideStartupBanner -Selection $choice) {
        [void]$list.Children.Add((New-WinToolSimpleIncludedRow -Title (Get-WinToolText "catalog.terminal.extra.hide-startup-banner.name") -Detail (Get-WinToolText "msg.no-copyright-or-profile-loading-line-when-a-terminal-ope") -Badge "Terminal" -Glyph 0xE7B3))
    }
    $lead = Get-WinToolUi -Name "TerminalSimpleLead"
    if ($null -ne $lead) {
        $lead.Text = (Get-WinToolText "msg.windows-terminal-powershell-7-oh-my-posh-a-nerd-font-fil")
    }
}

function Update-WinToolSimplePreview {
    # Paints the recommended prompt from memory. The Simple click does not call this.
    $sample = Get-WinToolUi -Name "TerminalSimpleSample"
    $screen = Get-WinToolUi -Name "TerminalSimpleScreen"
    if ($null -eq $sample -or $null -eq $screen) { return }
    try {
    $choice = Get-WinToolSimpleTerminalChoice
    $theme = $null
    if ([string]$choice.prompt -eq "oh-my-posh" -and $null -ne $script:WinToolOmpThemeCache) {
        $file = Get-WinToolOmpThemeFileName -ThemeId ([string]$choice.promptStyle) -Themes @(Get-WinToolActiveOhMyPoshTheme)
        if (-not [string]::IsNullOrWhiteSpace($file) -and $script:WinToolOmpThemeCache.ContainsKey($file)) {
            $theme = $script:WinToolOmpThemeCache[$file]
        }
    }
    $segments = @(Get-WinToolPromptPreview -PromptId ([string]$choice.prompt) -PromptStyle ([string]$choice.promptStyle) -Theme $theme)
    $scheme = $null
    foreach ($item in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())) {
        if ([string]$item.id -eq [string]$choice.schemeId) { $scheme = $item; break }
    }
    if ($null -eq $scheme) {
        $scheme = [pscustomobject]@{ name = "Night"; background = "#1B2230"; foreground = "#E8EDF7"; cursor = "#6C9BFF"; palette = $null }
    }
    $background = ConvertTo-WinToolPreviewBrush -Color ([string]$scheme.background)
    if ($null -ne $background) {
        $screen.Background = $background
        $tab = Get-WinToolUi -Name "TerminalSimpleTab"
        if ($null -ne $tab) { $tab.Background = $background }
    }
    $foreground = ConvertTo-WinToolPreviewBrush -Color ([string]$scheme.foreground)
    if ($null -ne $foreground) { $sample.Foreground = $foreground }
    $face = "CaskaydiaCove Nerd Font"
    foreach ($font in @(Get-WinToolActiveFont)) {
        if ([string]$font.id -eq [string]$choice.fontId) { $face = [string]$font.face; break }
    }
    Set-WinToolPreviewFontFamily -Element $sample
    Set-WinToolLigatureTypography -Element $sample
    $size = 12
    $sizeValue = Get-WinToolNote -Object $choice -Name "fontSize"
    if ($null -ne $sizeValue -and [int]$sizeValue -gt 0) { $size = [int]$sizeValue }
    $sample.FontSize = [Math]::Round($size * 1.1, 1)
    $sample.LineHeight = [Math]::Round($sample.FontSize * 1.5)
    $palette = Get-WinToolNote -Object $scheme -Name "palette"
    $red = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "red" -Default "#F07178")) -Palette $null
    $yellow = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "yellow" -Default "#EED49F")) -Palette $null
    $blue = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "blue" -Default "#6C9BFF")) -Palette $null
    $dim = ConvertTo-WinToolPreviewColor -Value ([string](Get-WinToolNote -Object $palette -Name "brightBlack" -Default "#5B6680")) -Palette $null
    $script:WinToolPreviewEmSize = [double]$sample.FontSize
    $sample.Inlines.Clear()
    $text = { param([string]$Value, [string]$Color) New-WinToolPreviewSegment -Text $Value -Foreground $Color }
    $addLine = {
        param([object[]]$Parts)
        Add-WinToolPreviewLine -Inlines $sample.Inlines -Segment $Parts -EmSize ([double]$sample.FontSize) -Break
    }
    & $addLine @((& $text "PowerShell 7" $dim))
    & $addLine @((& $text " " ""))
    & $addLine (@($segments) + @((& $text " git status" "")))
    & $addLine @((& $text "On branch main" ""))
    & $addLine @((& $text "Changes not staged for commit:" ""))
    & $addLine @((& $text "        modified:   src/app.ts" $red))
    & $addLine @((& $text " " ""))
    & $addLine (@($segments) + @((& $text " ls" "")))
    $folder = ""
    $file = ""
    if ([bool]$choice.terminalIcons) {
        $folder = [string][char]0xF07B + " "
        $file = [string][char]0xF489 + " "
    }
    $listing = ""
    foreach ($name in @("assets", "build", "data", "src")) { $listing += $folder + $name + "   " }
    & $addLine @((& $text $listing $blue), (& $text ($file + "wintool.ps1") $yellow))
    & $addLine @((& $text " " ""))
    $last = @($segments) + @((& $text " git s" ""), (New-WinToolPreviewSegment -Text " " -Background ([string]$scheme.cursor)))
    if ([bool]$choice.psReadLine) { $last += (& $text "tatus" $dim) }
    & $addLine $last
    $caption = Get-WinToolUi -Name "TerminalSimpleCaption"
    if ($null -ne $caption) {
        $themeName = [string]$choice.promptStyle
        foreach ($row in @(Get-WinToolActiveOhMyPoshTheme)) {
            if ([string]$row.id -eq [string]$choice.promptStyle) { $themeName = [string]$row.name; break }
        }
        $fontName = $face
        foreach ($font in @(Get-WinToolActiveFont)) {
            if ([string]$font.id -eq [string]$choice.fontId) { $fontName = [string]$font.name; break }
        }
        $dot = " " + [string][char]0x00B7 + " "
        $caption.Text = ("Oh My Posh" + $dot + $themeName + $dot + $fontName + $dot + [string]$scheme.name)
    }
    }
    catch {
        $null = $_.Exception.Message
    }
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
    Update-WinToolThemePreviewImage
    Request-WinToolTerminalPreview
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
        Update-WinToolSimplePreview
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
    Set-WinToolPreviewFontFamily -Element $text
    $text.SetResourceReference([System.Windows.Controls.TextBlock]::FontSizeProperty, "FontSizeBody")
    $text.TextWrapping = "Wrap"
    foreach ($segment in @($Segments)) {
        $color = [string]$segment.color
        if ([string]::IsNullOrWhiteSpace($color)) { $color = [string]$segment.fg }
        Add-WinToolPreviewRun -Inlines $text.Inlines -Segment ([pscustomobject]@{ Text = [string]$segment.text; Foreground = $color; Background = [string]$segment.bg })
    }
    $border.Child = $text
    return $border
}

function Update-WinToolTerminalCatalogOnline {
    if ($null -ne $script:WinToolState.CatalogJob) {
        return
    }
    Write-WinToolLog -Message (Get-WinToolText "msg.refreshing-nerd-fonts-and-oh-my-posh-themes-from-github") -Level "info"
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
        Write-WinToolLog -Message (Get-WinToolText "msg.could-not-refresh-catalogs-builtin-available-n" $_.Exception.Message) -Level "warn"
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
        Write-WinToolLog -Message (Get-WinToolText "msg.could-not-refresh-catalogs-builtin-available-n" $errText) -Level "warn"
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
        Write-WinToolLog -Message (Get-WinToolText "msg.catalog-refresh-added-n-fonts-and-n-themes" @($added.ToArray()).Count @($extraThemes.ToArray()).Count) -Level "ok"
    }
    catch {
        Write-WinToolLog -Message (Get-WinToolText "msg.could-not-apply-the-refreshed-catalogs-n" $_.Exception.Message) -Level "warn"
    }
}

function Complete-WinToolTerminalApply {
    Reset-WinToolFontResolution
    Update-WinToolLocalPackageCache | Out-Null
    $script:WinToolConfigNeedCache = $null
    try { Update-WinToolFontList } catch { $null = $_.Exception.Message }
    try { Update-WinToolTerminalSummary } catch { $null = $_.Exception.Message }
    Start-WinToolAppDetection
}

function Invoke-WinToolTerminalClick {
    param(
        [switch]$Update
    )
    $choice = Get-WinToolTerminalChoice
    $summary = @(Get-WinToolTerminalSummary -Selection $choice -Update:$Update)
    $preview = ($summary -join "`n")
    $title = "Apply this terminal setup?"
    $done = "Terminal setup finished. Open a new terminal window to see the prompt."
    if ($Update) {
        $title = "Update this terminal setup?"
        $done = "Terminal update finished. Open a new terminal window to see the prompt."
    }
    $ok = Request-WinToolConfirmation -Message ($title + "`n`n" + $preview) -Title "Terminal"
    if (-not $ok) { return }
    $steps = @(Get-WinToolTerminalPlan -Selection $choice)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage $done -AfterDone "Complete-WinToolTerminalApply" -Update:$Update
}

function Initialize-WinToolTerminalView {
    $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
    $script:WinToolTerminalMode = "simple"
    $script:WinToolTerminalFilter = "all"
    $script:WinToolTerminalSyncing = $false
    $script:WinToolExtraFont = @()
    $script:WinToolExtraOhMyPoshTheme = @()
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeSimple") -EventName "Checked" -Name "Terminal: Simple mode" -Action {
        Start-WinToolSurfaceTiming -Name "Terminal Simple"
        $script:WinToolTerminalMode = "simple"
        Set-WinToolTerminalModeView
        $script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
        Update-WinToolTerminalSummary
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalModeAdvanced") -EventName "Checked" -Name "Terminal: Advanced mode" -Action {
        Start-WinToolSurfaceTiming -Name "Terminal Advanced"
        $script:WinToolTerminalMode = "advanced"
        Set-WinToolTerminalModeView
        # The lists and the preview are built at startup. When they already
        # match the choice, the click only brings that page forward.
        $styleList = Get-WinToolUi -Name "TerminalStyleList"
        $promptList = Get-WinToolUi -Name "TerminalPromptList"
        $promptNow = [string]$script:WinToolTerminalChoice.prompt
        $styleNow = [string]$script:WinToolTerminalChoice.promptStyle
        $listWas = [string]$styleList.Tag
        $listReady = (
            [string]$styleList.Tag -eq $promptNow -and
            [string]$script:WinToolThemeListKey -eq (Get-WinToolThemeListKey) -and
            $null -ne $styleList.SelectedItem -and
            [string]$styleList.SelectedItem.Tag -eq $styleNow -and
            $null -ne $promptList.SelectedItem -and
            [string]$promptList.SelectedItem.Tag -eq $promptNow -and
            [string]$script:WinToolPreviewKey -eq (Get-WinToolPreviewKey)
        )
        if (-not $listReady) {
            Update-WinToolPromptStyleList
            Update-WinToolPromptSelection
            Update-WinToolExtraToggle
            Update-WinToolFontSizeSelection
            Sync-WinToolFontSelection
            Update-WinToolSchemeSelection
            Update-WinToolTerminalSummary
            # A different engine has to show its own sample before the click
            # returns. The same engine can repaint after the first frame.
            if ($listWas -ne $promptNow) { Update-WinToolTerminalPreview }
            else { Request-WinToolTerminalPreview }
        }
        $script:WinToolTerminalScrollPending = $true
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontNerdOnly") -EventName "Click" -Name "Terminal: Nerd Fonts only" -Action {
        Start-WinToolSurfaceTiming -Name "Terminal fonts"
        Update-WinToolFontList
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalThemeSearch") -EventName "TextChanged" -Name "Terminal: theme search" -Action {
        Start-WinToolSurfaceTiming -Name "Terminal search"
        Sync-WinToolSearchHint -BoxName "TerminalThemeSearch" -HintName "TerminalThemeSearchHint"
        $beforeStyle = [string]$script:WinToolTerminalChoice.promptStyle
        Update-WinToolPromptStyleList
        if ($beforeStyle -ne [string]$script:WinToolTerminalChoice.promptStyle) {
            Update-WinToolTerminalSummary
            Request-WinToolTerminalPreview
        }
    }
    foreach ($filterName in @("TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd")) {
        Register-WinToolUiEvent -Control (Get-WinToolUi -Name $filterName) -EventName "Checked" -Name "Terminal: theme filter" -Action {
            param($source, $eventData)
            $null = $eventData
            if ($script:WinToolTerminalSyncing) { return }
            Start-WinToolSurfaceTiming -Name ("Terminal " + [string]$source.Tag)
            $script:WinToolTerminalFilter = [string]$source.Tag
            $beforeStyle = [string]$script:WinToolTerminalChoice.promptStyle
            Update-WinToolPromptStyleList
            if ($beforeStyle -ne [string]$script:WinToolTerminalChoice.promptStyle) {
                Update-WinToolTerminalSummary
                Request-WinToolTerminalPreview
            }
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalRefresh") -EventName "Click" -Name "Terminal: refresh lists" -Action { Update-WinToolTerminalCatalogOnline }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalSetup") -EventName "Click" -Name "Terminal: apply setup" -Action { Invoke-WinToolTerminalClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalUpdate") -EventName "Click" -Name "Terminal: update setup" -Action { Invoke-WinToolTerminalClick -Update }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontList") -EventName "SelectionChanged" -Name "Terminal: choose font" -Action {
        if ($script:WinToolTerminalSyncing) { return }
        Update-WinToolFontSample
        Update-WinToolTerminalSummary
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalFontSize") -EventName "SelectionChanged" -Name "Terminal: choose font size" -Action {
        $sizeBox = Get-WinToolUi -Name "TerminalFontSize"
        if ($null -ne $sizeBox.SelectedItem -and -not $script:WinToolTerminalSyncing) {
            Set-WinToolTerminalChoiceValue -Name "fontSize" -Value ([int]$sizeBox.SelectedItem.Tag)
            Update-WinToolTerminalSummary
            Request-WinToolTerminalPreview
        }
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "TerminalStyleList") -EventName "SelectionChanged" -Name "Terminal: choose prompt style" -Action {
        # While the list is rebuilt for another engine, its selection changes
        # are not clicks: they must not copy other controls into the choice.
        if ($script:WinToolTerminalSyncing) { return }
        # The theme-row pictures stay cached. A click stores the style, updates
        # the plan text, and queues only the large live preview.
        $list = Get-WinToolUi -Name "TerminalStyleList"
        if ($null -ne $list.SelectedItem -and [string]$list.Tag -eq [string]$script:WinToolTerminalChoice.prompt) {
            $script:WinToolTerminalChoice.promptStyle = [string]$list.SelectedItem.Tag
        }
        Update-WinToolTerminalSummary
        Request-WinToolTerminalPreview
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
    Update-WinToolSimplePreview
    # Keep Advanced measured behind Simple so the first click does not lay it out.
    $script:WinToolTerminalSurfaceWarm = $true
    Set-WinToolTerminalModeView
    Request-WinToolThemeViewCache
}

function Set-WinToolTerminalModeView {
    $advanced = ($script:WinToolTerminalMode -eq "advanced")
    $body = Get-WinToolUi -Name "TerminalBodyScroll"
    $simple = Get-WinToolUi -Name "TerminalSimpleScroll"
    $subtitle = Get-WinToolUi -Name "TerminalSubtitle"
    if ($advanced) {
        $subtitle.Text = (Get-WinToolText "msg.pick-a-prompt-a-theme-a-font-and-a-color-scheme-the-prev")
    }
    else {
        $subtitle.Text = (Get-WinToolText "ui.TerminalSubtitle.Text")
    }
    if (-not $script:WinToolTerminalSurfaceWarm) {
        if ($advanced) {
            $simple.Visibility = "Collapsed"
            $body.Visibility = "Visible"
        }
        else {
            $body.Visibility = "Collapsed"
            $simple.Visibility = "Visible"
        }
        return
    }
    # Both stay drawn at full opacity. The one underneath is covered by the
    # opaque page on top, so showing it does not paint the tree again.
    $body.Visibility = "Visible"
    $simple.Visibility = "Visible"
    $body.Opacity = 1
    $simple.Opacity = 1
    if ($advanced) {
        $body.IsHitTestVisible = $true
        $body.Focusable = $true
        [System.Windows.Controls.Panel]::SetZIndex($body, 2)
        $simple.IsHitTestVisible = $false
        $simple.Focusable = $false
        [System.Windows.Controls.Panel]::SetZIndex($simple, 0)
    }
    else {
        $simple.IsHitTestVisible = $true
        $simple.Focusable = $true
        [System.Windows.Controls.Panel]::SetZIndex($simple, 2)
        $body.IsHitTestVisible = $false
        $body.Focusable = $false
        [System.Windows.Controls.Panel]::SetZIndex($body, 0)
    }
}

function Select-WinToolTerminalPrompt {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId
    )
    Set-WinToolTerminalChoiceValue -Name "prompt" -Value $PromptId
    # A new engine starts on All, so a filter never leaves its list empty.
    $script:WinToolTerminalFilter = "all"
    $wasSyncing = [bool]$script:WinToolTerminalSyncing
    $script:WinToolTerminalSyncing = $true
    try {
        $allChip = Get-WinToolUi -Name "TerminalFilterAll"
        if ($null -ne $allChip -and $allChip.IsChecked -ne $true) { $allChip.IsChecked = $true }
        Update-WinToolPromptStyleList
        Update-WinToolPromptSelection
        Update-WinToolTerminalSummary
    }
    finally {
        $script:WinToolTerminalSyncing = $wasSyncing
    }
    # The theme list is swapped from cache. Pictures and the large preview
    # are painted after this click, on the background dispatcher queue.
    Request-WinToolTerminalPreview
    Request-WinToolVisibleThemePreview
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
        (Get-WinToolUi -Name "TerminalPromptCount").Text = (Get-WinToolText "msg.n-engines" $prompts.Count)
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
    $aboutBlock.ToolTip = ($aboutBlock.Text + "`n`n" + (Get-WinToolText "msg.installs-colon-n" ((@($prompt.installs) -join ", "))) + "`n" + [string]$info.Runs).Trim()
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

function Get-WinToolPreviewKey {
    $choice = $script:WinToolTerminalChoice
    if ($null -eq $choice) { return "" }
    return ([string]$choice.prompt + "|" + [string]$choice.promptStyle + "|" + [string]$choice.fontId + "|" + [string](Get-WinToolNote -Object $choice -Name "fontSize" -Default 12) + "|" + [string]$choice.schemeId + "|" + [string]$choice.terminalIcons + "|" + [string]$choice.psReadLine + "|" + [string]$choice.zoxide + "|" + [string]$choice.fzf)
}

function Get-WinToolThemeListKey {
    $prompt = [string]$script:WinToolTerminalChoice.prompt
    $filter = [string]$script:WinToolTerminalFilter
    if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "all" }
    $query = ""
    $box = Get-WinToolUi -Name "TerminalThemeSearch"
    if ($null -ne $box) { $query = [string]$box.Text }
    return ($prompt + "|" + $filter + "|" + $query)
}

function Initialize-WinToolThemeViewCache {
    # Build every engine's theme rows and list entries once, off the click
    # path. Pictures stay lazy.
    $ids = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @() | ForEach-Object { [string]$_.id })
    foreach ($promptId in $ids) {
        if ([string]::IsNullOrWhiteSpace($promptId)) { continue }
        $null = Get-WinToolCachedThemeRow -PromptId $promptId
        if ($null -eq $script:WinToolThemeViewByPrompt) { $script:WinToolThemeViewByPrompt = @{} }
        if ($script:WinToolThemeViewByPrompt.ContainsKey($promptId)) { continue }
        Initialize-WinToolThemeEntryType
        $rows = @(Get-WinToolCachedThemeRow -PromptId $promptId)
        $entries = New-Object System.Collections.Generic.List[object]
        foreach ($row in $rows) {
            [void]$entries.Add((Get-WinToolCachedThemeEntry -Row $row -PromptId $promptId))
        }
        $filterObject = New-Object WinToolThemeFilter
        $view = [System.Windows.Data.ListCollectionView]::new($entries)
        $filterObject.Mode = "all"
        $filterObject.Query = ""
        $filterObject.Attach($view)
        $script:WinToolThemeViewByPrompt[$promptId] = [pscustomobject]@{
            Entries = $entries
            Filter  = $filterObject
            View    = $view
        }
    }
}

function Request-WinToolThemeViewCache {
    if ($script:WinToolThemeViewCacheQueued) { return }
    $script:WinToolThemeViewCacheQueued = $true
    if ($null -eq $script:WinToolWindow) {
        $script:WinToolThemeViewCacheQueued = $false
        Initialize-WinToolThemeViewCache
        return
    }
    $callback = [scriptblock]::Create("Complete-WinToolQueuedThemeViewCache")
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$callback)
}

function Complete-WinToolQueuedThemeViewCache {
    $script:WinToolThemeViewCacheQueued = $false
    Initialize-WinToolThemeViewCache
}

function Reset-WinToolThemeListCache {
    param([switch]$Force)
    $extra = @($script:WinToolExtraOhMyPoshTheme).Count
    if (-not $Force -and [int]$script:WinToolThemeExtraCount -eq $extra -and $null -ne $script:WinToolThemeRowCache) { return }
    $script:WinToolThemeExtraCount = $extra
    $script:WinToolThemeRowCache = @{}
    $script:WinToolThemeItemCache = @{}
    $script:WinToolThemeViewByPrompt = @{}
    $script:WinToolThemeImageByKey = @{}
    $script:WinToolActiveOhMyPoshTheme = $null
    $script:WinToolThemeListKey = ""
    $script:WinToolThemeEntryPrompt = ""
    $script:WinToolThemeView = $null
    $script:WinToolThemeEntries = $null
    $script:WinToolThemeFilter = $null
}

function Get-WinToolCachedThemeRow {
    param(
        [Parameter(Mandatory = $true)][string]$PromptId
    )
    if ($null -eq $script:WinToolThemeRowCache) { $script:WinToolThemeRowCache = @{} }
    if ($script:WinToolThemeRowCache.ContainsKey($PromptId)) {
        return @($script:WinToolThemeRowCache[$PromptId])
    }
    $rows = @(Get-WinToolThemeRow -PromptId $PromptId -OhMyPoshTheme @(Get-WinToolActiveOhMyPoshTheme))
    $script:WinToolThemeRowCache[$PromptId] = $rows
    return $rows
}

function Initialize-WinToolThemeEntryType {
    # Plain objects, not ListBoxItems. A C# predicate filters them, so the
    # click does not walk the catalog in PowerShell or build a row visual.
    if ($null -ne ("WinToolThemeEntry" -as [type])) { return }
    $refs = @(
        [System.Windows.Threading.DispatcherObject].Assembly.Location,
        [System.Windows.Media.Visual].Assembly.Location,
        [System.Windows.Data.ListCollectionView].Assembly.Location
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Windows.Data;
public class WinToolThemeEntry : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    public string Tag { get; set; }
    public string Name { get; set; }
    public string Tip { get; set; }
    public string Nerd { get; set; }
    public string SampleVisible { get; set; }
    public string Hay { get; set; }
    public int Powerline { get; set; }
    public int NerdFont { get; set; }
    private object previewImage;
    public object PreviewImage {
        get { return previewImage; }
        set {
            previewImage = value;
            var changed = PropertyChanged;
            if (changed != null) {
                changed(this, new PropertyChangedEventArgs("PreviewImage"));
            }
        }
    }
}
public class WinToolThemeFilter {
    public string Mode;
    public string Query;
    public void Attach(ListCollectionView view) {
        view.Filter = new Predicate<object>(AllowObject);
    }
    private bool AllowObject(object item) {
        return Allow(item as WinToolThemeEntry);
    }
    public bool Allow(WinToolThemeEntry entry) {
        if (entry == null) return false;
        if (Mode == "powerline" && entry.Powerline != 1) return false;
        if (Mode == "minimal" && entry.Powerline != 2) return false;
        if (Mode == "no-nerd" && entry.NerdFont != 2) return false;
        if (string.IsNullOrWhiteSpace(Query)) return true;
        if (string.IsNullOrEmpty(entry.Hay)) return false;
        return entry.Hay.IndexOf(Query.Trim(), StringComparison.OrdinalIgnoreCase) >= 0;
    }
}
"@
}

function New-WinToolPreviewImage {
    param(
        [object[]]$Segment,
        [double]$EmSize = 14.0,
        [switch]$SkipCache
    )
    # One frozen drawing per theme line, painted from each face's GlyphTypeface
    # (GlyphRun). FontFamily by name is not used, so a per-user Nerd Font is
    # not drawn as an empty box.
    $segments = @($Segment | Where-Object { $null -ne $_ -and -not [string]::IsNullOrEmpty([string]$_.Text) })
    if ($segments.Count -eq 0) {
        $script:WinToolLastPreviewDrawn = @()
        return $null
    }
    if ($EmSize -le 0) { $EmSize = 14.0 }
    $cacheKey = $null
    if (-not $SkipCache) {
        $cacheKey = Get-WinToolPreviewImageCacheKey -Segment $segments -EmSize $EmSize
        if ($null -eq $script:WinToolPreviewImageCache) { $script:WinToolPreviewImageCache = @{} }
        if ($script:WinToolPreviewImageCache.ContainsKey($cacheKey)) {
            $hit = $script:WinToolPreviewImageCache[$cacheKey]
            $script:WinToolLastPreviewDrawn = @($hit.Drawn)
            return $hit.Image
        }
    }
    Initialize-WinToolGlyphDraw
    $rows = New-Object System.Collections.Generic.List[object]
    $drawn = New-Object System.Collections.Generic.List[object]
    $lineHeight = $EmSize
    $baseline = $EmSize * 0.8
    foreach ($segment in $segments) {
        $color = [string]$segment.Foreground
        if ([string]::IsNullOrWhiteSpace($color)) { $color = "#E8EDF7" }
        $fg = ConvertTo-WinToolPreviewBrush -Color $color
        if ($null -eq $fg) { continue }
        $parts = New-Object System.Collections.Generic.List[object]
        $width = 0.0
        foreach ($piece in @(Split-WinToolCoveredText -Text ([string]$segment.Text))) {
            if ($null -eq $piece.Glyph -or [string]::IsNullOrEmpty([string]$piece.Text)) { continue }
            $codes = [int[]]@(Get-WinToolTextCode -Text ([string]$piece.Text))
            if ($codes.Count -eq 0) { continue }
            $pieceWidth = [WinToolGlyphDraw]::Measure($piece.Glyph, $codes, $EmSize)
            $lineHeight = [Math]::Max($lineHeight, [WinToolGlyphDraw]::LineHeight($piece.Glyph, $EmSize))
            $baseline = [Math]::Max($baseline, [WinToolGlyphDraw]::Baseline($piece.Glyph, $EmSize))
            [void]$parts.Add([pscustomobject]@{ Glyph = $piece.Glyph; Codes = $codes; Width = $pieceWidth; Brush = $fg })
            [void]$drawn.Add([pscustomobject]@{
                Text = [string]$piece.Text
                Foreground = $color
                Background = [string]$segment.Background
            })
            $width += $pieceWidth
        }
        if ($parts.Count -eq 0) { continue }
        [void]$rows.Add([pscustomobject]@{
            Parts = $parts.ToArray()
            Width = $width
            Background = [string]$segment.Background
        })
    }
    if ($rows.Count -eq 0) {
        $script:WinToolLastPreviewDrawn = @()
        return $null
    }
    $group = New-Object System.Windows.Media.DrawingGroup
    $x = 0.0
    foreach ($row in $rows) {
        $fillName = [string]$row.Background
        if (-not [string]::IsNullOrWhiteSpace($fillName)) {
            $fill = ConvertTo-WinToolPreviewBrush -Color $fillName
            if ($null -ne $fill) {
                $rect = New-Object System.Windows.Media.RectangleGeometry ([System.Windows.Rect]::new($x, 0.0, [double]$row.Width, $lineHeight))
                if ($rect.CanFreeze) { $rect.Freeze() }
                $back = New-Object System.Windows.Media.GeometryDrawing $fill, $null, $rect
                if ($back.CanFreeze) { $back.Freeze() }
                [void]$group.Children.Add($back)
            }
        }
        $pieceX = $x
        foreach ($part in @($row.Parts)) {
            $run = $null
            try { $run = [WinToolGlyphDraw]::MakeRun($part.Glyph, [int[]]$part.Codes, $EmSize, $pieceX, $baseline) } catch { $null = $_.Exception.Message }
            if ($null -ne $run) {
                $glyph = New-Object System.Windows.Media.GlyphRunDrawing $part.Brush, $run
                if ($glyph.CanFreeze) { $glyph.Freeze() }
                [void]$group.Children.Add($glyph)
            }
            $pieceX += [double]$part.Width
        }
        $x += [double]$row.Width
    }
    if ($group.Children.Count -eq 0) {
        $script:WinToolLastPreviewDrawn = @()
        return $null
    }
    if ($group.CanFreeze) { $group.Freeze() }
    $image = New-Object System.Windows.Media.DrawingImage $group
    if ($image.CanFreeze) { $image.Freeze() }
    $script:WinToolLastPreviewDrawn = $drawn.ToArray()
    if ($null -ne $cacheKey -and $script:WinToolPreviewImageCache.Count -lt 512) {
        $script:WinToolPreviewImageCache[$cacheKey] = [pscustomobject]@{ Image = $image; Drawn = $script:WinToolLastPreviewDrawn }
    }
    return $image
}

function Get-WinToolPreviewImageCacheKey {
    param(
        [object[]]$Segment,
        [double]$EmSize
    )
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append((Get-WinToolPreviewFontKey))
    [void]$builder.Append("|")
    [void]$builder.Append($EmSize.ToString([System.Globalization.CultureInfo]::InvariantCulture))
    foreach ($part in @($Segment)) {
        [void]$builder.Append("`n")
        [void]$builder.Append([string]$part.Text)
        [void]$builder.Append("`t")
        [void]$builder.Append([string]$part.Foreground)
        [void]$builder.Append("`t")
        [void]$builder.Append([string]$part.Background)
    }
    return $builder.ToString()
}

function Get-WinToolCachedThemeEntry {
    param(
        $Row,
        [Parameter(Mandatory = $true)][string]$PromptId
    )
    Initialize-WinToolThemeEntryType
    if ($null -eq $script:WinToolThemeItemCache) { $script:WinToolThemeItemCache = @{} }
    $id = $PromptId + "|" + [string]$Row.Id
    if ($script:WinToolThemeItemCache.ContainsKey($id)) {
        return $script:WinToolThemeItemCache[$id]
    }
    $entry = New-Object WinToolThemeEntry
    $entry.Tag = [string]$Row.Id
    $entry.Name = [string]$Row.Name
    $tip = [string]$Row.Id
    if (-not [string]::IsNullOrWhiteSpace([string]$Row.Description)) { $tip = ([string]$Row.Description + "`n" + $tip) }
    $entry.Tip = $tip
    $entry.Hay = ([string]$Row.Name + " " + [string]$Row.Id + " " + [string]$Row.Description)
    $entry.Nerd = "Collapsed"
    if ($Row.NerdFont -eq $true) { $entry.Nerd = "Visible" }
    $entry.Powerline = 0
    if ($Row.Powerline -eq $true) { $entry.Powerline = 1 }
    elseif ($Row.Powerline -eq $false) { $entry.Powerline = 2 }
    $entry.NerdFont = 0
    if ($Row.NerdFont -eq $true) { $entry.NerdFont = 1 }
    elseif ($Row.NerdFont -eq $false) { $entry.NerdFont = 2 }
    $entry.PreviewImage = $null
    $entry.SampleVisible = "Collapsed"
    $hasSample = $false
    foreach ($segment in @($Row.Preview)) {
        if ($null -ne $segment -and -not [string]::IsNullOrEmpty([string]$segment.Text)) { $hasSample = $true; break }
    }
    if ($hasSample) { $entry.SampleVisible = "Visible" }
    $script:WinToolThemeItemCache[$id] = $entry
    return $entry
}

function Update-WinToolThemePreviewImage {
    # Theme-row pictures are cached per font. A font change drops the
    # pictures on the visible entries; only those rows are redrawn.
    $key = Get-WinToolPreviewFontKey
    if ($key -eq [string]$script:WinToolThemePreviewFontKey) { return }
    $script:WinToolThemePreviewFontKey = $key
    $script:WinToolPreviewImageCache = @{}
    if ($null -ne $script:WinToolThemeViewByPrompt) {
        foreach ($promptId in @($script:WinToolThemeViewByPrompt.Keys)) {
            $pack = $script:WinToolThemeViewByPrompt[$promptId]
            if ($null -eq $pack -or $null -eq $pack.Entries) { continue }
            $entries = $pack.Entries
            for ($index = 0; $index -lt $entries.Count; $index++) {
                $entry = $entries[$index]
                if ($null -ne $entry) { $entry.PreviewImage = $null }
            }
        }
    }
    if ($null -ne $script:WinToolThemeEntries) {
        $entries = $script:WinToolThemeEntries
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            if ($null -ne $entry) { $entry.PreviewImage = $null }
        }
    }
    Request-WinToolVisibleThemePreview
}

function Add-WinToolThemeEntryPreview {
    param(
        $Entry,
        [string]$PromptId
    )
    if ($null -eq $Entry) { return }
    $fontKey = Get-WinToolPreviewFontKey
    $cacheKey = $fontKey + "|" + $PromptId + "|" + [string]$Entry.Tag
    if ($null -eq $script:WinToolThemeImageByKey) { $script:WinToolThemeImageByKey = @{} }
    if ($script:WinToolThemeImageByKey.ContainsKey($cacheKey)) {
        $cached = $script:WinToolThemeImageByKey[$cacheKey]
        if (-not [object]::Equals($Entry.PreviewImage, $cached)) { $Entry.PreviewImage = $cached }
        if ($null -ne $cached) { $Entry.SampleVisible = "Visible" }
        return
    }
    if ($null -ne $Entry.PreviewImage) { return }
    $row = $null
    if ($null -ne $script:WinToolTerminalRowById -and $script:WinToolTerminalRowById.ContainsKey([string]$Entry.Tag)) {
        $row = $script:WinToolTerminalRowById[[string]$Entry.Tag]
    }
    else {
        foreach ($item in @($script:WinToolTerminalRows)) {
            if ($null -ne $item -and [string]$item.Id -eq [string]$Entry.Tag) { $row = $item; break }
        }
    }
    if ($null -eq $row) { return }
    $image = New-WinToolPreviewImage -Segment @($row.Preview) -SkipCache
    $script:WinToolThemeImageByKey[$cacheKey] = $image
    $Entry.PreviewImage = $image
    if ($null -ne $image) { $Entry.SampleVisible = "Visible" }
}

function Get-WinToolVisibleThemeRange {
    # Returns the first and last theme-row indexes that should get a picture.
    # A ScrollViewer viewport can be in items or in pixels; a value larger
    # than the catalog is always treated as pixels. The cap keeps a broken
    # viewport from painting every Oh My Zsh theme on a click.
    param($List)
    $count = $List.Items.Count
    $start = 0
    $end = [Math]::Min($count - 1, 11)
    $viewer = Find-WinToolChildScrollViewer -Element $List
    if ($null -ne $viewer -and $viewer.ViewportHeight -gt 0) {
        $offset = [double]$viewer.VerticalOffset
        $view = [double]$viewer.ViewportHeight
        if ($view -le ($count + 2) -and $offset -le ($count + 2)) {
            $start = [Math]::Max(0, [int][Math]::Floor($offset) - 2)
            $end = [Math]::Min($count - 1, [int][Math]::Ceiling($offset + $view) + 2)
        }
        else {
            $row = 56.0
            $start = [Math]::Max(0, [int][Math]::Floor($offset / $row) - 2)
            $end = [Math]::Min($count - 1, [int][Math]::Ceiling(($offset + $view) / $row) + 2)
        }
    }
    $generator = $List.ItemContainerGenerator
    if ($null -ne $generator) {
        $firstReal = -1
        $lastReal = -1
        for ($index = 0; $index -lt $count; $index++) {
            if ($null -ne $generator.ContainerFromIndex($index)) {
                if ($firstReal -lt 0) { $firstReal = $index }
                $lastReal = $index
            }
        }
        if ($firstReal -ge 0) {
            $start = [Math]::Max(0, $firstReal - 2)
            $end = [Math]::Min($count - 1, $lastReal + 2)
        }
    }
    if ($List.SelectedIndex -ge 0) {
        $start = [Math]::Min($start, [Math]::Max(0, $List.SelectedIndex - 2))
        $end = [Math]::Max($end, [Math]::Min($count - 1, $List.SelectedIndex + 2))
    }
    if (($end - $start) -gt 16) {
        $anchor = $start
        if ($List.SelectedIndex -ge 0) { $anchor = [Math]::Max($start, $List.SelectedIndex - 4) }
        $start = [Math]::Max(0, $anchor)
        $end = [Math]::Min($count - 1, $start + 16)
    }
    return [pscustomobject]@{ Start = $start; End = $end }
}

function Sync-WinToolVisibleThemePreview {
    # Paint only the theme rows that are on screen (plus a short buffer).
    $list = Get-WinToolUi -Name "TerminalStyleList"
    if ($null -eq $list -or $list.Items.Count -eq 0) { return }
    Register-WinToolThemePreviewHook
    $range = Get-WinToolVisibleThemeRange -List $list
    $prompt = ""
    if ($null -ne $script:WinToolTerminalChoice) { $prompt = [string]$script:WinToolTerminalChoice.prompt }
    for ($index = $range.Start; $index -le $range.End; $index++) {
        Add-WinToolThemeEntryPreview -Entry $list.Items[$index] -PromptId $prompt
    }
}

function Request-WinToolVisibleThemePreview {
    if ($script:WinToolThemePreviewQueued) { return }
    $script:WinToolThemePreviewQueued = $true
    if ($null -eq $script:WinToolWindow) {
        $script:WinToolThemePreviewQueued = $false
        Sync-WinToolVisibleThemePreview
        return
    }
    $callback = [scriptblock]::Create("Complete-WinToolQueuedThemePreview")
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$callback)
}

function Complete-WinToolQueuedThemePreview {
    $script:WinToolThemePreviewQueued = $false
    Sync-WinToolVisibleThemePreview
}

function Register-WinToolThemePreviewHook {
    if ($script:WinToolThemePreviewHooked) { return }
    $list = Get-WinToolUi -Name "TerminalStyleList"
    if ($null -eq $list) { return }
    $viewer = Find-WinToolChildScrollViewer -Element $list
    if ($null -eq $viewer) { return }
    $script:WinToolThemePreviewHooked = $true
    Register-WinToolUiEvent -Control $viewer -EventName "ScrollChanged" -Name "Terminal: theme list scroll" -Action {
        Request-WinToolVisibleThemePreview
    }
}

function Update-WinToolPromptStyleList {
    $list = Get-WinToolUi -Name "TerminalStyleList"
    $prompt = [string]$script:WinToolTerminalChoice.prompt
    Reset-WinToolThemeListCache
    $key = Get-WinToolThemeListKey
    # The list remembers which prompt it was built for, so an old selection
    # never overwrites the style of a newly picked prompt.
    if ([string]$list.Tag -eq $prompt -and [string]$script:WinToolThemeListKey -eq $key -and $list.Items.Count -gt 0) {
        $wanted = [string]$script:WinToolTerminalChoice.promptStyle
        if ($null -eq $list.SelectedItem -or [string]$list.SelectedItem.Tag -ne $wanted) {
            $wasSyncing = [bool]$script:WinToolTerminalSyncing
            $script:WinToolTerminalSyncing = $true
            try {
                for ($index = 0; $index -lt $list.Items.Count; $index++) {
                    $item = $list.Items[$index]
                    if ([string]$item.Tag -eq $wanted) { $list.SelectedItem = $item; break }
                }
            }
            finally {
                $script:WinToolTerminalSyncing = $wasSyncing
            }
        }
        return
    }
    $wasSyncing = [bool]$script:WinToolTerminalSyncing
    $script:WinToolTerminalSyncing = $true
    try {
        $query = [string](Get-WinToolUi -Name "TerminalThemeSearch").Text
        $note = Get-WinToolUi -Name "TerminalStyleNote"
        $filter = [string]$script:WinToolTerminalFilter
        if ([string]::IsNullOrWhiteSpace($filter)) { $filter = "all" }
        $titles = Get-WinToolThemeTitle -PromptId $prompt
        (Get-WinToolUi -Name "TerminalThemeTitle").Text = [string]$titles.Title
        (Get-WinToolUi -Name "TerminalThemeSearchHint").Text = ([string]$titles.Hint + [string][char]0x2026)
        $rows = @(Get-WinToolCachedThemeRow -PromptId $prompt)
        $script:WinToolTerminalRows = $rows
        $byId = @{}
        foreach ($row in $rows) {
            if ($null -ne $row) { $byId[[string]$row.Id] = $row }
        }
        $script:WinToolTerminalRowById = $byId
        if ($null -eq $script:WinToolThemeViewByPrompt) { $script:WinToolThemeViewByPrompt = @{} }
        $pack = $null
        if ($script:WinToolThemeViewByPrompt.ContainsKey($prompt)) { $pack = $script:WinToolThemeViewByPrompt[$prompt] }
        if ($null -eq $pack) {
            # Entries are cheap: pictures are painted later for the rows on
            # screen. Each engine keeps its list, so a warm switch only swaps
            # the bound view.
            Initialize-WinToolThemeEntryType
            $entries = New-Object System.Collections.Generic.List[object]
            foreach ($row in $rows) {
                [void]$entries.Add((Get-WinToolCachedThemeEntry -Row $row -PromptId $prompt))
            }
            $filterObject = New-Object WinToolThemeFilter
            $view = [System.Windows.Data.ListCollectionView]::new($entries)
            $filterObject.Mode = $filter
            $filterObject.Query = $query
            $filterObject.Attach($view)
            $pack = [pscustomobject]@{
                Entries = $entries
                Filter  = $filterObject
                View    = $view
            }
            $script:WinToolThemeViewByPrompt[$prompt] = $pack
        }
        $script:WinToolThemeEntries = $pack.Entries
        $script:WinToolThemeFilter = $pack.Filter
        $script:WinToolThemeView = $pack.View
        $script:WinToolThemeEntryPrompt = $prompt
        $script:WinToolThemeFilter.Mode = $filter
        $script:WinToolThemeFilter.Query = $query
        if (-not [object]::Equals($list.ItemsSource, $pack.View)) {
            $list.ItemsSource = $pack.View
        }
        $script:WinToolThemeView.Refresh()
        $wanted = [string]$script:WinToolTerminalChoice.promptStyle
        $chosen = $null
        for ($index = 0; $index -lt $list.Items.Count; $index++) {
            $entry = $list.Items[$index]
            if ([string]$entry.Tag -eq $wanted) { $chosen = $entry; break }
        }
        if ($null -ne $chosen) { $list.SelectedItem = $chosen }
        elseif ($list.Items.Count -gt 0) { $list.SelectedIndex = 0 }
        else { $list.SelectedIndex = -1 }
        (Get-WinToolUi -Name "TerminalThemeCount").Text = (Get-WinToolText "msg.n-of-n" $list.Items.Count $rows.Count)
        if ($list.Items.Count -eq 0) {
            $note.Visibility = "Visible"
            if ($rows.Count -eq 0) { $note.Text = (Get-WinToolText "msg.this-prompt-has-its-own-default-look-the-font-and-extras") }
            else { $note.Text = (Get-WinToolText "msg.no-n-match-the-search-or-filter" $titles.Noun) }
        }
        else {
            $note.Visibility = "Collapsed"
        }
        $list.Tag = $prompt
        $script:WinToolThemeListKey = $key
        if ([string]::IsNullOrEmpty([string]$script:WinToolThemePreviewFontKey)) {
            $script:WinToolThemePreviewFontKey = Get-WinToolPreviewFontKey
        }
        if ($null -ne $list.SelectedItem) {
            $script:WinToolTerminalChoice.promptStyle = [string]$list.SelectedItem.Tag
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $wasSyncing
    }
    $script:WinToolTerminalScrollPending = $true
    Register-WinToolThemePreviewHook
    Request-WinToolVisibleThemePreview
}

function Set-WinToolPreviewFontFamily {
    param($Element)
    # The base face is the first one that loaded from a file. Runs that need
    # a different face set their own FontFamily.
    if ($null -eq $Element) { return }
    $chain = @(Get-WinToolPreviewFontChain)
    if ($chain.Count -gt 0 -and $null -ne $chain[0].Family) {
        $Element.FontFamily = $chain[0].Family
        return
    }
    $Element.FontFamily = [System.Windows.Media.FontFamily]::new("Consolas")
}

function Set-WinToolLigatureTypography {
    param($Element)
    # Windows Terminal setup always turns ligatures on, so previews draw them too.
    if ($null -eq $Element) { return }
    [System.Windows.Documents.Typography]::SetStandardLigatures($Element, $true)
    [System.Windows.Documents.Typography]::SetContextualAlternates($Element, $true)
}

function Add-WinToolPreviewLine {
    param(
        $Inlines,
        [object[]]$Segment,
        [double]$EmSize = 0,
        [switch]$Break
    )
    # One GlyphRun image for the whole line, so every icon is painted from
    # the file face that covers it.
    if ($null -eq $Inlines) { return }
    if ($EmSize -le 0) { $EmSize = [double]$script:WinToolPreviewEmSize }
    if ($EmSize -le 0) { $EmSize = 14.0 }
    $parts = @($Segment | Where-Object { $null -ne $_ })
    $source = New-WinToolPreviewImage -Segment $parts -EmSize $EmSize
    if ($null -eq $source) { return }
    if ($Break -and $Inlines.Count -gt 0) {
        [void]$Inlines.Add((New-Object System.Windows.Documents.LineBreak))
    }
    $image = New-Object System.Windows.Controls.Image
    $image.Source = $source
    $image.Stretch = [System.Windows.Media.Stretch]::None
    $image.SnapsToDevicePixels = $true
    # Tag holds the text after coverage and ASCII fallback, which is what
    # was actually painted, not the raw prompt string.
    $drawn = @($script:WinToolLastPreviewDrawn)
    $text = New-Object System.Text.StringBuilder
    foreach ($piece in $drawn) { [void]$text.Append([string]$piece.Text) }
    $image.Tag = [pscustomobject]@{ Text = $text.ToString(); Parts = $drawn }
    $container = New-Object System.Windows.Documents.InlineUIContainer
    $container.Child = $image
    $container.BaselineAlignment = "Bottom"
    [void]$Inlines.Add($container)
}

function Add-WinToolPreviewRun {
    param(
        $Inlines,
        $Segment,
        [double]$EmSize = 0
    )
    Add-WinToolPreviewLine -Inlines $Inlines -Segment @($Segment) -EmSize $EmSize
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
            Request-WinToolTerminalPreview
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
    if ($ExtraId -eq "hide-startup-banner") { return "hideStartupBanner" }
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
        if ($choiceName -eq "hideStartupBanner") {
            $toggle.IsChecked = Test-WinToolHideStartupBanner -Selection $script:WinToolTerminalChoice
            continue
        }
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
        Add-WinToolPreviewRun -Inlines $mark.Inlines -Segment ([pscustomobject]@{ Text = ([string][char]0x276F + " "); Foreground = [string](Get-WinToolNote -Object $palette -Name "green" -Default ([string]$scheme.cursor)); Background = $null })
        Add-WinToolPreviewRun -Inlines $mark.Inlines -Segment ([pscustomobject]@{ Text = [string]$scheme.name; Foreground = [string]$scheme.foreground; Background = $null })
        $grid = $mark
        $card.Child = $grid
        Register-WinToolUiEvent -Control $card -EventName "MouseLeftButtonUp" -Name "Terminal: choose color scheme" -Data ([string]$scheme.id) -Action {
            param($source, $eventData, $schemeId)
            $null = $source, $eventData
            Set-WinToolTerminalChoiceValue -Name "schemeId" -Value $schemeId
            Update-WinToolTerminalSummary
            Update-WinToolSchemeSelection
            Request-WinToolTerminalPreview
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
    # The lists scroll themselves. A leftover page scroll gets clamped when a
    # shorter theme list is shown, and the prompt card jumps.
    if ($scroll.VerticalOffset -ne 0) {
        $scroll.ScrollToVerticalOffset(0)
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

function Sync-WinToolFontSelection {
    $list = Get-WinToolUi -Name "TerminalFontList"
    if ($null -eq $list -or $list.Items.Count -eq 0) { return }
    $wanted = [string]$script:WinToolTerminalChoice.fontId
    if ($null -ne $list.SelectedItem -and [string]$list.SelectedItem.Tag -eq $wanted) { return }
    $wasSyncing = [bool]$script:WinToolTerminalSyncing
    $script:WinToolTerminalSyncing = $true
    try {
        for ($index = 0; $index -lt $list.Items.Count; $index++) {
            $item = $list.Items[$index]
            if ([string]$item.Tag -eq $wanted) {
                $list.SelectedItem = $item
                break
            }
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $wasSyncing
    }
}

function Update-WinToolFontList {
    $list = Get-WinToolUi -Name "TerminalFontList"
    $nerdOnly = ((Get-WinToolUi -Name "TerminalFontNerdOnly").IsChecked -eq $true)
    $allFonts = @(Get-WinToolResolvableFont)
    $fonts = @(Select-WinToolFont -Font $allFonts -Query "" -NerdOnly $nerdOnly)
    $fontIds = (@($allFonts | ForEach-Object { [string]$_.id }) -join ",")
    $fontKey = ([string]$nerdOnly + "|" + $fontIds)
    if ([string]$script:WinToolFontListKey -eq $fontKey -and ($list.Items.Count -gt 0 -or $fonts.Count -eq 0)) {
        Sync-WinToolFontSelection
        return
    }
    $script:WinToolFontListKey = ""
    $script:WinToolTerminalSyncing = $true
    try {
        if ($null -eq $script:WinToolFontItemCache) { $script:WinToolFontItemCache = @{} }
        $list.Items.Clear()
        foreach ($font in $fonts) {
            $fontId = [string]$font.id
            if (-not $script:WinToolFontItemCache.ContainsKey($fontId)) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $badge = "Installed - Programming font"
                if ($font.nerd) { $badge = "Installed - Nerd Font" }
                $item.Content = [string]$font.name
                $item.ToolTip = $badge
                $item.Tag = $fontId
                $script:WinToolFontItemCache[$fontId] = $item
            }
            $cached = $script:WinToolFontItemCache[$fontId]
            [void]$list.Items.Add($cached)
            if ($fontId -eq [string]$script:WinToolTerminalChoice.fontId) {
                $list.SelectedItem = $cached
            }
        }
        if ($null -eq $list.SelectedItem -and $list.Items.Count -gt 0) {
            $best = Get-WinToolBestNerdFont
            $picked = $false
            if ($null -ne $best) {
                for ($index = 0; $index -lt $list.Items.Count; $index++) {
                    if ([string]$list.Items[$index].Tag -eq [string]$best.Id) {
                        $list.SelectedIndex = $index
                        $picked = $true
                        break
                    }
                }
            }
            if (-not $picked) { $list.SelectedIndex = 0 }
        }
    }
    finally {
        $script:WinToolTerminalSyncing = $false
    }
    if ($null -ne $list.SelectedItem) {
        $script:WinToolTerminalChoice.fontId = [string]$list.SelectedItem.Tag
    }
    $nerdCount = @($allFonts | Where-Object { $_.nerd }).Count
    $schemeCount = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @()).Count
    $dot = " " + [string][char]0x00B7 + " "
    $countBlock = Get-WinToolUi -Name "TerminalFontCount"
    if ($null -ne $countBlock) {
        $countBlock.Text = (Get-WinToolText "msg.n-installed-n-nerd-fonts-n-schemes" $allFonts.Count $nerdCount $schemeCount)
    }
    $script:WinToolFontListKey = $fontKey
    Update-WinToolFontSizeSelection
    Request-WinToolTerminalPreview
}

function Show-WinToolTerminalSelection {
    # Brings the chosen engine and theme into view in their lists. When a list
    # is not laid out yet, the log pump calls this again a moment later.
    # The Simple / Advanced click does not call this. The list's own
    # UpdateLayout is only the list, and it runs after that first frame.
    $script:WinToolTerminalScrollPending = $false
    foreach ($name in @("TerminalPromptList", "TerminalStyleList")) {
        $list = Get-WinToolUi -Name $name
        if ($null -eq $list -or $null -eq $list.SelectedItem) { continue }
        try {
            $list.UpdateLayout()
            # Scroll the list's own viewer. ScrollIntoView also scrolls the page
            # and the prompt card jumps when the theme list gets shorter.
            $viewer = Find-WinToolChildScrollViewer -Element $list
            if ($null -ne $viewer -and $list.SelectedIndex -ge 0 -and $viewer.ViewportHeight -gt 0) {
                $target = [Math]::Max(0, $list.SelectedIndex - 1)
                if ($list.SelectedIndex -lt $viewer.VerticalOffset -or $list.SelectedIndex -ge ($viewer.VerticalOffset + $viewer.ViewportHeight)) {
                    $viewer.ScrollToVerticalOffset($target)
                    $list.UpdateLayout()
                }
            }
            if ($list.ActualHeight -le 0 -and $script:WinToolTerminalMode -eq "advanced") {
                $script:WinToolTerminalScrollPending = $true
            }
            if ($name -eq "TerminalStyleList") {
                Register-WinToolThemePreviewHook
                Request-WinToolVisibleThemePreview
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    $bodyScroll = Get-WinToolUi -Name "TerminalBodyScroll"
    if ($null -ne $bodyScroll -and $bodyScroll.VerticalOffset -ne 0) {
        $bodyScroll.ScrollToVerticalOffset(0)
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

function Request-WinToolTerminalPreview {
    # The click returns as soon as the choice is stored. The sample is drawn
    # on the background queue, after the first frame.
    $wanted = Get-WinToolPreviewKey
    if ([string]$script:WinToolPreviewKey -eq $wanted) { return }
    $script:WinToolPreviewWanted = $wanted
    if ($script:WinToolPreviewQueued) { return }
    $script:WinToolPreviewQueued = $true
    if ($null -eq $script:WinToolWindow) {
        $script:WinToolPreviewQueued = $false
        Update-WinToolTerminalPreview
        return
    }
    $callback = [scriptblock]::Create("Complete-WinToolQueuedPreview")
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Action]$callback)
}

function Complete-WinToolQueuedPreview {
    $script:WinToolPreviewQueued = $false
    if ([string]$script:WinToolPreviewKey -eq (Get-WinToolPreviewKey)) { return }
    Update-WinToolTerminalPreview
}

function Complete-WinToolStyleSelectionWork {
    # Tests and timing flush any coalesced click work on this thread.
    $script:WinToolChoicePaintQueued = $false
    $script:WinToolPreviewQueued = $false
    $script:WinToolThemePreviewQueued = $false
    Update-WinToolTerminalSummary
    Update-WinToolTerminalPreview
    Sync-WinToolVisibleThemePreview
}

function Restore-WinToolLivePreview {
    param($State)
    if ($null -eq $State) { return $false }
    $sample = Get-WinToolUi -Name "TerminalFontSample"
    $border = Get-WinToolUi -Name "TerminalFontPreview"
    if ($null -eq $sample -or $null -eq $border) { return $false }
    if ($null -ne $State.BorderBackground) { $border.Background = $State.BorderBackground }
    $tab = Get-WinToolUi -Name "TerminalPreviewTab"
    if ($null -ne $tab -and $null -ne $State.TabBackground) { $tab.Background = $State.TabBackground }
    $tabText = Get-WinToolUi -Name "TerminalPreviewTabText"
    if ($null -ne $tabText -and $null -ne $State.TabText) { $tabText.Text = [string]$State.TabText }
    if ($null -ne $State.Foreground) { $sample.Foreground = $State.Foreground }
    if ($null -ne $State.FontFamily) { $sample.FontFamily = $State.FontFamily }
    if ($State.FontSize -gt 0) { $sample.FontSize = [double]$State.FontSize }
    if ($State.LineHeight -gt 0) { $sample.LineHeight = [double]$State.LineHeight }
    $infoBlock = Get-WinToolUi -Name "TerminalPreviewInfo"
    if ($null -ne $infoBlock) {
        $infoBlock.Text = [string]$State.Info
        $infoBlock.ToolTip = [string]$State.Info
    }
    $border.ToolTip = [string]$State.Tip
    $sample.Inlines.Clear()
    foreach ($inline in @($State.Inline)) {
        [void]$sample.Inlines.Add($inline)
    }
    $script:WinToolPreviewKey = [string]$State.Key
    return $true
}

function Save-WinToolLivePreview {
    param([string]$Key)
    $sample = Get-WinToolUi -Name "TerminalFontSample"
    $border = Get-WinToolUi -Name "TerminalFontPreview"
    if ($null -eq $sample -or $null -eq $border -or [string]::IsNullOrWhiteSpace($Key)) { return }
    if ($null -eq $script:WinToolLivePreviewCache) { $script:WinToolLivePreviewCache = @{} }
    $tab = Get-WinToolUi -Name "TerminalPreviewTab"
    $tabText = Get-WinToolUi -Name "TerminalPreviewTabText"
    $infoBlock = Get-WinToolUi -Name "TerminalPreviewInfo"
    $inlines = New-Object System.Collections.Generic.List[object]
    foreach ($inline in @($sample.Inlines)) { [void]$inlines.Add($inline) }
    $script:WinToolLivePreviewCache[$Key] = [pscustomobject]@{
        Key = $Key
        Inline = $inlines.ToArray()
        BorderBackground = $border.Background
        TabBackground = $(if ($null -ne $tab) { $tab.Background } else { $null })
        TabText = $(if ($null -ne $tabText) { [string]$tabText.Text } else { "" })
        Foreground = $sample.Foreground
        FontFamily = $sample.FontFamily
        FontSize = [double]$sample.FontSize
        LineHeight = [double]$sample.LineHeight
        Info = $(if ($null -ne $infoBlock) { [string]$infoBlock.Text } else { "" })
        Tip = [string]$border.ToolTip
    }
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
    Update-WinToolThemePreviewImage
    $wanted = Get-WinToolPreviewKey
    if ($null -eq $script:WinToolLivePreviewCache) { $script:WinToolLivePreviewCache = @{} }
    if ($script:WinToolLivePreviewCache.ContainsKey($wanted)) {
        if (Restore-WinToolLivePreview -State $script:WinToolLivePreviewCache[$wanted]) { return }
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
        Set-WinToolPreviewFontFamily -Element $sample
        Set-WinToolLigatureTypography -Element $sample
        $styleList = Get-WinToolUi -Name "TerminalStyleList"
        if ($null -ne $styleList -and -not [object]::Equals($styleList.Resources["TerminalPreviewFont"], $sample.FontFamily)) {
            $styleList.Resources["TerminalPreviewFont"] = $sample.FontFamily
        }
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

        $script:WinToolPreviewEmSize = [double]$sample.FontSize
        $sample.Inlines.Clear()
        $addLine = {
            param([object[]]$Parts)
            Add-WinToolPreviewLine -Inlines $sample.Inlines -Segment $Parts -EmSize ([double]$sample.FontSize) -Break
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
        $script:WinToolPreviewKey = Get-WinToolPreviewKey
        Save-WinToolLivePreview -Key $script:WinToolPreviewKey
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Read-WinToolExtraSelection {
    $flags = @{ "terminal-icons" = $false; psreadline = $false; zoxide = $false; fzf = $false; "hide-startup-banner" = $true }
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
            $script:WinToolTerminalChoice.hideStartupBanner = [bool]$flags["hide-startup-banner"]
        }
    }
    $steps = @(Get-WinToolTerminalPlan -Selection $script:WinToolTerminalChoice)
    $lines = @($steps | ForEach-Object { [string]$_.Label })
    $planText = ($lines -join "`n")
    $chips = @(Get-WinToolSummaryChip -Step $steps -Selection $script:WinToolTerminalChoice)
    $chipKey = (@($chips | ForEach-Object { [string]$_.Kind + "|" + [string]$_.Text }) -join ";")
    $summaryKey = $planText + "`n" + $chipKey
    $planChanged = ($summaryKey -ne [string]$script:WinToolSummaryPlanKey)
    $script:WinToolSummaryPlanKey = $summaryKey
    (Get-WinToolUi -Name "TerminalSummary").Text = $planText
    $extrasCount = Get-WinToolUi -Name "TerminalExtrasCount"
    if ($null -ne $extrasCount) {
        $flags = Read-WinToolExtraSelection
        $on = 0
        foreach ($flagKey in $flags.Keys) { if ($flags[$flagKey]) { $on++ } }
        $extrasCount.Text = ([string]$on + " of " + [string]$flags.Count + " on")
    }
    $summaryHost = Get-WinToolUi -Name "TerminalSummaryHost"
    if ($null -eq $summaryHost) { return }
    if (-not $planChanged -and $summaryHost.Children.Count -gt 0) { return }
    $labels = New-Object System.Collections.Generic.List[object]
    foreach ($kind in @("add", "update", "change", "have", "set")) {
        foreach ($chip in @($chips | Where-Object { $_.Kind -eq $kind })) {
            if ($kind -eq "add") { $caption = "+ " + [string]$chip.Text }
            elseif ($kind -eq "update") { $caption = ([string][char]0x2191 + " " + [string]$chip.Text) }
            elseif ($kind -eq "change") { $caption = ([string][char]0x007E + " " + [string]$chip.Text) }
            elseif ($kind -eq "have") { $caption = (Get-WinToolText "msg.already-installed-colon-n" $chip.Text) }
            else { $caption = (Get-WinToolText "msg.already-set-colon-n" $chip.Text) }
            [void]$labels.Add([pscustomobject]@{ Kind = $kind; Text = $caption })
        }
    }
    $summaryHost.ToolTip = $planText
    # Reuse the existing chips when only a label changed (for example the
    # Starship preset name), so a click does not rebuild the action bar.
    if ($summaryHost.Children.Count -eq $labels.Count -and $labels.Count -gt 0) {
        $sameKind = $true
        for ($index = 0; $index -lt $labels.Count; $index++) {
            if ([string]$summaryHost.Children[$index].Tag -ne [string]$labels[$index].Kind) { $sameKind = $false; break }
        }
        if ($sameKind) {
            for ($index = 0; $index -lt $labels.Count; $index++) {
                $child = $summaryHost.Children[$index].Child
                if ($child -is [System.Windows.Controls.TextBlock]) { $child.Text = [string]$labels[$index].Text }
            }
            return
        }
    }
    # One wrapping row of chips: missing (+), updates, changes (~), then
    # already installed and already set.
    $summaryHost.Children.Clear()
    foreach ($item in $labels) {
        $kind = [string]$item.Kind
        if ($kind -eq "add") {
            $element = New-WinToolTerminalChip -Text ([string]$item.Text) -Background "BrushOkSoft" -Foreground "BrushOk"
        }
        elseif ($kind -eq "update") {
            $element = New-WinToolTerminalChip -Text ([string]$item.Text) -Background "BrushOkSoft" -Foreground "BrushOk"
        }
        elseif ($kind -eq "change") {
            $element = New-WinToolTerminalChip -Text ([string]$item.Text) -Background "BrushWarnSoft" -Foreground "BrushWarn"
        }
        else {
            $element = New-WinToolTerminalChip -Text ([string]$item.Text) -Background "BrushNavHover" -Foreground "BrushMuted"
        }
        $element.Tag = $kind
        [void]$summaryHost.Children.Add($element)
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
        hideStartupBanner = [bool](Test-WinToolHideStartupBanner -Selection $choice)
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
    $script:WinToolTerminalChoice.hideStartupBanner = Test-WinToolHideStartupBanner -Selection $Selection
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
