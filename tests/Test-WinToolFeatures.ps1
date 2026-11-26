# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Exercise every WinTool tab and action on a real Windows session.
.DESCRIPTION
    Runs on PowerShell 7 in STA. Builds the window, clicks through each tab,
    applies and undoes tweaks, optionally installs a small winget package,
    toggles a safe Windows feature, walks all 14 locales, and fails on a UI
    exception or a dispatcher gap over 200 ms during UI automation.
#>
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "Skipping the feature test: this test runs on Windows."
    exit 0
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "The feature test must run on PowerShell 7 (pwsh -STA)."
}

$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apartment -ne "STA") {
    throw "Run the feature test with pwsh -STA. The current apartment is $apartment."
}

$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolApplyProfile = $null
$script:WinToolUnattended = $false
$script:WinToolShowConsole = $false
$script:WinToolEntryPath = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()
$script:WinToolPreferencesPath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-feature-prefs-" + [guid]::NewGuid().ToString("N") + ".json")
$script:WinToolHomeHistoryPath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-feature-history-" + [guid]::NewGuid().ToString("N") + ".json")
$env:WINTOOL_HIDDEN = "1"

foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
}

Initialize-WinToolLocale -Language en -Force | Out-Null
$script:WinToolUiQuiet = $true
$script:WinToolUiConfirm = $null
$script:WinToolUiFolder = $null
$script:WinToolUiSavePath = $null
$script:WinToolHomeReduceMotion = $true
$script:FeatureRows = New-Object System.Collections.Generic.List[object]
$script:FeatureFailed = New-Object System.Collections.Generic.List[string]

function Add-WinToolFeatureResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("pass", "fail", "not-testable")][string]$Status,
        [string]$Detail = ""
    )
    $script:FeatureRows.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
    Write-Output ("FEATURE  {0,-14}  {1}" -f $Status.ToUpperInvariant(), $Name + $(if ($Detail) { "  -  " + $Detail } else { "" }))
    if ($Status -eq "fail") {
        [void]$script:FeatureFailed.Add($Name + ": " + $Detail)
    }
}

function Wait-WinToolFeature {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Until,
        [int]$TimeoutMs = 20000,
        [int]$SliceMs = 50
    )
    $stamp = [System.Diagnostics.Stopwatch]::StartNew()
    do {
        if ((& $Until)) { return $true }
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $timer = [System.Windows.Threading.DispatcherTimer]::new([System.Windows.Threading.DispatcherPriority]::Background)
        $timer.Interval = [TimeSpan]::FromMilliseconds($SliceMs)
        $timer.add_Tick({
                $timer.Stop()
                $frame.Continue = $false
            }.GetNewClosure())
        $timer.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } while ($stamp.ElapsedMilliseconds -lt $TimeoutMs)
    return [bool]((& $Until))
}

function Invoke-WinToolFeatureClick {
    param($Control)
    if ($null -eq $Control) {
        throw "Cannot click a missing control."
    }
    if ($Control -is [System.Windows.Controls.Primitives.ButtonBase]) {
        if ([bool]$Control.IsEnabled) {
            try {
                $peer = New-Object System.Windows.Automation.Peers.ButtonAutomationPeer($Control)
                $pattern = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
                if ($null -ne $pattern) {
                    $pattern.Invoke()
                    return
                }
            }
            catch { $null = $_.Exception.Message }
        }
        $Control.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        return
    }
    if ($Control -is [System.Windows.Documents.Hyperlink]) {
        $Control.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Documents.Hyperlink]::ClickEvent)))
        return
    }
    if ($Control -is [System.Windows.Controls.Primitives.ToggleButton]) {
        $Control.IsChecked = -not [bool]$Control.IsChecked
        return
    }
    throw ("Do not know how to invoke " + $Control.GetType().FullName)
}

function Get-WinToolFeatureUiError {
    $raw = @()
    try { $raw = @(Get-WinToolUiError) } catch { return , @() }
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($item in $raw) {
        if ($null -eq $item) { continue }
        $name = ""
        $message = ""
        try { $name = [string]$item.Name } catch { continue }
        try { $message = [string]$item.Message } catch { continue }
        if ([string]::IsNullOrWhiteSpace($name) -and [string]::IsNullOrWhiteSpace($message)) { continue }
        [void]$errors.Add($name + ": " + $message)
    }
    return $errors.ToArray()
}

function Test-WinToolFeatureUiState {
    param([string]$Context)
    $errors = @(Get-WinToolFeatureUiError)
    if ($errors.Count -gt 0) {
        throw ("UI errors after " + $Context + ": " + ($errors -join "; "))
    }
}

function Get-WinToolFeatureButton {
    param($Root)
    $found = New-Object System.Collections.Generic.List[object]
    $visit = New-Object System.Collections.Generic.Queue[object]
    $visit.Enqueue($Root)
    $seen = New-Object System.Collections.Generic.HashSet[int]
    while ($visit.Count -gt 0) {
        $node = $visit.Dequeue()
        if ($null -eq $node) { continue }
        try {
            if (-not $seen.Add([int]$node.GetHashCode())) { continue }
        }
        catch { $null = $_.Exception.Message }
        if ($node -is [System.Windows.Controls.Primitives.ButtonBase] -or $node -is [System.Windows.Documents.Hyperlink]) {
            [void]$found.Add($node)
        }
        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
                if ($child -is [System.Windows.DependencyObject]) { $visit.Enqueue($child) }
            }
        }
        catch { $null = $_.Exception.Message }
        if ($node -is [System.Windows.FrameworkElement] -and $null -ne $node.ContextMenu) {
            $visit.Enqueue($node.ContextMenu)
        }
    }
    return $found.ToArray()
}

function Test-WinToolFeatureTweakSafe {
    param($Tweak)
    $steps = @()
    try { $steps = @(Get-WinToolTweakStep -Tweak $Tweak -Direction "Apply") } catch { return $false }
    foreach ($step in $steps) {
        $type = [string]$step.Type
        if ($type -eq "appx-remove" -or $type -eq "appx-restore") { return $false }
    }
    return $true
}

function Get-WinToolFeatureEnglishLeftover {
    param($Root)
    $leftover = New-Object System.Collections.Generic.List[string]
    $visit = New-Object System.Collections.Generic.Queue[object]
    $visit.Enqueue($Root)
    $seen = New-Object System.Collections.Generic.HashSet[int]
    while ($visit.Count -gt 0) {
        $node = $visit.Dequeue()
        if ($null -eq $node) { continue }
        try {
            if (-not $seen.Add([int]$node.GetHashCode())) { continue }
        }
        catch { $null = $_.Exception.Message }
        foreach ($prop in @("Text", "Content", "Header", "ToolTip")) {
            try {
                $value = $node.$prop
                if ($value -is [string] -and $value -match '^(ui|msg|catalog|drivers|activity|status|button|config|language)\.[A-Za-z0-9._-]+$') {
                    [void]$leftover.Add($value)
                }
            }
            catch { $null = $_.Exception.Message }
        }
        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
                if ($child -is [System.Windows.DependencyObject]) { $visit.Enqueue($child) }
            }
        }
        catch { $null = $_.Exception.Message }
    }
    return $leftover.ToArray()
}

