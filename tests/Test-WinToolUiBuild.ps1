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

# Home checks are fed by the test, without motion, until the real run at the end.
$script:WinToolHomeNoJobs = $true
$script:WinToolHomeReduceMotion = $true
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
$iconImages = 0
$iconLetters = 0
foreach ($row in $appRows) {
    if ($null -eq $row.Checkbox) {
        throw "An app row was built without a checkbox."
    }
    if ($null -eq $row.IconHost -or [double]$row.IconHost.Width -ne 32 -or [double]$row.IconHost.Height -ne 32) {
        throw ("The app icon slot must stay 32 px: " + $row.Id)
    }
    if ($null -ne $row.IconImage) {
        $iconImages++
        if ([double]$row.IconImage.Width -ne 32 -or [double]$row.IconImage.Height -ne 32) {
            throw ($row.Id + " icon image is not 32 px.")
        }
        if ($row.IconImage.Stretch -ne [System.Windows.Media.Stretch]::Uniform) {
            throw ($row.Id + " icon must keep its aspect ratio.")
        }
        $scaling = [System.Windows.Media.RenderOptions]::GetBitmapScalingMode($row.IconImage)
        if ($scaling -ne [System.Windows.Media.BitmapScalingMode]::HighQuality) {
            throw ($row.Id + " icon must use high-quality scaling.")
        }
        if ($null -eq $row.IconImage.Source -or -not $row.IconImage.Source.IsFrozen) {
            throw ($row.Id + " icon bitmap should be decoded once and frozen.")
        }
        if ($null -eq $row.IconImage.CacheMode) {
            throw ($row.Id + " icon should cache its scaled bitmap.")
        }
        $plate = $row.IconHost.Background.Color
        if ($plate.R -ne 0xF3 -or $plate.G -ne 0xF5 -or $plate.B -ne 0xF8) {
            throw ($row.Id + " icon backplate should be the shared light plate.")
        }
    }
    else {
        $iconLetters++
        if ($row.IconHost.Child -isnot [System.Windows.Controls.TextBlock]) {
            throw ($row.Id + " should keep the letter tile.")
        }
    }
}
$firefoxIcon = @($appRows | Where-Object { $_.Id -eq "firefox" })[0]
$operaIcon = @($appRows | Where-Object { $_.Id -eq "opera" })[0]
if ($null -eq $firefoxIcon.IconImage -or $null -ne $operaIcon.IconImage) {
    throw "Firefox should show its icon and Opera should keep the letter tile."
}
if ($iconImages -lt 100 -or $iconLetters -lt 1) {
    throw ("Expected real icons and letter tiles, got " + $iconImages + " icons and " + $iconLetters + " tiles.")
}
Write-Output ("Install icons: " + $iconImages + " images, " + $iconLetters + " letter tiles.")
foreach ($row in $tweakRows) {
    if ($null -eq $row.Checkbox) {
        throw "A tweak row was built without a checkbox."
    }
}

