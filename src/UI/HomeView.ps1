# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# The Home page: a score ring, five checks in a fixed order and three small
# cards. Every state (analyzing, done, fixing) uses the same slots, so only
# the content inside them changes.

function Get-WinToolHomeEllipsis {
    return [string][char]0x2026
}

function Test-WinToolHomeReduceMotion {
    if ($script:WinToolHomeReduceMotion) { return $true }
    try { return (-not [System.Windows.SystemParameters]::ClientAreaAnimation) } catch { return $false }
}

function New-WinToolHomeBrush {
    param([string]$From, [string]$To, [switch]$Vertical, [double]$Alpha = 1)
    $brush = New-Object System.Windows.Media.LinearGradientBrush
    $brush.StartPoint = [System.Windows.Point]::new(0, 0)
    if ($Vertical) { $brush.EndPoint = [System.Windows.Point]::new(0, 1) } else { $brush.EndPoint = [System.Windows.Point]::new(1, 1) }
    $first = [System.Windows.Media.ColorConverter]::ConvertFromString($From)
    $second = [System.Windows.Media.ColorConverter]::ConvertFromString($To)
    if ($Alpha -lt 1) {
        $first = [System.Windows.Media.Color]::FromArgb([byte][Math]::Round(255 * $Alpha), $first.R, $first.G, $first.B)
        $second = [System.Windows.Media.Color]::FromArgb([byte]0, $second.R, $second.G, $second.B)
    }
    $brush.GradientStops.Add((New-Object System.Windows.Media.GradientStop($first, 0)))
    $brush.GradientStops.Add((New-Object System.Windows.Media.GradientStop($second, 1)))
    return $brush
}

function Get-WinToolHomeArcData {
    # Path data for an arc that starts at the top and runs clockwise.
    param([double]$CenterX, [double]$CenterY, [double]$Radius, [double]$Angle)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $sweep = [Math]::Max(0.5, [Math]::Min(359.6, $Angle))
    $radians = $sweep * [Math]::PI / 180
    $x = $CenterX + $Radius * [Math]::Sin($radians)
    $y = $CenterY - $Radius * [Math]::Cos($radians)
    $large = 0
    if ($sweep -gt 180) { $large = 1 }
    $text = [string]::Format($culture, "M {0},{1} A {2},{2} 0 {3} 1 {4:0.###},{5:0.###}", $CenterX, ($CenterY - $Radius), $Radius, $large, $x, $y)
    return [pscustomobject]@{ Data = $text; X = $x; Y = $y }
}

function Set-WinToolHomeArc {
    param([double]$Angle)
    $hs = $script:WinToolState.Home
    $hs.Arc = $Angle
    $arc = Get-WinToolUi -Name "HomeArc"
    $cap = Get-WinToolUi -Name "HomeArcCap"
    if ($Angle -lt 1) {
        $arc.Visibility = "Hidden"
        $cap.Visibility = "Hidden"
        return
    }
    $shape = Get-WinToolHomeArcData -CenterX 118 -CenterY 118 -Radius 94 -Angle $Angle
    $arc.Data = [System.Windows.Media.Geometry]::Parse($shape.Data)
    [System.Windows.Controls.Canvas]::SetLeft($cap, $shape.X - 6)
    [System.Windows.Controls.Canvas]::SetTop($cap, $shape.Y - 6)
    $arc.Visibility = "Visible"
    $cap.Visibility = "Visible"
}

function New-WinToolHomeRow {
    param(
        [Parameter(Mandatory = $true)]$Check,
        [bool]$Last
    )
    $border = New-Object System.Windows.Controls.Border
    $border.Height = 56
    $border.Padding = [System.Windows.Thickness]::new(14, 0, 14, 0)
    if (-not $Last) {
        $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $border.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    }
    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @(28, 12, -1, 12, 76)) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -lt 0) { $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = [System.Windows.GridLength]::new($width) }
        $grid.ColumnDefinitions.Add($column)
    }
    $border.Child = $grid

    $content = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetColumnSpan($content, 3)
    $null = $grid.Children.Add($content)
    foreach ($width in @(28, 12, -1)) {
        $column = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -lt 0) { $column.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $column.Width = [System.Windows.GridLength]::new($width) }
        $content.ColumnDefinitions.Add($column)
    }

    $icon = New-Object System.Windows.Controls.Grid
    $icon.Width = 22
    $icon.Height = 22
    $icon.VerticalAlignment = "Center"
    $disc = New-Object System.Windows.Shapes.Ellipse
    $disc.Width = 22
    $disc.Height = 22
    $glyph = New-Object System.Windows.Shapes.Path
    $glyph.StrokeThickness = 2
    $glyph.StrokeStartLineCap = "Round"
    $glyph.StrokeEndLineCap = "Round"
    $glyph.StrokeLineJoin = "Round"
    $spinner = New-Object System.Windows.Shapes.Path
    $spinner.StrokeThickness = 2
    $spinner.StrokeStartLineCap = "Round"
    $spinner.StrokeEndLineCap = "Round"
    $spinner.Data = [System.Windows.Media.Geometry]::Parse("M 11,3 A 8,8 0 0 1 19,11")
    $spinner.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, "BrushAccent")
    $spinner.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
    $spinner.RenderTransform = New-Object System.Windows.Media.RotateTransform(0)
    $spinner.Width = 22
    $spinner.Height = 22
    $null = $icon.Children.Add($disc)
    $null = $icon.Children.Add($glyph)
    $null = $icon.Children.Add($spinner)
    $null = $content.Children.Add($icon)

    $text = New-Object System.Windows.Controls.StackPanel
    $text.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($text, 2)
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = [string]$Check.Name
    $label.FontWeight = "SemiBold"
    $label.TextTrimming = "CharacterEllipsis"
    $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushInk")
    $result = New-Object System.Windows.Controls.TextBlock
    $result.Text = "Waiting" + (Get-WinToolHomeEllipsis)
    $result.TextTrimming = "CharacterEllipsis"
    $result.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushMuted")
    $null = $text.Children.Add($label)
    $null = $text.Children.Add($result)
    $null = $content.Children.Add($text)

    $button = New-Object System.Windows.Controls.Button
    $button.Style = $script:WinToolWindow.FindResource("HomeRowButton")
    $button.Content = "Fix"
    $button.VerticalAlignment = "Center"
    $button.IsEnabled = $false
    [System.Windows.Controls.Grid]::SetColumn($button, 4)
    $null = $grid.Children.Add($button)

    $row = [pscustomobject]@{
        Id = [string]$Check.Id
        Name = [string]$Check.Name
        Border = $border
        Content = $content
        Disc = $disc
        Glyph = $glyph
        Spinner = $spinner
        Label = $label
        Result = $result
        Button = $button
        Status = "busy"
    }
    Register-WinToolUiEvent -Control $button -EventName "Click" -Name ("Home: " + [string]$Check.Name) -Data ([string]$Check.Id) -Action {
        param($source, $eventData, $checkId)
        $null = $source, $eventData
        Invoke-WinToolHomeAction -Id $checkId
    }
    return $row
}