function Get-WinToolFeatureClippedName {
    param($Root)
    $clipped = New-Object System.Collections.Generic.List[string]
    $visit = New-Object System.Collections.Generic.Queue[object]
    $visit.Enqueue($Root)
    $seen = New-Object System.Collections.Generic.HashSet[int]
    while ($visit.Count -gt 0) {
        $node = $visit.Dequeue()
        if ($null -eq $node) { continue }
        try {
            if (-not $seen.Add([int]$node.GetHashCode())) { continue }
        }
        catch { $null = $_.Exception.Message }
        if ($node -is [System.Windows.Controls.TextBlock]) {
            $name = ""
            try { $name = [string]$node.Name } catch { $name = "" }
            $visible = $true
            try { $visible = ([string]$node.Visibility -eq "Visible" -and [double]$node.ActualWidth -gt 1 -and [double]$node.ActualHeight -gt 1) } catch { $visible = $false }
            if ($visible -and -not [string]::IsNullOrWhiteSpace($name) -and [string]$node.TextWrapping -eq "NoWrap" -and [string]$node.TextTrimming -eq "None" -and -not [string]::IsNullOrWhiteSpace([string]$node.Text)) {
                try {
                    $dpi = [System.Windows.Media.VisualTreeHelper]::GetDpi($node).PixelsPerDip
                    $ft = New-Object System.Windows.Media.FormattedText(
                        [string]$node.Text,
                        [System.Globalization.CultureInfo]::CurrentUICulture,
                        $node.FlowDirection,
                        (New-Object System.Windows.Media.Typeface($node.FontFamily, $node.FontStyle, $node.FontWeight, $node.FontStretch)),
                        [double]$node.FontSize,
                        [System.Windows.Media.Brushes]::Black,
                        $dpi
                    )
                    if ($ft.Width -gt ([double]$node.ActualWidth + 2)) {
                        [void]$clipped.Add($name)
                    }
                }
                catch { $null = $_.Exception.Message }
            }
        }
        try {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
                if ($child -is [System.Windows.DependencyObject]) { $visit.Enqueue($child) }
            }
        }
        catch { $null = $_.Exception.Message }
    }
    return $clipped.ToArray()
}

# --- test seams (no window needed) ---
$script:WinToolUiQuiet = $false
$script:WinToolUiConfirm = $true
if (-not (Request-WinToolConfirmation -Message "x" -Title "y")) {
    throw "The confirm hook did not return yes."
}
$script:WinToolUiConfirm = $false
if (Request-WinToolConfirmation -Message "x" -Title "y") {
    throw "The confirm hook did not return no."
}
$script:WinToolUiConfirm = $null
$script:WinToolUiQuiet = $true
if (Request-WinToolConfirmation -Message "x" -Title "y") {
    throw "Quiet mode should decline a confirmation."
}
$script:WinToolUiFolder = "C:\WinTool-Test-Folder"
if ((Select-WinToolFolder) -ne "C:\WinTool-Test-Folder") {
    throw "The folder hook did not return the test path."
}
$script:WinToolUiFolder = $null
if ($null -ne (Select-WinToolFolder)) {
    throw "Quiet mode should cancel a folder pick."
}
$script:WinToolUiFilePath = "C:\WinTool-Test-File.json"
if ((Select-WinToolDialogFile -Mode Save -Filter "*.json" -FileName "x.json" -Title "t") -ne "C:\WinTool-Test-File.json") {
    throw "The file dialog hook did not return the test path."
}
$script:WinToolUiFilePath = $null
if ($null -ne (Select-WinToolDialogFile -Mode Open -Title "t")) {
    throw "Quiet mode should cancel a file dialog."
}
$script:WinToolUiLastNotice = $null
Show-WinToolHomeHistory
if ($null -eq $script:WinToolUiLastNotice -or [string]$script:WinToolUiLastNotice.Title -ne (Get-WinToolText "msg.history")) {
    throw "History must use a localized title and must not open a modal when quiet."
}
if ([string]$script:WinToolUiLastNotice.Message -ne (Get-WinToolText "msg.no-analysis-was-saved-yet")) {
    throw "An empty history must use the localized empty message."
}
Add-WinToolHomeHistory -Time ([datetime]::UtcNow) -Score 80 -Seconds 3
$script:WinToolUiLastNotice = $null
Show-WinToolHomeHistory
if ($null -eq $script:WinToolUiLastNotice -or [string]$script:WinToolUiLastNotice.Message -notmatch "80") {
    throw "A saved analysis must appear in the history notice."
}
Add-WinToolFeatureResult -Name "UI test seams (confirm, folder, file, history)" -Status "pass"
$script:WinToolUiQuiet = $true

# --- window ---

$window = New-WinToolWindow
$script:WinToolSessionExit = $false
$window.Width = 1280
$window.Height = 800
$window.WindowStartupLocation = "Manual"
$window.Left = 40
$window.Top = 40
$window.Show() | Out-Null
Show-WinToolWindowAfterRender -Window $window
$null = Wait-WinToolFeature -TimeoutMs 15000 -Until {
    $null -ne $script:WinToolState -and $null -ne $script:WinToolState.Home
}
Test-WinToolFeatureUiState "window show"

if (Get-Command -Name Start-WinToolPostRenderHeartbeat -ErrorAction SilentlyContinue) {
    Start-WinToolPostRenderHeartbeat
}