$fontList = $window.FindName("TerminalFontList")
if ($null -eq $fontList) {
    throw "The Terminal tab did not build the font list."
}
foreach ($fontItem in @($fontList.Items)) {
    $fontId = [string]$fontItem.Tag
    if (-not (Test-WinToolFontResolve -Id $fontId)) {
        throw ("The font list includes " + $fontId + ", which did not load.")
    }
    if ([string]$fontItem.ToolTip -notlike "Installed*") {
        throw ($fontId + " is not marked as installed.")
    }
}
$catalogFonts = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())
if ($catalogFonts.Count -lt 70) {
    throw "The font catalog shrank."
}
if ($fontList.Items.Count -gt $catalogFonts.Count) {
    throw "The font list is larger than the fonts that loaded."
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
    "View history",
    "Fix all",
    "Start the Home analysis"
)
# Every handler whose name starts with one of these changes the system.
$skipPrefix = @("Fixes: ", "Home: ")
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
Set-WinToolFeatureState -State $fakeState

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
$selectedFont = $window.FindName("TerminalFontList").SelectedItem
if ($null -ne $selectedFont -and -not (Test-WinToolFontResolve -Id ([string]$selectedFont.Tag))) {
    throw "The selected font did not load."
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
    Complete-WinToolMotion
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
    if ($body.VerticalOffset -ne 0) { $body.ScrollToVerticalOffset(0) }
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

foreach ($size in @(@(1280, 800, "mockup"), @(1280, 900, "wide"), @(1000, 1300, "narrow"))) {
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
$styleForLigature = $window.FindName("TerminalStyleList")
$styleGenerator = $styleForLigature.ItemContainerGenerator
for ($styleIndex = 0; $styleIndex -lt $styleForLigature.Items.Count; $styleIndex++) {
    $styleContainer = $styleGenerator.ContainerFromIndex($styleIndex)
    if ($null -eq $styleContainer) { continue }
    foreach ($styleNode in @(Get-WinToolVisualChild -Root $styleContainer)) {
        if ($styleNode -is [System.Windows.Controls.TextBlock] -and $styleNode.Inlines.Count -gt 0) {
            $themeLine = $styleNode
            break
        }
    }
    if ($null -ne $themeLine) { break }
}
if ($null -ne $themeLine -and -not [System.Windows.Documents.Typography]::GetStandardLigatures($themeLine)) {
    throw "Theme previews should draw font ligatures."
}
# Sizes from the 14 px standard: chips and buttons 32, search 34, engine rows about 36.
Invoke-WinToolTerminalShotLayout -Width 1280 -Height 800
foreach ($chipName in @("TerminalFilterAll", "TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalSetup", "TerminalUpdate", "TerminalRefresh")) {
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
# The action bar stays fully in view at 1280 x 800; a short body scrolls instead of clipping cards.
$summaryCard = $window.FindName("TerminalSummaryCard")
$summaryBottom = $summaryCard.TranslatePoint([System.Windows.Point]::new(0, $summaryCard.ActualHeight), $rootVisual).Y
if ($summaryBottom -gt 800) { throw ("The Terminal action bar should stay in view at 1280 x 800: bottom at " + $summaryBottom) }
$bodyScroll = $window.FindName("TerminalBodyScroll")
$advancedHost = $window.FindName("TerminalAdvancedHost")
$bodyNeed = Get-WinToolTerminalBodyMinHeight -Width $bodyScroll.ActualWidth
if ($advancedHost.ActualHeight + 0.5 -lt $bodyNeed) { throw ("The Advanced body should never be squeezed below " + $bodyNeed + " px.") }
Write-Output ("Terminal body at 1280 x 800: viewport " + [Math]::Round($bodyScroll.ViewportHeight) + " px, cards need " + $bodyNeed + " px, scrolls " + [Math]::Max(0, [Math]::Round($bodyScroll.ExtentHeight - $bodyScroll.ViewportHeight)) + " px.")
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
    Update-WinToolTerminalPreview
    Complete-WinToolMotion
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

function Test-WinToolPrivateUseText {
    param([AllowEmptyString()][string]$Text)
    foreach ($code in @(Get-WinToolTextCode -Text $Text)) {
        if ($code -ge 0xE000 -and $code -le 0xF8FF) { return $true }
    }
    return $false
}

function Get-WinToolPreviewSamplePiece {
    param($Sample)
    $list = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Sample) { return @() }
    foreach ($inline in @($Sample.Inlines)) {
        if ($inline -is [System.Windows.Documents.Run]) {
            $fill = $null
            if ($null -ne $inline.Background) { $fill = [string]$inline.Background }
            [void]$list.Add([pscustomobject]@{ Text = [string]$inline.Text; Background = $fill })
            continue
        }
        if ($inline -isnot [System.Windows.Documents.InlineUIContainer] -or $null -eq $inline.Child) { continue }
        $tag = $inline.Child.Tag
        if ($null -eq $tag) { continue }
        $parts = $null
        if ($null -ne $tag.PSObject.Properties["Parts"]) { $parts = @($tag.Parts) }
        if ($null -ne $parts -and $parts.Count -gt 0) {
            foreach ($part in $parts) { [void]$list.Add($part) }
        }
        else {
            [void]$list.Add($tag)
        }
    }
    return $list.ToArray()
}

function Get-WinToolSampleInlineText {
    param($Sample)
    $drawn = New-Object System.Text.StringBuilder
    foreach ($piece in @(Get-WinToolPreviewSamplePiece -Sample $Sample)) {
        [void]$drawn.Append([string]$piece.Text)
    }
    return $drawn.ToString()
}

function Assert-WinToolPreviewImagePixel {
    param(
        $Image,
        [int]$Code,
        [string]$Label
    )
    if ($null -eq $Image) { throw ($Label + " U+" + $Code.ToString("X") + " produced no preview image.") }
    $imageWidth = $Image.Width
    $imageHeight = $Image.Height
    if ([double]::IsNaN($imageWidth) -or $imageWidth -le 0) { $imageWidth = 48 }
    if ([double]::IsNaN($imageHeight) -or $imageHeight -le 0) { $imageHeight = 48 }
    $width = [Math]::Max(16, [int][Math]::Ceiling($imageWidth) + 8)
    $height = [Math]::Max(16, [int][Math]::Ceiling($imageHeight) + 8)
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $visual = New-Object System.Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    $context.DrawImage($Image, [System.Windows.Rect]::new(2, 2, $imageWidth, $imageHeight))
    $context.Close()
    $bitmap.Render($visual)
    $pixels = New-Object byte[] ($width * $height * 4)
    $bitmap.CopyPixels($pixels, $width * 4, 0)
    $lit = 0
    $minX = $width
    $minY = $height
    $maxX = -1
    $maxY = -1
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt $width; $x++) {
            $index = (($y * $width) + $x) * 4
            if ($pixels[$index + 3] -lt 32) { continue }
            $lit++
            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
    if ($lit -lt 8) {
        throw ($Label + " U+" + $Code.ToString("X") + " drew too few pixels (" + $lit + ").")
    }
    if ($Code -eq 0xE0B0) {
        $area = ($maxX - $minX + 1) * ($maxY - $minY + 1)
        if ($area -le 0) { throw ($Label + " U+E0B0 has an empty bounding box.") }
        $ratio = $lit / $area
        # A powerline arrow is a triangle. A solid tofu box fills almost all of
        # its bounds; a hollow .notdef box has a similar left and right edge.
        if ($ratio -gt 0.92) {
            throw ($Label + " U+E0B0 looks like a solid box (fill " + ("{0:0.00}" -f $ratio) + ").")
        }
        $span = $maxX - $minX + 1
        $edge = [Math]::Max(1, [int]($span * 0.28))
        $leftLit = 0
        $rightLit = 0
        for ($y = $minY; $y -le $maxY; $y++) {
            for ($x = $minX; $x -lt ($minX + $edge); $x++) {
                $index = (($y * $width) + $x) * 4
                if ($pixels[$index + 3] -ge 32) { $leftLit++ }
            }
            for ($x = ($maxX - $edge + 1); $x -le $maxX; $x++) {
                $index = (($y * $width) + $x) * 4
                if ($pixels[$index + 3] -ge 32) { $rightLit++ }
            }
        }
        if ($rightLit -ge ($leftLit * 0.7) -and $ratio -lt 0.35) {
            throw ($Label + " U+E0B0 looks like a hollow box (fill " + ("{0:0.00}" -f $ratio) + ").")
        }
    }
}

function Assert-WinToolNerdFontGeometry {
    $best = Get-WinToolBestNerdFont
    if ($null -eq $best -or $null -eq $best.Glyph) { throw "No Nerd Font loaded for the outline check." }
    $codes = @(0xE0B0, 0xE0A0, 0xF07B, 0xE0B4, 0xE0B6, 0xF418, 0xE718, 0xF489, 0xF126)
    foreach ($code in $codes) {
        if (-not (Test-WinToolGlyphDrawable -Glyph $best.Glyph -Code $code)) {
            throw ("U+" + $code.ToString("X") + " is not drawable in " + [string]$best.FamilyName + ".")
        }
        $probe = [char]::ConvertFromUtf32([int]$code)
        $pieces = @(Split-WinToolCoveredText -Text $probe)
        if ($pieces.Count -ne 1 -or [string]$pieces[0].Text -ne $probe -or [string]$pieces[0].Path -ne [string]$best.Path) {
            throw ("U+" + $code.ToString("X") + " was not kept on " + [string]$best.FamilyName + ".")
        }
        $image = New-WinToolPreviewImage -Segment @([pscustomobject]@{ Text = $probe; Foreground = "#FFFF00"; Background = $null }) -EmSize 48
        Assert-WinToolPreviewImagePixel -Image $image -Code $code -Label ([string]$best.FamilyName)
    }
    Write-Output ("Outlined " + $codes.Count + " Nerd Font icons from " + [string]$best.FamilyName)
}

function Assert-WinToolLivePreviewPixel {
    param([string]$Label)
    $preview = $window.FindName("TerminalFontPreview")
    if ($null -eq $preview) { throw ($Label + ": TerminalFontPreview is missing.") }
    $rootVisual.UpdateLayout()
    $width = [Math]::Max(1, [int][Math]::Ceiling($preview.ActualWidth))
    $height = [Math]::Max(1, [int][Math]::Ceiling($preview.ActualHeight))
    if ($width -lt 16 -or $height -lt 16) {
        throw ($Label + " live preview was too small to inspect: " + $width + "x" + $height + ".")
    }
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($preview)
    $pixels = New-Object byte[] ($width * $height * 4)
    $bitmap.CopyPixels($pixels, $width * 4, 0)
    $scheme = Get-WinToolTerminalScheme
    $background = ConvertTo-WinToolPreviewColor -Value ([string]$scheme.background) -Palette $null
    $bgR = 27; $bgG = 34; $bgB = 48
    if ($background -match '^#(?<a>[0-9A-Fa-f]{2})?(?<r>[0-9A-Fa-f]{2})(?<g>[0-9A-Fa-f]{2})(?<b>[0-9A-Fa-f]{2})$') {
        $bgR = [Convert]::ToInt32($Matches.r, 16)
        $bgG = [Convert]::ToInt32($Matches.g, 16)
        $bgB = [Convert]::ToInt32($Matches.b, 16)
    }
    $lit = 0
    for ($index = 0; $index -lt $pixels.Length; $index += 4) {
        if ($pixels[$index + 3] -lt 32) { continue }
        $db = [Math]::Abs([int]$pixels[$index] - $bgB)
        $dg = [Math]::Abs([int]$pixels[$index + 1] - $bgG)
        $dr = [Math]::Abs([int]$pixels[$index + 2] - $bgR)
        if (($dr + $dg + $db) -gt 36) { $lit++ }
    }
    if ($lit -lt 40) {
        throw ($Label + " live preview has too few non-background pixels (" + $lit + ").")
    }
    Write-Output ($Label + " live preview has " + $lit + " non-background pixels.")
}

function Assert-WinToolSampleGlyph {
    param(
        $Sample,
        [string]$Label,
        [switch]$ForbidPrivateUse
    )
    Complete-WinToolStyleSelectionWork
    if ($null -eq $Sample) { throw ($Label + " sample is missing.") }
    $drawn = Get-WinToolSampleInlineText -Sample $Sample
    if ([string]::IsNullOrEmpty($drawn)) { throw ($Label + " drew no text.") }
    if ($ForbidPrivateUse -and (Test-WinToolPrivateUseText -Text $drawn)) {
        throw ($Label + " still draws a private-use glyph.")
    }
    if ($ForbidPrivateUse) { return }
    $best = Get-WinToolBestNerdFont
    if ($null -eq $best -or $null -eq $best.Glyph) { return }
    foreach ($code in @(Get-WinToolTextCode -Text $drawn)) {
        if ($code -lt 0xE000 -or $code -gt 0xF8FF) { continue }
        if (-not (Test-WinToolGlyphDrawable -Glyph $best.Glyph -Code $code)) {
            throw ($Label + " U+" + $code.ToString("X") + " has no outline in " + [string]$best.FamilyName + ".")
        }
    }
}

function Assert-WinToolCatalogGlyph {
    param(
        [switch]$RequireNerd,
        [switch]$ForbidPrivateUse
    )
    $best = Get-WinToolBestNerdFont
    if ($RequireNerd) {
        if ($null -eq $best) { throw "No Nerd Font loaded for the preview." }
        if ([string]$best.Source -ne "HKCU") { throw ("The preview Nerd Font came from " + [string]$best.Source + ", not HKCU.") }
    }
    foreach ($sample in @(Get-WinToolPreviewSampleText)) {
        if (-not (Test-WinToolPreviewTextCovered -Text $sample)) {
            throw ("A preview string is not covered: " + $sample)
        }
        if ($ForbidPrivateUse) {
            $drawn = ""
            foreach ($piece in @(Split-WinToolCoveredText -Text $sample)) { $drawn += [string]$piece.Text }
            if (Test-WinToolPrivateUseText -Text $drawn) {
                throw ("Fallback kept a private-use glyph in: " + $sample)
            }
        }
    }
    if ($RequireNerd) {
        foreach ($code in @(0xE0B0, 0xE0B4, 0xE0B6, 0xF418, 0xE718, 0xF07B, 0xF489, 0xE0A0, 0xF126)) {
            $probe = [char]::ConvertFromUtf32([int]$code)
            $pieces = @(Split-WinToolCoveredText -Text $probe)
            if ($pieces.Count -ne 1 -or [string]$pieces[0].Text -ne $probe -or [string]$pieces[0].Path -ne [string]$best.Path) {
                throw ("U+" + ([int]$code).ToString("X") + " was not drawn from " + [string]$best.FamilyName + ".")
            }
            if (-not (Test-WinToolGlyphDrawable -Glyph $best.Glyph -Code $code)) {
                throw ("U+" + ([int]$code).ToString("X") + " has no outline in " + [string]$best.FamilyName + ".")
            }
        }
    }
}

function Assert-WinToolStyleSwitchSpeed {
    param(
        [string]$PromptId = "starship",
        [int]$LimitMs = 150
    )
    if ([string]$script:WinToolTerminalChoice.prompt -ne $PromptId) {
        Select-WinToolTerminalPrompt -PromptId $PromptId
    }
    $list = $window.FindName("TerminalStyleList")
    $entryList = @($list.Items)
    if ($entryList.Count -lt 8) {
        throw ("The " + $PromptId + " list is too short to time style switches: " + $entryList.Count)
    }
    $format = [System.Globalization.CultureInfo]::InvariantCulture

    function Measure-WinToolStylePaint {
        param($Entry)
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $list.SelectedItem = $Entry
        Complete-WinToolStyleSelectionWork
        $watch.Stop()
        return $watch.Elapsed.TotalMilliseconds
    }

    # Cold paint: empty outline and picture caches, same work as a click.
    Reset-WinToolPreviewDrawCache
    $coldMs = Measure-WinToolStylePaint -Entry $entryList[0]
    Write-Output ("Starship style switch uncached: " + $coldMs.ToString("0.0", $format) + " ms (" + [string]$entryList[0].Name + ")")

    $warmPart = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entryList) {
        $ms = Measure-WinToolStylePaint -Entry $entry
        [void]$warmPart.Add(([string]$entry.Name + " " + $ms.ToString("0.0", $format) + "ms"))
    }
    Write-Output ("Starship style switch warmup: " + ($warmPart -join ", "))

    $times = New-Object System.Collections.Generic.List[object]
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entryList) {
        $ms = Measure-WinToolStylePaint -Entry $entry
        [void]$times.Add([pscustomobject]@{ Name = [string]$entry.Name; Id = [string]$entry.Tag; Ms = $ms })
        [void]$parts.Add(([string]$entry.Name + " " + $ms.ToString("0.0", $format) + "ms"))
    }
    $max = ($times | Measure-Object -Property Ms -Maximum).Maximum
    $avg = ($times | Measure-Object -Property Ms -Average).Average
    Write-Output ("Starship style switch after warmup: " + ($parts -join ", "))
    Write-Output ("Starship style switch after warmup: max " + $max.ToString("0.0", $format) + " ms, average " + $avg.ToString("0.0", $format) + " ms, limit " + $LimitMs + " ms.")
    if ($max -ge $LimitMs) {
        throw ("Picking a Starship preset took " + $max.ToString("0.0", $format) + " ms after warmup; expected well under " + $LimitMs + " ms.")
    }
}

