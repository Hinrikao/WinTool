# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Open the real WinTool window on PowerShell 7, time startup, and fail on a crash.
.DESCRIPTION
    Runs ShowDialog for several seconds, warms the Terminal theme list, captures
    the first painted frame, and fails if that frame is a white window or if an
    exception escapes the dispatcher.
#>
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "Skipping the startup test: this test runs on Windows."
    exit 0
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "The startup test must run on PowerShell 7 (pwsh -STA)."
}

$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apartment -ne "STA") {
    throw "Run the startup test with pwsh -STA. The current apartment is $apartment."
}

$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolApplyProfile = $null
$script:WinToolUnattended = $false
$script:WinToolShowConsole = $false
$script:WinToolEntryPath = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()
$env:WINTOOL_HIDDEN = "1"
$log = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-startup-" + [guid]::NewGuid().ToString("N") + ".log")
$env:WINTOOL_STARTUP_LOG = $log
$script:StartupShot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-first-frame-" + [guid]::NewGuid().ToString("N") + ".png")
if (-not [string]::IsNullOrWhiteSpace($env:WINTOOL_SHOT_DIR)) {
    if (-not (Test-Path -LiteralPath $env:WINTOOL_SHOT_DIR)) {
        New-Item -ItemType Directory -Path $env:WINTOOL_SHOT_DIR -Force | Out-Null
    }
    $script:StartupShot = Join-Path $env:WINTOOL_SHOT_DIR "startup-first-frame.png"
}

foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
}

Initialize-WinToolLocale -Language en -Force | Out-Null
$script:WinToolStartupStamp = [System.Diagnostics.Stopwatch]::StartNew()
$script:StartupErrors = New-Object System.Collections.Generic.List[string]
$script:StartupWhiteShare = -1
$script:StartupShown = $false

function Save-WinToolStartupFrame {
    param($Window)
    if ($null -eq $Window) { return }
    $width = [Math]::Max(1, [int]$Window.ActualWidth)
    $height = [Math]::Max(1, [int]$Window.ActualHeight)
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $backdrop = New-Object System.Windows.Media.DrawingVisual
    $context = $backdrop.RenderOpen()
    $brush = $Window.Background
    if ($null -eq $brush) { $brush = [System.Windows.Media.Brushes]::Black }
    $context.DrawRectangle($brush, $null, [System.Windows.Rect]::new(0, 0, $width, $height))
    $context.Close()
    $bitmap.Render($backdrop)
    $bitmap.Render($Window)
    $pixels = New-Object byte[] ($width * $height * 4)
    $bitmap.CopyPixels($pixels, $width * 4, 0)
    $white = 0
    $sampled = 0
    for ($i = 0; $i -lt $pixels.Length; $i += 16) {
        $b = [int]$pixels[$i]
        $g = [int]$pixels[$i + 1]
        $r = [int]$pixels[$i + 2]
        $a = [int]$pixels[$i + 3]
        if ($a -lt 16) { continue }
        $sampled++
        if ($r -ge 240 -and $g -ge 240 -and $b -ge 240) { $white++ }
    }
    if ($sampled -gt 0) {
        $script:StartupWhiteShare = [math]::Round((100.0 * $white) / $sampled, 1)
    }
    try {
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [System.IO.File]::Create($script:StartupShot)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    catch {
        $null = $_.Exception.Message
    }
}

$parseMs = $null
$built = Join-Path $script:WinToolRoot "wintool.ps1"
if (Test-Path -LiteralPath $built) {
    $parseStamp = [System.Diagnostics.Stopwatch]::StartNew()
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($built, [ref]$tokens, [ref]$parseErrors)
    $parseMs = [int]$parseStamp.ElapsedMilliseconds
    if (@($parseErrors).Count -gt 0) {
        throw ("wintool.ps1 does not parse: " + $parseErrors[0].ToString())
    }
    Write-Output ("wintool.ps1 parse: {0} ms ({1:N1} MB)" -f $parseMs, ((Get-Item -LiteralPath $built).Length / 1MB))
}

try {
    $window = New-WinToolWindow -DeferViews
    $script:WinToolSessionExit = $false
    Register-WinToolUiEvent -Control $window -EventName "ContentRendered" -Name "Startup first frame" -Action {
        $window = $script:WinToolWindow
        try {
            Show-WinToolWindowAfterRender -Window $window
            $window.UpdateLayout()
            Save-WinToolStartupFrame -Window $window
            $script:StartupShown = $true
        }
        catch {
            [void]$script:StartupErrors.Add($_.Exception.Message)
        }
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(8)
    $timer.add_Tick({
            $timer.Stop()
            if ($null -ne $script:WinToolWindow) { $script:WinToolWindow.Close() }
        }.GetNewClosure())
    $timer.Start()
    $null = $window.ShowDialog()
}
catch {
    [void]$script:StartupErrors.Add($_.Exception.Message)
    throw
}
finally {
    try { Stop-WinToolBackgroundWork } catch { $null = $_.Exception.Message }
}

$uiErrors = @()
try { $uiErrors = @(Get-WinToolUiError) } catch { $null = $_.Exception.Message }
foreach ($uiError in $uiErrors) {
    [void]$script:StartupErrors.Add(([string]$uiError.Name + ": " + [string]$uiError.Message))
}

if ($null -ne $script:WinToolStartupMarks) {
    if ($null -ne $parseMs) { $script:WinToolStartupMarks["scriptParseMs"] = $parseMs }
    Write-WinToolStartupLog
    foreach ($key in @($script:WinToolStartupMarks.Keys)) {
        Write-Output ("startup {0}: {1} ms" -f $key, $script:WinToolStartupMarks[$key])
    }
}

if (-not $script:StartupShown) {
    throw "The WinTool window never reached its first painted frame."
}
if ([double]$script:StartupWhiteShare -ge 20) {
    throw ("The first painted frame is too white ({0}% near-white pixels). Shot: {1}" -f $script:StartupWhiteShare, $script:StartupShot)
}
Write-Output ("First painted frame is not white ({0}% near-white). Shot: {1}" -f $script:StartupWhiteShare, $script:StartupShot)

if ($script:StartupErrors.Count -gt 0) {
    throw ("Startup failed: " + ($script:StartupErrors -join "; "))
}
Write-Output "ShowDialog ran with theme warmup and did not crash."
exit 0