function Set-WinToolHomeRow {
    # Shows one state in a row's fixed slots. Action "none" hides the button
    # but keeps its slot; "off" shows it greyed out.
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][ValidateSet("busy", "ok", "warn", "bad", "unknown")][string]$Status,
        [Parameter(Mandatory = $true)][string]$Text,
        [ValidateSet("fix", "review", "none", "off")][string]$Action = "none",
        [switch]$Fade
    )
    $Row.Status = $Status
    $Row.Result.Text = $Text
    $rotate = $Row.Spinner.RenderTransform
    if ($Status -eq "busy") {
        $Row.Disc.Fill = [System.Windows.Media.Brushes]::Transparent
        $Row.Glyph.Visibility = "Hidden"
        $Row.Spinner.Visibility = "Visible"
        if (-not (Test-WinToolHomeReduceMotion)) {
            $spin = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, [System.Windows.Duration]::new([TimeSpan]::FromSeconds(1)))
            $spin.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $rotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $spin)
        }
    }
    else {
        $rotate.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $null)
        $Row.Spinner.Visibility = "Hidden"
        $Row.Glyph.Visibility = "Visible"
        $look = switch ($Status) {
            "ok" { @{ Soft = "BrushOkSoft"; Ink = "BrushOk"; Data = "M 7,11.5 L 10,14.5 L 15.5,8" } }
            "warn" { @{ Soft = "BrushWarnSoft"; Ink = "BrushWarn"; Data = "M 11,6.5 L 11,12 M 11,15.5 L 11,15.6" } }
            "bad" { @{ Soft = "BrushBadSoft"; Ink = "BrushBad"; Data = "M 8,8 L 14,14 M 14,8 L 8,14" } }
            default { @{ Soft = "BrushNavHover"; Ink = "BrushMuted"; Data = "M 11,10 L 11,15.5 M 11,6.5 L 11,6.6" } }
        }
        $Row.Disc.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $look.Soft)
        $Row.Glyph.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, $look.Ink)
        $Row.Glyph.Data = [System.Windows.Media.Geometry]::Parse($look.Data)
    }
    $button = $Row.Button
    switch ($Action) {
        "fix" {
            $button.Content = "Fix"
            $button.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "BrushAccentSoft")
            $button.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushAccent")
            $button.Visibility = "Visible"
            $button.IsEnabled = $true
        }
        "review" {
            $button.Content = "Review"
            $button.Background = [System.Windows.Media.Brushes]::Transparent
            $button.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushLine")
            $button.Visibility = "Visible"
            $button.IsEnabled = $true
        }
        "off" {
            $button.Content = "Fix"
            $button.Background = [System.Windows.Media.Brushes]::Transparent
            $button.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BrushLine")
            $button.Visibility = "Visible"
            $button.IsEnabled = $false
        }
        default {
            $button.Visibility = "Hidden"
            $button.IsEnabled = $false
        }
    }
    if ($Fade -and -not (Test-WinToolHomeReduceMotion)) {
        $animation = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 1, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(320)))
        $Row.Content.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animation)
    }
}