function Write-WinToolThemeListStat {
    param([string]$Label)
    $format = [System.Globalization.CultureInfo]::InvariantCulture
    $list = $window.FindName("TerminalStyleList")
    if ($null -eq $list) {
        Write-Host ("Theme list " + $Label + ": missing")
        return
    }
    $realized = 0
    $generator = $list.ItemContainerGenerator
    if ($null -ne $generator) {
        for ($index = 0; $index -lt $list.Items.Count; $index++) {
            if ($null -ne $generator.ContainerFromIndex($index)) { $realized++ }
        }
    }
    $viewer = Find-WinToolChildScrollViewer -Element $list
    $view = 0.0
    $offset = 0.0
    if ($null -ne $viewer) {
        $view = [double]$viewer.ViewportHeight
        $offset = [double]$viewer.VerticalOffset
    }
    Write-Host ("Theme list " + $Label + ": items " + $list.Items.Count + ", realized " + $realized + ", height " + $list.ActualHeight.ToString("0.0", $format) + ", viewport " + $view.ToString("0.0", $format) + ", offset " + $offset.ToString("0.0", $format) + ".")
}

function Measure-WinToolEngineSwitch {
    param([Parameter(Mandatory = $true)][string]$PromptId)
    $format = [System.Globalization.CultureInfo]::InvariantCulture
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Select-WinToolTerminalPrompt -PromptId $PromptId
    $clickMs = $watch.Elapsed.TotalMilliseconds
    $watch.Restart()
    Complete-WinToolStyleSelectionWork
    $flushMs = $watch.Elapsed.TotalMilliseconds
    Write-Host ("Engine switch phases " + $PromptId + ": click " + $clickMs.ToString("0.0", $format) + " ms, preview flush " + $flushMs.ToString("0.0", $format) + " ms, total " + ($clickMs + $flushMs).ToString("0.0", $format) + " ms.")
    Write-WinToolThemeListStat -Label $PromptId
    return ,([double]$clickMs)
}

function Measure-WinToolUiAction {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [switch]$Flush
    )
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    if ($Flush) { Complete-WinToolStyleSelectionWork }
    $watch.Stop()
    return $watch.Elapsed.TotalMilliseconds
}

function Assert-WinToolUiSwitchSpeed {
    param(
        [int]$WarmLimitMs = 150,
        [int]$ColdLimitMs = 400
    )
    $format = [System.Globalization.CultureInfo]::InvariantCulture
    $window.FindName("NavTerminal").IsChecked = $true
    $window.FindName("TerminalModeAdvanced").IsChecked = $true
    Invoke-WinToolTerminalShotLayout -Width 1280 -Height 800

    $ids = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "prompts" -Default @() | ForEach-Object { [string]$_.id })
    if ($ids.Count -lt 8) { throw ("Expected 8 prompt engines, found " + $ids.Count + ".") }

    Reset-WinToolThemeListCache -Force
    Initialize-WinToolThemeViewCache
    Reset-WinToolPreviewDrawCache
    $script:WinToolThemePreviewFontKey = Get-WinToolPreviewFontKey

    $coldPart = New-Object System.Collections.Generic.List[string]
    $coldTime = New-Object System.Collections.Generic.List[object]
    foreach ($id in $ids) {
        $ms = [double](Measure-WinToolEngineSwitch -PromptId $id)
        [void]$coldTime.Add([pscustomobject]@{ Name = $id; Ms = $ms })
        [void]$coldPart.Add($id + " " + $ms.ToString("0.0", $format) + "ms")
        Write-Output ("Engine switch cold " + $id + ": " + $ms.ToString("0.0", $format) + " ms")
    }
    $coldMax = ($coldTime | Measure-Object -Property Ms -Maximum).Maximum
    $coldAvg = ($coldTime | Measure-Object -Property Ms -Average).Average
    Write-Output ("Engine switch cold: " + ($coldPart -join ", "))
    Write-Output ("Engine switch cold: max " + $coldMax.ToString("0.0", $format) + " ms, average " + $coldAvg.ToString("0.0", $format) + " ms, limit " + $ColdLimitMs + " ms.")
    if ($coldMax -ge $ColdLimitMs) {
        throw ("Switching prompt engine took " + $coldMax.ToString("0.0", $format) + " ms cold; expected under " + $ColdLimitMs + " ms.")
    }

    $warmPart = New-Object System.Collections.Generic.List[string]
    $warmTime = New-Object System.Collections.Generic.List[object]
    foreach ($id in $ids) {
        $ms = [double](Measure-WinToolEngineSwitch -PromptId $id)
        [void]$warmTime.Add([pscustomobject]@{ Name = $id; Ms = $ms })
        [void]$warmPart.Add($id + " " + $ms.ToString("0.0", $format) + " ms")
        Write-Output ("Engine switch warm " + $id + ": " + $ms.ToString("0.0", $format) + " ms")
    }
    $warmMax = ($warmTime | Measure-Object -Property Ms -Maximum).Maximum
    $warmAvg = ($warmTime | Measure-Object -Property Ms -Average).Average
    Write-Output ("Engine switch after warmup: " + ($warmPart -join ", "))
    Write-Output ("Engine switch after warmup: max " + $warmMax.ToString("0.0", $format) + " ms, average " + $warmAvg.ToString("0.0", $format) + " ms, limit " + $WarmLimitMs + " ms.")
    if ($warmMax -ge $WarmLimitMs) {
        throw ("Switching prompt engine took " + $warmMax.ToString("0.0", $format) + " ms after warmup; expected well under " + $WarmLimitMs + " ms.")
    }

    Select-WinToolTerminalPrompt -PromptId "starship"
    Complete-WinToolStyleSelectionWork
    $themeSearch = $window.FindName("TerminalThemeSearch")
    $themeSearch.Text = ""
    Complete-WinToolStyleSelectionWork

    $filterPass = New-Object System.Collections.Generic.List[object]
    foreach ($filterName in @("TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalFilterAll")) {
        $ms = Measure-WinToolUiAction -Flush -Action { $window.FindName($filterName).IsChecked = $true }.GetNewClosure()
        $label = "filter " + [string]$window.FindName($filterName).Tag
        [void]$filterPass.Add([pscustomobject]@{ Name = $label; Ms = $ms })
        Write-Output ("Theme " + $label + " warmup: " + $ms.ToString("0.0", $format) + " ms")
    }
    $filterPart = New-Object System.Collections.Generic.List[string]
    $filterTime = New-Object System.Collections.Generic.List[object]
    foreach ($filterName in @("TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalFilterAll")) {
        if ($filterName -eq "TerminalFilterAll") { $window.FindName("TerminalFilterPowerline").IsChecked = $true }
        else { $window.FindName("TerminalFilterAll").IsChecked = $true }
        Complete-WinToolStyleSelectionWork
        $ms = Measure-WinToolUiAction -Flush -Action { $window.FindName($filterName).IsChecked = $true }.GetNewClosure()
        $label = "filter " + [string]$window.FindName($filterName).Tag
        [void]$filterTime.Add([pscustomobject]@{ Name = $label; Ms = $ms })
        [void]$filterPart.Add($label + " " + $ms.ToString("0.0", $format) + "ms")
        Write-Output ("Theme " + $label + " warm: " + $ms.ToString("0.0", $format) + " ms")
    }

    $searchCold = Measure-WinToolUiAction -Flush -Action { $themeSearch.Text = "tokyo" }.GetNewClosure()
    Write-Output ("Theme search cold: " + $searchCold.ToString("0.0", $format) + " ms")
    $searchClear = Measure-WinToolUiAction -Flush -Action { $themeSearch.Text = "" }.GetNewClosure()
    Write-Output ("Theme search clear: " + $searchClear.ToString("0.0", $format) + " ms")
    $searchWarm = Measure-WinToolUiAction -Flush -Action { $themeSearch.Text = "tokyo" }.GetNewClosure()
    Write-Output ("Theme search warm: " + $searchWarm.ToString("0.0", $format) + " ms")
    $themeSearch.Text = ""
    Complete-WinToolStyleSelectionWork

    $fontList = $window.FindName("TerminalFontList")
    $fontItem = @($fontList.Items)
    $fontCold = -1.0
    $fontWarm = -1.0
    if ($fontItem.Count -ge 2) {
        $firstFont = $fontList.SelectedItem
        if ($null -eq $firstFont) { $firstFont = $fontItem[0] }
        $otherFont = $null
        foreach ($item in $fontItem) {
            if (-not [object]::Equals($item, $firstFont)) { $otherFont = $item; break }
        }
        if ($null -ne $otherFont) {
            $fontCold = Measure-WinToolUiAction -Flush -Action { $fontList.SelectedItem = $otherFont }.GetNewClosure()
            Write-Output ("Font switch cold (" + [string]$otherFont.Tag + "): " + $fontCold.ToString("0.0", $format) + " ms")
            $fontWarm = Measure-WinToolUiAction -Flush -Action { $fontList.SelectedItem = $firstFont }.GetNewClosure()
            Write-Output ("Font switch warm (" + [string]$firstFont.Tag + "): " + $fontWarm.ToString("0.0", $format) + " ms")
        }
    }

    $schemeHost = $window.FindName("TerminalSchemeHost")
    $schemeTile = @($schemeHost.Children)
    $schemeCold = -1.0
    $schemeWarm = -1.0
    if ($schemeTile.Count -ge 2) {
        $clickScheme = {
            param($Tile)
            $mouseArgs = [System.Windows.Input.MouseButtonEventArgs]::new([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $mouseArgs.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $Tile.RaiseEvent($mouseArgs)
        }
        $firstScheme = $schemeTile[0]
        $secondScheme = $schemeTile[1]
        $schemeCold = Measure-WinToolUiAction -Flush -Action { & $clickScheme $secondScheme }.GetNewClosure()
        Write-Output ("Scheme switch cold (" + [string]$secondScheme.Tag + "): " + $schemeCold.ToString("0.0", $format) + " ms")
        $schemeWarm = Measure-WinToolUiAction -Flush -Action { & $clickScheme $firstScheme }.GetNewClosure()
        Write-Output ("Scheme switch warm (" + [string]$firstScheme.Tag + "): " + $schemeWarm.ToString("0.0", $format) + " ms")
    }

    $navNames = @("Install", "Tweaks", "Terminal", "Drivers", "Updates", "Fixes", "Features", "Config", "Home")
    $tabColdPart = New-Object System.Collections.Generic.List[string]
    $tabColdTime = New-Object System.Collections.Generic.List[object]
    foreach ($navName in $navNames) {
        $ms = Measure-WinToolUiAction -Action { $window.FindName("Nav" + $navName).IsChecked = $true }.GetNewClosure()
        [void]$tabColdTime.Add([pscustomobject]@{ Name = $navName; Ms = $ms })
        [void]$tabColdPart.Add($navName + " " + $ms.ToString("0.0", $format) + "ms")
        Write-Output ("Tab switch cold " + $navName + ": " + $ms.ToString("0.0", $format) + " ms")
    }
    $tabWarmPart = New-Object System.Collections.Generic.List[string]
    $tabWarmTime = New-Object System.Collections.Generic.List[object]
    foreach ($navName in $navNames) {
        $ms = Measure-WinToolUiAction -Action { $window.FindName("Nav" + $navName).IsChecked = $true }.GetNewClosure()
        [void]$tabWarmTime.Add([pscustomobject]@{ Name = $navName; Ms = $ms })
        [void]$tabWarmPart.Add($navName + " " + $ms.ToString("0.0", $format) + "ms")
        Write-Output ("Tab switch warm " + $navName + ": " + $ms.ToString("0.0", $format) + " ms")
    }
    $tabColdMax = ($tabColdTime | Measure-Object -Property Ms -Maximum).Maximum
    $tabWarmMax = ($tabWarmTime | Measure-Object -Property Ms -Maximum).Maximum
    Write-Output ("Tab switch cold: " + ($tabColdPart -join ", "))
    Write-Output ("Tab switch after warmup: " + ($tabWarmPart -join ", "))
    Write-Output ("Tab switch: cold max " + $tabColdMax.ToString("0.0", $format) + " ms, warm max " + $tabWarmMax.ToString("0.0", $format) + " ms.")

    $window.FindName("NavTerminal").IsChecked = $true
    $window.FindName("TerminalModeAdvanced").IsChecked = $true
    Complete-WinToolStyleSelectionWork

    $failures = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $filterTime.Count; $index++) {
        $row = $filterTime[$index]
        if ($row.Ms -ge $WarmLimitMs) { [void]$failures.Add($row.Name + " " + $row.Ms.ToString("0.0", $format) + " ms after warmup") }
    }
    if ($searchCold -ge $ColdLimitMs) { [void]$failures.Add("search " + $searchCold.ToString("0.0", $format) + " ms cold") }
    if ($searchWarm -ge $WarmLimitMs) { [void]$failures.Add("search " + $searchWarm.ToString("0.0", $format) + " ms after warmup") }
    if ($searchClear -ge $WarmLimitMs) { [void]$failures.Add("search clear " + $searchClear.ToString("0.0", $format) + " ms") }
    if ($fontCold -ge 0 -and $fontCold -ge $ColdLimitMs) { [void]$failures.Add("font " + $fontCold.ToString("0.0", $format) + " ms cold") }
    if ($fontWarm -ge 0 -and $fontWarm -ge $WarmLimitMs) { [void]$failures.Add("font " + $fontWarm.ToString("0.0", $format) + " ms after warmup") }
    if ($schemeCold -ge 0 -and $schemeCold -ge $ColdLimitMs) { [void]$failures.Add("scheme " + $schemeCold.ToString("0.0", $format) + " ms cold") }
    if ($schemeWarm -ge 0 -and $schemeWarm -ge $WarmLimitMs) { [void]$failures.Add("scheme " + $schemeWarm.ToString("0.0", $format) + " ms after warmup") }
    if ($tabColdMax -ge $ColdLimitMs) { [void]$failures.Add("tab " + $tabColdMax.ToString("0.0", $format) + " ms cold") }
    if ($tabWarmMax -ge $WarmLimitMs) { [void]$failures.Add("tab " + $tabWarmMax.ToString("0.0", $format) + " ms after warmup") }
    if ($failures.Count -gt 0) {
        throw ("UI switch was too slow: " + ($failures -join "; ") + ".")
    }
}