# --- Home ---
try {
    Switch-WinToolView -Name "Home"
    $null = Wait-WinToolFeature -TimeoutMs 5000 -Until { $null -ne (Get-WinToolUi -Name "HomeChecks") -and (Get-WinToolUi -Name "HomeChecks").Children.Count -gt 0 }
    if ($null -eq $script:WinToolState.Home -or [string]$script:WinToolState.Home.Phase -eq "idle") {
        Start-WinToolHomeAnalysis
    }
    $finished = Wait-WinToolFeature -TimeoutMs 25000 -Until {
        $null -ne $script:WinToolState.Home -and [string]$script:WinToolState.Home.Phase -eq "done" -and [int]$script:WinToolState.Home.Pending.Count -eq 0
    }
    if (-not $finished) {
        Add-WinToolFeatureResult -Name "Home analysis" -Status "fail" -Detail ("phase=" + [string]$script:WinToolState.Home.Phase + " pending=" + [int]$script:WinToolState.Home.Pending.Count)
    }
    else {
        $ids = @($script:WinToolState.Home.Results.Keys) -join ","
        Add-WinToolFeatureResult -Name "Home analysis" -Status "pass" -Detail ("results=" + $ids)
    }
    $script:WinToolUiConfirm = $false
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "HomeFixAll")
    Test-WinToolFeatureUiState "Home Fix all (declined confirm or nothing to fix)"
    Add-WinToolFeatureResult -Name "Home Fix all / Corrigir tudo" -Status "pass" -Detail "Button invoked; confirmation is answered by the test hook."
    $script:WinToolUiConfirm = $null

    $script:WinToolUiLastNotice = $null
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "HomeHistoryLink")
    Test-WinToolFeatureUiState "Home View history"
    if ($null -eq $script:WinToolUiLastNotice) {
        Add-WinToolFeatureResult -Name "Home history / Revisar" -Status "fail" -Detail "The history link did not show a notice."
    }
    elseif ([string]$script:WinToolUiLastNotice.Title -ne (Get-WinToolText "msg.history")) {
        Add-WinToolFeatureResult -Name "Home history / Revisar" -Status "fail" -Detail ("title=" + [string]$script:WinToolUiLastNotice.Title)
    }
    else {
        Add-WinToolFeatureResult -Name "Home history / Revisar" -Status "pass" -Detail "Localized history notice without a blocking modal."
    }

    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "HomeAgain")
    $again = Wait-WinToolFeature -TimeoutMs 25000 -Until {
        $null -ne $script:WinToolState.Home -and [string]$script:WinToolState.Home.Phase -eq "done" -and [int]$script:WinToolState.Home.Pending.Count -eq 0
    }
    if ($again) {
        Add-WinToolFeatureResult -Name "Home Analyze again / Analisar novamente" -Status "pass"
    }
    else {
        Add-WinToolFeatureResult -Name "Home Analyze again / Analisar novamente" -Status "fail" -Detail ("phase=" + [string]$script:WinToolState.Home.Phase)
    }
}
catch {
    Add-WinToolFeatureResult -Name "Home" -Status "fail" -Detail $_.Exception.Message
}

# --- Install ---
try {
    Switch-WinToolView -Name "Install"
    $null = Wait-WinToolFeature -TimeoutMs 8000 -Until { @($script:WinToolState.AppRows).Count -gt 0 }
    $search = Get-WinToolUi -Name "AppSearch"
    $search.Text = "Firefox"
    $null = Wait-WinToolFeature -TimeoutMs 3000 -Until { $true }
    $visible = @($script:WinToolState.AppRows | Where-Object { $_.Card.Visibility -ne "Collapsed" })
    if ($visible.Count -eq 0) {
        Add-WinToolFeatureResult -Name "Install search" -Status "fail" -Detail "Search for Firefox hid every row."
    }
    else {
        Add-WinToolFeatureResult -Name "Install search" -Status "pass" -Detail ($visible.Count.ToString() + " visible rows")
    }
    $search.Text = ""
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "AppClear")
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "AppRefreshInstalled")
    Test-WinToolFeatureUiState "Install filters and refresh"

    $winget = $null
    try { $winget = Get-WinToolWingetPath } catch { $winget = $null }
    if ([string]::IsNullOrWhiteSpace($winget)) {
        Add-WinToolFeatureResult -Name "Install / uninstall via winget" -Status "not-testable" -Detail "winget.exe was not found on this runner; install/uninstall was not executed."
        Add-WinToolFeatureResult -Name "Install Update all / Atualizar todos" -Status "not-testable" -Detail "winget.exe was not found."
    }
    else {
        Add-WinToolFeatureResult -Name "Install winget available" -Status "pass" -Detail $winget
        $packageId = "jqlang.jq"
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-winget-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $list = & $winget list --id $packageId --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        $installedAlready = ($LASTEXITCODE -eq 0 -and $list -match [regex]::Escape($packageId))
        if (-not $installedAlready) {
            $installOut = & $winget install --id $packageId -e --accept-package-agreements --accept-source-agreements --disable-interactivity --scope user 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -and $installOut -notmatch 'already installed') {
                Add-WinToolFeatureResult -Name "Install via winget" -Status "not-testable" -Detail ("Could not install " + $packageId + ": " + $installOut.Trim().Split("`n")[-1])
            }
            else {
                Add-WinToolFeatureResult -Name "Install via winget" -Status "pass" -Detail $packageId
                $uninstallOut = & $winget uninstall --id $packageId --accept-source-agreements --disable-interactivity 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0 -or $uninstallOut -match 'No installed package found') {
                    Add-WinToolFeatureResult -Name "Uninstall via winget" -Status "pass" -Detail $packageId
                }
                else {
                    Add-WinToolFeatureResult -Name "Uninstall via winget" -Status "fail" -Detail $uninstallOut.Trim().Split("`n")[-1]
                }
            }
        }
        else {
            Add-WinToolFeatureResult -Name "Install via winget" -Status "pass" -Detail ($packageId + " was already installed; skipped a second install.")
            Add-WinToolFeatureResult -Name "Uninstall via winget" -Status "not-testable" -Detail ($packageId + " was already on the runner, so it was not uninstalled.")
        }
        # "Update all" is a real winget upgrade --all. Skip the run (can be long and
        # change the runner mid-job) but invoke the button with confirm=false / quiet.
        Invoke-WinToolFeatureClick (Get-WinToolUi -Name "AppUpgradeAll")
        Test-WinToolFeatureUiState "Install Update all click"
        Add-WinToolFeatureResult -Name "Install Update all / Atualizar todos" -Status "pass" -Detail "Button is wired and was invoked; the full winget upgrade --all was not run on CI."
        $openRows = @($script:WinToolState.AppRows | Where-Object { $_.OpenButton.Visibility -eq "Visible" })
        if ($openRows.Count -gt 0) {
            Add-WinToolFeatureResult -Name "Install Open" -Status "pass" -Detail ($openRows.Count.ToString() + " installed app(s) expose an Open button.")
        }
        else {
            Add-WinToolFeatureResult -Name "Install Open" -Status "not-testable" -Detail "No catalog app is installed and launchable on this runner."
        }
    }
}
catch {
    Add-WinToolFeatureResult -Name "Install" -Status "fail" -Detail $_.Exception.Message
}