function New-WinToolHomeMini {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Title,
        [int]$Column,
        [string]$From,
        [string]$To,
        [string]$Line
    )
    $card = New-Object System.Windows.Controls.Border
    $card.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $card.BorderThickness = [System.Windows.Thickness]::new(1)
    $card.Padding = [System.Windows.Thickness]::new(18)
    $card.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BrushCard")
    $card.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, "BrushLine")
    [System.Windows.Controls.Grid]::SetColumn($card, $Column)
    $grid = New-Object System.Windows.Controls.Grid
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::Auto }))
    $grid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $card.Child = $grid

    $top = New-Object System.Windows.Controls.Grid
    $top.Height = 56
    foreach ($width in @(56, 14, -1)) {
        $colDef = New-Object System.Windows.Controls.ColumnDefinition
        if ($width -lt 0) { $colDef.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $colDef.Width = [System.Windows.GridLength]::new($width) }
        $top.ColumnDefinitions.Add($colDef)
    }
    $null = $grid.Children.Add($top)

    $ring = New-Object System.Windows.Controls.Canvas
    $ring.Width = 56
    $ring.Height = 56
    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Width = 49
    $track.Height = 49
    $track.StrokeThickness = 5
    $track.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, "BrushProgressTrack")
    [System.Windows.Controls.Canvas]::SetLeft($track, 3.5)
    [System.Windows.Controls.Canvas]::SetTop($track, 3.5)
    $arc = New-Object System.Windows.Shapes.Path
    $arc.StrokeThickness = 5
    $arc.StrokeStartLineCap = "Round"
    $arc.StrokeEndLineCap = "Round"
    $arc.Stroke = New-WinToolHomeBrush -From $From -To $To
    $arc.Visibility = "Hidden"
    $null = $ring.Children.Add($track)
    $null = $ring.Children.Add($arc)
    $null = $top.Children.Add($ring)

    $info = New-Object System.Windows.Controls.Grid
    $info.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($info, 2)
    foreach ($height in @(24, 20, 20)) {
        $info.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition -Property @{ Height = [System.Windows.GridLength]::new($height) }))
    }
    $null = $top.Children.Add($info)
    $titleRow = New-Object System.Windows.Controls.Grid
    $titleRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }))
    $titleRow.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = [System.Windows.GridLength]::Auto }))
    $null = $info.Children.Add($titleRow)
    $titleText = New-Object System.Windows.Controls.TextBlock
    $titleText.Text = $Title
    $titleText.FontWeight = "Bold"
    $titleText.VerticalAlignment = "Center"
    $titleText.TextTrimming = "CharacterEllipsis"
    $titleText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushInk")
    $null = $titleRow.Children.Add($titleText)
    $tag = New-Object System.Windows.Controls.Border
    $tag.Height = 22
    $tag.MinWidth = 88
    $tag.CornerRadius = [System.Windows.CornerRadius]::new(11)
    $tag.Padding = [System.Windows.Thickness]::new(8, 0, 8, 0)
    $tag.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $tag.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($tag, 1)
    $tagText = New-Object System.Windows.Controls.TextBlock
    $tagText.FontWeight = "SemiBold"
    $tagText.HorizontalAlignment = "Center"
    $tagText.VerticalAlignment = "Center"
    $tagText.Text = "Reading"
    $tag.Child = $tagText
    $null = $titleRow.Children.Add($tag)
    $value = New-Object System.Windows.Controls.TextBlock
    $value.FontWeight = "SemiBold"
    $value.TextTrimming = "CharacterEllipsis"
    $value.Text = "Reading" + (Get-WinToolHomeEllipsis)
    $value.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushInk")
    [System.Windows.Controls.Grid]::SetRow($value, 1)
    $null = $info.Children.Add($value)
    $detail = New-Object System.Windows.Controls.TextBlock
    $detail.TextTrimming = "CharacterEllipsis"
    $detail.Text = " "
    $detail.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "BrushMuted")
    [System.Windows.Controls.Grid]::SetRow($detail, 2)
    $null = $info.Children.Add($detail)

    # The chart takes the rest of the card, so taller windows get a taller chart.
    $spark = New-Object System.Windows.Controls.Grid
    $spark.MinHeight = 40
    $spark.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)
    $spark.VerticalAlignment = "Stretch"
    $spark.ClipToBounds = $true
    [System.Windows.Controls.Grid]::SetRow($spark, 1)
    $fill = New-Object System.Windows.Shapes.Path
    $fill.Fill = New-WinToolHomeBrush -From $Line -To $Line -Vertical -Alpha 0.28
    $stroke = New-Object System.Windows.Shapes.Path
    $stroke.StrokeThickness = 1.6
    $stroke.StrokeLineJoin = "Round"
    $stroke.Stroke = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString($Line))
    $null = $spark.Children.Add($fill)
    $null = $spark.Children.Add($stroke)
    $null = $grid.Children.Add($spark)

    $mini = [pscustomobject]@{
        Key = $Key
        Card = $card
        Arc = $arc
        Tag = $tag
        TagText = $tagText
        Value = $value
        Detail = $detail
        Spark = $spark
        SparkFill = $fill
        SparkLine = $stroke
        Points = (New-Object System.Collections.Generic.List[double])
    }
    Register-WinToolUiEvent -Control $spark -EventName "SizeChanged" -Name ("Home card " + $Key) -Data $mini -Action {
        param($source, $eventData, $card)
        $null = $source, $eventData
        Update-WinToolHomeSpark -Mini $card
    }
    return $mini
}

function Set-WinToolHomeMiniTag {
    param($Mini, [string]$Text, [ValidateSet("ok", "warn", "bad", "neutral")][string]$Tone)
    $Mini.TagText.Text = $Text
    $look = switch ($Tone) {
        "ok" { @("BrushOkSoft", "BrushOk") }
        "warn" { @("BrushWarnSoft", "BrushWarn") }
        "bad" { @("BrushBadSoft", "BrushBad") }
        default { @("BrushNavHover", "BrushMuted") }
    }
    $Mini.Tag.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $look[0])
    $Mini.TagText.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $look[1])
}

function Set-WinToolHomeMiniRing {
    param($Mini, [double]$Fraction)
    if ($Fraction -le 0) {
        $Mini.Arc.Visibility = "Hidden"
        return
    }
    $angle = [Math]::Min(1.0, $Fraction) * 360
    $shape = Get-WinToolHomeArcData -CenterX 28 -CenterY 28 -Radius 22 -Angle $angle
    $Mini.Arc.Data = [System.Windows.Media.Geometry]::Parse($shape.Data)
    $Mini.Arc.Visibility = "Visible"
}

function Add-WinToolHomeSparkPoint {
    param($Mini, [double]$Value)
    if ($Value -lt 0) { return }
    $Mini.Points.Add([Math]::Max(0, [Math]::Min(100, $Value)))
    while ($Mini.Points.Count -gt 24) { $Mini.Points.RemoveAt(0) }
    Update-WinToolHomeSpark -Mini $Mini
}

function Update-WinToolHomeSpark {
    # The newest sample sits on the right; 24 samples fill the width.
    param($Mini)
    $width = [double]$Mini.Spark.ActualWidth
    $height = [double]$Mini.Spark.ActualHeight
    $count = $Mini.Points.Count
    if ($width -le 0 -or $height -le 0 -or $count -lt 2) {
        $Mini.SparkLine.Data = $null
        $Mini.SparkFill.Data = $null
        return
    }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $step = $width / 23
    $points = New-Object System.Collections.Generic.List[string]
    $firstX = 0
    for ($i = 0; $i -lt $count; $i++) {
        $x = $width - ($count - 1 - $i) * $step
        if ($i -eq 0) { $firstX = $x }
        $y = ($height - 2) - ($Mini.Points[$i] / 100) * ($height - 8)
        $points.Add([string]::Format($culture, "{0:0.##},{1:0.##}", $x, $y))
    }
    $line = "M " + ($points -join " L ")
    $Mini.SparkLine.Data = [System.Windows.Media.Geometry]::Parse($line)
    $Mini.SparkFill.Data = [System.Windows.Media.Geometry]::Parse(($line + [string]::Format($culture, " L {0:0.##},{2:0.##} L {1:0.##},{2:0.##} Z", $width, $firstX, $height)))
}