function Install-WinToolPerUserNerdFont {
    $zip = Join-Path ([System.IO.Path]::GetTempPath()) "wintool-cascadia-nf.zip"
    $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/CascadiaCode.zip"
    Write-Output "Downloading CaskaydiaCove Nerd Font for the per-user glyph check."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client = New-Object System.Net.WebClient
    $client.Headers["User-Agent"] = "WinTool"
    $client.DownloadFile($url, $zip)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    $dest = ""
    try {
        $entry = $null
        foreach ($item in $archive.Entries) {
            if ($item.Name -eq "CaskaydiaCoveNerdFontMono-Regular.ttf") { $entry = $item; break }
        }
        if ($null -eq $entry) { throw "CascadiaCode.zip has no CaskaydiaCove Mono Regular font." }
        $folder = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $dest = Join-Path $folder $entry.Name
        $stream = [System.IO.File]::Create($dest)
        try {
            $source = $entry.Open()
            try { $source.CopyTo($stream) } finally { $source.Dispose() }
        }
        finally { $stream.Dispose() }
    }
    finally { $archive.Dispose() }
    $reg = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    if (-not (Test-Path -LiteralPath $reg)) { New-Item -Path $reg -Force | Out-Null }
    New-ItemProperty -LiteralPath $reg -Name "CaskaydiaCove Nerd Font Mono (TrueType)" -Value $dest -PropertyType String -Force | Out-Null
    Reset-WinToolFontResolution
    $script:WinToolFontListKey = ""
    $script:WinToolTerminalChoice.fontId = "cascadiacode-nf"
    Update-WinToolFontList
    Update-WinToolThemePreviewImage
    Update-WinToolTerminalPreview
    Update-WinToolSimplePreview
    if (-not (Test-WinToolFontResolve -Id "cascadiacode-nf")) { throw "CaskaydiaCove installed per-user did not resolve." }
    if ([string]$window.FindName("TerminalFontList").SelectedItem.Tag -ne "cascadiacode-nf") {
        throw "The installed Nerd Font should be selected."
    }
    $record = (Get-WinToolResolvedFontMap)["cascadiacode-nf"]
    if ([string]$record.Source -ne "HKCU") { throw "CaskaydiaCove was not read from the per-user font registry." }
    Write-Output ("Loaded " + $record.FamilyName + " from " + $record.Path)
}

function Hide-WinToolInstalledNerdFont {
    # The no-font check has to be true on a machine that already has one.
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-WinToolRegisteredFont)) {
        $blob = (([string]$item.Name) + " " + [string]$item.Data).ToLowerInvariant()
        if ($blob.Contains("nerd")) { continue }
        [void]$kept.Add($item)
    }
    Reset-WinToolFontResolution
    $script:WinToolRegisteredFontCache = $kept.ToArray()
    $script:WinToolFontListKey = ""
    $script:WinToolThemeItemCache = @{}
    Update-WinToolFontList
    Update-WinToolThemePreviewImage
    Update-WinToolTerminalPreview
    Update-WinToolSimplePreview
    if ($null -ne (Get-WinToolBestNerdFont)) {
        throw "A Nerd Font was still used after hiding installed Nerd Fonts."
    }
    Write-Output "Nerd Fonts are hidden. Previews must use the ASCII fallback."
}