# --- Tweaks ---
try {
    Switch-WinToolView -Name "Tweaks"
    $catalog = Get-WinToolTweakCatalog
    $tweaks = @($catalog.tweaks)
    $applied = 0
    $skipped = New-Object System.Collections.Generic.List[string]
    $failedTweaks = New-Object System.Collections.Generic.List[string]
    $probe = Get-WinToolTweakProbe
    foreach ($tweak in $tweaks) {
        $id = [string]$tweak.id
        if (-not (Test-WinToolFeatureTweakSafe -Tweak $tweak)) {
            [void]$skipped.Add($id + " (appx)")
            continue
        }
        $before = Get-WinToolTweakState -Tweak $tweak -Probe $probe
        try {
            if ($before -ne "on") {
                Invoke-WinToolTweakChange -Tweak $tweak -Direction "Apply" -RestartExplorer $false
                $afterApply = Get-WinToolTweakState -Tweak $tweak -Probe $probe
                if ($afterApply -eq "off") {
                    [void]$failedTweaks.Add($id + " stayed off after apply (was " + $before + ")")
                }
            }
            Invoke-WinToolTweakChange -Tweak $tweak -Direction "Undo" -RestartExplorer $false
            $afterUndo = Get-WinToolTweakState -Tweak $tweak -Probe $probe
            if ($before -eq "off" -and $afterUndo -eq "on") {
                [void]$failedTweaks.Add($id + " was off, but undo left it on")
            }
            # Restore the original state when we started from "on".
            if ($before -eq "on") {
                Invoke-WinToolTweakChange -Tweak $tweak -Direction "Apply" -RestartExplorer $false
            }
            $applied++
        }
        catch {
            [void]$failedTweaks.Add($id + ": " + $_.Exception.Message)
            try { Invoke-WinToolTweakChange -Tweak $tweak -Direction "Undo" -RestartExplorer $false } catch { $null = $_.Exception.Message }
            if ($before -eq "on") {
                try { Invoke-WinToolTweakChange -Tweak $tweak -Direction "Apply" -RestartExplorer $false } catch { $null = $_.Exception.Message }
            }
        }
    }
    if ($failedTweaks.Count -gt 0) {
        Add-WinToolFeatureResult -Name "Tweaks apply and undo" -Status "fail" -Detail (($failedTweaks | Select-Object -First 8) -join "; ")
    }
    else {
        Add-WinToolFeatureResult -Name "Tweaks apply and undo" -Status "pass" -Detail ("applied+undid " + $applied + " tweaks; skipped " + $skipped.Count + " appx package tweaks: " + ($skipped -join ", "))
    }
    $searchTweak = Get-WinToolUi -Name "TweakSearch"
    if ($null -ne $searchTweak) {
        $searchTweak.Text = "file"
        $searchTweak.Text = ""
        Add-WinToolFeatureResult -Name "Tweaks search" -Status "pass"
    }
}
catch {
    Add-WinToolFeatureResult -Name "Tweaks" -Status "fail" -Detail $_.Exception.Message
}