function Format-WinToolHomeSize {
    # Installed sizes read best rounded: 32 GB of memory, 512 GB disk.
    param([double]$Bytes, [switch]$Decimal)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Decimal) {
        $gb = $Bytes / 1e9
        if ($gb -ge 1000) { return [string]::Format($culture, "{0:0.#} TB", $gb / 1000) }
        return [string]::Format($culture, "{0:0} GB", $gb)
    }
    $gib = $Bytes / 1GB
    if ([Math]::Abs($gib - [Math]::Round($gib)) -lt 0.06) { return [string]::Format($culture, "{0:0} GB", $gib) }
    return [string]::Format($culture, "{0:0.0} GB", $gib)
}

function Update-WinToolHomeCard {
    # Fills the three cards from the static PC info and the latest sample.
    $hs = $script:WinToolState.Home
    $dot = " " + [string][char]0x00B7 + " "
    $info = $hs.Info
    $sample = $hs.LastSample
    $memory = $hs.Minis["memory"]
    $disk = $hs.Minis["disk"]
    $pc = $hs.Minis["pc"]
    if ($null -ne $sample -and [double]$sample.MemoryTotal -gt 0) {
        $fraction = [double]$sample.MemoryUsed / [double]$sample.MemoryTotal
        Set-WinToolHomeMiniRing -Mini $memory -Fraction $fraction
        Set-WinToolHomeMiniTag -Mini $memory -Text ("{0:0}% used" -f ($fraction * 100)) -Tone "neutral"
        $memory.Value.Text = (Format-WinToolByteSize -Bytes ([double]$sample.MemoryUsed)) + " in use"
        $total = [double]$sample.MemoryTotal
        $kind = ""
        if ($null -ne $info) {
            if ([double]$info.MemoryTotal -gt 0) { $total = [double]$info.MemoryTotal }
            $kind = Get-WinToolMemoryTypeName -Code ([int]$info.MemoryType)
        }
        $text = (Format-WinToolHomeSize -Bytes $total) + " total"
        if (-not [string]::IsNullOrWhiteSpace($kind)) { $text += $dot + $kind }
        $memory.Detail.Text = $text
    }
    if ($null -ne $sample -and [double]$sample.DiskTotal -gt 0) {
        $free = [double]$sample.DiskFree / [double]$sample.DiskTotal
        Set-WinToolHomeMiniRing -Mini $disk -Fraction (1 - $free)
        Set-WinToolHomeMiniTag -Mini $disk -Text ("{0:0}% free" -f ($free * 100)) -Tone (Get-WinToolHomeDiskTone -FreePercent ($free * 100))
        $disk.Value.Text = (Format-WinToolByteSize -Bytes ([double]$sample.DiskFree)) + " free"
        $size = [double]$sample.DiskTotal
        $media = ""
        if ($null -ne $info) {
            if ([double]$info.DiskSize -gt 0) { $size = [double]$info.DiskSize }
            if (@("SSD", "HDD") -contains [string]$info.DiskMedia) { $media = " " + [string]$info.DiskMedia }
        }
        $letter = ([string]$env:SystemDrive)
        if ([string]::IsNullOrWhiteSpace($letter)) { $letter = "C:" }
        $disk.Detail.Text = (Format-WinToolHomeSize -Bytes $size -Decimal) + $media + $dot + "Drive " + $letter
    }
    if ($null -ne $info) {
        Set-WinToolHomeMiniRing -Mini $pc -Fraction 1
        if (-not [string]::IsNullOrWhiteSpace([string]$info.Os)) { $pc.Value.Text = [string]$info.Os }
        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace([string]$info.Version)) { $parts += [string]$info.Version }
        $cpu = Format-WinToolCpuName -Name ([string]$info.Cpu)
        if (-not [string]::IsNullOrWhiteSpace($cpu)) { $parts += $cpu }
        if ($parts.Count -gt 0) { $pc.Detail.Text = ($parts -join $dot) }
    }
    $driver = $hs.Results["drivers"]
    $diskHealth = $hs.Results["disk"]
    if ($hs.Phase -eq "analyzing" -or $null -eq $driver -or $null -eq $diskHealth) {
        Set-WinToolHomeMiniTag -Mini $pc -Text "Checking" -Tone "neutral"
    }
    elseif ($driver.Status -eq "bad" -or $diskHealth.Status -eq "bad") {
        Set-WinToolHomeMiniTag -Mini $pc -Text "Attention" -Tone "warn"
    }
    else {
        Set-WinToolHomeMiniTag -Mini $pc -Text "Healthy" -Tone "ok"
    }
}

function Add-WinToolHomeSample {
    param([Parameter(Mandatory = $true)]$Sample)
    $hs = $script:WinToolState.Home
    $hs.LastSample = $Sample
    if ([double]$Sample.MemoryTotal -gt 0) {
        Add-WinToolHomeSparkPoint -Mini $hs.Minis["memory"] -Value (100 * [double]$Sample.MemoryUsed / [double]$Sample.MemoryTotal)
    }
    Add-WinToolHomeSparkPoint -Mini $hs.Minis["disk"] -Value ([double]$Sample.DiskBusy)
    Add-WinToolHomeSparkPoint -Mini $hs.Minis["pc"] -Value ([double]$Sample.Cpu)
    Update-WinToolHomeCard
}