# Card 2 always matches the checked engine. The old bug: Advanced, pick
# Starship, go to Simple (the choice resets to Oh My Posh), back to Advanced:
# Oh My Posh was checked but card 2 still listed the Starship presets.
$window.FindName("NavTerminal").IsChecked = $true
$window.FindName("TerminalModeAdvanced").IsChecked = $true
$themeList = $window.FindName("TerminalStyleList")
function Assert-WinToolThemeCard {
    param([string]$Label)
    Complete-WinToolStyleSelectionWork
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
    Invoke-WinToolTerminalShotLayout -Width 1280 -Height 800
    $after = Get-WinToolTerminalBound
    foreach ($key in $Before.Keys) {
        if ($after[$key] -ne $Before[$key]) { throw ($Label + " moved or resized " + $key + ": " + $Before[$key] + " -> " + $after[$key]) }
    }
}
Hide-WinToolInstalledNerdFont
Select-WinToolTerminalPrompt -PromptId "oh-my-posh"
Invoke-WinToolTerminalShotLayout -Width 1280 -Height 800
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
Assert-WinToolCatalogGlyph -ForbidPrivateUse
foreach ($engine in $engines) {
    Select-WinToolTerminalPrompt -PromptId ([string]$engine.id)
    Assert-WinToolThemeCard -Label ("Engine " + [string]$engine.id)
    Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalFontSample") -Label ([string]$engine.id) -ForbidPrivateUse
    Assert-WinToolTerminalBound -Before $terminalBounds -Label ("Picking " + [string]$engine.id)
}
Update-WinToolSimplePreview
Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalSimpleSample") -Label "Simple" -ForbidPrivateUse
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
Save-WinToolTerminalShot -Name "terminal-extras-all-on" -Width 1280 -Height 800
foreach ($extraBox in @($script:WinToolTerminalExtraBox)) { $extraBox.IsChecked = ([string]$extraBox.Tag -in @("terminal-icons", "psreadline")); $extraBox.RaiseEvent($clickEvent) }
Save-WinToolTerminalShot -Name "terminal-extras-default" -Width 1280 -Height 800

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
$blocks = @(Get-WinToolPreviewSamplePiece -Sample $window.FindName("TerminalFontSample") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Background) })
if ($blocks.Count -lt 2) { throw "The Rainbow preview should draw colored blocks." }
$planText = (@(Get-WinToolTerminalPlan -Selection $script:WinToolTerminalChoice | ForEach-Object { [string]$_.Label }) -join " | ")
Write-Output ("Powerlevel10k plan: " + $planText)
$styleList.SelectedIndex = 0
if ([string]$script:WinToolTerminalChoice.promptStyle -ne [string]$styleList.Items[0].Tag) {
    throw "Picking another style should change the Terminal choice."
}
$styleList.SelectedIndex = 2
Save-WinToolTerminalShot -Name "terminal-p10k" -Width 1280 -Height 800
$script:WinToolTerminalChoice.prompt = "starship"
$script:WinToolTerminalChoice.promptStyle = "pastel-powerline"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
$blocks = @(Get-WinToolPreviewSamplePiece -Sample $window.FindName("TerminalFontSample") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Background) })
if ($blocks.Count -lt 2) { throw "The Starship Pastel powerline preview should draw colored blocks." }
Save-WinToolTerminalShot -Name "terminal-starship" -Width 1280 -Height 800
Save-WinToolTerminalShot -Name "terminal-starship-no-nerd" -Width 1280 -Height 800
Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalFontSample") -Label "Starship without a Nerd Font" -ForbidPrivateUse
Install-WinToolPerUserNerdFont
Assert-WinToolCatalogGlyph -RequireNerd
Update-WinToolTerminalPreview
Assert-WinToolNerdFontGeometry
Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalFontSample") -Label "Starship with a Nerd Font"
$withNerd = Get-WinToolSampleInlineText -Sample $window.FindName("TerminalFontSample")
if (-not (Test-WinToolPrivateUseText -Text $withNerd)) {
    throw "The Nerd Font preview substituted the icons instead of drawing them."
}
Save-WinToolTerminalShot -Name "terminal-starship-with-nerd" -Width 1280 -Height 800
Assert-WinToolLivePreviewPixel -Label "Starship with a Nerd Font"
Assert-WinToolStyleSwitchSpeed
Assert-WinToolUiSwitchSpeed
foreach ($engine in $engines) {
    Select-WinToolTerminalPrompt -PromptId ([string]$engine.id)
    Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalFontSample") -Label ([string]$engine.id + " with a Nerd Font")
}
Update-WinToolSimplePreview
Assert-WinToolSampleGlyph -Sample $window.FindName("TerminalSimpleSample") -Label "Simple with a Nerd Font"
$simpleDrawn = Get-WinToolSampleInlineText -Sample $window.FindName("TerminalSimpleSample")
if (-not (Test-WinToolPrivateUseText -Text $simpleDrawn)) {
    throw "The Simple preview substituted the icons instead of drawing them."
}
$script:WinToolTerminalChoice.prompt = "oh-my-zsh"
$script:WinToolTerminalChoice.promptStyle = "agnoster"
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
Save-WinToolTerminalShot -Name "terminal-omz" -Width 1280 -Height 800
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
    Complete-WinToolMotion
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
if ($firefox.InstallButton.Visibility -ne "Visible" -or $firefox.UninstallButton.Visibility -ne "Hidden") {
    throw "An app that is not installed should show only Install, with the second slot kept."
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
Save-WinToolViewShot -Name "install-noselection" -Width 1280 -Height 800
$before = $firefox.Panel.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
$firefox.Checkbox.IsChecked = $true
$chrome.Checkbox.IsChecked = $true
Save-WinToolViewShot -Name "install-selected" -Width 1280 -Height 800
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
Save-WinToolViewShot -Name "install-noselection" -Width 1280 -Height 800
$installBefore = & $installBounds
$browserChip = @($window.FindName("AppFilters").Children | Where-Object { [string]$_.Tag -like "category:*" })[0]
$browserChip.IsChecked = $true
Save-WinToolViewShot -Name "install-filtered" -Width 1280 -Height 800
Update-WinToolInstallLayout -Width (Get-WinToolInstallWidth)
Save-WinToolViewShot -Name "install-filtered" -Width 1280 -Height 800
$installAfter = & $installBounds
if ($installAfter -ne $installBefore) { throw ("Clicking the " + $browserChip.Content + " chip moved or resized the cards: " + $installBefore + " -> " + $installAfter) }
@($window.FindName("AppFilters").Children)[0].IsChecked = $true
Set-WinToolAppStatus -Text "Checking installed apps..."
$script:WinToolState.LogExpanded = $true
Sync-WinToolLogPanel
Save-WinToolViewShot -Name "install-log-open" -Width 1280 -Height 800
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
foreach ($size in @(@(1024, 576, "install-1024"), @(1264, 704, "install-1264"), @(1920, 1080, "install-1920"), @(1280, 800, "install-mockup"))) {
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
foreach ($size in @(@(1024, 576, "tweaks-1024"), @(1920, 1080, "tweaks-1920"), @(1280, 800, "tweaks-mockup"))) {
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

# Home: analyzing, done and fixing share one layout. Stub results stand in
# for the checks so the shots match the mockups; then the real checks run.
$window.FindName("NavHome").IsChecked = $true
if ($window.FindName("ViewHome").Visibility -ne "Visible") { throw "The Home tab did not open." }
$script:WinToolState.LogExpanded = $false
$script:WinToolState.Busy = $false
Sync-WinToolLogPanel
$homeStub = @{
    junk = @([pscustomobject]@{ Id = "temp"; Name = "Your temporary files"; Bytes = [double]12GB }, [pscustomobject]@{ Id = "recycle"; Name = "Recycle Bin"; Bytes = [double]6.7GB })
    tweaks = @(1..10 | ForEach-Object { $tweakState = "on"; if ($_ -le 8) { $tweakState = "off" }; [pscustomobject]@{ Id = "t$_"; Name = "Tweak $_"; State = $tweakState } })
    startup = @("OneDrive", "Discord", "Steam", "Spotify" | ForEach-Object { [pscustomobject]@{ Name = $_; Source = "Run, this user"; Approved = -1 } })
    drivers = @()
    disk = @([pscustomobject]@{ Name = "NVMe SSD"; MediaType = "SSD"; Health = "Healthy" })
}
$script:WinToolState.Home.Info = [pscustomobject]@{ Os = "Windows 11 Pro"; Version = "24H2"; Cpu = "AMD Ryzen 7 7700 8-Core Processor"; MemoryTotal = [double]32GB; MemoryType = 34; DiskSize = [double]512e9; DiskMedia = "SSD" }
$sampleWave = @(38, 44, 41, 52, 47, 58, 50, 46, 55, 49, 61, 51)
for ($i = 0; $i -lt $sampleWave.Count; $i++) {
    Add-WinToolHomeSample -Sample ([pscustomobject]@{ MemoryUsed = [double]32GB * $sampleWave[$i] / 100; MemoryTotal = [double]32GB; DiskFree = [double]148GB; DiskTotal = [double]510GB; DiskBusy = [double](($sampleWave[$i] * 7) % 60); Cpu = [double](($sampleWave[$i] * 3) % 45 + 5) })
}
function Get-WinToolHomeBound {
    Complete-WinToolMotion
    $hs = $script:WinToolState.Home
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($name in @("HomeHero", "HomeRing", "HomeInfo", "HomeHeadline", "HomeLead", "HomeMeta", "HomeCheckCount", "HomeFixAll", "HomeChecks", "HomeMinis", "HomeAgain", "HomeRunText")) {
        $items.Add([pscustomobject]@{ Name = $name; Element = $window.FindName($name) })
    }
    foreach ($check in @(Get-WinToolHomeCheckList)) {
        $items.Add([pscustomobject]@{ Name = ("row " + $check.Id); Element = $hs.Rows[$check.Id].Border })
        $items.Add([pscustomobject]@{ Name = ("button " + $check.Id); Element = $hs.Rows[$check.Id].Button })
        $items.Add([pscustomobject]@{ Name = ("text " + $check.Id); Element = $hs.Rows[$check.Id].Result })
    }
    foreach ($key in @("memory", "disk", "pc")) {
        $items.Add([pscustomobject]@{ Name = ("card " + $key); Element = $hs.Minis[$key].Card })
        $items.Add([pscustomobject]@{ Name = ("tag " + $key); Element = $hs.Minis[$key].Tag })
        $items.Add([pscustomobject]@{ Name = ("spark " + $key); Element = $hs.Minis[$key].Spark })
    }
    $out = @{}
    foreach ($item in $items) {
        $point = $item.Element.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
        $out[$item.Name] = "{0:0.#},{1:0.#} {2:0.#}x{3:0.#}" -f $point.X, $point.Y, $item.Element.ActualWidth, $item.Element.ActualHeight
    }
    return $out
}
function Compare-WinToolHomeBound {
    param([hashtable]$Before, [hashtable]$After, [string]$Label)
    $moved = @()
    foreach ($key in $Before.Keys) {
        if ($Before[$key] -ne $After[$key]) { $moved += ("{0}: {1} -> {2}" -f $key, $Before[$key], $After[$key]) }
    }
    if ($moved.Count -gt 0) { throw ("Home " + $Label + " moved or resized: " + ($moved -join "; ")) }
}
foreach ($size in @(@(1280, 800), @(1920, 1080), @(1024, 640))) {
    $w = [double]$size[0]
    $h = [double]$size[1]
    $script:WinToolState.Home.Phase = "idle"
    Start-WinToolHomeAnalysis
    foreach ($id in @("junk", "tweaks", "startup", "drivers")) { Complete-WinToolHomeCheck -Id $id -Data $homeStub[$id] }
    $script:WinToolState.Home.Started = [DateTime]::Now.AddSeconds(-18)
    Sync-WinToolHomeRunText
    $hsRows = $script:WinToolState.Home.Rows
    if ($window.FindName("HomeFixAll").IsEnabled -or $window.FindName("HomeAgain").IsEnabled) { throw "Fix all and Analyze again must be off while analyzing." }
    if ($hsRows["drivers"].Button.Visibility -ne "Hidden" -or $hsRows["disk"].Button.Visibility -ne "Visible" -or $hsRows["disk"].Button.IsEnabled) { throw "While analyzing: a clean row hides its button, a busy row shows Fix greyed out." }
    if ($window.FindName("HomeCheckCount").Text -ne "4 of 5 complete" -or $window.FindName("HomeRingProgress").Text -ne "4 of 5 checks") { throw ("The progress counts are wrong: " + $window.FindName("HomeCheckCount").Text) }
    Save-WinToolViewShot -Name ("home-analyzing-" + $size[0]) -Width $w -Height $h
    Save-WinToolViewShot -Name ("home-analyzing-" + $size[0]) -Width $w -Height $h
    $analyzing = Get-WinToolHomeBound
    Complete-WinToolHomeCheck -Id "disk" -Data $homeStub["disk"]
    $script:WinToolState.Home.Seconds = 31
    Sync-WinToolHomeRunText
    if ($script:WinToolState.Home.Phase -ne "done") { throw "Home should be done after five checks." }
    if ([string]$window.FindName("HomeScore").Text -ne "72" -or [string]$window.FindName("HomeVerdictText").Text -ne "Needs attention") { throw ("The stub results should score 72, got " + $window.FindName("HomeScore").Text) }
    if (-not $window.FindName("HomeFixAll").IsEnabled -or -not $window.FindName("HomeAgain").IsEnabled) { throw "Fix all and Analyze again turn on when the analysis is done." }
    if ([string]$hsRows["junk"].Button.Content -ne "Fix" -or [string]$hsRows["startup"].Button.Content -ne "Review" -or $hsRows["disk"].Button.Visibility -ne "Hidden") { throw "Done rows show Fix, Review or an empty slot as in the mockup." }
    if ($window.FindName("HomeCheckCount").Text -ne "2 of 5 can be fixed" -or $window.FindName("HomeRunText").Text -ne "Finished in 31s") { throw ("The done header is wrong: " + $window.FindName("HomeCheckCount").Text + " / " + $window.FindName("HomeRunText").Text) }
    Save-WinToolViewShot -Name ("home-done-" + $size[0]) -Width $w -Height $h
    $done = Get-WinToolHomeBound
    Compare-WinToolHomeBound -Before $analyzing -After $done -Label ("done at " + $size[0])
    Start-WinToolHomeClean
    if ($script:WinToolState.Home.Phase -ne "fixing") { throw "Fixing junk should enter the fixing state." }
    Save-WinToolViewShot -Name ("home-fixing-" + $size[0]) -Width $w -Height $h
    $fixing = Get-WinToolHomeBound
    Compare-WinToolHomeBound -Before $analyzing -After $fixing -Label ("fixing at " + $size[0])
    Complete-WinToolHomeCheck -Id "junk" -Data @([pscustomobject]@{ Name = "Temp"; Bytes = [double]0 })
    if ($script:WinToolState.Home.Phase -ne "done" -or [string]$window.FindName("HomeScore").Text -ne "84") { throw ("After the junk fix the score should be 84, got " + $window.FindName("HomeScore").Text) }
    if (-not ([string]$window.FindName("HomeMetaText").Text).Contains("Score 84")) { throw ("HomeMetaText should sync to Score 84 after fixing, got " + [string]$window.FindName("HomeMetaText").Text) }
    if ([string]$script:WinToolState.Home.Minis["pc"].TagText.Text -ne "Healthy") { throw ("This PC should show Healthy when drivers and disk are ok, got " + [string]$script:WinToolState.Home.Minis["pc"].TagText.Text) }
    Complete-WinToolHomeCheck -Id "drivers" -Data @([pscustomobject]@{ Name = "USB Serial"; Class = "Ports"; Status = "Error"; Problem = 28 })
    if ([string]$script:WinToolState.Home.Minis["pc"].TagText.Text -ne "Driver issue") { throw ("This PC should show 'Driver issue' when a driver fails, got " + [string]$script:WinToolState.Home.Minis["pc"].TagText.Text) }
    Complete-WinToolHomeCheck -Id "drivers" -Data @()
    # The page fills the width: the hero and the cards end at the same right edge.
    $hero = $window.FindName("HomeHero")
    $right = $hero.TranslatePoint([System.Windows.Point]::new($hero.ActualWidth, 0), $rootVisual).X
    $cards = $window.FindName("HomeMinis")
    $cardsRight = $cards.TranslatePoint([System.Windows.Point]::new($cards.ActualWidth, 0), $rootVisual).X
    if ([Math]::Abs($right - $cardsRight) -gt 1.5 -or $right -lt ($w - 40)) { throw ("Home should fill the width at " + $size[0] + ": hero ends at " + $right + ", cards at " + $cardsRight) }
    Write-Output ("Home at {0}x{1}: analyzing, done and fixing share the same bounds (hero {2:0}x{3:0})." -f $size[0], $size[1], $hero.ActualWidth, $hero.ActualHeight)
}

# The real checks on this runner, in background runspaces.
$script:WinToolHomeNoJobs = $false
$script:WinToolState.Home.Phase = "idle"
$script:WinToolState.Home.Info = $null
Start-WinToolHomeSampler
Start-WinToolHomeAnalysis
$homeWait = [datetime]::UtcNow.AddSeconds(180)
while ([datetime]::UtcNow -lt $homeWait) {
    Update-WinToolHomePoll
    if ($script:WinToolState.Home.Phase -eq "done" -and $null -ne $script:WinToolState.Home.Info -and $null -ne $script:WinToolState.Home.LastSample -and $script:WinToolState.Home.LastSample.PSObject.Properties["Time"]) { break }
    Start-Sleep -Milliseconds 250
}
if ($script:WinToolState.Home.Phase -ne "done") { throw "The real Home checks did not finish in 180 seconds." }
foreach ($check in @(Get-WinToolHomeCheckList)) {
    $real = $script:WinToolState.Home.Results[$check.Id]
    Write-Output ("Home real check {0}: {1} '{2}' ({3}) {4}" -f $check.Id, $real.Status, $real.Text, $real.Action, (@($real.Detail | Select-Object -First 3) -join " | "))
    if ($check.Id -ne "disk" -and $check.Id -ne "drivers" -and $real.Status -eq "unknown") { throw ("The real " + $check.Id + " check failed: " + (@($real.Detail) -join " ")) }
}
Write-Output ("Home real score {0}, info: {1} / {2} / {3}" -f $window.FindName("HomeScore").Text, $script:WinToolState.Home.Info.Os, $script:WinToolState.Home.Info.Version, $script:WinToolState.Home.Info.Cpu)
Save-WinToolViewShot -Name "home-real-1280" -Width 1280 -Height 800
$script:WinToolState.HomeSampler.Sync.Stop = $true
Stop-WinToolThread -Job $script:WinToolState.HomeSampler
$script:WinToolState.HomeSampler = $null
Stop-WinToolThread -Job $script:WinToolState.HomeInfoJob
$script:WinToolState.HomeInfoJob = $null
$script:WinToolHomeNoJobs = $true

$uiErrors = Get-WinToolUiError
if ($uiErrors.Count -gt 0) {
    foreach ($uiError in $uiErrors) {
        Write-Output ("UI handler failed: " + $uiError.Name + ": " + $uiError.Message)
    }
    throw "$($uiErrors.Count) UI handler(s) failed."
}
Write-Output "Raised $raised UI events without errors."

# Verify Appearance controls are absent, Config ComboBoxes use the dark 34 px style,
# ProfileSummary names every prompt engine accurately, and LogPanel clearance keeps top cards still.
if ($null -ne $window.FindName("ThemePicker") -or $null -ne $window.FindName("AccentSwatches")) {
    throw "Appearance controls should be removed from MainWindow.xaml."
}
$window.FindName("NavConfig").IsChecked = $true
$window.FindName("ConfigTabProfile").IsChecked = $true
# The handler sweep raises Checked on every tab without changing IsChecked, so the
# profile radio can stay ticked while the last handler (Power) is what is on screen.
Show-WinToolConfigPanel -Name "Profile"
$script:WinToolTerminalChoice.prompt = "powerlevel10k"
Update-WinToolProfileSummary
if (-not ([string]$window.FindName("ProfileSummary").Text).Contains("Prompt: Powerlevel10k.")) {
    throw ("Config ProfileSummary should name Powerlevel10k, got: " + [string]$window.FindName("ProfileSummary").Text)
}
$script:WinToolTerminalChoice.prompt = "oh-my-posh"
Update-WinToolProfileSummary
if ($window.FindName("DnsAdapter").Height -ne 34 -or $window.FindName("DnsProvider").Height -ne 34) {
    throw "Config DNS ComboBoxes should be 34 px tall."
}
Save-WinToolViewShot -Name "config-1280" -Width 1280 -Height 800
$configFirstCard = $window.FindName("ConfigProfileCard")
$cardBefore = $configFirstCard.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
$script:WinToolState.LogExpanded = $true
Sync-WinToolLogPanel
Save-WinToolViewShot -Name "config-log-open" -Width 1280 -Height 800
$cardAfter = $configFirstCard.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual)
$cardDelta = [Math]::Abs($cardAfter.Y - $cardBefore.Y)
$configBottom = $window.FindName("ConfigBody").Margin.Bottom
# UseLayoutRounding can move a wrapped line by 1 px when the log reserves its
# scroll margin. A real jump (an extra line, a collapsed row) is far larger.
if ($cardDelta -gt 1.5 -or $configBottom -lt 180) {
    throw ("Opening LogPanel on Config should keep cards in place while adding bottom scroll clearance. Moved " + $cardDelta + " px, bottom margin " + $configBottom + ".")
}
$script:WinToolState.LogExpanded = $false
Sync-WinToolLogPanel
$window.FindName("NavDrivers").IsChecked = $true
Save-WinToolViewShot -Name "drivers-1280" -Width 1280 -Height 800
if ($null -eq $window.FindName("DriversScan") -or $null -eq $window.FindName("DriversToolList") -or $window.FindName("DriversToolList").Children.Count -lt 8) {
    throw "The Drivers tab is missing the scan button or its tool cards."
}
if ($window.FindName("DriversStart").Visibility -ne [System.Windows.Visibility]::Visible) {
    throw "The Drivers tab should show the start screen before a scan."
}
$window.FindName("NavUpdates").IsChecked = $true
Save-WinToolViewShot -Name "updates-1280" -Width 1280 -Height 800
$modeList = $window.FindName("UpdateModeList")
foreach ($modeRadio in @($modeList.Children)) {
    if ($modeRadio.DesiredSize.Width -gt ($modeList.ActualWidth + 1.0)) {
        throw ("Update mode radio text did not wrap inside the card: " + $modeRadio.DesiredSize.Width + " > " + $modeList.ActualWidth)
    }
}
$window.FindName("NavFixes").IsChecked = $true
Save-WinToolViewShot -Name "fixes-1280" -Width 1280 -Height 800
$window.FindName("NavFeatures").IsChecked = $true
Set-WinToolFeatureState -State $fakeState
Save-WinToolViewShot -Name "features-1280" -Width 1280 -Height 800
$window.FindName("NavHome").IsChecked = $true

if (-not (Initialize-WinToolConsoleApi)) {
    throw "The console helper did not compile on Windows PowerShell."
}
$null = [WinToolConsoleApi]::GetConsoleWindow()
Write-Output "Console helper compiled."

# The first pass builds each page. The second pass is a repeat visit and must
# not block the dispatcher. Input runs after Render and Loaded, and before
# the background timers, so the number is the click itself.
function Invoke-WinToolNavPump {
    $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Input, [System.Action]([scriptblock]::Create("return"))) | Out-Null
}
$navNames = @("Install", "Tweaks", "Terminal", "Drivers", "Updates", "Fixes", "Features", "Config", "Home")
foreach ($navName in $navNames) {
    $window.FindName("Nav" + $navName).IsChecked = $true
    Invoke-WinToolNavPump
}
$navSlow = New-Object System.Collections.Generic.List[string]
foreach ($navName in $navNames) {
    $script:WinToolState.NavMilliseconds = -1
    $window.FindName("Nav" + $navName).IsChecked = $true
    Invoke-WinToolNavPump
    $navMs = [int]$script:WinToolState.NavMilliseconds
    Write-Output ("Nav " + $navName + ": " + $navMs + "ms")
    if ($navMs -lt 0 -or $navMs -gt 250) {
        $navSlow.Add($navName + " " + $navMs + "ms")
    }
}
if ($navSlow.Count -gt 0) {
    throw ("Navigation blocked the dispatcher: " + ($navSlow -join ", "))
}

# In-page switches. The first pass warms each one. The second pass is what
# must stay under 250 ms. Input runs the Loaded timing callback and not the
# background timers, so the number is the click itself.
$script:WinToolUiQuiet = $true
$surfaceSlow = New-Object System.Collections.Generic.List[string]
function Measure-WinToolSurface {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    $script:WinToolState.NavMilliseconds = -1
    & $Action
    Invoke-WinToolNavPump
    $surfaceMs = [int]$script:WinToolState.NavMilliseconds
    Write-Output ("Nav " + $Label + ": " + $surfaceMs + "ms")
    if ($surfaceMs -lt 0 -or $surfaceMs -gt 250) {
        $script:WinToolSurfaceSlow.Add($Label + " " + $surfaceMs + "ms")
    }
}
$script:WinToolSurfaceSlow = $surfaceSlow
$surfaceClick = New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)

