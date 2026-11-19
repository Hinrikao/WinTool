# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Initialize-WinToolTerminalView {
    $catalog = Get-WinToolTerminalCatalog
    $picker = Get-WinToolUi -Name "FontPicker"
    $picker.Items.Clear()
    foreach ($font in @(Get-WinToolNote -Object $catalog -Name "fonts" -Default @())) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$font.name
        $item.Tag = [string]$font.id
        [void]$picker.Items.Add($item)
    }
    if ($picker.Items.Count -gt 0) {
        $picker.SelectedIndex = 0
    }
    (Get-WinToolUi -Name "WslCheck").Add_Checked({
        (Get-WinToolUi -Name "ZshCheck").IsEnabled = $true
    })
    (Get-WinToolUi -Name "WslCheck").Add_Unchecked({
        $zsh = Get-WinToolUi -Name "ZshCheck"
        $zsh.IsChecked = $false
        $zsh.IsEnabled = $false
    })
    (Get-WinToolUi -Name "TerminalSetup").Add_Click({
        Invoke-WinToolTerminalClick
    })
}

function Get-WinToolTerminalChoice {
    $prompt = "oh-my-posh"
    if ((Get-WinToolUi -Name "PromptStarship").IsChecked -eq $true) {
        $prompt = "starship"
    }
    $picker = Get-WinToolUi -Name "FontPicker"
    $fontId = ""
    if ($null -ne $picker.SelectedItem) {
        $fontId = [string]$picker.SelectedItem.Tag
    }
    return [pscustomobject]@{
        enabled = ((Get-WinToolUi -Name "TerminalEnabled").IsChecked -eq $true)
        prompt = $prompt
        fontId = $fontId
        terminalIcons = ((Get-WinToolUi -Name "TerminalIconsCheck").IsChecked -eq $true)
        wsl = ((Get-WinToolUi -Name "WslCheck").IsChecked -eq $true)
        zsh = ((Get-WinToolUi -Name "ZshCheck").IsChecked -eq $true)
    }
}

function Sync-WinToolTerminalChoice {
    param($Selection)
    if ($null -eq $Selection) {
        return
    }
    $prompt = [string](Get-WinToolNote -Object $Selection -Name "prompt" -Default "oh-my-posh")
    (Get-WinToolUi -Name "PromptStarship").IsChecked = ($prompt -eq "starship")
    (Get-WinToolUi -Name "PromptOhMyPosh").IsChecked = ($prompt -ne "starship")
    $fontId = [string](Get-WinToolNote -Object $Selection -Name "fontId" -Default "")
    $picker = Get-WinToolUi -Name "FontPicker"
    for ($index = 0; $index -lt $picker.Items.Count; $index++) {
        $item = $picker.Items[$index]
        if ([string]$item.Tag -eq $fontId) {
            $picker.SelectedItem = $item
        }
    }
    (Get-WinToolUi -Name "TerminalIconsCheck").IsChecked = [bool](Get-WinToolNote -Object $Selection -Name "terminalIcons" -Default $true)
    $wsl = [bool](Get-WinToolNote -Object $Selection -Name "wsl" -Default $false)
    (Get-WinToolUi -Name "WslCheck").IsChecked = $wsl
    (Get-WinToolUi -Name "ZshCheck").IsEnabled = $wsl
    (Get-WinToolUi -Name "ZshCheck").IsChecked = [bool](Get-WinToolNote -Object $Selection -Name "zsh" -Default $false)
    (Get-WinToolUi -Name "TerminalEnabled").IsChecked = [bool](Get-WinToolNote -Object $Selection -Name "enabled" -Default $true)
}

function Invoke-WinToolTerminalClick {
    $choice = Get-WinToolTerminalChoice
    $promptName = "Oh My Posh"
    if ($choice.prompt -eq "starship") {
        $promptName = "Starship"
    }
    $ok = Request-WinToolConfirmation -Message ("Set up Windows Terminal with {0}? This installs a few packages with winget." -f $promptName) -Title "Terminal"
    if (-not $ok) {
        return
    }
    $steps = @(Get-WinToolTerminalPlan -Selection $choice)
    Invoke-WinToolPlanAsync -Step $steps -DoneMessage "Terminal setup finished. Open a new terminal window to see the prompt."
}