function Initialize-WinToolHomeView {
    $script:WinToolState.Home = @{
        Phase = "idle"
        Results = @{}
        Rows = @{}
        Minis = @{}
        Pending = @{}
        Started = $null
        Finished = $null
        Seconds = 0
        Score = $null
        Arc = 0.0
        ArcTarget = 0.0
        AnimStart = [DateTime]::Now
        Info = $null
        LastSample = $null
        WaitTweaks = $false
        Previous = $null
    }
    $hs = $script:WinToolState.Home
    $checkHost = Get-WinToolUi -Name "HomeChecks"
    $checks = @(Get-WinToolHomeCheckList)
    for ($i = 0; $i -lt $checks.Count; $i++) {
        $row = New-WinToolHomeRow -Check $checks[$i] -Last ($i -eq $checks.Count - 1)
        $hs.Rows[$row.Id] = $row
        $null = $checkHost.Children.Add($row.Border)
        Set-WinToolHomeRow -Row $row -Status "busy" -Text ("Waiting" + (Get-WinToolHomeEllipsis)) -Action "off"
    }
    $minis = Get-WinToolUi -Name "HomeMinis"
    $hs.Minis["memory"] = New-WinToolHomeMini -Key "memory" -Title "Memory" -Column 0 -From "#4C8DFF" -To "#8B5CF6" -Line "#8B7CF6"
    $hs.Minis["disk"] = New-WinToolHomeMini -Key "disk" -Title "Windows disk" -Column 2 -From "#F5B942" -To "#F07178" -Line "#F5A742"
    $hs.Minis["pc"] = New-WinToolHomeMini -Key "pc" -Title "This PC" -Column 4 -From "#3DD68C" -To "#4C8DFF" -Line "#4C8DFF"
    foreach ($key in @("memory", "disk", "pc")) { $null = $minis.Children.Add($hs.Minis[$key].Card) }
    Update-WinToolHomeCard

    $history = @(Read-WinToolHomeHistory)
    if ($history.Count -gt 0) { $hs.Previous = $history[-1] }
    (Get-WinToolUi -Name "HomeMetaText").Text = Format-WinToolHomeMeta -Last $hs.Previous
    Set-WinToolHomeArc -Angle 0
    Sync-WinToolHomeHeader

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "HomeAgain") -EventName "Click" -Name "Analyze again" -Action {
        Start-WinToolHomeAnalysis
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "HomeFixAll") -EventName "Click" -Name "Fix all" -Action {
        Invoke-WinToolHomeFixAll
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "HomeHistoryLink") -EventName "Click" -Name "View history" -Action {
        Show-WinToolHomeHistory
    }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "HomeScroll") -EventName "SizeChanged" -Name "Home height" -Action {
        Update-WinToolHomeLayout
    }
    Register-WinToolUiEvent -Control $script:WinToolWindow -EventName "Loaded" -Name "Start the Home analysis" -Action {
        Start-WinToolHomeTimer
        Start-WinToolHomeSampler
        Start-WinToolHomeAnalysis
    }
}

function Update-WinToolHomeLayout {
    # The cards row fills the rest of the page; a short window scrolls.
    $scroll = Get-WinToolUi -Name "HomeScroll"
    $body = Get-WinToolUi -Name "HomeBody"
    $body.MinHeight = [Math]::Max(0, [double]$scroll.ActualHeight - 16)
}

function Sync-WinToolHomeHeader {
    $hs = $script:WinToolState.Home
    $done = @($hs.Results.Values).Count
    $total = @(Get-WinToolHomeCheckList).Count
    $busyRing = Get-WinToolUi -Name "HomeRingBusy"
    $doneRing = Get-WinToolUi -Name "HomeRingDone"
    $fixAll = Get-WinToolUi -Name "HomeFixAll"
    $again = Get-WinToolUi -Name "HomeAgain"
    $headline = Get-WinToolUi -Name "HomeHeadline"
    $lead = Get-WinToolUi -Name "HomeLead"
    $count = Get-WinToolUi -Name "HomeCheckCount"
    (Get-WinToolUi -Name "HomeRingProgress").Text = "{0} of {1} checks" -f $done, $total
    switch ($hs.Phase) {
        "done" {
            $results = @($hs.Results.Values)
            $score = $hs.Score
            if ($null -eq $score) { $score = Get-WinToolHomeScore -Result $results }
            $verdict = Get-WinToolHomeVerdict -Score $score
            $fixable = @($results | Where-Object { $_.Fixable }).Count
            $busyRing.Visibility = "Collapsed"
            $doneRing.Visibility = "Visible"
            (Get-WinToolUi -Name "HomeScore").Text = [string]$score
            (Get-WinToolUi -Name "HomeVerdictText").Text = $verdict.Text
            $tone = @{ ok = @("BrushOkSoft", "BrushOk"); warn = @("BrushWarnSoft", "BrushWarn"); bad = @("BrushBadSoft", "BrushBad") }[$verdict.Tone]
            (Get-WinToolUi -Name "HomeVerdict").SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, $tone[0])
            (Get-WinToolUi -Name "HomeVerdictText").SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $tone[1])
            $headline.Text = "Analysis complete"
            $lead.Text = Get-WinToolHomeLead -Result $results
            $count.Text = "{0} of {1} can be fixed" -f $fixable, $total
            $fixAll.IsEnabled = ($fixable -gt 0)
            $again.IsEnabled = $true
            $hs.ArcTarget = 360.0 * $score / 100
        }
        "fixing" {
            $busyRing.Visibility = "Collapsed"
            $doneRing.Visibility = "Visible"
            $headline.Text = "Fixing" + (Get-WinToolHomeEllipsis)
            $lead.Text = "Only safe changes are made. You can keep using your PC."
            $count.Text = "{0} of {1} complete" -f $done, $total
            $fixAll.IsEnabled = $false
            $again.IsEnabled = $false
        }
        default {
            $busyRing.Visibility = "Visible"
            $doneRing.Visibility = "Collapsed"
            $headline.Text = "Analyzing your PC" + (Get-WinToolHomeEllipsis)
            $lead.Text = "Takes less than a minute. Nothing is changed during the analysis."
            $count.Text = "{0} of {1} complete" -f $done, $total
            $fixAll.IsEnabled = $false
            $again.IsEnabled = ($hs.Phase -eq "idle")
        }
    }
    Sync-WinToolHomeRunText
}