$window.FindName("NavTerminal").IsChecked = $true
Invoke-WinToolNavPump
$script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolTerminalPreview
$window.FindName("TerminalModeSimple").IsChecked = $true
Invoke-WinToolNavPump
$window.FindName("TerminalModeAdvanced").IsChecked = $true
Invoke-WinToolNavPump
$window.FindName("TerminalModeSimple").IsChecked = $true
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Terminal Advanced" -Action {
    $window.FindName("TerminalModeAdvanced").IsChecked = $true
}
Measure-WinToolSurface -Label "Terminal Simple" -Action {
    $window.FindName("TerminalModeAdvanced").IsChecked = $true
    $window.FindName("TerminalModeSimple").IsChecked = $true
}
$window.FindName("TerminalModeAdvanced").IsChecked = $true
Invoke-WinToolNavPump
foreach ($filterName in @("TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalFilterAll")) {
    $window.FindName($filterName).IsChecked = $true
    Invoke-WinToolNavPump
}
foreach ($filterName in @("TerminalFilterPowerline", "TerminalFilterMinimal", "TerminalFilterNoNerd", "TerminalFilterAll")) {
    $filterLabel = [string]$window.FindName($filterName).Tag
    Measure-WinToolSurface -Label ("Terminal " + $filterLabel) -Action {
        if ($filterName -eq "TerminalFilterAll") { $window.FindName("TerminalFilterPowerline").IsChecked = $true }
        else { $window.FindName("TerminalFilterAll").IsChecked = $true }
        $window.FindName($filterName).IsChecked = $true
    }
}
$themeSearch = $window.FindName("TerminalThemeSearch")
$themeSearch.Text = "jan"
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Terminal search" -Action { $themeSearch.Text = "" }
Measure-WinToolSurface -Label "Terminal search" -Action { $themeSearch.Text = "night" }
$themeSearch.Text = ""
Invoke-WinToolNavPump
$nerdBox = $window.FindName("TerminalFontNerdOnly")
$nerdBox.IsChecked = $false
$nerdBox.RaiseEvent($surfaceClick)
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Terminal fonts" -Action {
    $nerdBox.IsChecked = $true
    $nerdBox.RaiseEvent($surfaceClick)
}

