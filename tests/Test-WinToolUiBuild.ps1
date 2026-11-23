# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Build the WinTool window without showing it.
.DESCRIPTION
    Runs on Windows PowerShell 5.1 in STA. It loads the XAML and builds every
    tab, then fails if startup prints extra objects or a row has no checkbox.
#>
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "Skipping the window build: this test runs on Windows."
    exit 0
}

$apartment = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apartment -ne "STA") {
    throw "Build the window with powershell.exe -STA. The current apartment is $apartment."
}

$root = Split-Path -Parent $PSScriptRoot
$script:WinToolRoot = $root
$script:WinToolEmbedded = $null
$script:WinToolApplyProfile = $null
$script:WinToolUnattended = $false
$script:WinToolEntryPath = $null
$versionPath = Join-Path $root "build/version.txt"
$script:WinToolVersion = ([System.IO.File]::ReadAllText($versionPath)).Trim()

$listPath = Join-Path $root "build/files.txt"
foreach ($relative in [System.IO.File]::ReadAllLines($listPath)) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        continue
    }
    $path = Join-Path $root ($trimmed -replace '\\', '/')
    . $path
}

$results = @(New-WinToolWindow)
if ($results.Count -ne 1) {
    throw "WinTool startup produced $($results.Count) outputs. A collection method is leaking its return value."
}

$window = $script:WinToolWindow
if ($null -eq $window) {
    throw "WinTool did not keep a window."
}

$appHost = $window.FindName("AppCategories")
$tweakHost = $window.FindName("TweakCategories")
if ($null -eq $appHost -or $appHost.Children.Count -lt 1) {
    throw "The Install tab did not build any categories."
}
if ($null -eq $tweakHost -or $tweakHost.Children.Count -lt 1) {
    throw "The Tweaks tab did not build any categories."
}

$appRows = @($script:WinToolState.AppRows)
$tweakRows = @($script:WinToolState.TweakRows)
if ($appRows.Count -lt 1) {
    throw "The Install tab did not build any app rows."
}
if ($tweakRows.Count -lt 1) {
    throw "The Tweaks tab did not build any tweak rows."
}
foreach ($row in $appRows) {
    if ($null -eq $row.Checkbox) {
        throw "An app row was built without a checkbox."
    }
}
foreach ($row in $tweakRows) {
    if ($null -eq $row.Checkbox) {
        throw "A tweak row was built without a checkbox."
    }
}