function Sync-WinToolHomeRunText {
    $hs = $script:WinToolState.Home
    $text = Get-WinToolUi -Name "HomeRunText"
    if ($null -eq $hs.Started) {
        $text.Text = " "
        return
    }
    switch ($hs.Phase) {
        "analyzing" { $text.Text = "Running for {0}s" -f [int]([DateTime]::Now - [datetime]$hs.Started).TotalSeconds }
        "fixing" { $text.Text = "Fixing" + (Get-WinToolHomeEllipsis) }
        default { $text.Text = "Finished in {0}s" -f [int]$hs.Seconds }
    }
}

function Start-WinToolHomeTimer {
    if ($null -ne $script:WinToolState.HomeTimer) { return }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    Register-WinToolUiEvent -Control $timer -EventName "Tick" -Name "Home refresh" -Action { Update-WinToolHomePoll }
    $timer.Start()
    $script:WinToolState.HomeTimer = $timer
    $animation = New-Object System.Windows.Threading.DispatcherTimer
    $animation.Interval = [TimeSpan]::FromMilliseconds(16)
    Register-WinToolUiEvent -Control $animation -EventName "Tick" -Name "Home ring" -Action { Update-WinToolHomeAnimation }
    $script:WinToolState.HomeAnimTimer = $animation
}

function Start-WinToolHomeAnimation {
    if ((Test-WinToolHomeReduceMotion) -or $null -eq $script:WinToolState.HomeAnimTimer) {
        $hs = $script:WinToolState.Home
        if ($hs.Phase -eq "analyzing") {
            $done = @($hs.Results.Values).Count
            Set-WinToolHomeArc -Angle ([Math]::Max(24, 360.0 * $done / 5 * 0.9))
        }
        else {
            Set-WinToolHomeArc -Angle $hs.ArcTarget
        }
        return
    }
    $script:WinToolState.HomeAnimTimer.Start()
}

function Update-WinToolHomeAnimation {
    # While analyzing the arc grows and shrinks; afterwards it eases to the score.
    $hs = $script:WinToolState.Home
    if ($hs.Phase -eq "analyzing") {
        $t = ([DateTime]::Now - [datetime]$hs.AnimStart).TotalSeconds
        $wave = 0.5 - 0.5 * [Math]::Cos(2 * [Math]::PI * $t / 2.4)
        Set-WinToolHomeArc -Angle (50 + 260 * $wave)
        return
    }
    $diff = [double]$hs.ArcTarget - [double]$hs.Arc
    if ([Math]::Abs($diff) -lt 0.4) {
        Set-WinToolHomeArc -Angle $hs.ArcTarget
        $script:WinToolState.HomeAnimTimer.Stop()
        return
    }
    Set-WinToolHomeArc -Angle ([double]$hs.Arc + $diff * 0.14)
}

function Start-WinToolHomeCheck {
    # Starts one check in its own runspace. Tests set WinToolHomeNoJobs and
    # feed the results through Complete-WinToolHomeCheck.
    param([Parameter(Mandatory = $true)][string]$Id)
    $hs = $script:WinToolState.Home
    $hs.Pending[$Id] = $true
    $hs.Results.Remove($Id)
    Set-WinToolHomeRow -Row $hs.Rows[$Id] -Status "busy" -Text ("Checking" + (Get-WinToolHomeEllipsis)) -Action "off"
    if ($script:WinToolHomeNoJobs) { return }
    $key = "HomeJob_" + $Id
    Stop-WinToolThread -Job $script:WinToolState[$key]
    try {
        $scriptText = Get-WinToolHomeCheckScript -Id $Id
        switch ($Id) {
            "junk" { $job = Start-WinToolHomeJob -ScriptText $scriptText -Argument @(, @(Get-WinToolHomeJunkLocation)) }
            "tweaks" {
                $recommended = @(Get-WinToolPresetTweak -Catalog (Get-WinToolTweakCatalog) -PresetId "recommended")
                $job = Start-WinToolHomeJob -ScriptText $scriptText -Argument @(, $recommended) -WithWinTool
            }
            default { $job = Start-WinToolHomeJob -ScriptText $scriptText }
        }
        $script:WinToolState[$key] = $job
    }
    catch {
        Complete-WinToolHomeCheck -Id $Id -ErrorMessage $_.Exception.Message
    }
}

function Complete-WinToolHomeCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        $Data,
        [string]$ErrorMessage
    )
    $hs = $script:WinToolState.Home
    $result = ConvertTo-WinToolHomeResult -Id $Id -Data $Data -ErrorMessage $ErrorMessage
    $hs.Results[$Id] = $result
    $hs.Pending.Remove($Id)
    $action = [string]$result.Action
    Set-WinToolHomeRow -Row $hs.Rows[$Id] -Status $result.Status -Text $result.Text -Action $action -Fade
    if ($result.Status -eq "unknown" -and @($result.Detail).Count -gt 0) {
        Write-WinToolLog -Message ("Home: {0} could not be checked. {1}" -f $result.Name, (@($result.Detail) -join " ")) -Level "warn" -Diagnostic
    }
    if ($hs.Phase -eq "analyzing") {
        Sync-WinToolHomeHeader
        if ($hs.Pending.Count -eq 0) { Complete-WinToolHomeAnalysis }
        elseif (Test-WinToolHomeReduceMotion) { Start-WinToolHomeAnimation }
        return
    }
    Test-WinToolHomeFixDone
}

function Start-WinToolHomeAnalysis {
    $hs = $script:WinToolState.Home
    if ($null -eq $hs -or $hs.Phase -eq "analyzing" -or $hs.Phase -eq "fixing") { return }
    $hs.Phase = "analyzing"
    $hs.Results = @{}
    $hs.Pending = @{}
    $hs.Score = $null
    $hs.Started = [DateTime]::Now
    $hs.AnimStart = [DateTime]::Now
    Sync-WinToolHomeHeader
    foreach ($check in @(Get-WinToolHomeCheckList)) {
        Start-WinToolHomeCheck -Id $check.Id
    }
    Update-WinToolHomeCard
    Start-WinToolHomeAnimation
    if ($hs.Phase -eq "analyzing" -and $hs.Pending.Count -eq 0) { Complete-WinToolHomeAnalysis }
}