$window.FindName("NavInstall").IsChecked = $true
Invoke-WinToolNavPump
$appChips = @{}
foreach ($chip in @($window.FindName("AppFilters").Children)) { $appChips[[string]$chip.Tag] = $chip }
foreach ($chipTag in @("installed", "updates", "category:browsers", "all")) {
    if ($appChips.ContainsKey($chipTag)) {
        $appChips[$chipTag].IsChecked = $true
        Invoke-WinToolNavPump
    }
}
foreach ($chipTag in @("installed", "updates", "category:browsers", "all")) {
    if (-not $appChips.ContainsKey($chipTag)) { continue }
    Measure-WinToolSurface -Label ("Install " + $chipTag) -Action {
        if ($chipTag -eq "all") { $appChips["installed"].IsChecked = $true }
        else { $appChips["all"].IsChecked = $true }
        $appChips[$chipTag].IsChecked = $true
    }
}
$appSearch = $window.FindName("AppSearch")
$appSearch.Text = "zip"
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Install search" -Action { $appSearch.Text = "" }
Measure-WinToolSurface -Label "Install search" -Action { $appSearch.Text = "code" }
$appSearch.Text = ""
Invoke-WinToolNavPump
if ($appChips.ContainsKey("all")) { $appChips["all"].IsChecked = $true }

$window.FindName("NavTweaks").IsChecked = $true
Invoke-WinToolNavPump
$tweakSearch = $window.FindName("TweakSearch")
$tweakSearch.Text = "dark"
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Tweaks search" -Action { $tweakSearch.Text = "" }
Measure-WinToolSurface -Label "Tweaks search" -Action { $tweakSearch.Text = "explorer" }
$tweakSearch.Text = ""
Invoke-WinToolNavPump
foreach ($presetButton in @($window.FindName("TweakPresets").Children)) {
    $presetButton.RaiseEvent($surfaceClick)
    Invoke-WinToolNavPump
}
foreach ($presetButton in @($window.FindName("TweakPresets").Children)) {
    Measure-WinToolSurface -Label ("Tweaks " + [string]$presetButton.Content) -Action {
        $presetButton.RaiseEvent($surfaceClick)
    }
}

$window.FindName("NavUpdates").IsChecked = $true
Invoke-WinToolNavPump
$updateRadios = @($window.FindName("UpdateModeList").Children)
foreach ($updateRadio in $updateRadios) {
    $updateRadio.IsChecked = $true
    Invoke-WinToolNavPump
}
foreach ($updateRadio in $updateRadios) {
    Measure-WinToolSurface -Label ("Updates " + [string]$updateRadio.Tag) -Action {
        $otherRadio = $updateRadios[0]
        if ([object]::ReferenceEquals($updateRadio, $updateRadios[0])) { $otherRadio = $updateRadios[1] }
        $otherRadio.IsChecked = $true
        $updateRadio.IsChecked = $true
    }
}

$window.FindName("NavConfig").IsChecked = $true
Invoke-WinToolNavPump
foreach ($configTab in @("ConfigTabProfile", "ConfigTabWinget", "ConfigTabTweaks", "ConfigTabDns", "ConfigTabPower")) {
    $window.FindName($configTab).IsChecked = $true
    Invoke-WinToolNavPump
}
foreach ($configTab in @("ConfigTabProfile", "ConfigTabWinget", "ConfigTabTweaks", "ConfigTabDns", "ConfigTabPower")) {
    Measure-WinToolSurface -Label ("Config " + $configTab.Replace("ConfigTab", "")) -Action {
        if ($configTab -eq "ConfigTabProfile") { $window.FindName("ConfigTabWinget").IsChecked = $true }
        else { $window.FindName("ConfigTabProfile").IsChecked = $true }
        $window.FindName($configTab).IsChecked = $true
    }
}

