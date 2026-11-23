# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolConfigView {
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "SaveProfile") -EventName "Click" -Name "Config: save profile" -Action { Invoke-WinToolSaveProfile }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "LoadProfile") -EventName "Click" -Name "Config: load profile" -Action { Invoke-WinToolLoadProfile }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ExportWinget") -EventName "Click" -Name "Config: export winget list" -Action { Invoke-WinToolExportWinget }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ImportWinget") -EventName "Click" -Name "Config: import winget list" -Action { Invoke-WinToolImportWinget }
    Initialize-WinToolSystemView
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

function Initialize-WinToolSystemView {
    $catalog = Get-WinToolSystemCatalog
    $providerBox = Get-WinToolUi -Name "DnsProvider"
    $providerBox.Items.Clear()
    foreach ($provider in (Get-WinToolDnsProvider -Catalog $catalog)) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$provider.name
        $item.Tag = [string]$provider.id
        $item.ToolTip = [string](Get-WinToolNote -Object $provider -Name "description" -Default "")
        [void]$providerBox.Items.Add($item)
    }
    $providerBox.SelectedIndex = 0
    $plan = Get-WinToolNote -Object $catalog -Name "powerPlan"
    (Get-WinToolUi -Name "PowerPlanDescription").Text = [string]$plan.description

    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "DnsAdapter") -EventName "SelectionChanged" -Name "Config: pick adapter" -Action { Sync-WinToolDnsSummary }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "RefreshDns") -EventName "Click" -Name "Config: refresh adapters" -Action { Update-WinToolSystemView }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "ApplyDns") -EventName "Click" -Name "Config: apply DNS" -Action { Invoke-WinToolDnsClick }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "AddUltimatePlan") -EventName "Click" -Name "Config: add Ultimate Performance" -Action { Invoke-WinToolPowerPlanClick -Action "add" }
    Register-WinToolUiEvent -Control (Get-WinToolUi -Name "RemoveUltimatePlan") -EventName "Click" -Name "Config: remove Ultimate Performance" -Action { Invoke-WinToolPowerPlanClick -Action "remove" }
}

function Update-WinToolSystemView {
    $adapters = @()
    try {
        $adapters = @(Get-WinToolDnsAdapter)
    }
    catch {
        Write-WinToolLog -Message ("Could not read network adapters. " + $_.Exception.Message) -Level "warn"
    }
    $script:WinToolState.DnsAdapters = $adapters
    $box = Get-WinToolUi -Name "DnsAdapter"
    $box.Items.Clear()
    if ($adapters.Count -gt 1) {
        $all = New-Object System.Windows.Controls.ComboBoxItem
        $all.Content = "All connected adapters"
        $all.Tag = -1
        [void]$box.Items.Add($all)
    }
    foreach ($adapter in $adapters) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = ("{0}  -  {1}" -f [string]$adapter.Name, [string]$adapter.Description)
        $item.Tag = [int]$adapter.Index
        [void]$box.Items.Add($item)
    }
    if ($box.Items.Count -gt 0) {
        $box.SelectedIndex = 0
    }
    Sync-WinToolDnsSummary
    Sync-WinToolPowerPlanStatus
}

function Get-WinToolSelectedDnsAdapter {
    $item = (Get-WinToolUi -Name "DnsAdapter").SelectedItem
    if ($null -eq $item) {
        return @()
    }
    $index = [int]$item.Tag
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in @($script:WinToolState.DnsAdapters)) {
        if ($index -eq -1 -or [int]$adapter.Index -eq $index) {
            $list.Add($adapter)
        }
    }
    return $list.ToArray()
}

function Sync-WinToolDnsSummary {
    $selected = @(Get-WinToolSelectedDnsAdapter)
    $text = "No connected network adapter found."
    if ($selected.Count -gt 0) {
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($adapter in $selected) {
            $lines.Add((Format-WinToolDnsSummary -Adapter $adapter))
        }
        $text = "Now: " + ($lines -join [Environment]::NewLine)
    }
    (Get-WinToolUi -Name "DnsCurrent").Text = $text
}

function Sync-WinToolPowerPlanStatus {
    $text = "Power plans are only on Windows."
    if (Test-WinToolWindows) {
        try {
            $schemes = ConvertFrom-WinToolPowerList -Text ((& powercfg.exe /list) | Out-String)
            $catalog = Get-WinToolSystemCatalog
            $state = Get-WinToolPowerPlanState -Scheme $schemes -Catalog $catalog
            $text = Format-WinToolPowerPlanStatus -State $state -Name ([string]$catalog.powerPlan.name)
            (Get-WinToolUi -Name "RemoveUltimatePlan").IsEnabled = [bool]$state.Added
        }
        catch {
            $text = "Could not read power plans. " + $_.Exception.Message
        }
    }
    (Get-WinToolUi -Name "PowerPlanStatus").Text = $text
}

function Invoke-WinToolDnsClick {
    $adapters = @(Get-WinToolSelectedDnsAdapter)
    if ($adapters.Count -eq 0) {
        Write-WinToolLog -Message "Pick a network adapter first." -Level "warn"
        return
    }
    $item = (Get-WinToolUi -Name "DnsProvider").SelectedItem
    if ($null -eq $item) {
        Write-WinToolLog -Message "Pick a DNS provider first." -Level "warn"
        return
    }
    $provider = Find-WinToolDnsProvider -Id ([string]$item.Tag)
    $ipv6 = ((Get-WinToolUi -Name "DnsIncludeIpv6").IsChecked -eq $true)
    $servers = @(Get-WinToolDnsServerList -Provider $provider -IncludeIpv6 $ipv6)
    $what = "automatic (DHCP)"
    if ($servers.Count -gt 0) {
        $what = [string]$provider.name + " (" + ($servers -join ", ") + ")"
    }
    $names = (@($adapters | ForEach-Object { [string]$_.Name })) -join ", "
    $ok = Request-WinToolConfirmation -Message ("Set DNS on {0} to {1}?" -f $names, $what) -Title "DNS servers"
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolDnsPlan -Adapter $adapters -Provider $provider -IncludeIpv6 $ipv6)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "DNS servers changed." -AfterDone "Update-WinToolSystemView"
}

function Invoke-WinToolPowerPlanClick {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("add", "remove")][string]$Action
    )
    $message = "Add the Ultimate Performance power plan and switch to it?"
    if ($Action -eq "remove") {
        $message = "Remove the Ultimate Performance plan WinTool added? If it is active, Windows goes back to Balanced."
    }
    $ok = Request-WinToolConfirmation -Message $message -Title "Power plan"
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolPowerPlanPlan -Action $Action)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "Power plan updated." -AfterDone "Sync-WinToolPowerPlanStatus"
}