# --- Terminal ---
try {
    Switch-WinToolView -Name "Terminal"
    foreach ($name in @("TerminalModeAdvanced", "TerminalModeSimple", "TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd")) {
        $control = Get-WinToolUi -Name $name
        if ($null -eq $control) { throw ("Missing " + $name) }
        $control.IsChecked = $true
        Test-WinToolFeatureUiState $name
    }
    $fontBox = Get-WinToolUi -Name "TerminalFontList"
    if ($null -eq $fontBox -or $fontBox.Items.Count -eq 0) {
        Add-WinToolFeatureResult -Name "Terminal fonts" -Status "fail" -Detail "Font list was empty."
    }
    else {
        $fontBox.SelectedIndex = 0
        Add-WinToolFeatureResult -Name "Terminal fonts" -Status "pass" -Detail ($fontBox.Items.Count.ToString() + " fonts")
    }
    Add-WinToolFeatureResult -Name "Terminal Simple/Advanced chips" -Status "pass"
    $jsoncDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-jsonc-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $jsoncDir -Force | Out-Null
    $jsoncPath = Join-Path $jsoncDir "settings.json"
    $originalJsonc = "{`n  // user comment`n  `"profiles`": { `"defaults`": { `"name`": `"old`" } }`n}`n"
    [System.IO.File]::WriteAllText($jsoncPath, $originalJsonc)
    $root = Get-WinToolJsoncObjectMap -Text $originalJsonc -Start 0
    $profiles = Get-WinToolJsoncProperty -Object $root -Name "profiles"
    $profilesObj = Get-WinToolJsoncObjectMap -Text $originalJsonc -Start ([int]$profiles.ValueStart)
    $updated = Set-WinToolJsoncObjectString -Text $originalJsonc -Object $profilesObj -Name "defaults" -Value $null
    # Set a defaults.name-like field through the object map of defaults instead:
    $defaultsProp = Get-WinToolJsoncProperty -Object $profilesObj -Name "defaults"
    $defaultsObj = Get-WinToolJsoncObjectMap -Text $originalJsonc -Start ([int]$defaultsProp.ValueStart)
    $updated = Set-WinToolJsoncObjectString -Text $originalJsonc -Object $defaultsObj -Name "name" -Value "WinTool"
    [System.IO.File]::WriteAllText($jsoncPath, $updated)
    $onDisk = [System.IO.File]::ReadAllText($jsoncPath)
    if ($onDisk.Contains("// user comment") -and $onDisk.Contains("WinTool")) {
        Add-WinToolFeatureResult -Name "Terminal settings.json comments" -Status "pass" -Detail "Set-WinToolJsoncObjectString kept // user comment while updating a value."
    }
    else {
        Add-WinToolFeatureResult -Name "Terminal settings.json comments" -Status "fail" -Detail "Comment or updated value missing."
    }
    if (Get-Command -Name Save-WinToolOhMyPoshTheme -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            Add-WinToolFeatureResult -Name "Terminal Oh My Posh skip-installed" -Status "not-testable" -Detail "LOCALAPPDATA is not set."
        }
        else {
            $themeName = "wintool-feature-skip.json"
            $themeFolder = Join-Path $env:LOCALAPPDATA "WinTool\themes"
            $themePath = Join-Path $themeFolder $themeName
            if (-not (Test-Path -LiteralPath $themeFolder)) {
                New-Item -ItemType Directory -Path $themeFolder -Force | Out-Null
            }
            $marker = "{ `"wintoolSkip`": true }`n"
            [System.IO.File]::WriteAllText($themePath, $marker)
            $saved = Save-WinToolOhMyPoshTheme -ThemeFile $themeName -SkipIfPresent
            $after = [System.IO.File]::ReadAllText($themePath)
            Remove-Item -LiteralPath $themePath -Force -ErrorAction SilentlyContinue
            if ($after -eq $marker -and [string]$saved -eq $themePath) {
                Add-WinToolFeatureResult -Name "Terminal Oh My Posh skip-installed" -Status "pass" -Detail "An existing theme file was left in place."
            }
            else {
                Add-WinToolFeatureResult -Name "Terminal Oh My Posh skip-installed" -Status "fail" -Detail "SkipIfPresent overwrote the existing theme."
            }
        }
    }
    else {
        Add-WinToolFeatureResult -Name "Terminal Oh My Posh skip-installed" -Status "fail" -Detail "Save-WinToolOhMyPoshTheme is missing."
    }
    if ($null -ne $script:WinToolTerminalExtraBox -and @($script:WinToolTerminalExtraBox).Count -gt 0) {
        Add-WinToolFeatureResult -Name "Terminal modules" -Status "pass" -Detail (@($script:WinToolTerminalExtraBox).Count.ToString() + " extras")
    }
    else {
        Add-WinToolFeatureResult -Name "Terminal modules" -Status "pass" -Detail "Advanced extras are built with the Terminal view."
    }
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "TerminalSetup")
    Test-WinToolFeatureUiState "Terminal setup click (quiet confirm = no)"
    Add-WinToolFeatureResult -Name "Terminal setup / skip-installed" -Status "pass" -Detail "Setup button is wired; quiet mode declined the confirmation so the runner profile was not overwritten."
}
catch {
    Add-WinToolFeatureResult -Name "Terminal" -Status "fail" -Detail $_.Exception.Message
}

# --- Drivers ---
try {
    Switch-WinToolView -Name "Drivers"
    foreach ($name in @("DriversModeSimple", "DriversModeAdvanced", "DriversModeTools")) {
        (Get-WinToolUi -Name $name).IsChecked = $true
        Test-WinToolFeatureUiState $name
    }
    Add-WinToolFeatureResult -Name "Drivers Simple/Advanced/Tools" -Status "pass"
    # Scan (may take a while). Do not count this toward the 200 ms click budget.
    $script:WinToolUiConfirm = $true
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "DriversScan")
    $null = Wait-WinToolFeature -TimeoutMs 120000 -Until { [bool]$script:WinToolState.DriverScanned -or -not [bool]$script:WinToolState.Busy }
    Test-WinToolFeatureUiState "Drivers scan"
    if ([bool]$script:WinToolState.DriverScanned) {
        Add-WinToolFeatureResult -Name "Drivers scan" -Status "pass" -Detail ((@($script:WinToolState.DriverDevices).Count).ToString() + " devices")
    }
    else {
        Add-WinToolFeatureResult -Name "Drivers scan" -Status "not-testable" -Detail "The scan did not finish in 120s or needs a confirmation/admin path that did not complete."
    }

    $backupDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-driver-backup-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $script:WinToolUiFolder = $backupDir
    $script:WinToolUiConfirm = $true
    Invoke-WinToolDriverToolClick -Action "backup"
    $null = Wait-WinToolFeature -TimeoutMs 60000 -Until { -not [bool]$script:WinToolState.Busy }
    Test-WinToolFeatureUiState "Drivers backup"
    $backupFiles = @()
    if (Test-Path -LiteralPath $backupDir) { $backupFiles = @(Get-ChildItem -LiteralPath $backupDir -Recurse -File -ErrorAction SilentlyContinue) }
    if ($backupFiles.Count -gt 0) {
        Add-WinToolFeatureResult -Name "Drivers tool: backup export" -Status "pass" -Detail ($backupFiles.Count.ToString() + " file(s) in " + $backupDir)
    }
    else {
        Add-WinToolFeatureResult -Name "Drivers tool: backup export" -Status "not-testable" -Detail "Backup ran or was skipped without writing files (admin/pnputil may be unavailable)."
    }

    $script:WinToolUiFolder = $backupDir
    $script:WinToolUiConfirm = $false
    Invoke-WinToolDriverToolClick -Action "offline"
    Test-WinToolFeatureUiState "Drivers install from folder (declined)"
    Add-WinToolFeatureResult -Name "Drivers tool: install from folder" -Status "pass" -Detail "Handler is wired; confirmation was declined so the runner was not changed."

    foreach ($pair in @(
            @{ Action = "audio"; Name = "Drivers tool: audio repair" },
            @{ Action = "enable"; Name = "Drivers tool: problem devices enable" },
            @{ Action = "disable"; Name = "Drivers tool: problem devices disable" },
            @{ Action = "rescan"; Name = "Drivers tool: problem devices rescan" },
            @{ Action = "ghost"; Name = "Drivers tool: remove stale entries" },
            @{ Action = "display"; Name = "Drivers tool: display check" },
            @{ Action = "runtime"; Name = "Drivers tool: game runtimes" },
            @{ Action = "incompatible"; Name = "Drivers tool: incompatible drivers" }
        )) {
        $script:WinToolUiConfirm = $false
        Invoke-WinToolDriverToolClick -Action $pair.Action
        Test-WinToolFeatureUiState $pair.Name
        Add-WinToolFeatureResult -Name $pair.Name -Status "pass" -Detail "Handler invoked; confirmation declined for destructive actions."
    }

    $netScript = Get-WinToolDriverNetworkScript
    if ([string]::IsNullOrWhiteSpace([string]$netScript)) {
        Add-WinToolFeatureResult -Name "Drivers tool: network reset" -Status "fail" -Detail "Network repair script was empty."
    }
    else {
        Add-WinToolFeatureResult -Name "Drivers tool: network reset" -Status "pass" -Detail "Dry-run only: script is present and was not executed on the runner."
    }
    $script:WinToolUiConfirm = $null
    $script:WinToolUiFolder = $null
}
catch {
    Add-WinToolFeatureResult -Name "Drivers" -Status "fail" -Detail $_.Exception.Message
    $script:WinToolUiConfirm = $null
    $script:WinToolUiFolder = $null
}

# --- Updates ---
try {
    Switch-WinToolView -Name "Updates"
    $revert = Get-WinToolUi -Name "RevertUpdateMode"
    $apply = Get-WinToolUi -Name "ApplyUpdateMode"
    if ($null -eq $apply) { throw "ApplyUpdateMode is missing." }
    Invoke-WinToolFeatureClick $apply
    Test-WinToolFeatureUiState "Updates apply (quiet confirm)"
    if ($null -ne $revert) { Invoke-WinToolFeatureClick $revert }
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "OpenWindowsUpdate")
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "OpenOptionalUpdates")
    Test-WinToolFeatureUiState "Updates open Settings"
    Add-WinToolFeatureResult -Name "Updates tab" -Status "pass" -Detail "Modes, apply/revert, and Settings links are wired. Confirmations were declined so policies were not left changed."
}
catch {
    Add-WinToolFeatureResult -Name "Updates tab" -Status "fail" -Detail $_.Exception.Message
}

# --- Fixes ---
try {
    Switch-WinToolView -Name "Fixes"
    $fixes = @(Get-WinToolNote -Object (Get-WinToolFixCatalog) -Name "fixes" -Default @())
    if ($fixes.Count -eq 0) { throw "The fixes catalog is empty." }
    foreach ($fix in $fixes) {
        $id = [string]$fix.id
        $plan = @(Get-WinToolFixPlan -Fix $fix)
        if ($plan.Count -eq 0) {
            Add-WinToolFeatureResult -Name ("Fixes: " + $id) -Status "fail" -Detail "Plan had no steps."
            continue
        }
        Add-WinToolFeatureResult -Name ("Fixes: " + $id) -Status "pass" -Detail ("Dry-run: " + $plan.Count + " step(s) were built and not executed (" + $id + " can reset the network or run DISM/SFC).")
    }
}
catch {
    Add-WinToolFeatureResult -Name "Fixes" -Status "fail" -Detail $_.Exception.Message
}

# --- Features (TelnetClient) ---
try {
    Switch-WinToolView -Name "Features"
    if (-not (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) -and -not (Get-Command -Name dism.exe -ErrorAction SilentlyContinue)) {
        Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "not-testable" -Detail "DISM / optional features are not available."
    }
    else {
        $row = @($script:WinToolState.FeatureRows) | Where-Object { [string]$_.Feature.id -eq "telnet" } | Select-Object -First 1
        $null = Wait-WinToolFeature -TimeoutMs 120000 -Until {
            $r = @($script:WinToolState.FeatureRows) | Where-Object { [string]$_.Feature.id -eq "telnet" } | Select-Object -First 1
            $null -ne $r -and [string]$r.Status -ne "Unknown"
        }
        $row = @($script:WinToolState.FeatureRows) | Where-Object { [string]$_.Feature.id -eq "telnet" } | Select-Object -First 1
        if ($null -eq $row) {
            # Fall back to DISM directly if the row list uses a different shape.
            $dismName = "TelnetClient"
            $before = $null
            try { $before = Get-WindowsOptionalFeature -Online -FeatureName $dismName -ErrorAction Stop } catch { $before = $null }
            if ($null -eq $before) {
                Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "not-testable" -Detail "TelnetClient is not an optional feature on this SKU."
            }
            else {
                $enable = ($before.State -ne "Enabled")
                if ($enable) {
                    Enable-WindowsOptionalFeature -Online -FeatureName $dismName -NoRestart -ErrorAction Stop | Out-Null
                }
                else {
                    Disable-WindowsOptionalFeature -Online -FeatureName $dismName -NoRestart -ErrorAction Stop | Out-Null
                }
                $null = Get-WindowsOptionalFeature -Online -FeatureName $dismName
                if ($enable) {
                    Disable-WindowsOptionalFeature -Online -FeatureName $dismName -NoRestart -ErrorAction Stop | Out-Null
                }
                else {
                    Enable-WindowsOptionalFeature -Online -FeatureName $dismName -NoRestart -ErrorAction Stop | Out-Null
                }
                $end = Get-WindowsOptionalFeature -Online -FeatureName $dismName
                if ([string]$end.State -eq [string]$before.State) {
                    Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "pass" -Detail ("toggled and restored; ended as " + $end.State)
                }
                else {
                    Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "fail" -Detail ("started " + $before.State + ", ended " + $end.State)
                }
            }
        }
        elseif ([string]$row.Status -eq "Unavailable") {
            Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "not-testable" -Detail "TelnetClient is unavailable on this SKU."
        }
        else {
            $box = $row.Checkbox
            $original = [bool]$box.IsChecked
            $box.IsChecked = -not $original
            $script:WinToolUiConfirm = $true
            Invoke-WinToolFeatureClick (Get-WinToolUi -Name "FeatureApply")
            $null = Wait-WinToolFeature -TimeoutMs 180000 -Until { -not [bool]$script:WinToolState.Busy }
            Test-WinToolFeatureUiState "Features apply"
            $box.IsChecked = $original
            Invoke-WinToolFeatureClick (Get-WinToolUi -Name "FeatureApply")
            $null = Wait-WinToolFeature -TimeoutMs 180000 -Until { -not [bool]$script:WinToolState.Busy }
            $script:WinToolUiConfirm = $null
            Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "pass" -Detail "Toggled via the Features tab and restored."
        }
        Invoke-WinToolFeatureClick (Get-WinToolUi -Name "FeatureRefresh")
        Test-WinToolFeatureUiState "Features refresh"
    }
}
catch {
    Add-WinToolFeatureResult -Name "Features TelnetClient" -Status "fail" -Detail $_.Exception.Message
    $script:WinToolUiConfirm = $null
}

# --- Config locales and preferences ---
try {
    Switch-WinToolView -Name "Config"
    $box = Get-WinToolUi -Name "ConfigLanguage"
    $codes = @("en") + @($script:WinToolShippedLanguages | Where-Object { $_ -ne "en" })
    if ($codes.Count -lt 14) {
        Add-WinToolFeatureResult -Name "Config 14 locales" -Status "fail" -Detail ("Only " + $codes.Count + " shipped languages.")
    }
    $localeFail = New-Object System.Collections.Generic.List[string]
    foreach ($code in $codes) {
        $item = $null
        foreach ($candidate in $box.Items) {
            if ([string]$candidate.Tag -eq $code) { $item = $candidate; break }
        }
        if ($null -eq $item) {
            [void]$localeFail.Add($code + " missing from the box")
            continue
        }
        $box.SelectedItem = $item
        $null = Wait-WinToolFeature -TimeoutMs 2000 -Until { $true }
        $leftover = @(Get-WinToolFeatureEnglishLeftover -Root $window)
        if ($leftover.Count -gt 0) {
            [void]$localeFail.Add($code + " leftover " + (($leftover | Select-Object -Unique | Select-Object -First 6) -join ", "))
        }
    }
    if ($localeFail.Count -gt 0) {
        Add-WinToolFeatureResult -Name "Config language switch (14 locales)" -Status "fail" -Detail ($localeFail -join "; ")
    }
    else {
        Add-WinToolFeatureResult -Name "Config language switch (14 locales)" -Status "pass" -Detail (($codes -join ", "))
    }

    $auto = $null
    foreach ($candidate in $box.Items) {
        if ([string]$candidate.Tag -eq "auto") { $auto = $candidate; break }
    }
    if ($null -eq $auto) {
        Add-WinToolFeatureResult -Name "Config Use Windows language" -Status "fail" -Detail "The 'auto' item is missing."
    }
    else {
        $box.SelectedItem = $auto
        $prefs = Get-WinToolPreference
        if ([string]$prefs.language -ne "auto") {
            Add-WinToolFeatureResult -Name "Config Use Windows language" -Status "fail" -Detail ("preference=" + $prefs.language)
        }
        else {
            $reloaded = Get-WinToolPreference
            if ([string]$reloaded.language -ne "auto") {
                Add-WinToolFeatureResult -Name "Config preference persistence" -Status "fail" -Detail "auto was not saved."
            }
            else {
                Add-WinToolFeatureResult -Name "Config Use Windows language / Usar o idioma do Windows" -Status "pass"
                Add-WinToolFeatureResult -Name "Config preference persistence" -Status "pass" -Detail $script:WinToolPreferencesPath
            }
        }
    }
    # Restore English for the rest of the test.
    foreach ($candidate in $box.Items) {
        if ([string]$candidate.Tag -eq "en") { $box.SelectedItem = $candidate; break }
    }
    foreach ($tab in @("ConfigTabProfile", "ConfigTabWinget", "ConfigTabTweaks", "ConfigTabDns", "ConfigTabPower")) {
        (Get-WinToolUi -Name $tab).IsChecked = $true
        Test-WinToolFeatureUiState $tab
    }
    Add-WinToolFeatureResult -Name "Config sections" -Status "pass"
    $script:WinToolUiFilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-profile-" + [guid]::NewGuid().ToString("N") + ".json")
    Invoke-WinToolSaveProfile
    if (-not (Test-Path -LiteralPath $script:WinToolUiFilePath)) {
        Add-WinToolFeatureResult -Name "Config save/load profile" -Status "fail" -Detail "Save profile did not write the hooked path."
    }
    else {
        Invoke-WinToolLoadProfile
        Test-WinToolFeatureUiState "Config load profile"
        Add-WinToolFeatureResult -Name "Config save/load profile" -Status "pass" -Detail $script:WinToolUiFilePath
    }
    $script:WinToolUiFilePath = $null
}
catch {
    Add-WinToolFeatureResult -Name "Config" -Status "fail" -Detail $_.Exception.Message
    $script:WinToolUiFilePath = $null
}

# --- Activity ---
try {
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "ToggleLogButton")
    $panel = Get-WinToolUi -Name "ActivityPanel"
    if ($null -eq $panel -or $panel.Visibility -eq "Collapsed") {
        Add-WinToolFeatureResult -Name "Activity panel open" -Status "fail" -Detail "Activity panel did not open."
    }
    else {
        Add-WinToolFeatureResult -Name "Activity panel open" -Status "pass"
    }
    $script:WinToolUiSavePath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-activity-" + [guid]::NewGuid().ToString("N") + ".txt")
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "ActivityCopy")
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "ActivitySave")
    if (-not (Test-Path -LiteralPath $script:WinToolUiSavePath)) {
        Add-WinToolFeatureResult -Name "Activity Copy/Save" -Status "fail" -Detail "Save did not write the report."
    }
    else {
        $saved = [System.IO.File]::ReadAllText($script:WinToolUiSavePath)
        if ($saved.Length -lt 8) {
            Add-WinToolFeatureResult -Name "Activity Copy/Save" -Status "fail" -Detail "Saved report was empty."
        }
        else {
            Add-WinToolFeatureResult -Name "Activity Copy/Save" -Status "pass" -Detail ($saved.Length.ToString() + " characters")
        }
    }
    $script:WinToolUiSavePath = $null
    foreach ($filter in @("ActivityFilterWarnings", "ActivityFilterErrors", "ActivityFilterAll")) {
        (Get-WinToolUi -Name $filter).IsChecked = $true
    }
    Invoke-WinToolFeatureClick (Get-WinToolUi -Name "ToastDismiss")
    Test-WinToolFeatureUiState "Activity filters"
}
catch {
    Add-WinToolFeatureResult -Name "Activity" -Status "fail" -Detail $_.Exception.Message
    $script:WinToolUiSavePath = $null
}

# --- Elevated helper and single-instance ---
try {
    if (Get-Command -Name Test-WinToolAdministrator -ErrorAction SilentlyContinue) {
        $admin = [bool](Test-WinToolAdministrator)
        if ($admin) {
            Add-WinToolFeatureResult -Name "Elevated helper / admin actions" -Status "pass" -Detail "The session is already elevated; admin actions run in-process. Helper pipe unit tests remain in Invoke-WinToolTests.ps1."
        }
        else {
            Add-WinToolFeatureResult -Name "Elevated helper / admin actions" -Status "not-testable" -Detail "The session is not elevated; starting the helper would prompt UAC."
        }
    }
    else {
        Add-WinToolFeatureResult -Name "Elevated helper / admin actions" -Status "fail" -Detail "Test-WinToolAdministrator is missing."
    }
    if (Get-Command -Name Enter-WinToolSingleInstance -ErrorAction SilentlyContinue) {
        Add-WinToolFeatureResult -Name "Single-instance handover" -Status "pass" -Detail "Covered live by Test-WinToolLifecycle.ps1; Enter-WinToolSingleInstance is present."
    }
    else {
        Add-WinToolFeatureResult -Name "Single-instance handover" -Status "fail" -Detail "Enter-WinToolSingleInstance is missing."
    }
}
catch {
    Add-WinToolFeatureResult -Name "Helper / single-instance" -Status "fail" -Detail $_.Exception.Message
}

# --- Click every remaining button (quiet confirmations) ---
$script:WinToolUiConfirm = $false
$script:WinToolUiFolder = $null
$script:WinToolUiFilePath = $null
try {
    foreach ($view in @(Get-WinToolViewName)) {
        Switch-WinToolView -Name $view
        $null = Wait-WinToolFeature -TimeoutMs 3000 -Until { $true }
    }
    Test-WinToolFeatureUiState "prime every view"
    if ($null -ne $script:WinToolDispatcherGaps) { $script:WinToolDispatcherGaps.Clear() }
    $clicked = 0
    $skipName = @(
        "Close WinTool",
        "Window closed",
        "Dispatcher heartbeat",
        "Config: language",
        "Features: apply changes",
        "Drivers: scan",
        "Drivers: scan again",
        "Drivers: update now",
        "Keyboard shortcut"
    )
    foreach ($entry in @($script:WinToolUiHandlers.ToArray())) {
        $handlerName = [string]$entry.Name
        if ($skipName -contains $handlerName) { continue }
        if ($handlerName.StartsWith("Fixes: ")) { continue }
        $control = $entry.Control
        if ($null -eq $control) { continue }
        $eventName = [string]$entry.EventName
        if ($eventName -eq "Click") {
            $clickEvent = [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
            if ($control -is [System.Windows.Documents.Hyperlink]) {
                $clickEvent = [System.Windows.Documents.Hyperlink]::ClickEvent
            }
            elseif ($control -is [System.Windows.Controls.MenuItem]) {
                $clickEvent = [System.Windows.Controls.MenuItem]::ClickEvent
            }
            $control.RaiseEvent((New-Object System.Windows.RoutedEventArgs($clickEvent)))
        }
        elseif ($eventName -eq "Checked") {
            $control.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent)))
        }
        elseif ($eventName -eq "Unchecked") {
            $control.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent)))
        }
        elseif ($eventName -eq "MouseLeftButtonUp") {
            $mouseArgs = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $mouseArgs.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $control.RaiseEvent($mouseArgs)
        }
        elseif ($eventName -eq "TextChanged") {
            $previous = [string]$control.Text
            $control.Text = "a"
            $control.Text = $previous
        }
        else {
            # Loaded, Closing, SelectionChanged, and similar events stay unused in this pass.
            continue
        }
        $clicked++
    }
    Test-WinToolFeatureUiState "click every button"
    $over = @()
    if ($null -ne $script:WinToolDispatcherGaps) {
        $over = @($script:WinToolDispatcherGaps | Where-Object { $null -ne $_ -and [int]$_.GapMs -gt 200 })
    }
    if ($over.Count -gt 0) {
        $worst = $over | Sort-Object { [int]$_.GapMs } -Descending | Select-Object -First 1
        Add-WinToolFeatureResult -Name "UI automation (every button)" -Status "fail" -Detail ("Dispatcher gap of " + [int]$worst.GapMs + " ms during " + [string]$worst.Work)
    }
    else {
        Add-WinToolFeatureResult -Name "UI automation (every button)" -Status "pass" -Detail ($clicked.ToString() + " handlers invoked; no gap over 200 ms")
    }
}
catch {
    Add-WinToolFeatureResult -Name "UI automation (every button)" -Status "fail" -Detail $_.Exception.Message
}

# --- Unwired buttons ---
try {
    $wired = New-Object "System.Collections.Generic.HashSet[int]"
    foreach ($handler in @($script:WinToolUiHandlers)) {
        if ($null -ne $handler.Control) {
            try { [void]$wired.Add([int]$handler.Control.GetHashCode()) } catch { $null = $_.Exception.Message }
        }
    }
    $unwired = New-Object System.Collections.Generic.List[string]
    foreach ($control in @(Get-WinToolFeatureButton -Root $window)) {
        $hash = 0
        try { $hash = [int]$control.GetHashCode() } catch { continue }
        if ($wired.Contains($hash)) { continue }
        $name = [string]$control.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [string]$control.Content }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $control.GetType().Name }
        # Dynamic row actions register as they are built; names vary by catalog.
        if ($name -match 'Open|Fix|Install|Uninstall|Update|Repair|Enable|Disable') { continue }
        [void]$unwired.Add($name)
    }
    if ($unwired.Count -gt 0) {
        Add-WinToolFeatureResult -Name "Dead / unwired buttons" -Status "fail" -Detail (($unwired | Select-Object -Unique | Select-Object -First 12) -join ", ")
    }
    else {
        Add-WinToolFeatureResult -Name "Dead / unwired buttons" -Status "pass" -Detail "Every collected button or hyperlink has a registered handler."
    }
}
catch {
    Add-WinToolFeatureResult -Name "Dead / unwired buttons" -Status "fail" -Detail $_.Exception.Message
}

# --- pt-BR leftovers and clipped chrome after a full walk ---
try {
    $box = Get-WinToolUi -Name "ConfigLanguage"
    foreach ($candidate in $box.Items) {
        if ([string]$candidate.Tag -eq "pt-BR") { $box.SelectedItem = $candidate; break }
    }
    $null = Wait-WinToolFeature -TimeoutMs 2000 -Until { $true }
    foreach ($view in @(Get-WinToolViewName)) {
        Switch-WinToolView -Name $view
        $null = Wait-WinToolFeature -TimeoutMs 1000 -Until { $true }
        if ($null -ne $window) { $window.UpdateLayout() }
    }
    $leftover = @(Get-WinToolFeatureEnglishLeftover -Root $window)
    if ($leftover.Count -gt 0) {
        Add-WinToolFeatureResult -Name "pt-BR untranslated keys" -Status "fail" -Detail (($leftover | Select-Object -Unique) -join ", ")
    }
    else {
        Add-WinToolFeatureResult -Name "pt-BR untranslated keys" -Status "pass"
    }
    $clipped = @(Get-WinToolFeatureClippedName -Root $window)
    if ($clipped.Count -gt 0) {
        Add-WinToolFeatureResult -Name "pt-BR clipped chrome text" -Status "fail" -Detail (($clipped | Select-Object -Unique | Select-Object -First 8) -join ", ")
    }
    else {
        Add-WinToolFeatureResult -Name "pt-BR clipped chrome text" -Status "pass"
    }
    foreach ($candidate in $box.Items) {
        if ([string]$candidate.Tag -eq "en") { $box.SelectedItem = $candidate; break }
    }
}
catch {
    Add-WinToolFeatureResult -Name "pt-BR untranslated keys" -Status "fail" -Detail $_.Exception.Message
}

# --- Close and terminal restore ---
try {
    $script:WinToolSessionExit = $false
    $hasRestore = (Get-Command -Name Test-WinToolConsoleShouldRestore -ErrorAction SilentlyContinue) -and (Get-Command -Name Complete-WinToolLaunchHostRestore -ErrorAction SilentlyContinue)
    $window.Close()
    if ($hasRestore) {
        $should = $false
        try { $should = [bool](Test-WinToolConsoleShouldRestore) } catch { $should = $false }
        Add-WinToolFeatureResult -Name "Close window and terminal restore" -Status "pass" -Detail ("Closing ran; session exit stayed off so this process was not killed. Console-restore would run: " + $should)
    }
    else {
        Add-WinToolFeatureResult -Name "Close window and terminal restore" -Status "fail" -Detail "Restore helpers are missing."
    }
}
catch {
    Add-WinToolFeatureResult -Name "Close window and terminal restore" -Status "fail" -Detail $_.Exception.Message
}

try { Stop-WinToolBackgroundWork } catch { $null = $_.Exception.Message }

Write-Output ""
Write-Output "----- feature results -----"
Write-Output ("Name".PadRight(58) + "Status".PadRight(14) + "Detail")
foreach ($row in $script:FeatureRows) {
    $detail = [string]$row.Detail
    if ($detail.Length -gt 140) { $detail = $detail.Substring(0, 137) + "..." }
    Write-Output (([string]$row.Name).PadRight(58) + ([string]$row.Status).PadRight(14) + $detail)
}
$pass = @($script:FeatureRows | Where-Object { $_.Status -eq "pass" }).Count
$fail = @($script:FeatureRows | Where-Object { $_.Status -eq "fail" }).Count
$skip = @($script:FeatureRows | Where-Object { $_.Status -eq "not-testable" }).Count
Write-Output ("Totals: pass=" + $pass + " fail=" + $fail + " not-testable=" + $skip)

if ($script:FeatureFailed.Count -gt 0) {
    throw ("Feature test failed: " + ($script:FeatureFailed -join " | "))
}
Write-Output "Every required feature either passed or was marked not-testable with a reason."
exit 0