function Complete-WinToolHomeAnalysis {
    $hs = $script:WinToolState.Home
    $hs.Phase = "done"
    $hs.Finished = [DateTime]::Now
    $hs.Seconds = [int][Math]::Max(1, ([datetime]$hs.Finished - [datetime]$hs.Started).TotalSeconds)
    $results = @($hs.Results.Values)
    $score = Get-WinToolHomeScore -Result $results
    $hs.Score = $score
    if (-not $script:WinToolHomeNoJobs) {
        Add-WinToolHomeHistory -Time $hs.Finished -Score $score -Seconds $hs.Seconds
    }
    $hs.Previous = [pscustomobject]@{ Time = $hs.Finished; Score = $score; Seconds = $hs.Seconds }
    (Get-WinToolUi -Name "HomeMetaText").Text = Format-WinToolHomeMeta -Last $hs.Previous
    Sync-WinToolHomeHeader
    Update-WinToolHomeCard
    Start-WinToolHomeAnimation
    Write-WinToolLog -Message ("Home: analysis finished in {0}s, score {1}." -f $hs.Seconds, $score) -Level "info" -Diagnostic
}

function Start-WinToolHomeInfo {
    if ($script:WinToolHomeNoJobs -or $null -ne $script:WinToolState.HomeInfoJob) { return }
    $script:WinToolState.HomeInfoJob = Start-WinToolHomeJob -ScriptText (Get-WinToolHomeCheckScript -Id "info")
}

function Start-WinToolHomeSampler {
    if ($script:WinToolHomeNoJobs) { return }
    Start-WinToolHomeInfo
    if ($null -ne $script:WinToolState.HomeSampler) { return }
    $script:WinToolState.HomeSampler = Start-WinToolHomeJob -ScriptText (Get-WinToolHomeCheckScript -Id "sampler")
}

function Update-WinToolHomePoll {
    $hs = $script:WinToolState.Home
    if ($null -eq $hs) { return }
    foreach ($check in @(Get-WinToolHomeCheckList)) {
        $key = "HomeJob_" + $check.Id
        $job = $script:WinToolState[$key]
        if ($null -eq $job -or -not $job.Sync.Done) { continue }
        $data = $job.Sync.Data
        $errorText = [string]$job.Sync.Error
        Stop-WinToolThread -Job $job
        $script:WinToolState[$key] = $null
        Complete-WinToolHomeCheck -Id $check.Id -Data $data -ErrorMessage $errorText
    }
    $clean = $script:WinToolState.HomeCleanJob
    if ($null -ne $clean -and $clean.Sync.Done) {
        $freed = [double]$clean.Sync.Data
        $errorText = [string]$clean.Sync.Error
        Stop-WinToolThread -Job $clean
        $script:WinToolState.HomeCleanJob = $null
        if ([string]::IsNullOrWhiteSpace($errorText)) {
            Write-WinToolLog -Message ("Junk files: freed {0}. Files in use were skipped." -f (Format-WinToolByteSize -Bytes $freed)) -Level "ok"
        }
        else {
            Write-WinToolLog -Message ("Junk files: cleaning stopped. {0}" -f $errorText) -Level "warn"
        }
        Start-WinToolHomeCheck -Id "junk"
    }
    if ($hs.WaitTweaks -and $null -eq $script:WinToolState.TweakQueue -and $null -eq $script:WinToolState.RestoreJob -and -not $script:WinToolState.Busy) {
        $hs.WaitTweaks = $false
        Start-WinToolHomeCheck -Id "tweaks"
    }
    $info = $script:WinToolState.HomeInfoJob
    if ($null -ne $info -and $info.Sync.Done -and $null -eq $hs.Info) {
        $hs.Info = $info.Sync.Data
        if ($null -eq $hs.Info) { $hs.Info = [pscustomobject]@{ Os = ""; Version = ""; Cpu = ""; MemoryTotal = 0; MemoryType = 0; DiskSize = 0; DiskMedia = "" } }
        Update-WinToolHomeCard
    }
    $sampler = $script:WinToolState.HomeSampler
    if ($null -ne $sampler) {
        $sampler.Sync.Paused = ((Get-WinToolUi -Name "ViewHome").Visibility -ne "Visible")
        $sample = $null
        while ($sampler.Sync.Queue.TryDequeue([ref]$sample)) {
            Add-WinToolHomeSample -Sample $sample
        }
    }
    if ($hs.Phase -eq "analyzing") { Sync-WinToolHomeRunText }
}

function Test-WinToolHomeFixDone {
    $hs = $script:WinToolState.Home
    if ($hs.Phase -ne "fixing") { return }
    if ($hs.Pending.Count -gt 0 -or $hs.WaitTweaks -or $null -ne $script:WinToolState.HomeCleanJob) { return }
    $hs.Phase = "done"
    $results = @($hs.Results.Values)
    $hs.Score = Get-WinToolHomeScore -Result $results
    Sync-WinToolHomeHeader
    Update-WinToolHomeCard
    Start-WinToolHomeAnimation
}

function Start-WinToolHomeClean {
    $hs = $script:WinToolState.Home
    $hs.Phase = "fixing"
    $hs.Pending["junk"] = $true
    $hs.Results.Remove("junk")
    Set-WinToolHomeRow -Row $hs.Rows["junk"] -Status "busy" -Text ("Cleaning" + (Get-WinToolHomeEllipsis)) -Action "off"
    Sync-WinToolHomeHeader
    Write-WinToolLog -Message "Junk files: cleaning temporary files, the Recycle Bin and caches." -Level "info"
    if ($script:WinToolHomeNoJobs) { return }
    $script:WinToolState.HomeCleanJob = Start-WinToolHomeJob -ScriptText (Get-WinToolHomeCheckScript -Id "clean") -Argument @(, @(Get-WinToolHomeJunkLocation))
}

