# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Open the real WinTool window on PowerShell 7, time startup, and fail on a crash.
.DESCRIPTION
    Runs ShowDialog for 20 seconds with a dispatcher heartbeat, prints a phase
    table and any dispatcher gaps, captures the first painted frame, and fails
    if that frame is a white window or if an exception escapes the dispatcher.
    This audit run records timings and does not yet fail the first-frame budget.
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

$sourceMarks = [ordered]@{}
$sourceStamp = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    $fileStamp = [System.Diagnostics.Stopwatch]::StartNew()
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
    $sourceMarks[$trimmed] = [int]$fileStamp.ElapsedMilliseconds
}
$sourceMs = [int]$sourceStamp.ElapsedMilliseconds

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
            Write-WinToolStartupMark -Name "firstFrameMs"
        }
        catch {
            [void]$script:StartupErrors.Add($_.Exception.Message)
        }
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(20)
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
try { $uiErrors = @(@(Get-WinToolUiError) | Where-Object { $null -ne $_ }) } catch { $null = $_.Exception.Message }
foreach ($uiError in $uiErrors) {
    $name = [string]$uiError.Name
    $message = [string]$uiError.Message
    if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($message)) { continue }
    [void]$script:StartupErrors.Add(($name + ": " + $message))
}

if ($null -ne $sourceMs) {
    Write-Output ("source tree: {0} ms" -f $sourceMs)
    foreach ($key in @($sourceMarks.Keys)) {
        if ([int]$sourceMarks[$key] -ge 5) {
            Write-Output ("source {0}: {1} ms" -f $key, $sourceMarks[$key])
        }
    }
}
if ($null -ne $script:WinToolStartupMarks) {
    if ($null -ne $parseMs) { $script:WinToolStartupMarks["scriptParseMs"] = $parseMs }
    if ($null -ne $sourceMs) { $script:WinToolStartupMarks["sourceTreeMs"] = $sourceMs }
    Write-WinToolStartupLog
}
Write-WinToolStartupPhaseTable
if ($null -ne $script:WinToolState -and $null -ne $script:WinToolState.Home) {
    $hs = $script:WinToolState.Home
    $done = @($hs.Results.Keys) -join ","
    Write-Output ("Home analysis phase={0} results={1} pending={2}" -f [string]$hs.Phase, $done, $hs.Pending.Count)
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
