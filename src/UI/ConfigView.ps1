# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolConfigView {
    (Get-WinToolUi -Name "SaveProfile").Add_Click({ Invoke-WinToolSaveProfile })
    (Get-WinToolUi -Name "LoadProfile").Add_Click({ Invoke-WinToolLoadProfile })
    (Get-WinToolUi -Name "ExportWinget").Add_Click({ Invoke-WinToolExportWinget })
    (Get-WinToolUi -Name "ImportWinget").Add_Click({ Invoke-WinToolImportWinget })
    Update-WinToolProfileSummary
}

function Update-WinToolProfileSummary {
    $apps = @(Get-WinToolCheckedApp)
    $tweaks = @(Get-WinToolCheckedTweak)
    $terminal = Get-WinToolTerminalChoice
    $prompt = "Oh My Posh"
    if ($terminal.prompt -eq "starship") {
        $prompt = "Starship"
    }
    $replay = "Terminal setup is saved with the profile."
    if (-not $terminal.enabled) {
        $replay = "Terminal setup is not included when this profile is replayed."
    }
    $text = "{0} apps selected, {1} tweaks selected. Prompt: {2}. {3}" -f $apps.Count, $tweaks.Count, $prompt, $replay
    (Get-WinToolUi -Name "ProfileSummary").Text = $text
}

function Get-WinToolProfileFromUi {
    $apps = @(Get-WinToolCheckedApp)
    $tweaks = @(Get-WinToolCheckedTweak)
    $appIds = New-Object System.Collections.Generic.List[string]
    foreach ($app in $apps) {
        $appIds.Add([string]$app.Id)
    }
    $tweakIds = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in $tweaks) {
        $tweakIds.Add([string]$tweak.id)
    }
    return (ConvertTo-WinToolProfile -AppId $appIds.ToArray() -TweakId $tweakIds.ToArray() -Terminal (Get-WinToolTerminalChoice) -Name "My WinTool profile")
}

function Import-WinToolProfileToUi {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    $toolProfile = Read-WinToolProfile -Path $Path
    $resolved = Resolve-WinToolProfileSelection -Profile $toolProfile
    foreach ($id in @($resolved.UnknownApps)) {
        Write-WinToolLog -Message "Unknown app id '$id' in the profile." -Level "warn"
    }
    foreach ($id in @($resolved.UnknownTweaks)) {
        Write-WinToolLog -Message "Unknown tweak id '$id' in the profile." -Level "warn"
    }
    $appIds = New-Object System.Collections.Generic.List[string]
    foreach ($app in @($resolved.AppRecords)) {
        $appIds.Add([string]$app.id)
    }
    $tweakIds = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in @($resolved.TweakRecords)) {
        $tweakIds.Add([string]$tweak.id)
    }
    Sync-WinToolAppCheck -Id $appIds.ToArray() -OnlyThese
    Sync-WinToolTweakCheck -Id $tweakIds.ToArray() -OnlyThese
    Sync-WinToolTerminalChoice -Selection (Get-WinToolNote -Object $toolProfile -Name "terminal")
    Update-WinToolProfileSummary
    Write-WinToolLog -Message ("Loaded {0}. Nothing was installed yet." -f $Path) -Level "ok"
}

function Invoke-WinToolSaveProfile {
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "WinTool profile (*.json)|*.json"
    $dialog.FileName = "wintool-profile.json"
    $dialog.Title = "Save WinTool profile"
    $accepted = $dialog.ShowDialog($script:WinToolWindow)
    if ($accepted -ne $true) {
        return
    }
    $toolProfile = Get-WinToolProfileFromUi
    Write-WinToolProfile -Path $dialog.FileName -Profile $toolProfile
    Write-WinToolLog -Message ("Saved profile to {0}" -f $dialog.FileName) -Level "ok"
}

function Invoke-WinToolLoadProfile {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = "WinTool profile (*.json)|*.json"
    $dialog.Title = "Load WinTool profile"
    $accepted = $dialog.ShowDialog($script:WinToolWindow)
    if ($accepted -ne $true) {
        return
    }
    try {
        Import-WinToolProfileToUi -Path $dialog.FileName
    }
    catch {
        Write-WinToolLog -Message ("Could not load that profile. {0}" -f $_.Exception.Message) -Level "error"
    }
}

function Invoke-WinToolExportWinget {
    $winget = Get-WinToolWingetPath
    if ([string]::IsNullOrWhiteSpace($winget)) {
        Write-WinToolLog -Message "winget was not found. Install App Installer from the Microsoft Store, then try again." -Level "warn"
        return
    }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "winget package list (*.json)|*.json"
    $dialog.FileName = "winget-packages.json"
    $dialog.Title = "Export winget package list"
    $accepted = $dialog.ShowDialog($script:WinToolWindow)
    if ($accepted -ne $true) {
        return
    }
    $step = [pscustomobject]@{
        Type = "process"
        Label = "Export winget packages"
        FilePath = $winget
        Arguments = @("export", "-o", $dialog.FileName, "--accept-source-agreements")
    }
    Invoke-WinToolPlanAsync -Step @($step) -DoneMessage "winget export finished."
}

function Invoke-WinToolImportWinget {
    $winget = Get-WinToolWingetPath
    if ([string]::IsNullOrWhiteSpace($winget)) {
        Write-WinToolLog -Message "winget was not found. Install App Installer from the Microsoft Store, then try again." -Level "warn"
        return
    }
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = "winget package list (*.json)|*.json"
    $dialog.Title = "Import winget package list"
    $accepted = $dialog.ShowDialog($script:WinToolWindow)
    if ($accepted -ne $true) {
        return
    }
    $ok = Request-WinToolConfirmation -Message "Ask winget to install every package in this file?" -Title "Import winget list"
    if (-not $ok) {
        return
    }
    $step = [pscustomobject]@{
        Type = "process"
        Label = "Import winget packages"
        FilePath = $winget
        Arguments = @("import", "-i", $dialog.FileName, "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
    }
    Invoke-WinToolPlanAsync -Step @($step) -DoneMessage "winget import finished."
}