$window.FindName("NavFixes").IsChecked = $true
Invoke-WinToolNavPump
$fixButtons = New-Object System.Collections.Generic.List[object]
foreach ($fixCard in @($window.FindName("FixList").Children)) {
    $fixGrid = $fixCard.Child
    if ($null -eq $fixGrid) { continue }
    foreach ($fixChild in @($fixGrid.Children)) {
        if ($fixChild -is [System.Windows.Controls.Button]) { $fixButtons.Add($fixChild) }
        if ($fixChild -is [System.Windows.Controls.Grid]) {
            foreach ($fixInner in @($fixChild.Children)) {
                if ($fixInner -is [System.Windows.Controls.Button]) { $fixButtons.Add($fixInner) }
            }
        }
    }
}
foreach ($fixButton in $fixButtons.ToArray()) {
    $fixButton.RaiseEvent($surfaceClick)
    Invoke-WinToolNavPump
}
foreach ($fixButton in $fixButtons.ToArray()) {
    $fixTitle = "Run fix"
    $fixCardGrid = $fixButton.Parent
    if ($null -ne $fixCardGrid) { $fixCardGrid = $fixCardGrid.Parent }
    if ($null -ne $fixCardGrid -and $fixCardGrid.Children.Count -gt 0) {
        $fixTitle = [string]$fixCardGrid.Children[0].Text
    }
    Measure-WinToolSurface -Label ("Fixes " + $fixTitle) -Action {
        $fixButton.RaiseEvent($surfaceClick)
    }
}

$window.FindName("NavFeatures").IsChecked = $true
Invoke-WinToolNavPump
$window.FindName("FeatureApply").RaiseEvent($surfaceClick)
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Features apply" -Action {
    $window.FindName("FeatureApply").RaiseEvent($surfaceClick)
}

$window.FindName("NavHome").IsChecked = $true
Invoke-WinToolNavPump
$window.FindName("ToggleLogButton").RaiseEvent($surfaceClick)
Invoke-WinToolNavPump
$window.FindName("ToggleLogButton").RaiseEvent($surfaceClick)
Invoke-WinToolNavPump
Measure-WinToolSurface -Label "Show log" -Action { $window.FindName("ToggleLogButton").RaiseEvent($surfaceClick) }
Measure-WinToolSurface -Label "Hide log" -Action { $window.FindName("ToggleLogButton").RaiseEvent($surfaceClick) }
if ($script:WinToolState.LogExpanded) {
    $script:WinToolState.LogExpanded = $false
    $script:WinToolState.LogPinned = $false
    Sync-WinToolLogPanel
}

if ($surfaceSlow.Count -gt 0) {
    throw ("In-page switches blocked the dispatcher: " + ($surfaceSlow -join ", "))
}

# Terminal Simple should fill the space above "What will happen" at both sizes.
$window.FindName("NavTerminal").IsChecked = $true
Invoke-WinToolNavPump
$window.FindName("TerminalFilterAll").IsChecked = $true
$window.FindName("TerminalThemeSearch").Text = ""
$script:WinToolTerminalChoice = Get-WinToolSimpleTerminalChoice
Update-WinToolPromptStyleList
Update-WinToolTerminalSummary
Update-WinToolSimplePreview
$window.FindName("TerminalModeSimple").IsChecked = $true
Invoke-WinToolNavPump
function Assert-WinToolSimpleFill {
    param([string]$Label)
    $rootVisual.UpdateLayout()
    Sync-WinToolScrollFill -ScrollName "TerminalSimpleScroll" -BodyName "TerminalSimpleHost"
    $rootVisual.UpdateLayout()
    $preview = $window.FindName("TerminalSimplePreview")
    $included = $window.FindName("TerminalSimpleIncluded")
    $summary = $window.FindName("TerminalSummaryCard")
    $sample = $window.FindName("TerminalSimpleSample")
    $gap = $summary.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual).Y - $preview.TranslatePoint([System.Windows.Point]::new(0, $preview.ActualHeight), $rootVisual).Y
    Write-Output ("{0}: preview {1:0}x{2:0}, included {3:0}x{4:0}, gap {5:0}, lines {6}" -f $Label, $preview.ActualWidth, $preview.ActualHeight, $included.ActualWidth, $included.ActualHeight, $gap, @($sample.Inlines).Count)
    if (@($sample.Inlines).Count -lt 4) { throw ($Label + " preview did not draw the recommended prompt.") }
    if ($window.FindName("TerminalSimpleIncludedList").Children.Count -lt 5) { throw ($Label + " is missing the included list.") }
    if ($preview.ActualHeight -lt 280 -or $included.ActualHeight -lt 280) { throw ($Label + " cards are still a short strip.") }
    if ([Math]::Abs($preview.ActualHeight - $included.ActualHeight) -gt 4) { throw ($Label + " cards are not the same height.") }
    if ($gap -gt 48) { throw ($Label + " leaves " + [int]$gap + " px between the preview and What will happen.") }
}
function Invoke-WinToolFillShot {
    param([string]$Name, [double]$Width, [double]$Height, [string]$ScrollName, [string]$BodyName)
    $rootVisual.Measure([System.Windows.Size]::new($Width, $Height))
    $rootVisual.Arrange([System.Windows.Rect]::new(0, 0, $Width, $Height))
    $rootVisual.UpdateLayout()
    Sync-WinToolScrollFill -ScrollName $ScrollName -BodyName $BodyName
    $rootVisual.UpdateLayout()
    Save-WinToolViewShot -Name $Name -Width $Width -Height $Height
}
Invoke-WinToolFillShot -Name "terminal-simple-1280" -Width 1280 -Height 800 -ScrollName "TerminalSimpleScroll" -BodyName "TerminalSimpleHost"
Assert-WinToolSimpleFill -Label "Terminal Simple 1280"
Invoke-WinToolFillShot -Name "terminal-simple-1920" -Width 1920 -Height 1080 -ScrollName "TerminalSimpleScroll" -BodyName "TerminalSimpleHost"
Assert-WinToolSimpleFill -Label "Terminal Simple 1920"
$window.FindName("TerminalModeAdvanced").IsChecked = $true
Invoke-WinToolNavPump
Save-WinToolTerminalShot -Name "terminal-advanced-1280" -Width 1280 -Height 800
Save-WinToolTerminalShot -Name "terminal-advanced-1920" -Width 1920 -Height 1080

function Assert-WinToolPageFill {
    param($Element, [string]$Label, [string]$ScrollName, [string]$BodyName)
    $rootVisual.UpdateLayout()
    Sync-WinToolScrollFill -ScrollName $ScrollName -BodyName $BodyName
    $rootVisual.UpdateLayout()
    $status = $window.FindName("StatusBar")
    $bottom = $Element.TranslatePoint([System.Windows.Point]::new(0, $Element.ActualHeight), $rootVisual).Y
    $limit = $status.TranslatePoint([System.Windows.Point]::new(0, 0), $rootVisual).Y
    $gap = $limit - $bottom
    Write-Output ("{0}: fill gap {1:0} px, height {2:0}" -f $Label, $gap, $Element.ActualHeight)
    if ($gap -gt 96) { throw ($Label + " leaves " + [int]$gap + " px empty above the status bar.") }
}
$window.FindName("NavDrivers").IsChecked = $true
Invoke-WinToolNavPump
Invoke-WinToolFillShot -Name "drivers-1920" -Width 1920 -Height 1080 -ScrollName "ViewDrivers" -BodyName "DriversBody"
Assert-WinToolPageFill -Element $window.FindName("DriversBody") -Label "Drivers 1920" -ScrollName "ViewDrivers" -BodyName "DriversBody"
$window.FindName("NavUpdates").IsChecked = $true
Invoke-WinToolNavPump
Invoke-WinToolFillShot -Name "updates-1920" -Width 1920 -Height 1080 -ScrollName "ViewUpdates" -BodyName "UpdatesBody"
Assert-WinToolPageFill -Element $window.FindName("UpdateModeList").Parent.Parent -Label "Updates 1920" -ScrollName "ViewUpdates" -BodyName "UpdatesBody"
$window.FindName("NavFixes").IsChecked = $true
Invoke-WinToolNavPump
Invoke-WinToolFillShot -Name "fixes-1920" -Width 1920 -Height 1080 -ScrollName "ViewFixes" -BodyName "FixesBody"
Assert-WinToolPageFill -Element $window.FindName("FixList") -Label "Fixes 1920" -ScrollName "ViewFixes" -BodyName "FixesBody"
$window.FindName("NavFeatures").IsChecked = $true
Invoke-WinToolNavPump
Invoke-WinToolFillShot -Name "features-1920" -Width 1920 -Height 1080 -ScrollName "ViewFeatures" -BodyName "FeaturesBody"
Assert-WinToolPageFill -Element $window.FindName("FeatureList").Parent -Label "Features 1920" -ScrollName "ViewFeatures" -BodyName "FeaturesBody"
$window.FindName("NavConfig").IsChecked = $true
$window.FindName("ConfigTabProfile").IsChecked = $true
Invoke-WinToolNavPump
Invoke-WinToolFillShot -Name "config-1920" -Width 1920 -Height 1080 -ScrollName "ViewConfig" -BodyName "ConfigBody"
Assert-WinToolPageFill -Element $window.FindName("ConfigProfileCard") -Label "Config 1920" -ScrollName "ViewConfig" -BodyName "ConfigBody"

try {
    $window.Close()
}
catch {
    Write-Output $_.Exception.Message
}

Write-Output "WinTool window built: $($appRows.Count) apps, $($tweakRows.Count) tweaks."
exit 0