function Start-WinToolHomeTweakFix {
    # Uses the Tweaks page's own apply path: same confirmation, same restore point.
    param([switch]$NoConfirm)
    $hs = $script:WinToolState.Home
    if (-not $script:WinToolState.TweakStateRead) { Update-WinToolTweakState }
    $ids = @(Get-WinToolPresetTweak -Catalog (Get-WinToolTweakCatalog) -PresetId "recommended" | ForEach-Object { [string]$_.id })
    $script:WinToolState.TweakRequestStarted = $false
    Request-WinToolTweakOn -Id $ids -Label "the Recommended preset" -NoConfirm:$NoConfirm
    if (-not $script:WinToolState.TweakRequestStarted) {
        return $false
    }
    $hs.Phase = "fixing"
    $hs.WaitTweaks = $true
    $hs.Pending["tweaks"] = $true
    $hs.Results.Remove("tweaks")
    Set-WinToolHomeRow -Row $hs.Rows["tweaks"] -Status "busy" -Text ("Applying" + (Get-WinToolHomeEllipsis)) -Action "off"
    Sync-WinToolHomeHeader
    return $true
}

function Get-WinToolHomeJunkPrompt {
    $result = $script:WinToolState.Home.Results["junk"]
    $lines = @($result.Detail | ForEach-Object { "- " + $_ })
    return ("Delete {0} of junk files?`n`n{1}`n`nTemporary files from the last day and files in use are kept." -f (Format-WinToolByteSize -Bytes ([double]$result.Amount)), ($lines -join "`n"))
}

function Invoke-WinToolHomeAction {
    param([Parameter(Mandatory = $true)][string]$Id)
    $hs = $script:WinToolState.Home
    $result = $hs.Results[$Id]
    if ($hs.Phase -ne "done" -or $null -eq $result) { return }
    if ($result.Action -eq "review") {
        Show-WinToolHomeReview -Result $result
        return
    }
    if ($result.Action -ne "fix") { return }
    if ($Id -eq "junk") {
        if (Request-WinToolConfirmation -Message (Get-WinToolHomeJunkPrompt) -Title "Junk files") {
            Start-WinToolHomeClean
        }
        return
    }
    if ($Id -eq "tweaks") {
        $null = Start-WinToolHomeTweakFix
    }
}

function Invoke-WinToolHomeFixAll {
    $hs = $script:WinToolState.Home
    if ($hs.Phase -ne "done") { return }
    $fixable = @($hs.Results.Values | Where-Object { $_.Fixable })
    if ($fixable.Count -eq 0) { return }
    $lines = New-Object System.Collections.Generic.List[string]
    $junk = $hs.Results["junk"]
    $tweaks = $hs.Results["tweaks"]
    if ($null -ne $junk -and $junk.Fixable) { $lines.Add(("- Delete {0} of junk files (recent and in-use files are kept)" -f (Format-WinToolByteSize -Bytes ([double]$junk.Amount)))) }
    if ($null -ne $tweaks -and $tweaks.Fixable) { $lines.Add(("- Turn on {0} Recommended tweak(s); WinTool creates a restore point first" -f [int]$tweaks.Amount)) }
    $ok = Request-WinToolConfirmation -Message ("Fix {0} item(s)?`n`n{1}`n`nNothing else is changed." -f $lines.Count, ($lines -join "`n")) -Title "Fix all"
    if (-not $ok) { return }
    if ($null -ne $tweaks -and $tweaks.Fixable) { $null = Start-WinToolHomeTweakFix -NoConfirm }
    if ($null -ne $junk -and $junk.Fixable) { Start-WinToolHomeClean }
}

function Show-WinToolHomeReview {
    param([Parameter(Mandatory = $true)]$Result)
    $lines = @($Result.Detail | Select-Object -First 15 | ForEach-Object { "- " + $_ })
    if (@($Result.Detail).Count -gt 15) { $lines += "- ..." }
    $list = $lines -join "`n"
    switch ($Result.Id) {
        "startup" {
            if (Request-WinToolConfirmation -Message ("{0}:`n`n{1}`n`nOpen Task Manager to turn programs off?" -f $Result.Text, $list) -Title "Startup programs") {
                try { Start-Process -FilePath "taskmgr.exe" -ArgumentList "/0 /startup" } catch { Write-WinToolLog -Message ("Could not open Task Manager. {0}" -f $_.Exception.Message) -Level "warn" }
            }
        }
        "drivers" {
            if (Request-WinToolConfirmation -Message ("{0}:`n`n{1}`n`nOpen Device Manager?" -f $Result.Text, $list) -Title "Drivers") {
                try { Start-Process -FilePath "devmgmt.msc" } catch { Write-WinToolLog -Message ("Could not open Device Manager. {0}" -f $_.Exception.Message) -Level "warn" }
            }
        }
        "disk" {
            if (Request-WinToolConfirmation -Message ("{0}:`n`n{1}`n`nBack up your files soon. Open Disks and volumes in Settings?" -f $Result.Text, $list) -Title "Disk health") {
                try { Start-Process -FilePath "ms-settings:disksandvolumes" } catch { Write-WinToolLog -Message ("Could not open Settings. {0}" -f $_.Exception.Message) -Level "warn" }
            }
        }
    }
}

function Show-WinToolHomeHistory {
    $items = @(Read-WinToolHomeHistory | Select-Object -Last 10)
    if ($items.Count -eq 0) {
        $null = [System.Windows.MessageBox]::Show("No analysis was saved yet.", "History")
        return
    }
    [array]::Reverse($items)
    $lines = @($items | ForEach-Object { "{0}    Score {1}    {2}s" -f (Format-WinToolHomeWhen -Time ([datetime]$_.Time)), [int]$_.Score, [int]$_.Seconds })
    $null = [System.Windows.MessageBox]::Show(($lines -join "`n"), "History")
}