$fontList = $window.FindName("TerminalFontList")
if ($null -eq $fontList -or $fontList.Items.Count -lt 50) {
    throw "The Terminal tab did not list the font catalog."
}
$consolas = Find-WinToolInstalledFontFile -Token "Consolas"
if ($null -eq $consolas) {
    throw "The installed-font check did not find Consolas."
}
$family = Get-WinToolFontFamilyName -Path ([string]$consolas.Data)
if ($family -ne "Consolas") {
    throw "The font family name read from $($consolas.Data) was '$family'."
}
# A font that is not installed must be skipped with a warning, not set.
Invoke-WinToolTerminalFont -Face "WinTool Missing Nerd Font" -Match "WinToolMissingNerdFont"
# Run each generated profile in a fresh Windows PowerShell 5.1 (and
# PowerShell 7 when present) with -NoProfile, as a new Terminal tab would.
# Fake oh-my-posh and starship commands stand in for the real tools, and
# POSH_THEMES_PATH is removed, as on a PC with a current Oh My Posh.
$fakeBin = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-fake-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fakeBin "oh-my-posh.cmd"), "@echo function global:prompt { 'omp-ok %*' }`r`n")
[System.IO.File]::WriteAllText((Join-Path $fakeBin "starship.cmd"), "@echo function global:prompt { 'starship-ok' }`r`n")
$themeFolder = Join-Path $env:LOCALAPPDATA "WinTool\themes"
New-Item -ItemType Directory -Path $themeFolder -Force | Out-Null
$themeFile = Join-Path $themeFolder "jandedobbeleer.omp.json"
if (-not (Test-Path -LiteralPath $themeFile)) { [System.IO.File]::WriteAllText($themeFile, "{}") }
$savedPath = $env:PATH
$env:PATH = $fakeBin + ";" + $env:PATH
$profileHosts = @((Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"))
$pwshCommand = Get-Command -Name pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $pwshCommand) { $profileHosts += [string]$pwshCommand.Source }
try {
    foreach ($promptItem in @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())) {
        $promptId = [string]$promptItem.id
        $profileText = Get-WinToolPromptScript -PromptId $promptId -TerminalIcons $true -PromptStyle "jandedobbeleer" -PsReadLine $true -Zoxide $true
        $profileFile = Join-Path $fakeBin ("profile-" + $promptId + ".ps1")
        [System.IO.File]::WriteAllText($profileFile, $profileText, (New-Object System.Text.UTF8Encoding($true)))
        foreach ($profileHost in $profileHosts) {
            $probe = 'Remove-Item Env:POSH_THEMES_PATH -ErrorAction Ignore; $Error.Clear(); . ''' + $profileFile + '''; foreach ($e in $Error) { "ERR: " + $e }; "PROMPT: " + (prompt); "WINTOOL-OK"'
            # -EncodedCommand: Windows PowerShell drops inner quotes from native arguments.
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($probe))
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $profileOutput = & $profileHost -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1
            $ErrorActionPreference = $savedPreference
            $profileJoined = (@($profileOutput) | ForEach-Object { [string]$_ }) -join " | "
            if (-not $profileJoined.Contains("WINTOOL-OK") -or $profileJoined.Contains("ERR:")) {
                throw ("The " + $promptId + " profile failed in " + $profileHost + ": " + $profileJoined)
            }
            if ($promptId -eq "oh-my-posh" -and -not ($profileJoined.Contains("omp-ok") -and $profileJoined.Contains("--config") -and $profileJoined.Contains("jandedobbeleer.omp.json"))) {
                throw ("The oh-my-posh profile did not load the saved theme in " + $profileHost + ": " + $profileJoined)
            }
            if ($promptId -eq "starship" -and -not $profileJoined.Contains("starship-ok")) {
                throw ("The starship profile did not start Starship in " + $profileHost + ": " + $profileJoined)
            }
        }
    }
    Write-Output ("Generated profiles ran cleanly in " + $profileHosts.Count + " PowerShell host(s).")
}
finally {
    $env:PATH = $savedPath
    Remove-Item -LiteralPath $fakeBin -Recurse -Force -ErrorAction SilentlyContinue
}
$promptList = $window.FindName("TerminalPromptList")
$promptItems = @($promptList.Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Tag) })
if ($null -eq $promptList -or $promptItems.Count -lt 8) {
    throw "The Terminal tab did not list the prompt engines."
}
$fixList = $window.FindName("FixList")
if ($null -eq $fixList -or $fixList.Children.Count -lt 4) {
    throw "The Fixes tab did not list the repairs."
}
$modeList = $window.FindName("UpdateModeList")
if ($null -eq $modeList -or $modeList.Children.Count -ne 3) {
    throw "The Updates tab did not list the three update modes."
}
# The runner may already carry Windows Update policies, which reads as Custom
# and leaves every choice clear, so only a known mode must be ticked.
$currentMode = [string]$script:WinToolState.UpdateModeCurrent
$expectedTicks = 1
if ($currentMode -eq "custom") {
    $expectedTicks = 0
}
if ([string]::IsNullOrWhiteSpace($currentMode) -or @($modeList.Children | Where-Object { $_.IsChecked -eq $true }).Count -ne $expectedTicks) {
    throw "The current update mode ($currentMode) should be selected."
}
Write-Output ("Update mode: " + $window.FindName("UpdateModeCurrent").Text)
$dnsProvider = $window.FindName("DnsProvider")
if ($null -eq $dnsProvider -or $dnsProvider.Items.Count -lt 5) {
    throw "The Config tab did not list the DNS providers."
}
Update-WinToolSystemView
if ([string]::IsNullOrWhiteSpace([string]$window.FindName("PowerPlanStatus").Text) -or $window.FindName("PowerPlanStatus").Text -eq "Checking...") {
    throw "The power plan status was not read."
}
Write-Output ("DNS: " + $window.FindName("DnsCurrent").Text)
Write-Output ("Power plan: " + $window.FindName("PowerPlanStatus").Text)
$logPanel = $window.FindName("LogPanel")
if ($null -eq $logPanel -or $logPanel.Visibility -ne "Collapsed") {
    throw "The log should be collapsed until a task starts."
}

# Raise the safe UI events the same way WPF does, so a broken handler fails CI.
# Handlers that install, change Windows, open dialogs, or go online are skipped.
$script:WinToolUiQuiet = $true
$script:WinToolUiErrors = $null
$skip = @(
    "Install: install selected",
    "Install: update selected",
    "Install: uninstall selected",
    "Install: update all",
    "Install: update one app",
    "Install: install one app",
    "Install: open app",
    "Install: uninstall one app",
    "Install: check installed",
    "Check installed apps",
    "Features: apply changes",
    "Features: refresh state",
    "Tweaks: switch",
    "Tweaks: preset",
    "Terminal: apply setup",
    "Terminal: refresh lists",
    "Updates: scan",
    "Updates: open Windows Update",
    "Updates: open optional updates",
    "Updates: install scanned updates",
    "Updates: apply mode",
    "Updates: back to default",
    "Updates: vendor downloads",
    "Config: save profile",
    "Config: load profile",
    "Config: export winget list",
    "Config: import winget list",
    "Config: apply DNS",
    "Config: add Ultimate Performance",
    "Config: remove Ultimate Performance",
    "Cancel",
    "Open project link",
    "Close WinTool",
    "Window closed",
    "Keyboard shortcut",
    "Appearance: accent color",
    "Appearance: theme"
)
# Every handler whose name starts with one of these changes the system.
$skipPrefix = @("Fixes: ")
$raised = 0
foreach ($entry in $script:WinToolUiHandlers.ToArray()) {
    if ($skip -contains [string]$entry.Name) {
        continue
    }
    $prefixed = $false
    foreach ($prefix in $skipPrefix) {
        if (([string]$entry.Name).StartsWith($prefix)) {
            $prefixed = $true
        }
    }
    if ($prefixed) {
        continue
    }
    $control = $entry.Control
    switch ([string]$entry.EventName) {
        "Click" {
            $clickEvent = [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
            if ($control -is [System.Windows.Controls.MenuItem]) {
                $clickEvent = [System.Windows.Controls.MenuItem]::ClickEvent
            }
            $control.RaiseEvent([System.Windows.RoutedEventArgs]::new($clickEvent))
        }
        "Checked" {
            $control.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ToggleButton]::CheckedEvent))
        }
        "Unchecked" {
            $control.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ToggleButton]::UncheckedEvent))
        }
        "MouseLeftButtonUp" {
            $mouseArgs = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $mouseArgs.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $control.RaiseEvent($mouseArgs)
        }
        "TextChanged" {
            $control.Text = "a"
            $control.Text = ""
        }
        "SelectionChanged" {
            if ($control.Items.Count -gt 1) {
                $control.SelectedIndex = 1
                $control.SelectedIndex = 0
            }
        }
        default {
            Invoke-WinToolUiEvent -Id ([int]$entry.Id) -Source $control -EventData $null
        }
    }
    $raised++
}

# Picking each prompt engine must update the Terminal choice, the theme
# column title, and the theme list.
$window.FindName("TerminalFilterNoNerd").IsChecked = $true
$filterResetSeen = $false
foreach ($engine in $promptItems) {
    $engineChanged = ([string]$script:WinToolTerminalChoice.prompt -ne [string]$engine.Tag)
    $promptList.SelectedItem = $engine
    if ($engineChanged -and $window.FindName("TerminalFilterAll").IsChecked -ne $true) {
        throw "Picking a prompt engine should reset the theme filter to All."
    }
    if ($engineChanged) { $filterResetSeen = $true }
    if ([string]$script:WinToolTerminalChoice.prompt -ne [string]$engine.Tag) {
        throw ("Picking the prompt engine '" + [string]$engine.Tag + "' did not select it.")
    }
    if ([string]$window.FindName("TerminalStyleList").Tag -ne [string]$engine.Tag -or $window.FindName("TerminalStyleList").Items.Count -lt 1) {
        throw ("The theme list did not follow the prompt engine '" + [string]$engine.Tag + "'.")
    }
}
if (-not $filterResetSeen) {
    throw "No prompt engine change was tested."
}
# The group headers in the engine list cannot be picked.
if (@($promptList.Items | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Tag) -and $_.IsEnabled }).Count -ne 0) {
    throw "The engine group headers should not be selectable."
}
# Clicking a color scheme tile must update the choice.
foreach ($tile in ($window.FindName("TerminalSchemeHost").Children | ForEach-Object { $_ })) {
    $mouseArgs = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
    $mouseArgs.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
    $tile.RaiseEvent($mouseArgs)
    if ([string]$script:WinToolTerminalChoice.schemeId -ne [string]$tile.Tag) {
        throw ("Clicking the color scheme '" + [string]$tile.Tag + "' did not select it.")
    }
}

# Installed and update badges follow the detected state.
$firstApp = $appRows[0]
$secondApp = $appRows[1]
$null = Set-WinToolAppState -InstalledId @($firstApp.WingetId) -UpgradeText ("Name Id Version Available`n" + $secondApp.Name + " " + $secondApp.WingetId + " 1.0 2.0")
if (-not $firstApp.Installed -or $firstApp.UpdateAvailable) {
    throw "The Installed badge did not follow the detected state."
}
if (-not $secondApp.UpdateAvailable -or -not $secondApp.Installed) {
    throw "The Update available badge did not follow the upgrade list."
}
$thirdApp = $appRows[2]
$byNameState = Set-WinToolAppState -InstalledId @($firstApp.WingetId) -UpgradeText ("Name Id Version Available`n" + $secondApp.Name + " " + $secondApp.WingetId + " 1.0 2.0") -DisplayName @(($thirdApp.Name + " 1.2.3 (64-bit)"))
if (-not $thirdApp.Installed -or @($byNameState.ByName) -notcontains $thirdApp.WingetId) {
    throw "An app found by its Apps and features name did not get the Installed badge."
}
$null = Set-WinToolAppState -InstalledId @($firstApp.WingetId) -UpgradeText ("Name Id Version Available`n" + $secondApp.Name + " " + $secondApp.WingetId + " 1.0 2.0")
# Notepad++ has plus signs in its id and name. It must get the badge from the
# export, from winget list alone, and from a shortened list id.
$notepadRow = @($appRows | Where-Object { [string]$_.WingetId -eq "Notepad++.Notepad++" })[0]
if ($null -eq $notepadRow) {
    throw "The catalog row for Notepad++ is missing."
}
$notepadCases = @(
    @{ Ids = @("Notepad++.Notepad++"); List = "" },
    @{ Ids = @(); List = "Notepad++ (x64)  Notepad++.Notepad++ 8.9.9.1 winget" },
    @{ Ids = @(); List = ("Notepad++ (x64)  Notepad++.Notep" + [char]0x2026 + " 8.9.9.1 winget") }
)
foreach ($case in $notepadCases) {
    $null = Set-WinToolAppState -InstalledId @() -UpgradeText "" -ListText ""
    $result = Set-WinToolAppState -InstalledId $case.Ids -UpgradeText "" -ListText $case.List
    if (-not $notepadRow.Installed -or @($result.InstalledIds) -notcontains "Notepad++.Notepad++") {
        throw ("Notepad++ did not get the Installed badge for: " + (@($case.Ids) -join ",") + " / " + $case.List)
    }
}
Write-Output "Notepad++ gets the Installed badge from export, list, and a shortened id."
$null = Set-WinToolAppState -InstalledId @($firstApp.WingetId) -UpgradeText ("Name Id Version Available`n" + $secondApp.Name + " " + $secondApp.WingetId + " 1.0 2.0")
Select-WinToolInstalledApp
if ($firstApp.Checkbox.IsChecked -ne $true -or $secondApp.Checkbox.IsChecked -ne $true -or $appRows[2].Checkbox.IsChecked -eq $true) {
    throw "Select installed did not tick exactly the installed apps."
}

# Feature ticks follow the state Windows reports.
$featureRows = @($script:WinToolState.FeatureRows)
if ($featureRows.Count -lt 8) {
    throw "The Features tab did not list the optional features."
}
$fakeState = @{}
foreach ($name in @($featureRows[0].Feature.names)) { $fakeState[[string]$name] = "Enabled" }
foreach ($name in @($featureRows[1].Feature.names)) { $fakeState[[string]$name] = "Disabled" }
Set-WinToolFeatureState -State $fakeState
if ($featureRows[0].Checkbox.IsChecked -ne $true -or $featureRows[1].Checkbox.IsChecked -ne $false -or $featureRows[2].Checkbox.IsEnabled) {
    throw "Feature checkboxes did not follow the reported state."
}
$featureRows[0].Checkbox.IsChecked = $false
$featureRows[1].Checkbox.IsChecked = $true
$featureChange = Get-WinToolFeatureChange
if (@($featureChange.Enable).Count -ne 1 -or @($featureChange.Disable).Count -ne 1) {
    throw "Feature changes were not worked out from the ticks."
}

# Installed-app detection on Windows PowerShell 5.1, first with a stand-in
# winget that writes to stderr (which used to abort the check on 5.1), then
# with the real winget when the runner has one.
$fixtures = Join-Path $PSScriptRoot "fixtures"
$fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-fake-winget-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
$fakeWinget = Join-Path $fakeDir "winget.cmd"
$fakeLines = @(
    "@echo off",
    "if ""%~1""==""--version"" (echo v1.29.380& exit /b 0)",
    ("if ""%~1""==""export"" (echo stderr noise 1>&2& copy /y ""{0}"" ""%~3"" >nul& exit /b 0)" -f (Join-Path $fixtures "winget-export.json")),
    ("if ""%~1""==""list"" (type ""{0}""& exit /b 0)" -f (Join-Path $fixtures "winget-list-ptbr.txt")),
    "if ""%~1""==""upgrade"" (echo Name Id Version Available& echo 7-Zip 7zip.7zip 24.08 24.09& exit /b 0)",
    "exit /b 1"
)
[System.IO.File]::WriteAllText($fakeWinget, ($fakeLines -join "`r`n") + "`r`n")
$oldPreference = $ErrorActionPreference
$stderrAborts = $false
try {
    $ErrorActionPreference = "Stop"
    $null = & $fakeWinget export --output (Join-Path $fakeDir "probe.json") 2>&1
}
catch {
    $stderrAborts = $true
}
finally {
    $ErrorActionPreference = $oldPreference
}
Write-Output ("Windows PowerShell 5.1 aborts on winget stderr under ErrorActionPreference Stop: " + $stderrAborts)
$detectJob = Start-WinToolScriptJob -ScriptText (Get-WinToolAppDetectionScript) -Argument @(@((Join-Path $fakeDir "missing\winget.exe"), $fakeWinget), (Join-Path $fakeDir "export.json"))
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while (-not $detectJob.Sync.Done -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 200
}
$detectOk = [bool]$detectJob.Sync.Ok
$detectError = [string]$detectJob.Sync.Error
$detectIds = @(ConvertFrom-WinToolWingetExport -Text ([string]$detectJob.Sync.ExportText))
$detectList = [string]$detectJob.Sync.ListText
Stop-WinToolThread -Job $detectJob
Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
if (-not $detectOk -or $detectIds.Count -ne 12 -or -not $detectList.Contains("Google.Chrome")) {
    throw ("Installed-app detection failed with a stand-in winget on 5.1: ok={0} ids={1} error={2}" -f $detectOk, $detectIds.Count, $detectError)
}
Write-Output "Installed-app detection works on 5.1 with a winget that writes to stderr."

$realCandidates = @(Get-WinToolWingetCandidate)
if ($realCandidates.Count -eq 0) {
    Write-Output "No winget on this runner; skipped the real detection run."
}
else {
    $script:WinToolState.DetectJob = $null
    Start-WinToolAppDetection
    $realJob = $script:WinToolState.DetectJob
    $deadline = [DateTime]::UtcNow.AddSeconds(240)
    while ($null -ne $realJob -and -not $realJob.Sync.Done -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if ($null -ne $realJob) {
        foreach ($line in @($realJob.Sync.Log.ToArray())) {
            Write-Output ("Real winget: " + $line)
        }
        if ($realJob.Sync.Done) {
            Complete-WinToolAppDetection
        }
        else {
            Stop-WinToolThread -Job $realJob
            $script:WinToolState.DetectJob = $null
            Write-Output "Real winget: still running after 240 seconds."
        }
    }
    Write-Output ("Real winget status: " + $window.FindName("AppInstalledStatus").Text)
}

# Render the Terminal tab (Advanced) to PNG files without showing the window,
# at a wide and a narrow size, so the layout can be checked from CI artifacts.
$shotFolder = $env:WINTOOL_SHOT_DIR
if ([string]::IsNullOrWhiteSpace($shotFolder)) {
    $shotFolder = Join-Path ([System.IO.Path]::GetTempPath()) "wintool-shots"
}
New-Item -ItemType Directory -Path $shotFolder -Force | Out-Null
$window.FindName("NavTerminal").IsChecked = $true
$window.FindName("TerminalModeSimple").IsChecked = $true
$window.FindName("TerminalModeAdvanced").IsChecked = $true
# Back to the recommended choices (the event test above clicked others) and
# the log folded, as a person opening the tab would see it.
$script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
(Get-WinToolUi -Name "TerminalThemeSearch").Text = ""
$script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
Update-WinToolPromptSelection
Update-WinToolSchemeSelection
Update-WinToolFontList
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
# Let the theme download for the preview finish (or give up) so the shot
# shows the real colors; the window never waits for it.
$previewWait = [datetime]::UtcNow.AddSeconds(20)
while ($null -ne $script:WinToolState.PreviewJob -and [datetime]::UtcNow -lt $previewWait) {
    if ($script:WinToolState.PreviewJob.Job.Sync.Done) { Complete-WinToolPreviewThemeDownload; break }
    Start-Sleep -Milliseconds 200
}
Update-WinToolTerminalPreview
if ([string]$window.FindName("TerminalFontList").SelectedItem.Tag -ne "cascadiacode-nf") {
    throw "The recommended font should be selected in the font list."
}
if ([string]$window.FindName("TerminalStyleList").SelectedItem.Tag -ne "jandedobbeleer") {
    throw "The recommended theme should be selected in the theme list."
}
if ($window.FindName("TerminalFontSample").Inlines.Count -lt 3) {
    throw "The Terminal preview did not draw the prompt line."
}
$script:WinToolState.LogExpanded = $false
$script:WinToolState.Busy = $false
Sync-WinToolLogPanel
$rootVisual = $window.Content
function Invoke-WinToolTerminalShotLayout {
    param([double]$Width, [double]$Height)
    # Lays the window out at a size, then lets the Terminal body take its
    # real height (fill, or a fixed height that scrolls) and lays out again.
    Update-WinToolTerminalLayout -Width ($Width - 248 - 40) -Height 0
    $rootVisual.Measure([System.Windows.Size]::new($Width, $Height))
    $rootVisual.Arrange([System.Windows.Rect]::new(0, 0, $Width, $Height))
    $rootVisual.UpdateLayout()
    $body = $window.FindName("TerminalBodyScroll")
    Update-WinToolTerminalLayout -Width $body.ActualWidth -Height $body.ActualHeight
    $rootVisual.Measure([System.Windows.Size]::new($Width, $Height))
    $rootVisual.Arrange([System.Windows.Rect]::new(0, 0, $Width, $Height))
    $rootVisual.UpdateLayout()
}

function Get-WinToolVisualChild {
    param($Root)
    # Every element under Root in the visual tree.
    $found = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Generic.Queue[object]
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $found.Add($node)
        if ($node -isnot [System.Windows.Media.Visual]) { continue }
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($node)
        for ($index = 0; $index -lt $count; $index++) {
            $queue.Enqueue([System.Windows.Media.VisualTreeHelper]::GetChild($node, $index))
        }
    }
    return $found.ToArray()
}

function Test-WinToolInsidePreview {
    param($Element)
    # True for the live terminal sample and theme sample lines: their size
    # follows the chosen terminal font (content, not interface text).
    $node = $Element
    while ($null -ne $node) {
        if ($node -is [System.Windows.FrameworkElement]) {
            if ([string]$node.Name -eq "TerminalFontPreview" -or [string]$node.Tag -eq "preview-content") { return $true }
        }
        $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
    }
    return $false
}

function Assert-WinToolTerminalText {
    param([string]$Label)
    # The 14 px standard on the Terminal page: every text is FontSizeBody,
    # only the page title is FontSizeTitle, and no single-line text is cut off.
    $view = $window.FindName("ViewTerminal")
    $body = [double]$window.FindResource("FontSizeBody")
    $title = [double]$window.FindResource("FontSizeTitle")
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($node in @(Get-WinToolVisualChild -Root $view)) {
        if ($node -isnot [System.Windows.FrameworkElement] -or -not $node.IsVisible) { continue }
        if (Test-WinToolInsidePreview -Element $node) { continue }
        if ($node -is [System.Windows.Controls.TextBlock]) {
            $size = [double]$node.FontSize
            if ($size -ne $body -and -not ($size -eq $title -and [string]$node.Text -eq "Terminal")) {
                $problems.Add(("'" + [string]$node.Text + "' is " + $size + " px"))
            }
            if ($node.TextWrapping -eq "NoWrap" -and $node.ActualWidth -gt 0 -and -not [string]::IsNullOrEmpty([string]$node.Text)) {
                $typeface = New-Object System.Windows.Media.Typeface($node.FontFamily, $node.FontStyle, $node.FontWeight, $node.FontStretch)
                $formatted = New-Object System.Windows.Media.FormattedText([string]$node.Text, [System.Globalization.CultureInfo]::CurrentUICulture, [System.Windows.FlowDirection]::LeftToRight, $typeface, $size, [System.Windows.Media.Brushes]::Black, 1.0)
                if ($formatted.WidthIncludingTrailingWhitespace -gt $node.ActualWidth + 1) {
                    $problems.Add(("'" + [string]$node.Text + "' is cut off: " + [Math]::Round($formatted.WidthIncludingTrailingWhitespace) + " > " + [Math]::Round($node.ActualWidth)))
                }
            }
        }
        elseif ($node -is [System.Windows.Controls.Control] -and $node -isnot [System.Windows.Controls.ScrollViewer] -and $node -isnot [System.Windows.Controls.Primitives.ScrollBar]) {
            if ([double]$node.FontSize -ne $body) {
                $problems.Add(($node.GetType().Name + " " + [string]$node.Name + " is " + [double]$node.FontSize + " px"))
            }
        }
    }
    if ($problems.Count -gt 0) {
        throw ("Terminal text at " + $Label + ": " + (($problems | Select-Object -Unique) -join "; "))
    }
    Write-Output ("Terminal text at " + $Label + ": all 14 px, nothing cut off.")
}

foreach ($size in @(@(1280, 760, "mockup"), @(1280, 900, "wide"), @(1000, 1300, "narrow"))) {
    $shotWidth = [double]$size[0]
    $shotHeight = [double]$size[1]
    Invoke-WinToolTerminalShotLayout -Width $shotWidth -Height $shotHeight
    Show-WinToolTerminalSelection
    $rootVisual.UpdateLayout()
    Assert-WinToolTerminalText -Label ([string]$size[0] + " x " + [string]$size[1])
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$shotWidth, [int]$shotHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    # The window background is not part of its content, so paint it first.
    $backdrop = New-Object System.Windows.Media.DrawingVisual
    $context = $backdrop.RenderOpen()
    $context.DrawRectangle($window.Background, $null, [System.Windows.Rect]::new(0, 0, $shotWidth, $shotHeight))
    $context.Close()
    $bitmap.Render($backdrop)
    $bitmap.Render($rootVisual)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $shotPath = Join-Path $shotFolder ("terminal-advanced-" + $size[2] + ".png")
    $stream = [System.IO.File]::Create($shotPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Output ("Saved " + $shotPath)
}
$advancedGrid = $window.FindName("TerminalAdvancedHost")
$sideColumn = $window.FindName("TerminalSideColumn")
Update-WinToolTerminalLayout -Width 1000
if ([System.Windows.Controls.Grid]::GetColumn($sideColumn) -ne 4 -or [System.Windows.Controls.Grid]::GetRow($sideColumn) -ne 0) {
    throw "The preview, font, and extras should sit in the right column on a wide window."
}
Update-WinToolTerminalLayout -Width 700
if ([System.Windows.Controls.Grid]::GetRow($sideColumn) -ne 1 -or [System.Windows.Controls.Grid]::GetColumnSpan($sideColumn) -ne 5) {
    throw "The preview, font, and extras should move under the lists on a narrow window."
}
Update-WinToolTerminalLayout -Width 1000
$summaryChips = @($window.FindName("TerminalSummaryHost").Children | ForEach-Object { $_ })
if ($null -eq $advancedGrid -or $summaryChips.Count -lt 3) {
    throw "The Terminal action bar did not list the steps."
}
$ligatureChip = @($summaryChips | Where-Object { $_ -is [System.Windows.Controls.Border] -and $_.Child -is [System.Windows.Controls.TextBlock] -and [string]$_.Child.Text -like "*Font ligatures on*" })
if ($ligatureChip.Count -ne 1) {
    throw "The Terminal action bar should show one 'Font ligatures on' change."
}
$ligatureNote = $window.FindName("TerminalFontLigatureNote")
if ($null -eq $ligatureNote -or [string]$ligatureNote.Text -notlike "*ligatures*" -or $ligatureNote.Visibility -ne "Visible") {
    throw "The Font and colors card should note that ligatures are always on."
}
$previewSample = $window.FindName("TerminalFontSample")
if (-not [System.Windows.Documents.Typography]::GetStandardLigatures($previewSample) -or -not [System.Windows.Documents.Typography]::GetContextualAlternates($previewSample)) {
    throw "The live preview should draw font ligatures."
}
$themeLine = $null
foreach ($themeItem in ($window.FindName("TerminalStyleList").Items | ForEach-Object { $_ })) {
    $parts = @($themeItem.Content.Children | Where-Object { $_ -is [System.Windows.Controls.Border] })
    if ($parts.Count -gt 0) { $themeLine = $parts[0].Child; break }
}
if ($null -ne $themeLine -and -not [System.Windows.Documents.Typography]::GetStandardLigatures($themeLine)) {
    throw "Theme previews should draw font ligatures."
}
# Sizes from the 14 px standard: chips and buttons 32, search 34, engine rows about 36.
Invoke-WinToolTerminalShotLayout -Width 1280 -Height 760
foreach ($chipName in @("TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalSetup", "TerminalRefresh")) {
    $chipControl = $window.FindName($chipName)
    if ([Math]::Abs($chipControl.ActualHeight - 32) -gt 0.5) { throw ($chipName + " should be 32 px tall, not " + $chipControl.ActualHeight) }
}
foreach ($chipElement in $summaryChips) {
    if ([Math]::Abs($chipElement.ActualHeight - 32) -gt 0.5) { throw ("Action chips should be 32 px tall, not " + $chipElement.ActualHeight) }
}
if ([Math]::Abs($window.FindName("TerminalThemeSearch").ActualHeight - 34) -gt 0.5) { throw "The theme search box should be 34 px tall." }
foreach ($engineRow in @($window.FindName("TerminalPromptList").Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Tag) })) {
    if ($engineRow.ActualHeight -gt 0 -and ($engineRow.ActualHeight -lt 32 -or $engineRow.ActualHeight -gt 40)) {
        throw ("Engine rows should be about 36 px tall, not " + $engineRow.ActualHeight)
    }
}
$segmentHeight = $window.FindName("TerminalModeAdvanced").ActualHeight + 2
if ([Math]::Abs($segmentHeight - 32) -gt 0.5) { throw ("The Simple / Advanced control should be 32 px tall, not " + $segmentHeight) }
# The four filter chips sit on one line at 1280 px.
$chipTops = @(@("TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd") | ForEach-Object { [Math]::Round($window.FindName($_).TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual).Y) } | Select-Object -Unique)
if ($chipTops.Count -ne 1) { throw "The theme filter chips should fit on one line at 1280 px." }
# Checkboxes use the shared rounded checkbox: no local style, no focus rectangle.
$terminalBoxes = @($window.FindName("TerminalEnabled"), $window.FindName("TerminalFontNerdOnly")) + @($script:WinToolTerminalExtraBox)
foreach ($terminalBox in $terminalBoxes) {
    if ($terminalBox.ReadLocalValue([System.Windows.FrameworkElement]::StyleProperty) -ne [System.Windows.DependencyProperty]::UnsetValue) {
        throw ("The checkbox " + [System.Windows.Automation.AutomationProperties]::GetName($terminalBox) + [string]$terminalBox.Content + " should use the shared rounded checkbox.")
    }
    if ($null -ne $terminalBox.FocusVisualStyle) { throw "Terminal checkboxes should not draw a dotted focus rectangle." }
    $boxPart = $terminalBox.Template.FindName("Box", $terminalBox)
    if ($null -eq $boxPart -or [Math]::Abs($boxPart.ActualWidth - 20) -gt 0.5) { throw "Terminal checkboxes should be the 20 px rounded box." }
}
# The action bar stays fully in view at 1280 x 760; a short body scrolls instead of clipping cards.
$summaryCard = $window.FindName("TerminalSummaryCard")
$summaryBottom = $summaryCard.TranslatePoint([System.Windows.Point]::new(0, $summaryCard.ActualHeight), $rootVisual).Y
if ($summaryBottom -gt 760) { throw ("The Terminal action bar should stay in view at 1280 x 760: bottom at " + $summaryBottom) }
$bodyScroll = $window.FindName("TerminalBodyScroll")
$advancedHost = $window.FindName("TerminalAdvancedHost")
$bodyNeed = Get-WinToolTerminalBodyMinHeight -Width $bodyScroll.ActualWidth
if ($advancedHost.ActualHeight + 0.5 -lt $bodyNeed) { throw ("The Advanced body should never be squeezed below " + $bodyNeed + " px.") }
Write-Output ("Terminal body at 1280 x 760: viewport " + [Math]::Round($bodyScroll.ViewportHeight) + " px, cards need " + $bodyNeed + " px, scrolls " + [Math]::Max(0, [Math]::Round($bodyScroll.ExtentHeight - $bodyScroll.ViewportHeight)) + " px.")
Invoke-WinToolTerminalShotLayout -Width 1000 -Height 1300
$engineScroll = $null
foreach ($node in @(Get-WinToolVisualChild -Root $window.FindName("TerminalPromptList"))) { if ($node -is [System.Windows.Controls.ScrollViewer]) { $engineScroll = $node; break } }
if ($null -ne $engineScroll -and $engineScroll.ExtentHeight -gt $engineScroll.ViewportHeight + 1) {
    throw ("On a narrow window every prompt engine should show without scrolling the list: " + $engineScroll.ExtentHeight + " > " + $engineScroll.ViewportHeight)
}
Invoke-WinToolTerminalShotLayout -Width 1280 -Height 900
Write-Output ("Terminal body at 1280 x 900: viewport " + [Math]::Round($bodyScroll.ViewportHeight) + " px, scrolls " + [Math]::Max(0, [Math]::Round($bodyScroll.ExtentHeight - $bodyScroll.ViewportHeight)) + " px.")
# Filters narrow the theme list, and the font size reaches the plan.
$script:WinToolTerminalChoice.prompt = "starship"
Update-WinToolPromptStyleList
$allCount = $window.FindName("TerminalStyleList").Items.Count
$window.FindName("TerminalFilterPowerline").IsChecked = $true
$powerCount = $window.FindName("TerminalStyleList").Items.Count
$window.FindName("TerminalFilterAll").IsChecked = $true
if ($powerCount -lt 1 -or $powerCount -ge $allCount -or $window.FindName("TerminalStyleList").Items.Count -ne $allCount) {
    throw ("The Powerline filter should narrow the Starship presets: " + $powerCount + " of " + $allCount)
}
$sizeBox = $window.FindName("TerminalFontSize")
foreach ($sizeItem in ($sizeBox.Items | ForEach-Object { $_ })) { if ([int]$sizeItem.Tag -eq 14) { $sizeBox.SelectedItem = $sizeItem } }
if ([int](Get-WinToolTerminalChoice).fontSize -ne 14 -or @(Get-WinToolTerminalPlan -Selection (Get-WinToolTerminalChoice) | Where-Object { $_.Type -eq "font" -and [int]$_.Size -eq 14 }).Count -ne 1) {
    throw "The chosen font size should reach the terminal plan."
}
foreach ($sizeItem in ($sizeBox.Items | ForEach-Object { $_ })) { if ([int]$sizeItem.Tag -eq 12) { $sizeBox.SelectedItem = $sizeItem } }
$script:WinToolTerminalChoice.prompt = "oh-my-posh"
$script:WinToolTerminalChoice.promptStyle = "jandedobbeleer"
Update-WinToolPromptStyleList
Update-WinToolPromptSelection

function Save-WinToolTerminalShot {
    param([string]$Name, [double]$Width, [double]$Height)
    Invoke-WinToolTerminalShotLayout -Width $Width -Height $Height
    Show-WinToolTerminalSelection
    $rootVisual.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$Width, [int]$Height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $backdrop = New-Object System.Windows.Media.DrawingVisual
    $context = $backdrop.RenderOpen()
    $context.DrawRectangle($window.Background, $null, [System.Windows.Rect]::new(0, 0, $Width, $Height))
    $context.Close()
    $bitmap.Render($backdrop)
    $bitmap.Render($rootVisual)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path = Join-Path $shotFolder ($Name + ".png")
    $stream = [System.IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Output ("Saved " + $path)
}

# Card 2 always matches the checked engine. The old bug: Advanced, pick
# Starship, go to Simple (the choice resets to Oh My Posh), back to Advanced:
# Oh My Posh was checked but card 2 still listed the Starship presets.
$window.FindName("NavTerminal").IsChecked = $true
$window.FindName("TerminalModeAdvanced").IsChecked = $true
$themeList = $window.FindName("TerminalStyleList")
function Assert-WinToolThemeCard {
    param([string]$Label)
    $engine = [string]$script:WinToolTerminalChoice.prompt
    $want = Get-WinToolThemeTitle -PromptId $engine
    $rows = @(Get-WinToolThemeRow -PromptId $engine -OhMyPoshTheme @(Get-WinToolActiveOhMyPoshTheme))
    if ([string]$themeList.Tag -ne $engine) { throw ($Label + ": card 2 was built for '" + [string]$themeList.Tag + "' but '" + $engine + "' is checked.") }
    if ([string]$window.FindName("TerminalThemeTitle").Text -ne [string]$want.Title) { throw ($Label + ": card 2 is titled '" + $window.FindName("TerminalThemeTitle").Text + "', expected '" + $want.Title + "'.") }
    if ($themeList.Items.Count -ne $rows.Count) { throw ($Label + ": card 2 lists " + $themeList.Items.Count + " items, the " + $engine + " catalog has " + $rows.Count + ".") }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ([string]$themeList.Items[$i].Tag -ne [string]$rows[$i].Id) { throw ($Label + ": item " + $i + " is '" + [string]$themeList.Items[$i].Tag + "', expected '" + [string]$rows[$i].Id + "'.") }
    }
    if ([string]$window.FindName("TerminalThemeCount").Text -ne ([string]$rows.Count + " of " + [string]$rows.Count)) { throw ($Label + ": the count reads '" + $window.FindName("TerminalThemeCount").Text + "'.") }
    $engineName = [string]$window.FindName("TerminalPromptName").Text
    if (-not ([string]$window.FindName("TerminalPreviewInfo").Text).StartsWith($engineName)) { throw ($Label + ": the preview describes '" + $window.FindName("TerminalPreviewInfo").Text + "', not " + $engineName + ".") }
    if ($rows.Count -gt 0 -and [string]$script:WinToolTerminalChoice.promptStyle -notin @($rows | ForEach-Object { [string]$_.Id })) { throw ($Label + ": the chosen style '" + $script:WinToolTerminalChoice.promptStyle + "' is not in the " + $engine + " list.") }
}
Select-WinToolTerminalPrompt -PromptId "starship"
$window.FindName("TerminalModeSimple").IsChecked = $true
$window.FindName("TerminalModeAdvanced").IsChecked = $true
Assert-WinToolThemeCard -Label "Simple then Advanced"
Write-Output ("Simple then Advanced: card 2 is '" + $window.FindName("TerminalThemeTitle").Text + "' for " + $script:WinToolTerminalChoice.prompt)

# Strict rule: clicking never moves or resizes the main Terminal panels.
function Get-WinToolTerminalBound {
    $bounds = @{}
    foreach ($panelName in @("TerminalCardPrompt", "TerminalCardTheme", "TerminalCardPreview", "TerminalCardFont", "TerminalCardExtras", "TerminalSummaryCard", "TerminalSummaryScroll", "TerminalSetup", "TerminalPromptList", "TerminalStyleList")) {
        $element = $window.FindName($panelName)
        $origin = $element.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
        $bounds[$panelName] = ("{0:0.0},{1:0.0} {2:0.0}x{3:0.0}" -f $origin.X, $origin.Y, $element.ActualWidth, $element.ActualHeight)
    }
    return $bounds
}
function Assert-WinToolTerminalBound {
    param($Before, [string]$Label)
    Invoke-WinToolTerminalShotLayout -Width 1280 -Height 760
    $after = Get-WinToolTerminalBound
    foreach ($key in $Before.Keys) {
        if ($after[$key] -ne $Before[$key]) { throw ($Label + " moved or resized " + $key + ": " + $Before[$key] + " -> " + $after[$key]) }
    }
}
Select-WinToolTerminalPrompt -PromptId "oh-my-posh"
Invoke-WinToolTerminalShotLayout -Width 1280 -Height 760
$terminalBounds = Get-WinToolTerminalBound
$clickEvent = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)
foreach ($pass in @(1, 2)) {
    foreach ($extraBox in @($script:WinToolTerminalExtraBox)) {
        $extraBox.IsChecked = -not ($extraBox.IsChecked -eq $true)
        $extraBox.RaiseEvent($clickEvent)
        Assert-WinToolTerminalBound -Before $terminalBounds -Label ("Toggling the extra " + [string]$extraBox.Tag)
    }
}
Write-Output ("Toggled " + @($script:WinToolTerminalExtraBox).Count + " extras on and off: the cards, the action bar, and Apply never moved; " + $window.FindName("TerminalSummaryHost").Children.Count + " chips on one line.")
$engines = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @())
foreach ($engine in $engines) {
    Select-WinToolTerminalPrompt -PromptId ([string]$engine.id)
    Assert-WinToolThemeCard -Label ("Engine " + [string]$engine.id)
    Assert-WinToolTerminalBound -Before $terminalBounds -Label ("Picking " + [string]$engine.id)
}
Write-Output ("Checked " + $engines.Count + " engines: card 2, its title, count, and the preview match each one, and nothing moved.")
$script:WinToolState.LogExpanded = $true
Sync-WinToolLogPanel
Assert-WinToolTerminalBound -Before $terminalBounds -Label "Opening the log"
$script:WinToolState.LogExpanded = $false
Sync-WinToolLogPanel
$script:WinToolTerminalChoice.prompt = "oh-my-posh"
$script:WinToolTerminalChoice.promptStyle = "jandedobbeleer"
Select-WinToolTerminalPrompt -PromptId "oh-my-posh"
foreach ($extraBox in @($script:WinToolTerminalExtraBox)) { $extraBox.IsChecked = $true; $extraBox.RaiseEvent($clickEvent) }
Save-WinToolTerminalShot -Name "terminal-extras-all-on" -Width 1280 -Height 760
foreach ($extraBox in @($script:WinToolTerminalExtraBox)) { $extraBox.IsChecked = ([string]$extraBox.Tag -in @("terminal-icons", "psreadline")); $extraBox.RaiseEvent($clickEvent) }
Save-WinToolTerminalShot -Name "terminal-extras-default" -Width 1280 -Height 760

# Prompt styles: Powerlevel10k shows its styles in the theme list, and the
# preview draws the chosen style's colored blocks. Long lists scroll inside
# their fixed-height card.
$styleList = $window.FindName("TerminalStyleList")
$listHeight = $styleList.ActualHeight
$script:WinToolTerminalChoice.prompt = "powerlevel10k"
$script:WinToolTerminalChoice.promptStyle = "rainbow"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
if ([string]$styleList.SelectedItem.Tag -ne "rainbow" -or $styleList.Items.Count -lt 4) {
    throw "Powerlevel10k should list its styles with Rainbow selected."
}
$blocks = @($window.FindName("TerminalFontSample").Inlines | Where-Object { $_ -is [System.Windows.Documents.Run] -and $null -ne $_.Background })
if ($blocks.Count -lt 2) { throw "The Rainbow preview should draw colored blocks." }
$planText = (@(Get-WinToolTerminalPlan -Selection $script:WinToolTerminalChoice | ForEach-Object { [string]$_.Label }) -join " | ")
Write-Output ("Powerlevel10k plan: " + $planText)
$styleList.SelectedIndex = 0
if ([string]$script:WinToolTerminalChoice.promptStyle -ne [string]$styleList.Items[0].Tag) {
    throw "Picking another style should change the Terminal choice."
}
$styleList.SelectedIndex = 2
Save-WinToolTerminalShot -Name "terminal-p10k" -Width 1280 -Height 760
$script:WinToolTerminalChoice.prompt = "starship"
$script:WinToolTerminalChoice.promptStyle = "pastel-powerline"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
$blocks = @($window.FindName("TerminalFontSample").Inlines | Where-Object { $_ -is [System.Windows.Documents.Run] -and $null -ne $_.Background })
if ($blocks.Count -lt 2) { throw "The Starship Pastel powerline preview should draw colored blocks." }
Save-WinToolTerminalShot -Name "terminal-starship" -Width 1280 -Height 760
$script:WinToolTerminalChoice.prompt = "oh-my-zsh"
$script:WinToolTerminalChoice.promptStyle = "agnoster"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
Save-WinToolTerminalShot -Name "terminal-omz" -Width 1280 -Height 760
if ($styleList.Items.Count -lt 100 -or $styleList.ActualHeight -gt ($listHeight + 120)) {
    throw ("The Oh My Zsh list should scroll inside its card: " + $styleList.Items.Count + " themes, height " + $styleList.ActualHeight + " vs " + $listHeight)
}
if ([string]$styleList.SelectedItem.Tag -ne "agnoster") { throw "agnoster should stay selected in the long list." }
$script:WinToolTerminalChoice.prompt = "oh-my-posh"
$script:WinToolTerminalChoice.promptStyle = "jandedobbeleer"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary

# Install and Tweaks tabs at 1280x760 (the approved mockups) and narrower.
function Save-WinToolViewShot {
    param([string]$Name, [double]$Width, [double]$Height)
    $rootVisual.Measure([System.Windows.Size]::new($Width, $Height))
    $rootVisual.Arrange([System.Windows.Rect]::new(0, 0, $Width, $Height))
    $rootVisual.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$Width, [int]$Height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $backdrop = New-Object System.Windows.Media.DrawingVisual
    $context = $backdrop.RenderOpen()
    $context.DrawRectangle($window.Background, $null, [System.Windows.Rect]::new(0, 0, $Width, $Height))
    $context.Close()
    $bitmap.Render($backdrop)
    $bitmap.Render($rootVisual)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path = Join-Path $shotFolder ($Name + ".png")
    $stream = [System.IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Output ("Saved " + $path)
}

# Sample state like the mockup: a few installed apps and two with updates.
Sync-WinToolAppCheck -Id @() -OnlyThese
$script:WinToolState.AppStartApps = @("Google Chrome`tChrome", "Discord`tcom.squirrel.Discord.Discord", "Telegram Desktop`tTelegram", "7-Zip File Manager`t7zFM")
$sampleIds = @()
foreach ($wingetId in @("Google.Chrome", "Brave.Brave", "Discord.Discord", "Telegram.TelegramDesktop", "Spotify.Spotify", "7zip.7zip")) {
    if (@($appRows | Where-Object { $_.WingetId -eq $wingetId }).Count -gt 0) { $sampleIds += $wingetId }
}
$null = Set-WinToolAppState -InstalledId $sampleIds -UpgradeText "Name Id Version Available`nBrave Brave.Brave 1.0 2.0`nSpotify Spotify.Spotify 1.0 2.0"
$script:WinToolState.AppFilter = "all"
$window.FindName("AppSearch").Text = ""
$allChip = @($window.FindName("AppFilters").Children)[0]
$allChip.IsChecked = $false
$allChip.IsChecked = $true
Update-WinToolAppFilter
$chrome = @($appRows | Where-Object { $_.WingetId -eq "Google.Chrome" })[0]
$brave = @($appRows | Where-Object { $_.WingetId -eq "Brave.Brave" })[0]
$firefox = @($appRows | Where-Object { $_.WingetId -eq "Mozilla.Firefox" })[0]
if ($chrome.OpenButton.Visibility -ne "Visible" -or $chrome.UninstallButton.Visibility -ne "Visible" -or $chrome.InstallButton.Visibility -ne "Collapsed" -or -not $chrome.Installed) {
    throw "An installed app card should show Open, Uninstall, and the Installed pill."
}
if ($brave.UpdateButton.Visibility -ne "Visible" -or $brave.OpenButton.Visibility -ne "Collapsed" -or -not $brave.UpdateAvailable -or $brave.UninstallButton.Visibility -ne "Visible") {
    throw "An app with an update should show Update, Uninstall, and the amber border."
}
if ($firefox.InstallButton.Visibility -ne "Visible" -or $firefox.UninstallButton.Visibility -ne "Collapsed") {
    throw "An app that is not installed should show only Install."
}
if ([string]$window.FindName("AppUpgradeAll").Content -ne "Update all (2)") {
    throw ("Update all should count the updates, got " + [string]$window.FindName("AppUpgradeAll").Content)
}
$installedChip = @($window.FindName("AppFilters").Children | Where-Object { [string]$_.Tag -eq "installed" })[0]
$installedChip.IsChecked = $true
if ($firefox.Panel.Visibility -ne "Collapsed" -or $chrome.Panel.Visibility -ne "Visible") {
    throw "The Installed chip should show only installed apps."
}
$allChip.IsChecked = $true
$firefox.Checkbox.IsChecked = $true
if ($window.FindName("AppBulkBar").Visibility -ne "Visible") {
    throw "Ticking an app should show the selection actions."
}
$firefox.Checkbox.IsChecked = $false
if ($window.FindName("AppBulkBar").Visibility -ne "Collapsed") {
    throw "The selection actions should hide when nothing is ticked."
}
# The selection actions sit on the title row, so ticking an app never moves the cards.
$window.FindName("NavInstall").IsChecked = $true
$script:WinToolState.LogExpanded = $false
Sync-WinToolLogPanel
$rootVisual = $window.Content
Save-WinToolViewShot -Name "install-noselection" -Width 1280 -Height 760
$before = $firefox.Panel.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
$firefox.Checkbox.IsChecked = $true
$chrome.Checkbox.IsChecked = $true
Save-WinToolViewShot -Name "install-selected" -Width 1280 -Height 760
$after = $firefox.Panel.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
if ([math]::Abs($after.Y - $before.Y) -gt 0.5) { throw ("Ticking an app moved the cards from " + $before.Y + " to " + $after.Y) }
if ([string]$window.FindName("AppCount").Text -ne "2 selected") { throw "The selection count should read 2 selected." }
$count = $window.FindName("AppCount")
# DesiredSize includes the margin, ActualWidth does not.
$countRoom = $count.ActualWidth + $count.Margin.Left + $count.Margin.Right
if ($countRoom + 0.5 -lt $count.DesiredSize.Width -or $count.ActualWidth -lt 40) { throw ("The selection count is clipped: " + $count.ActualWidth + " of " + $count.DesiredSize.Width) }
$bar = $window.FindName("AppBulkBar")
$barTop = $bar.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
$searchTop = $window.FindName("AppSearch").TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
if ($barTop.Y + $bar.ActualHeight -gt $searchTop.Y) { throw "The selection actions should sit on the title row, above the search box." }
# At 1280 every filter chip fits on its own row without scrolling.
$chipScroll = $window.FindName("AppFilterScroll")
$lastChip = $window.FindName("AppFilters").Children[$window.FindName("AppFilters").Children.Count - 1]
$chipRight = $lastChip.TranslatePoint([System.Windows.Point]::new($lastChip.ActualWidth, 0), $chipScroll).X
if ($chipRight -gt $chipScroll.ActualWidth + 0.5) { throw ("Filter chips are cut off at 1280: the last ends at " + [int]$chipRight + " of " + [int]$chipScroll.ActualWidth) }
Write-Output ("Selection actions on the title row; first card stays at y=" + [int]$after.Y + "; chips end at " + [int]$chipRight + " of " + [int]$chipScroll.ActualWidth)
Sync-WinToolAppCheck -Id @() -OnlyThese
# A filter chip, the log, and the installed-apps status never change the card size or the columns.
$installBounds = { "{0:0.0},{1:0.0} {2:0.0}x{3:0.0} cols {4}" -f $firefox.Panel.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual).X, $firefox.Panel.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual).Y, $firefox.Panel.ActualWidth, $firefox.Panel.ActualHeight, $script:WinToolState.CategoryRows[0].Grid.Columns }
Save-WinToolViewShot -Name "install-noselection" -Width 1280 -Height 760
$installBefore = & $installBounds
$browserChip = @($window.FindName("AppFilters").Children | Where-Object { [string]$_.Tag -like "category:*" })[0]
$browserChip.IsChecked = $true
Save-WinToolViewShot -Name "install-filtered" -Width 1280 -Height 760
Update-WinToolInstallLayout -Width (Get-WinToolInstallWidth)
Save-WinToolViewShot -Name "install-filtered" -Width 1280 -Height 760
$installAfter = & $installBounds
if ($installAfter -ne $installBefore) { throw ("Clicking the " + $browserChip.Content + " chip moved or resized the cards: " + $installBefore + " -> " + $installAfter) }
@($window.FindName("AppFilters").Children)[0].IsChecked = $true
Set-WinToolAppStatus -Text "Checking installed apps..."
$script:WinToolState.LogExpanded = $true
Sync-WinToolLogPanel
Save-WinToolViewShot -Name "install-log-open" -Width 1280 -Height 760
$installAfter = & $installBounds
if ($installAfter -ne $installBefore) { throw ("The status line or the log moved the cards: " + $installBefore + " -> " + $installAfter) }
$script:WinToolState.LogExpanded = $false
Sync-WinToolLogPanel
Set-WinToolAppStatus -Text "Installed apps checked." -Show $false
Write-Output ("Install: a filter chip, the status line, and the log leave the cards in place (" + $installBefore + ")")
$window.FindName("NavInstall").IsChecked = $true
$script:WinToolState.LogExpanded = $false
Sync-WinToolLogPanel
# Sizes in WPF units (DIPs): 1024x576 is what a 1280x720 screen at 125% or a
# 1536x864 screen at 150% gives; 1264 is a maximized 1280 window.
$installExpect = @{ "install-1024" = 3; "install-mockup" = 5; "install-1264" = 5; "install-1920" = 8 }
foreach ($size in @(@(1024, 576, "install-1024"), @(1264, 704, "install-1264"), @(1920, 1080, "install-1920"), @(1280, 760, "install-mockup"))) {
    Update-WinToolInstallLayout -Width ([double]$size[0] - 248 - 40)
    Save-WinToolViewShot -Name $size[2] -Width ([double]$size[0]) -Height ([double]$size[1])
    # After layout the real list width decides the columns, like SizeChanged does.
    Update-WinToolInstallLayout -Width (Get-WinToolInstallWidth)
    Save-WinToolViewShot -Name $size[2] -Width ([double]$size[0]) -Height ([double]$size[1])
    Write-Output ($size[2] + ": " + $script:WinToolState.CategoryRows[0].Grid.Columns + " cards per row, card width " + [int]$appRows[0].Panel.ActualWidth)
    if ($script:WinToolState.CategoryRows[0].Grid.Columns -ne $installExpect[$size[2]]) {
        throw ($size[2] + " should show " + $installExpect[$size[2]] + " cards per row.")
    }
}
# Responsive columns: as many 185 px cards as fit, stretched to fill the row.
foreach ($case in @(@(992, 5), @(1622, 8), @(726, 3), @(380, 2), @(150, 1))) {
    Update-WinToolInstallLayout -Width ([double]$case[0])
    if ($script:WinToolState.CategoryRows[0].Grid.Columns -ne [int]$case[1]) {
        throw ("Install at " + $case[0] + " px should have " + $case[1] + " columns, got " + $script:WinToolState.CategoryRows[0].Grid.Columns)
    }
}
Update-WinToolInstallLayout -Width 992

# Tweak switches follow the real state of this PC; registry tweaks must be readable.
$window.FindName("TweakSearch").Text = ""
Update-WinToolTweakState
$unreadable = @($tweakRows | Where-Object { $_.State -eq "unknown" -and [string]$_.Tweak.apply.type -eq "registry" })
if ($unreadable.Count -gt 0) {
    throw ("Registry tweaks whose state could not be read: " + (@($unreadable | ForEach-Object { $_.Id }) -join ", "))
}
Write-Output ("Tweaks on this runner: " + (@($tweakRows | Where-Object { $_.Checkbox.IsChecked -eq $true } | ForEach-Object { $_.Id }) -join ", "))
# The switch handler with a stand-in runner: on, then off, then a failure that reverts.
$script:WinToolState.RestorePointDone = $true
$script:WinToolTweakProbeOverride = @{ ReadValue = { throw "stand-in" } }
$script:TestTweakCalls = New-Object System.Collections.Generic.List[string]
$script:WinToolTweakRunnerOverride = { param($Tweak, $Direction) $script:TestTweakCalls.Add(([string]$Tweak.id + ":" + $Direction)) }
$switchRow = @($tweakRows | Where-Object { $_.Checkbox.IsChecked -ne $true })[0]
$clickEvent = [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
$switchRow.Checkbox.IsChecked = $true
$switchRow.Checkbox.RaiseEvent([System.Windows.RoutedEventArgs]::new($clickEvent))
if ($script:TestTweakCalls[0] -ne ($switchRow.Id + ":Apply") -or $switchRow.Checkbox.IsChecked -ne $true -or -not $switchRow.Checkbox.IsEnabled) {
    throw ("Turning a switch on did not apply the tweak: " + ($script:TestTweakCalls -join ", "))
}
$switchRow.Checkbox.IsChecked = $false
$switchRow.Checkbox.RaiseEvent([System.Windows.RoutedEventArgs]::new($clickEvent))
if ($script:TestTweakCalls[1] -ne ($switchRow.Id + ":Undo") -or $switchRow.Checkbox.IsChecked -ne $false) {
    throw "Turning a switch off did not run the undo."
}
$script:WinToolTweakRunnerOverride = { param($Tweak, $Direction) $null = $Tweak, $Direction; throw "stand-in failure" }
$switchRow.Checkbox.IsChecked = $true
$switchRow.Checkbox.RaiseEvent([System.Windows.RoutedEventArgs]::new($clickEvent))
if ($switchRow.Checkbox.IsChecked -ne $false -or -not $switchRow.Checkbox.IsEnabled) {
    throw "A failed tweak change should put the switch back."
}
$script:WinToolTweakRunnerOverride = $null
$script:WinToolTweakProbeOverride = $null
Update-WinToolTweakState
$window.FindName("NavTweaks").IsChecked = $true
foreach ($size in @(@(1024, 576, "tweaks-1024"), @(1920, 1080, "tweaks-1920"), @(1280, 760, "tweaks-mockup"))) {
    Update-WinToolTweakLayout -Width ([double]$size[0] - 248 - 40)
    Save-WinToolViewShot -Name $size[2] -Width ([double]$size[0]) -Height ([double]$size[1])
    Update-WinToolTweakLayout -Width (Get-WinToolTweakWidth)
    Save-WinToolViewShot -Name $size[2] -Width ([double]$size[0]) -Height ([double]$size[1])
    Write-Output ($size[2] + ": " + $script:WinToolState.TweakColumns + " tweak columns, planned heights " + ((@($script:WinToolState.TweakColumnHeights) | ForEach-Object { [int]$_ }) -join "/"))
}
foreach ($case in @(@(982, 3), @(1622, 4), @(700, 2), @(500, 1))) {
    Update-WinToolTweakLayout -Width ([double]$case[0])
    if ($script:WinToolState.TweakColumns -ne [int]$case[1]) {
        throw ("Tweaks at " + $case[0] + " px should have " + $case[1] + " columns, got " + $script:WinToolState.TweakColumns)
    }
}
Update-WinToolTweakLayout -Width 1622
$placed = @($script:WinToolState.TweakGroups | Where-Object { $_.Card.Visibility -eq "Visible" })
if (@($placed | Where-Object { (Get-WinToolTweakCardColumn -Group $_) -lt 0 }).Count -gt 0) { throw "Every tweak card needs a column." }
$grid = $window.FindName("TweakCategories")
$rootVisual.UpdateLayout()
$real = @($grid.Children | ForEach-Object { $_.DesiredSize.Height })
Write-Output ("Tweaks at 1920: real column heights " + (($real | ForEach-Object { [int]$_ }) -join "/"))
$rowsShown = 0
foreach ($column in @($grid.Children)) { foreach ($card in @($column.Children)) { $rowsShown += $card.Child.Children.Count - 1 } }
if ($rowsShown -ne @($tweakRows).Count) { throw ("Every tweak row should sit in a card, got " + $rowsShown + " of " + @($tweakRows).Count) }
$spread = ($real | Measure-Object -Maximum).Maximum - ($real | Measure-Object -Minimum).Minimum
if ($spread -gt 450) { throw ("The tweak columns are unbalanced: " + (($real | ForEach-Object { [int]$_ }) -join "/")) }
Update-WinToolTweakLayout -Width 992

$uiErrors = Get-WinToolUiError
if ($uiErrors.Count -gt 0) {
    foreach ($uiError in $uiErrors) {
        Write-Output ("UI handler failed: " + $uiError.Name + ": " + $uiError.Message)
    }
    throw "$($uiErrors.Count) UI handler(s) failed."
}
Write-Output "Raised $raised UI events without errors."

if (-not (Initialize-WinToolConsoleApi)) {
    throw "The console helper did not compile on Windows PowerShell."
}
$null = [WinToolConsoleApi]::GetConsoleWindow()
Write-Output "Console helper compiled."

try {
    $window.Close()
}
catch {
    Write-Output $_.Exception.Message
}

Write-Output "WinTool window built: $($appRows.Count) apps, $($tweakRows.Count) tweaks."
exit 0
