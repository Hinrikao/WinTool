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
$promptHost = $window.FindName("TerminalPromptHost")
if ($null -eq $promptHost -or $promptHost.Children.Count -lt 8) {
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
    "Install: uninstall one app",
    "Install: check installed",
    "Check installed apps",
    "Features: apply changes",
    "Features: refresh state",
    "Tweaks: apply selected",
    "Tweaks: undo selected",
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

# Clicking each prompt card must update the Terminal choice.
foreach ($card in @($promptHost.Children)) {
    $mouseArgs = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
    $mouseArgs.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
    $card.RaiseEvent($mouseArgs)
    if ([string]$script:WinToolTerminalChoice.prompt -ne [string]$card.Tag) {
        throw ("Clicking the prompt card '" + [string]$card.Tag + "' did not select it.")
    }
}

# Installed and update badges follow the detected state.
$firstApp = $appRows[0]
$secondApp = $appRows[1]
Set-WinToolAppState -InstalledId @($firstApp.WingetId) -UpgradeText ("Name Id Version Available`n" + $secondApp.Name + " " + $secondApp.WingetId + " 1.0 2.0")
if ($firstApp.InstalledBadge.Visibility -ne "Visible" -or $firstApp.UpdateBadge.Visibility -ne "Collapsed") {
    throw "The Installed badge did not follow the detected state."
}
if ($secondApp.UpdateBadge.Visibility -ne "Visible" -or -not $secondApp.Installed) {
    throw "The Update available badge did not follow the upgrade list."
}
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
