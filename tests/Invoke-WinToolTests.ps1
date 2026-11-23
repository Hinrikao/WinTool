# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

$ErrorActionPreference = "Stop"
$script:WinToolRoot = Split-Path -Parent $PSScriptRoot
$script:WinToolEmbedded = $null
$script:WinToolVersion = ([System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/version.txt"))).Trim()

$listPath = Join-Path $script:WinToolRoot "build/files.txt"
foreach ($relative in [System.IO.File]::ReadAllLines($listPath)) {
    $trimmed = $relative.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
        continue
    }
    if ($trimmed.StartsWith("src/UI/") -or $trimmed -eq "src/Entry.ps1") {
        continue
    }
    . (Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/'))
}

$script:WinToolFailures = New-Object System.Collections.Generic.List[string]

function Test-WinToolExpectation {
    param(
        [bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        $script:WinToolFailures.Add($Message)
        Write-Output "FAIL  $Message"
    }
}

function Invoke-WinToolCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    Write-Output "TEST  $Name"
    try {
        & $Body
    }
    catch {
        $script:WinToolFailures.Add("$Name threw: $($_.Exception.Message)")
        Write-Output "FAIL  $Name threw: $($_.Exception.Message)"
    }
}

Invoke-WinToolCase -Name "Catalog files are valid" -Body {
    $errors = @(Test-WinToolDataFile)
    Test-WinToolExpectation -Condition ($errors.Count -eq 0) -Message ("Catalog errors: " + ($errors -join " | "))
}

Invoke-WinToolCase -Name "Presets select the expected tweaks" -Body {
    $catalog = Get-WinToolTweakCatalog
    $minimal = @(Get-WinToolPresetTweak -Catalog $catalog -PresetId "minimal")
    $recommended = @(Get-WinToolPresetTweak -Catalog $catalog -PresetId "recommended")
    $minimalIds = @($minimal | ForEach-Object { $_.id })
    $recommendedIds = @($recommended | ForEach-Object { $_.id })
    Test-WinToolExpectation -Condition ($minimalIds -contains "show-file-extensions") -Message "Minimal preset includes file extensions."
    Test-WinToolExpectation -Condition ($minimalIds -contains "dark-mode") -Message "Minimal preset includes dark mode."
    Test-WinToolExpectation -Condition ($minimalIds -notcontains "remove-suggested-inbox-apps") -Message "Minimal preset does not debloat."
    Test-WinToolExpectation -Condition ($recommendedIds -contains "reduce-telemetry") -Message "Recommended preset reduces telemetry."
    Test-WinToolExpectation -Condition ($recommendedIds -contains "remove-suggested-inbox-apps") -Message "Recommended preset includes the small debloat."
    Test-WinToolExpectation -Condition ($recommendedIds -notcontains "classic-context-menu") -Message "Classic menu stays opt-in."
}

Invoke-WinToolCase -Name "Tweak steps describe apply and undo" -Body {
    $catalog = Get-WinToolTweakCatalog
    $extensions = $null
    $telemetry = $null
    $inbox = $null
    foreach ($tweak in @($catalog.tweaks)) {
        if ($tweak.id -eq "show-file-extensions") { $extensions = $tweak }
        if ($tweak.id -eq "reduce-telemetry") { $telemetry = $tweak }
        if ($tweak.id -eq "remove-suggested-inbox-apps") { $inbox = $tweak }
    }
    $apply = @(Get-WinToolTweakStep -Tweak $extensions -Direction "Apply")
    $undo = @(Get-WinToolTweakStep -Tweak $extensions -Direction "Undo")
    Test-WinToolExpectation -Condition ($apply.Count -eq 1 -and $apply[0].Type -eq "registry-set" -and $apply[0].Value -eq 0) -Message "Extensions are shown by setting HideFileExt to 0."
    Test-WinToolExpectation -Condition ($undo.Count -eq 1 -and $undo[0].Value -eq 1) -Message "Undo hides extensions again."
    $telemetryUndo = @(Get-WinToolTweakStep -Tweak $telemetry -Direction "Undo")
    $removed = @($telemetryUndo | Where-Object { $_.Type -eq "registry-remove-value" })
    Test-WinToolExpectation -Condition ($removed.Count -ge 2) -Message "Telemetry undo removes the policy values."
    $inboxUndo = @(Get-WinToolTweakStep -Tweak $inbox -Direction "Undo")
    Test-WinToolExpectation -Condition ($inboxUndo.Count -eq 1 -and $inboxUndo[0].Type -eq "appx-restore" -and @($inboxUndo[0].Packages).Count -gt 0) -Message "Inbox undo remembers the package names."
}

Invoke-WinToolCase -Name "winget arguments and results" -Body {
    $arguments = @(Get-WinToolWingetArgument -Id "Mozilla.Firefox")
    $line = ConvertTo-WinToolArgumentLine -ArgumentList $arguments
    Test-WinToolExpectation -Condition ($line -eq "install --id Mozilla.Firefox --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity") -Message "winget install arguments are non-interactive."
    $quoted = ConvertTo-WinToolArgumentLine -ArgumentList @("export", "-o", "C:\My Profiles\apps.json")
    Test-WinToolExpectation -Condition ($quoted -match '"C:\\My Profiles\\apps.json"') -Message "Paths with spaces are quoted."
    $installed = ConvertTo-WinToolWingetResult -ExitCode 0 -Output ""
    $already = ConvertTo-WinToolWingetResult -ExitCode -1978335189 -Output ""
    $text = ConvertTo-WinToolWingetResult -ExitCode 1 -Output "Found an existing package already installed"
    $failed = ConvertTo-WinToolWingetResult -ExitCode 1 -Output "No package found"
    Test-WinToolExpectation -Condition ($installed.Status -eq "Installed" -and $already.Status -eq "AlreadyInstalled" -and $text.Status -eq "AlreadyInstalled" -and $failed.Status -eq "Failed") -Message "winget exit codes are classified."
}

Invoke-WinToolCase -Name "JSON keeps one-item arrays and strips comments" -Body {
    $toolProfile = ConvertTo-WinToolProfile -AppId @("firefox") -TweakId @("dark-mode") -Terminal ([pscustomobject]@{ prompt = "starship"; enabled = $true }) -Name "Desk"
    $json = ConvertTo-WinToolJsonText -Value $toolProfile
    $again = ConvertFrom-WinToolJsonText -Text $json
    Test-WinToolExpectation -Condition (@($again.apps).Count -eq 1 -and $again.apps[0] -eq "firefox") -Message "A one-app profile stays an array."
    Test-WinToolExpectation -Condition ($again.terminal.prompt -eq "starship") -Message "Terminal choice round-trips."
    $sample = @"
{
  "site": "http://example.test",
  // comment
  "ok": true,
}
"@
    $plain = ConvertTo-WinToolPlainJson -Text $sample
    $parsed = ConvertFrom-WinToolJsonText -Text $sample
    $siteOk = $parsed.site -eq "http://example.test"
    Test-WinToolExpectation -Condition ($siteOk -and $parsed.ok -eq $true) -Message "JSON with comments still parses."
    Test-WinToolExpectation -Condition ($plain.IndexOf("comment") -lt 0) -Message "Line comments are removed."
}

Invoke-WinToolCase -Name "Profiles reject unknown ids and keep known ones" -Body {
    $toolProfile = [pscustomobject]@{
        schemaVersion = 1
        apps = @("firefox", "not-a-real-app")
        tweaks = @("dark-mode", "not-a-real-tweak")
    }
    $resolved = Resolve-WinToolProfileSelection -Profile $toolProfile
    Test-WinToolExpectation -Condition (@($resolved.AppRecords).Count -eq 1 -and $resolved.AppRecords[0].id -eq "firefox") -Message "Known apps are kept."
    Test-WinToolExpectation -Condition (@($resolved.UnknownApps) -contains "not-a-real-app") -Message "Unknown apps are reported."
    Test-WinToolExpectation -Condition (@($resolved.UnknownTweaks) -contains "not-a-real-tweak") -Message "Unknown tweaks are reported."
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-profile-" + [guid]::NewGuid().ToString() + ".json")
    try {
        Write-WinToolProfile -Path $temp -Profile $toolProfile
        $loaded = Read-WinToolProfile -Path $temp
        Test-WinToolExpectation -Condition ([int]$loaded.schemaVersion -eq 1) -Message "A profile file can be read back."
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Terminal plan, font face, and profile block" -Body {
    $selection = [pscustomobject]@{
        prompt = "starship"
        fontId = "jetbrains-mono"
        terminalIcons = $true
        wsl = $true
        zsh = $true
    }
    $plan = @(Get-WinToolTerminalPlan -Selection $selection)
    $types = @($plan | ForEach-Object { $_.Type })
    Test-WinToolExpectation -Condition ($types[0] -eq "winget" -and $types -contains "font" -and $types -contains "profile" -and $types -contains "wsl-shell") -Message "Terminal setup plans packages, the font, profiles, and zsh."
    Test-WinToolExpectation -Condition (@($plan | Where-Object { $_.WingetId -eq "Starship.Starship" }).Count -eq 1) -Message "Starship is the selected prompt package."
    $face = ConvertTo-WinToolFontFace -RegistryName "JetBrainsMono Nerd Font (TrueType)"
    Test-WinToolExpectation -Condition ($face -eq "JetBrainsMono Nerd Font") -Message "Font registry names drop the TrueType suffix."
    $settings = [pscustomobject]@{ profiles = [pscustomobject]@{ defaults = [pscustomobject]@{} } }
    Add-WinToolTerminalFont -Settings $settings -Face "JetBrainsMono Nerd Font" -Size 13 | Out-Null
    Test-WinToolExpectation -Condition ($settings.profiles.defaults.font.face -eq "JetBrainsMono Nerd Font" -and $settings.profiles.defaults.font.size -eq 13) -Message "Terminal settings receive the font face."
    $first = Update-WinToolManagedBlock -Text "Write-Host 'hi'" -Begin $script:WinToolProfileBegin -End $script:WinToolProfileEnd -Body "Get-Date"
    $second = Update-WinToolManagedBlock -Text $first -Begin $script:WinToolProfileBegin -End $script:WinToolProfileEnd -Body "Get-Location"
    Test-WinToolExpectation -Condition ($second.Contains("Get-Location") -and -not $second.Contains("Get-Date") -and $second.Contains("Write-Host 'hi'")) -Message "The managed profile block is replaced in place."
    $prompt = Get-WinToolPromptScript -PromptId "oh-my-posh" -TerminalIcons $true
    Test-WinToolExpectation -Condition ($prompt.Contains("oh-my-posh") -and $prompt.Contains("Terminal-Icons")) -Message "The Oh My Posh profile imports icons."
    $fonts = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())
    $nerd = @(Select-WinToolFont -Font $fonts -Query "fira" -NerdOnly $true)
    $plain = @(Select-WinToolFont -Font $fonts -Query "" -PlainOnly $true)
    Test-WinToolExpectation -Condition ($fonts.Count -ge 70 -and $nerd.Count -ge 1 -and $plain.Count -ge 1) -Message "The font catalog includes Nerd Fonts and plain programming fonts."
    $themes = @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @())
    Test-WinToolExpectation -Condition ($themes.Count -ge 100) -Message "The Oh My Posh gallery includes the official themes."
    $simple = Get-WinToolSimpleTerminalChoice
    $simplePlan = @(Get-WinToolTerminalPlan -Selection $simple)
    $simpleLabels = @($simplePlan | ForEach-Object { $_.Label }) -join " "
    Test-WinToolExpectation -Condition ($simpleLabels.Contains("Oh My Posh") -and $simpleLabels.Contains("PowerShell 7")) -Message "Simple mode installs the recommended prompt."
    $dark = Resolve-WinToolAppearance -Theme "dark" -Accent "teal" -SystemIsLight $true
    $light = Resolve-WinToolAppearance -Theme "system" -Accent "blue" -SystemIsLight $true
    Test-WinToolExpectation -Condition ($dark.Resolved -eq "dark" -and $dark.Brushes["BrushAccent"] -eq "#3DCEB5") -Message "Dark theme keeps the chosen accent."
    Test-WinToolExpectation -Condition ($light.Resolved -eq "light" -and $light.Brushes["BrushCanvas"] -eq "#F3F5F9") -Message "System theme follows a light Windows setting."
    $settingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-settings-" + [guid]::NewGuid().ToString() + ".json")
    try {
        Save-WinToolSetting -Setting ([pscustomobject]@{ theme = "system"; accent = "rose" }) -Path $settingsPath
        $loadedSetting = Read-WinToolSetting -Path $settingsPath
        Test-WinToolExpectation -Condition ($loadedSetting.theme -eq "system" -and $loadedSetting.accent -eq "rose") -Message "Appearance settings round-trip."
    }
    finally {
        Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Search and GPU vendor matching" -Body {
    Test-WinToolExpectation -Condition (Test-WinToolTextMatch -Haystack "Mozilla Firefox" -Query "fire") -Message "Search is case-insensitive."
    Test-WinToolExpectation -Condition (Test-WinToolTextMatch -Haystack "Firefox" -Query "   ") -Message "An empty search matches everything."
    Test-WinToolExpectation -Condition (-not (Test-WinToolTextMatch -Haystack "Firefox" -Query "steam")) -Message "Unrelated search text does not match."
    $vendors = @(Get-WinToolUpdateCatalog).vendors
    $nvidia = Resolve-WinToolGpuVendor -Name "NVIDIA GeForce RTX 4070" -Vendor $vendors
    $amd = Resolve-WinToolGpuVendor -Name "AMD Radeon Graphics" -Vendor $vendors
    $intel = Resolve-WinToolGpuVendor -Name "Intel(R) UHD Graphics" -Vendor $vendors
    Test-WinToolExpectation -Condition ($nvidia.id -eq "nvidia" -and $amd.id -eq "amd" -and $intel.id -eq "intel") -Message "GPU names map to the official vendor pages."
}

Invoke-WinToolCase -Name "winget update, uninstall, and installed detection" -Body {
    $upgrade = @(Get-WinToolWingetArgument -Id "Mozilla.Firefox" -Action "upgrade")
    Test-WinToolExpectation -Condition ($upgrade[0] -eq "upgrade" -and $upgrade -contains "--exact" -and $upgrade -contains "--accept-package-agreements") -Message "Update uses winget upgrade for one exact id."
    $remove = @(Get-WinToolWingetArgument -Id "Mozilla.Firefox" -Action "uninstall" -Scope "user")
    Test-WinToolExpectation -Condition ($remove[0] -eq "uninstall" -and -not ($remove -contains "--accept-package-agreements") -and -not ($remove -contains "--scope")) -Message "Uninstall uses only arguments winget uninstall accepts."
    $all = @(Get-WinToolWingetArgument -Action "upgrade-all")
    Test-WinToolExpectation -Condition ($all[0] -eq "upgrade" -and $all -contains "--all") -Message "Update all runs winget upgrade --all."
    $threw = $false
    try { $null = Get-WinToolWingetArgument -Id "" -Action "uninstall" } catch { $threw = $true }
    Test-WinToolExpectation -Condition $threw -Message "Uninstall without an id is refused."

    $known = @("Mozilla.Firefox", "Microsoft.VisualStudioCode", "Git.Git", "Valve.Steam")
    $table = @"
Name                     Id                            Version   Available Source
----------------------------------------------------------------------------------
Mozilla Firefox (x64 en) Mozilla.Firefox               120.0     121.0     winget
Visual Studio Code       Microsoft.VisualStudio$([char]0x2026) 1.84.0    1.85.0    winget
Something Else           Other.Package                 1.0       2.0       winget
2 upgrades available.
"@
    $found = @(Find-WinToolWingetIdInText -Text $table -KnownId $known)
    Test-WinToolExpectation -Condition ($found.Count -eq 2 -and $found -contains "Mozilla.Firefox" -and $found -contains "Microsoft.VisualStudioCode") -Message ("Update ids found in the winget table: " + ($found -join ", "))
    $state = Resolve-WinToolAppState -CatalogId $known -InstalledId @("git.git", "Unknown.App") -UpgradeText $table
    Test-WinToolExpectation -Condition ($state.Installed.ContainsKey("Git.Git") -and $state.Installed.ContainsKey("Mozilla.Firefox") -and -not $state.Installed.ContainsKey("Valve.Steam")) -Message "Installed apps come from the export and the update list, case-insensitively."
    Test-WinToolExpectation -Condition ($state.Updates.ContainsKey("Mozilla.Firefox") -and -not $state.Updates.ContainsKey("Git.Git")) -Message "Only listed apps show an update."
    $plan = @(Get-WinToolAppPlan -App @([pscustomobject]@{ name = "Git"; wingetId = "Git.Git" }) -Action "uninstall")
    Test-WinToolExpectation -Condition ($plan[0].Action -eq "uninstall" -and $plan[0].Label -eq "Uninstall Git") -Message "An uninstall plan is labelled for the log."
    $command = Get-WinToolPlanCommand -Step $plan[0]
    Test-WinToolExpectation -Condition (@($command.ArgumentList)[0] -eq "uninstall") -Message "The runner passes the uninstall action to winget."
    Test-WinToolExpectation -Condition ((Get-WinToolWingetOutcomeText -Action "upgrade" -Status "AlreadyInstalled") -eq "already up to date") -Message "An update with nothing new says up to date."
    $script = Get-WinToolAppDetectionScript
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
    Test-WinToolExpectation -Condition (@($errors).Count -eq 0 -and $script.Contains("export")) -Message "The detection script parses and uses winget export."
}

Invoke-WinToolCase -Name "Installed apps are read from a real winget export and list" -Body {
    $fixtures = Join-Path $PSScriptRoot "fixtures"
    $exportText = [System.IO.File]::ReadAllText((Join-Path $fixtures "winget-export.json"))
    $ids = @(ConvertFrom-WinToolWingetExport -Text $exportText)
    Test-WinToolExpectation -Condition ($ids.Count -eq 12 -and $ids -contains "7zip.7zip" -and $ids -contains "Microsoft.VisualStudio.Community") -Message ("The export fixture gives 12 ids, got " + $ids.Count)
    Test-WinToolExpectation -Condition (@(ConvertFrom-WinToolWingetExport -Text "").Count -eq 0) -Message "An empty export gives no ids."
    $listText = [System.IO.File]::ReadAllText((Join-Path $fixtures "winget-list-ptbr.txt"))

    $catalogIds = New-Object System.Collections.Generic.List[string]
    foreach ($category in @((Get-WinToolAppCatalog).categories)) {
        foreach ($app in @($category.apps)) { $catalogIds.Add([string]$app.wingetId) }
    }
    $state = Resolve-WinToolAppState -CatalogId $catalogIds.ToArray() -InstalledId $ids -ListText $listText -UpgradeText ""
    foreach ($id in @("7zip.7zip", "Git.Git", "Valve.Steam", "OBSProject.OBSStudio", "GitHub.cli", "Blizzard.BattleNet", "Google.GoogleDrive")) {
        Test-WinToolExpectation -Condition ($state.Installed.ContainsKey($id)) -Message "$id from the export should show as installed."
    }
    Test-WinToolExpectation -Condition ($state.Installed.ContainsKey("Google.Chrome")) -Message "An app only in winget list (pt-BR headers) still shows as installed."
    Test-WinToolExpectation -Condition ($state.Installed.ContainsKey("Microsoft.VisualStudioCode")) -Message "A shortened id in winget list is matched."
    Test-WinToolExpectation -Condition ($state.Updates.Count -eq 0) -Message "The list alone marks no updates."

    # Run the background detection script end to end with a stand-in winget.
    if (-not (Test-WinToolWindows) -and $null -ne (Get-Command -Name "bash" -ErrorAction SilentlyContinue)) {
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-fake-winget-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $fake = Join-Path $work "winget"
        $body = @"
#!/bin/bash
case "`$1" in
  --version) echo v1.29.380 ;;
  export) echo 'stderr noise' 1>&2; cp '$((Join-Path $fixtures "winget-export.json"))' "`$3" ;;
  list) cat '$((Join-Path $fixtures "winget-list-ptbr.txt"))' ;;
  upgrade) printf 'Name Id Version Available\n7-Zip 7zip.7zip 24.08 24.09\n' ;;
esac
"@
        [System.IO.File]::WriteAllText($fake, $body.Replace("`r`n", "`n"))
        & chmod +x $fake
        $missing = Join-Path $work "missing-winget"
        $job = Start-WinToolScriptJob -ScriptText (Get-WinToolAppDetectionScript) -Argument @(@($missing, $fake), (Join-Path $work "export.json"))
        $waited = 0
        while (-not $job.Sync.Done -and $waited -lt 300) {
            Start-Sleep -Milliseconds 100
            $waited++
        }
        $ok = [bool]$job.Sync.Ok
        $jobError = [string]$job.Sync.Error
        $found = @(ConvertFrom-WinToolWingetExport -Text ([string]$job.Sync.ExportText))
        $used = [string]$job.Sync.Winget
        $log = @($job.Sync.Log.ToArray())
        $upgrade = [string]$job.Sync.UpgradeText
        Stop-WinToolThread -Job $job
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        Test-WinToolExpectation -Condition $ok -Message ("The detection job failed: " + $jobError)
        Test-WinToolExpectation -Condition ($used -eq $fake) -Message "Detection skips a winget that does not start and uses the next one."
        Test-WinToolExpectation -Condition ($found.Count -eq 12) -Message "Detection returns the export even when winget writes to stderr."
        Test-WinToolExpectation -Condition ($upgrade.Contains("7zip.7zip")) -Message "Detection returns the upgrade table."
        Test-WinToolExpectation -Condition (($log -join "`n").Contains("did not start")) -Message "Detection logs the winget it could not start."
    }
}

Invoke-WinToolCase -Name "Ids with plus signs, dots, and brackets are matched literally" -Body {
    $known = @("Notepad++.Notepad++", "Microsoft.VCRedist.2015+.x64", "Test(1).App[x]", "Notepad.Notes", "Git.Git")
    $ellipsis = [string][char]0x2026
    $mojibake = [string][char]0x00D4 + [char]0x00C7 + [char]0x00AA
    $lines = @(
        "Notepad++ (x64)  Notepad++.Notepad++ 8.9.9.1 winget",
        ("Microsoft Visual C++ 2015-2022 Redistributable (x64)  Microsoft.VCRedist.2015+" + $ellipsis + " 14.40 winget"),
        "Bracket app  Test(1).App[x]  1.0 winget"
    )
    $found = @(Find-WinToolWingetIdInText -Text ($lines -join "`n") -KnownId $known)
    foreach ($id in @("Notepad++.Notepad++", "Microsoft.VCRedist.2015+.x64", "Test(1).App[x]")) {
        Test-WinToolExpectation -Condition ($found -contains $id) -Message "$id should be found as written. Found: $($found -join ', ')"
    }
    Test-WinToolExpectation -Condition (-not ($found -contains "Notepad.Notes")) -Message "Notepad++ must not match a similar id."
    foreach ($cut in @(("Notepad++.Notep" + $ellipsis), "Notepad++.Notep...", ("Notepad++.Notep" + $mojibake), "Notepad++.Notep?")) {
        $hit = @(Find-WinToolWingetIdInText -Text ("Notepad++ (x64)  " + $cut + "  8.9.9.1 winget") -KnownId $known)
        Test-WinToolExpectation -Condition ($hit.Count -eq 1 -and $hit[0] -eq "Notepad++.Notepad++") -Message "A shortened Notepad++ id ($cut) should still match. Got: $($hit -join ', ')"
    }
    $ambiguous = @(Find-WinToolWingetIdInText -Text ("Notepad  Notepad" + $ellipsis) -KnownId $known)
    Test-WinToolExpectation -Condition ($ambiguous.Count -eq 0) -Message "A short or shared prefix matches nothing."
    $plain = @(Find-WinToolWingetIdInText -Text "Notepad++ (x64) 8.9.9.1 Inc. (x64)" -KnownId $known)
    Test-WinToolExpectation -Condition ($plain.Count -eq 0) -Message "Names and versions are not taken for ids."

    $state = Resolve-WinToolAppState -CatalogId $known -InstalledId @("notepad++.notepad++") -UpgradeText "" -ListText ""
    Test-WinToolExpectation -Condition ($state.Installed.ContainsKey("Notepad++.Notepad++")) -Message "The export id for Notepad++ marks it installed."
    $export = '{"Sources":[{"Packages":[{"PackageIdentifier":"Notepad++.Notepad++"},{"PackageIdentifier":"Microsoft.VCRedist.2015+.x64"}]}]}'
    $exportIds = @(ConvertFrom-WinToolWingetExport -Text $export)
    Test-WinToolExpectation -Condition (($exportIds -join "|") -eq "Notepad++.Notepad++|Microsoft.VCRedist.2015+.x64") -Message "Export ids keep their plus signs."
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolAppNameKey -Text "Notepad++ (x64)") -eq (ConvertTo-WinToolAppNameKey -Text "Notepad++")) -Message "Notepad++ (x64) and Notepad++ have the same name key."
    $byName = @(Find-WinToolAppByName -DisplayName @("Notepad++ (64-bit x64)") -App @([pscustomobject]@{ Name = "Notepad++"; WingetId = "Notepad++.Notepad++"; DetectNames = @() }))
    Test-WinToolExpectation -Condition ($byName -contains "Notepad++.Notepad++") -Message "The Apps and features name of Notepad++ matches."
    Test-WinToolExpectation -Condition (Test-WinToolWingetId -Id "Notepad++.Notepad++") -Message "Notepad++.Notepad++ is a valid catalog id."
    $catalogIds = @((Get-WinToolAppCatalog).categories | ForEach-Object { $_.apps } | ForEach-Object { [string]$_.wingetId })
    Test-WinToolExpectation -Condition ($catalogIds -contains "Notepad++.Notepad++") -Message "The catalog lists Notepad++ with its winget id."
}

Invoke-WinToolCase -Name "Apps installed outside winget are found by name" -Body {
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolAppNameKey -Text "WinRAR 7.01 (64-bit)") -eq "winrar") -Message "Version and architecture words are dropped."
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolAppNameKey -Text "7-Zip 24.08 (x64)") -eq "7 zip") -Message "A leading number stays in the name."
    $names = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot "fixtures/installed-names.txt") -Encoding UTF8)
    $apps = New-Object System.Collections.Generic.List[object]
    foreach ($category in @((Get-WinToolAppCatalog).categories)) {
        foreach ($app in @($category.apps)) {
            $apps.Add([pscustomobject]@{ Name = [string]$app.name; WingetId = [string]$app.wingetId; DetectNames = @(Get-WinToolNote -Object $app -Name "detectNames" -Default @()) })
        }
    }
    $found = @(Find-WinToolAppByName -DisplayName $names -App $apps.ToArray())
    foreach ($id in @("Discord.Discord", "Telegram.TelegramDesktop", "Spotify.Spotify", "7zip.7zip", "vim.vim", "Microsoft.WindowsTerminal", "GitHub.GitHubDesktop", "RARLab.WinRAR")) {
        Test-WinToolExpectation -Condition ($found -contains $id) -Message "$id should be found by name. Found: $($found -join ', ')"
    }
    foreach ($id in @("Git.Git", "Zoom.Zoom", "Microsoft.Edge", "Python.Python.3.13")) {
        Test-WinToolExpectation -Condition (-not ($found -contains $id)) -Message "$id must not match a longer or different name."
    }
}

Invoke-WinToolCase -Name "Fixes run known programs and named scripts" -Body {
    $catalog = Get-WinToolFixCatalog
    $fixes = @{}
    foreach ($fix in @($catalog.fixes)) { $fixes[[string]$fix.id] = $fix }
    foreach ($id in @("windows-update-reset", "network-reset", "system-file-repair", "winget-repair")) {
        Test-WinToolExpectation -Condition ($fixes.ContainsKey($id)) -Message "Missing fix $id."
    }
    $network = @(Get-WinToolFixPlan -Fix $fixes["network-reset"])
    Test-WinToolExpectation -Condition ($network.Count -eq 4 -and $network[1].FilePath.EndsWith("\System32\netsh.exe") -and (@($network[1].Arguments) -join " ") -eq "winsock reset") -Message "Network reset runs netsh winsock reset."
    $repair = @(Get-WinToolFixPlan -Fix $fixes["system-file-repair"])
    Test-WinToolExpectation -Condition ($repair[0].FilePath.EndsWith("Dism.exe") -and $repair[1].FilePath.EndsWith("sfc.exe")) -Message "System repair runs DISM before SFC."
    foreach ($name in @(Get-WinToolFixScriptName)) {
        $text = Get-WinToolFixScript -Name $name
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "Fix script $name does not parse."
    }
    $update = @(Get-WinToolFixPlan -Fix $fixes["windows-update-reset"])
    $command = Get-WinToolPlanCommand -Step $update[0]
    Test-WinToolExpectation -Condition ($command.FilePath.EndsWith("powershell.exe") -and (@($command.ArgumentList) -contains "-File")) -Message "A fix script runs in Windows PowerShell."
    Remove-Item -LiteralPath @($command.ArgumentList)[-1] -Force -ErrorAction SilentlyContinue
    $bad = New-Object System.Collections.Generic.List[string]
    $badCatalog = [pscustomobject]@{ schemaVersion = 1; fixes = @([pscustomobject]@{ id = "x"; name = "X"; description = "d"; steps = @([pscustomobject]@{ type = "process"; file = "..\evil.exe" }, [pscustomobject]@{ type = "script"; script = "rm-rf" }) }) }
    Test-WinToolFixCatalog -Catalog $badCatalog -Errors $bad
    Test-WinToolExpectation -Condition ($bad.Count -ge 3) -Message "The fix catalog rejects outside programs and unknown scripts."
}

Invoke-WinToolCase -Name "Update modes set policies and revert to default" -Body {
    $catalog = Get-WinToolUpdateCatalog
    $ids = @(Get-WinToolUpdateMode -Catalog $catalog | ForEach-Object { [string]$_.id })
    Test-WinToolExpectation -Condition (($ids -join ",") -eq "default,security,disabled") -Message "Update modes should be Default, Security only, and Disabled."
    $managed = @(Get-WinToolManagedUpdatePolicy -Catalog $catalog)
    $security = Get-WinToolUpdateModeChange -ModeId "security" -Catalog $catalog
    $setNames = @($security.Set | ForEach-Object { $_.name })
    Test-WinToolExpectation -Condition (($setNames -contains "DeferFeatureUpdates") -and ($setNames -contains "DeferFeatureUpdatesPeriodInDays")) -Message "Security only defers feature updates."
    Test-WinToolExpectation -Condition (-not ($setNames -contains "NoAutoUpdate")) -Message "Security only keeps updates on."
    Test-WinToolExpectation -Condition (@($security.Remove).Count -eq $managed.Count) -Message "Every mode clears all managed policies first."
    $default = Get-WinToolUpdateModeChange -ModeId "default" -Catalog $catalog
    Test-WinToolExpectation -Condition (@($default.Set).Count -eq 0 -and @($default.Remove).Count -eq $managed.Count) -Message "Default removes every policy WinTool sets."
    $wu = @($default.Services | Where-Object { $_.name -eq "wuauserv" })[0]
    Test-WinToolExpectation -Condition ($wu.startupType -eq "Manual" -and -not $wu.stop) -Message "Default turns the update service back on."
    $disabled = Get-WinToolUpdateModeChange -ModeId "disabled" -Catalog $catalog
    Test-WinToolExpectation -Condition (@($disabled.Services | Where-Object { $_.startupType -eq "Disabled" -and $_.stop }).Count -eq 2) -Message "Disabled stops and disables both update services."
    foreach ($id in $ids) {
        $text = Get-WinToolUpdateModeScript -ModeId $id -Catalog $catalog
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
        Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "The $id mode script does not parse."
    }
    $plan = @(Get-WinToolUpdateModePlan -ModeId "security" -Catalog $catalog)
    $command = Get-WinToolPlanCommand -Step $plan[0]
    Test-WinToolExpectation -Condition ($command.FilePath.EndsWith("powershell.exe") -and (@($command.ArgumentList) -contains "-File")) -Message "The update mode runs in Windows PowerShell."
    $written = Get-Content -LiteralPath @($command.ArgumentList)[-1] -Raw
    Remove-Item -LiteralPath @($command.ArgumentList)[-1] -Force -ErrorAction SilentlyContinue
    Test-WinToolExpectation -Condition ($written.Contains("DeferFeatureUpdatesPeriodInDays")) -Message "The written script carries the mode settings."

    $root = "hklm:\software\policies\microsoft\windows\windowsupdate"
    Test-WinToolExpectation -Condition ((Resolve-WinToolUpdateMode -Catalog $catalog) -eq "default") -Message "No policies means Default."
    $values = @{}
    foreach ($item in @($security.Set)) { $values[(Get-WinToolUpdatePolicyKey -Policy $item)] = $item.value }
    Test-WinToolExpectation -Condition ((Resolve-WinToolUpdateMode -Values $values -Catalog $catalog) -eq "security") -Message "Security policies are detected."
    $values[$root + "\au|noautoupdate"] = 1
    Test-WinToolExpectation -Condition ((Resolve-WinToolUpdateMode -Values $values -Catalog $catalog) -eq "custom") -Message "Mixed policies show as custom."
    $off = @{ ($root + "\au|noautoupdate") = 1 }
    Test-WinToolExpectation -Condition ((Resolve-WinToolUpdateMode -Values $off -Services @{ wuauserv = "Disabled" } -Catalog $catalog) -eq "disabled") -Message "Disabled is detected."
    Test-WinToolExpectation -Condition ((Resolve-WinToolUpdateMode -Services @{ wuauserv = "Disabled" } -Catalog $catalog) -eq "custom") -Message "A disabled service without policies is custom."

    $bad = New-Object System.Collections.Generic.List[string]
    $badCatalog = [pscustomobject]@{ modes = @([pscustomobject]@{ id = "x"; name = "X"; description = "d"; policies = @([pscustomobject]@{ path = "HKLM:\SOFTWARE\Evil"; name = "A"; value = 1 }); services = @([pscustomobject]@{ name = "wuauserv"; startupType = "Sometimes" }) }) }
    Test-WinToolUpdateModeCatalog -Catalog $badCatalog -Errors $bad
    Test-WinToolExpectation -Condition ($bad.Count -ge 3) -Message "The update mode catalog rejects outside keys, bad startup types, and a missing default."
}

Invoke-WinToolCase -Name "DNS picker and Ultimate Performance plan" -Body {
    $catalog = Get-WinToolSystemCatalog
    $ids = @(Get-WinToolDnsProvider -Catalog $catalog | ForEach-Object { [string]$_.id })
    Test-WinToolExpectation -Condition (($ids -join ",") -eq "dhcp,cloudflare,google,quad9,adguard") -Message "DNS choices should be Automatic, Cloudflare, Google, Quad9, and AdGuard."
    $cloudflare = Find-WinToolDnsProvider -Id "cloudflare" -Catalog $catalog
    Test-WinToolExpectation -Condition ((@(Get-WinToolDnsServerList -Provider $cloudflare -IncludeIpv6 $true) -join ",") -eq "1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001") -Message "Cloudflare lists IPv4 then IPv6."
    Test-WinToolExpectation -Condition (@(Get-WinToolDnsServerList -Provider $cloudflare -IncludeIpv6 $false).Count -eq 2) -Message "IPv6 can be left out."
    $adapters = @([pscustomobject]@{ Index = 12; Name = "Ethernet"; Description = "NIC"; Servers = @("9.9.9.9", "2620:fe::fe") }, [pscustomobject]@{ Index = 7; Name = "Wi-Fi"; Description = "WLAN"; Servers = @("192.168.0.1") })
    Test-WinToolExpectation -Condition ((Resolve-WinToolDnsProvider -Server $adapters[0].Servers -Catalog $catalog).id -eq "quad9") -Message "Quad9 servers are recognized."
    Test-WinToolExpectation -Condition ($null -eq (Resolve-WinToolDnsProvider -Server $adapters[1].Servers -Catalog $catalog)) -Message "A router DNS is not named as a provider."
    Test-WinToolExpectation -Condition ((Format-WinToolDnsSummary -Adapter $adapters[0] -Catalog $catalog).EndsWith("(Quad9)")) -Message "The summary names the provider."
    $plan = @(Get-WinToolDnsPlan -Adapter $adapters -Provider $cloudflare -IncludeIpv6 $true)
    $text = [string]$plan[0].Text
    Test-WinToolExpectation -Condition ($text.Contains("@(12, 7)") -and $text.Contains("'2606:4700:4700::1111'") -and $text.Contains("Clear-DnsClientCache")) -Message "The DNS script targets the picked adapters."
    $dhcp = @(Get-WinToolDnsPlan -Adapter $adapters[1] -Provider (Find-WinToolDnsProvider -Id "dhcp" -Catalog $catalog))
    Test-WinToolExpectation -Condition ($dhcp[0].Text.Contains('$servers = @()') -and $dhcp[0].Text.Contains("-ResetServerAddresses")) -Message "Automatic resets the adapter DNS."
    $list = @"
Existing Power Schemes (* Active)
-----------------------------------
Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)
GUID do esquema de energia: 9358CB16-9734-43cb-9301-0fdff2f45345  (Desempenho Maximo) *
"@
    $schemes = @(ConvertFrom-WinToolPowerList -Text $list)
    Test-WinToolExpectation -Condition ($schemes.Count -eq 2 -and $schemes[1].Active -and -not $schemes[0].Active) -Message "powercfg output is read in any language."
    $state = Get-WinToolPowerPlanState -Scheme $schemes -Catalog $catalog
    Test-WinToolExpectation -Condition ($state.Added -and $state.Active -and -not $state.BuiltIn) -Message "The WinTool copy of the plan is found."
    Test-WinToolExpectation -Condition ((Format-WinToolPowerPlanStatus -State (Get-WinToolPowerPlanState -Scheme @($schemes[0]) -Catalog $catalog)) -eq "Ultimate Performance is not on this PC.") -Message "A missing plan is reported."
    foreach ($action in @("add", "remove")) {
        $script = [string]@(Get-WinToolPowerPlanPlan -Action $action -Catalog $catalog)[0].Text
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
        Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "The power plan $action script does not parse."
    }
    $add = [string]@(Get-WinToolPowerPlanPlan -Action "add" -Catalog $catalog)[0].Text
    Test-WinToolExpectation -Condition ($add.Contains("-duplicatescheme `$base `$copy") -and $add.Contains("e9a42b02-d5df-448d-aa00-03f14749eb61")) -Message "Adding copies the Ultimate Performance scheme to a fixed GUID."
    $remove = [string]@(Get-WinToolPowerPlanPlan -Action "remove" -Catalog $catalog)[0].Text
    Test-WinToolExpectation -Condition ($remove.Contains("-delete `$copy") -and -not $remove.Contains("-delete `$base")) -Message "Removing deletes only the WinTool copy."
    $parse = Get-WinToolDnsScript -InterfaceIndex @(3) -Provider $cloudflare
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($parse, [ref]$tokens, [ref]$errors)
    Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "The DNS script does not parse."
    $bad = New-Object System.Collections.Generic.List[string]
    $badCatalog = [pscustomobject]@{ schemaVersion = 1; dns = @([pscustomobject]@{ id = "x"; ipv4 = @("1.1.1.1; evil"); ipv6 = @("8.8.8.8") }); powerPlan = [pscustomobject]@{ baseGuid = "nope"; copyGuid = "x"; fallbackGuid = "y" } }
    Test-WinToolSystemCatalog -Catalog $badCatalog -Errors $bad
    Test-WinToolExpectation -Condition ($bad.Count -ge 6) -Message "The system catalog rejects bad addresses, GUIDs, and a missing Automatic choice."
}

Invoke-WinToolCase -Name "Windows features read state and plan DISM changes" -Body {
    $catalog = Get-WinToolFeatureCatalog
    $byId = @{}
    foreach ($feature in @($catalog.features)) { $byId[[string]$feature.id] = $feature }
    foreach ($id in @("hyper-v", "sandbox", "wsl", "vm-platform", "netfx3")) {
        Test-WinToolExpectation -Condition ($byId.ContainsKey($id)) -Message "Missing Windows feature $id."
    }
    $nfs = $byId["nfs-client"]
    $state = @{ "ServicesForNFS-ClientOnly" = "Enabled"; "ClientForNFS-Infrastructure" = "Disabled"; "NetFx3" = "Enabled"; "TelnetClient" = "Missing" }
    Test-WinToolExpectation -Condition ((Get-WinToolFeatureStatus -Feature $nfs -State $state) -eq "Partial") -Message "A half-enabled feature reads as partly on."
    Test-WinToolExpectation -Condition ((Get-WinToolFeatureStatus -Feature $byId["netfx3"] -State $state) -eq "On") -Message "An enabled feature reads as on."
    Test-WinToolExpectation -Condition ((Get-WinToolFeatureStatus -Feature $byId["telnet"] -State $state) -eq "Unavailable") -Message "A missing feature reads as unavailable."
    Test-WinToolExpectation -Condition ((Get-WinToolFeatureStatus -Feature $byId["tftp"] -State $state) -eq "Unavailable") -Message "A feature with no state reads as unavailable."
    $plan = @(Get-WinToolFeaturePlan -Enable @($byId["wsl"]) -Disable @($nfs))
    Test-WinToolExpectation -Condition ($plan.Count -eq 3) -Message "One enable and a two-part disable make three steps."
    Test-WinToolExpectation -Condition ((@($plan[0].Arguments) -join " ") -eq "/Online /Enable-Feature /FeatureName:Microsoft-Windows-Subsystem-Linux /All /NoRestart") -Message "Enable uses DISM with /All and /NoRestart."
    Test-WinToolExpectation -Condition ((@($plan[1].Arguments) -join " ") -eq "/Online /Disable-Feature /FeatureName:ClientForNFS-Infrastructure /NoRestart") -Message "Disable turns off the dependent part first."
    Test-WinToolExpectation -Condition ((Test-WinToolStepSuccess -Step $plan[0] -ExitCode 3010) -and -not (Test-WinToolStepSuccess -Step $plan[0] -ExitCode 1)) -Message "DISM's restart-needed code counts as success."
    Test-WinToolExpectation -Condition (-not (Test-WinToolStepSuccess -Step ([pscustomobject]@{ Type = "process" }) -ExitCode 3010)) -Message "Other steps succeed only with exit code 0."
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput((Get-WinToolFeatureStateScript), [ref]$tokens, [ref]$errors)
    Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "The feature state script parses."
}

Invoke-WinToolCase -Name "Catalogs are large enough and every tweak has an undo" -Body {
    $apps = Get-WinToolAppCatalog
    $appCount = 0
    $wingetIds = @{}
    foreach ($category in @($apps.categories)) {
        foreach ($app in @($category.apps)) {
            $appCount++
            $key = ([string]$app.wingetId).ToLowerInvariant()
            Test-WinToolExpectation -Condition (-not $wingetIds.ContainsKey($key)) -Message ("winget id listed twice: " + [string]$app.wingetId)
            $wingetIds[$key] = $true
        }
    }
    Test-WinToolExpectation -Condition ($appCount -ge 150) -Message "The app catalog should list at least 150 apps (has $appCount)."
    $tweaks = @((Get-WinToolTweakCatalog).tweaks)
    Test-WinToolExpectation -Condition ($tweaks.Count -ge 50) -Message ("The tweak catalog should list at least 50 tweaks (has " + $tweaks.Count + ").")
    foreach ($tweak in $tweaks) {
        Test-WinToolExpectation -Condition ($null -ne (Get-WinToolNote -Object $tweak -Name "undo")) -Message ("Tweak " + [string]$tweak.id + " has no undo.")
        if ([string]$tweak.risk -eq "caution") {
            $presets = @(Get-WinToolNote -Object $tweak -Name "presets" -Default @())
            Test-WinToolExpectation -Condition (-not ($presets -contains "minimal")) -Message ("Caution tweak " + [string]$tweak.id + " is in the Minimal preset.")
        }
    }
}

Invoke-WinToolCase -Name "App plan uses the catalog winget id" -Body {
    $catalog = Get-WinToolAppCatalog
    $firefox = $null
    foreach ($category in @($catalog.categories)) {
        foreach ($app in @($category.apps)) {
            if ($app.id -eq "firefox") { $firefox = $app }
        }
    }
    $plan = @(Get-WinToolAppPlan -App @($firefox))
    Test-WinToolExpectation -Condition ($plan.Count -eq 1 -and $plan[0].WingetId -eq "Mozilla.Firefox" -and $plan[0].Label -eq "Install Firefox") -Message "The app plan installs Firefox by its winget id."
}

Invoke-WinToolCase -Name "Every script parses and the window names exist" -Body {
    $files = New-Object System.Collections.Generic.List[string]
    $files.Add((Join-Path $script:WinToolRoot "build/Build-WinTool.ps1"))
    $files.Add((Join-Path $script:WinToolRoot "build/Invoke-CI.ps1"))
    $files.Add((Join-Path $script:WinToolRoot "src/Start-WinTool.ps1"))
    $files.Add((Join-Path $script:WinToolRoot "tests/Invoke-WinToolTests.ps1"))
    foreach ($relative in [System.IO.File]::ReadAllLines((Join-Path $script:WinToolRoot "build/files.txt"))) {
        $trimmed = $relative.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) { continue }
        $files.Add((Join-Path $script:WinToolRoot ($trimmed -replace '\\', '/')))
    }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file)) {
            Test-WinToolExpectation -Condition $false -Message "Missing $file"
            continue
        }
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message ("Parse error in " + $file)
    }
    [xml]$xaml = Get-WinToolPayloadText -Name "Xaml"
    $names = New-Object System.Collections.Generic.List[string]
    $pattern = 'Get-WinToolUi -Name "([^"]+)"|FindName\("([^"]+)"\)'
    foreach ($file in $files) {
        if ($file -notlike "*.ps1" -or $file -like "*Invoke-WinToolTests.ps1") { continue }
        $text = [System.IO.File]::ReadAllText($file)
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $name = $match.Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $match.Groups[2].Value }
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains($name)) {
                $names.Add($name)
            }
        }
    }
    $xml = $xaml.OuterXml
    foreach ($name in $names) {
        Test-WinToolExpectation -Condition ($xml.Contains('x:Name="' + $name + '"')) -Message "XAML is missing x:Name $name"
    }
}

Invoke-WinToolCase -Name "Startup errors include the location and a log" -Body {
    $record = $null
    try {
        throw "Argument types do not match"
    }
    catch {
        $record = $_
    }
    $text = Format-WinToolErrorText -ErrorRecord $record
    Test-WinToolExpectation -Condition ($text.Contains("Argument types do not match")) -Message "The startup error keeps the exception message."
    Test-WinToolExpectation -Condition ($text.Contains("WinTool could not start.")) -Message "The startup error names WinTool."
    $log = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-log-" + [guid]::NewGuid().ToString() + ".log")
    try {
        $written = Write-WinToolFailureLog -Text $text -Path $log
        $saved = [System.IO.File]::ReadAllText($written)
        Test-WinToolExpectation -Condition ($saved.Contains("Argument types do not match") -and $saved.Contains("====")) -Message "The startup log file stores the error."
    }
    finally {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Elevation relaunches the entry script" -Body {
    $source = New-WinToolRelaunchScript -WorkingDirectory "C:\Users\Hinrikao\Desktop\WinTool" -EntryPath "C:\Users\Hinrikao\Desktop\WinTool\src\Start-WinTool.ps1" -ApplyProfile "" -Unattended $false -LaunchUrl ""
    Test-WinToolExpectation -Condition ($source.Contains("C:\Users\Hinrikao\Desktop\WinTool\src\Start-WinTool.ps1")) -Message "The relaunch runs Start-WinTool.ps1."
    Test-WinToolExpectation -Condition ($source.Contains("Set-Location -LiteralPath 'C:\Users\Hinrikao\Desktop\WinTool'")) -Message "The relaunch restores the working directory."
    Test-WinToolExpectation -Condition ($source.Contains('$env:WINTOOL_PAUSE_ON_ERROR = "1"')) -Message "The elevated window stays open after an error."
    Test-WinToolExpectation -Condition ($source.Contains('Join-Path $env:TEMP "WinTool"')) -Message "The relaunch writes %TEMP%\WinTool\wintool.log."
    Test-WinToolExpectation -Condition (-not $source.Contains("Elevation.ps1")) -Message "The relaunch does not run a dot-sourced helper file."
    $quoted = New-WinToolRelaunchScript -WorkingDirectory "C:\O'Brien" -EntryPath "C:\O'Brien\WinTool.ps1" -ApplyProfile "C:\O'Brien\my profile.json" -Unattended $true -LaunchUrl ""
    Test-WinToolExpectation -Condition ($quoted.Contains("'C:\O''Brien\WinTool.ps1'") -and $quoted.Contains("-Unattended") -and $quoted.Contains("-ApplyProfile")) -Message "Paths with quotes and profile arguments are escaped."
    $downloaded = New-WinToolRelaunchScript -WorkingDirectory "C:\Users\Hinrikao" -EntryPath "" -ApplyProfile "" -Unattended $false -LaunchUrl "https://raw.githubusercontent.com/Hinrikao/WinTool/main/wintool.ps1"
    Test-WinToolExpectation -Condition ($downloaded.Contains("Invoke-RestMethod") -and $downloaded.Contains("https://raw.githubusercontent.com/Hinrikao/WinTool/main/wintool.ps1")) -Message "A piped launch relaunches by downloading the published script."
    $hostArguments = @(Get-WinToolHostArgument -LauncherPath "C:\Users\Hinrikao\AppData\Local\Temp\WinTool\relaunch.ps1")
    $hostLine = ConvertTo-WinToolArgumentLine -ArgumentList $hostArguments
    Test-WinToolExpectation -Condition ($hostLine.StartsWith("-STA -NoProfile -ExecutionPolicy Bypass -File ")) -Message "The new PowerShell process is STA and bypasses execution policy."
    $hiddenLine = ConvertTo-WinToolArgumentLine -ArgumentList @(Get-WinToolHostArgument -LauncherPath "C:\Temp\relaunch.ps1" -Hidden $true)
    Test-WinToolExpectation -Condition ($hiddenLine.StartsWith("-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ")) -Message "A hidden relaunch asks PowerShell for a hidden window."
    $hiddenScript = New-WinToolRelaunchScript -WorkingDirectory "C:\Temp" -EntryPath "C:\Temp\wintool.ps1" -ApplyProfile "" -Unattended $false -LaunchUrl "" -Hidden $true -ShowConsole $false
    Test-WinToolExpectation -Condition ($hiddenScript.Contains('$env:WINTOOL_HIDDEN = "1"') -and $hiddenScript.Contains("ShowWindow")) -Message "A hidden relaunch marks itself and shows the console again on an error."
    $hiddenTokens = $null
    $hiddenErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($hiddenScript, [ref]$hiddenTokens, [ref]$hiddenErrors)
    Test-WinToolExpectation -Condition (@($hiddenErrors).Count -eq 0) -Message "The hidden relaunch script parses."
    $debugScript = New-WinToolRelaunchScript -WorkingDirectory "C:\Temp" -EntryPath "C:\Temp\wintool.ps1" -ApplyProfile "" -Unattended $false -LaunchUrl "" -Hidden $false -ShowConsole $true
    Test-WinToolExpectation -Condition ($debugScript.Contains("-ShowConsole") -and $debugScript.Contains('$env:WINTOOL_SHOW_CONSOLE = "1"') -and -not $debugScript.Contains('$env:WINTOOL_HIDDEN = "1"')) -Message "-ShowConsole survives the relaunch and keeps the console visible."
    $preferred = Resolve-WinToolEntryPath -EntryPath "C:\repo\src\Start-WinTool.ps1" -CommandPath "C:\repo\src\Private\Elevation.ps1"
    Test-WinToolExpectation -Condition ($preferred -eq "C:\repo\src\Start-WinTool.ps1") -Message "The saved entry path wins over the helper file path."
}

Invoke-WinToolCase -Name "The console hides unless asked to stay" -Body {
    Test-WinToolExpectation -Condition ((Get-WinToolConsoleMode -ShowConsole $false -Unattended $false -TerminalSession "" -HiddenChild "") -eq "hide") -Message "A classic console is hidden behind the window."
    Test-WinToolExpectation -Condition ((Get-WinToolConsoleMode -ShowConsole $true -Unattended $false -TerminalSession "" -HiddenChild "") -eq "show") -Message "-ShowConsole keeps the console."
    Test-WinToolExpectation -Condition ((Get-WinToolConsoleMode -ShowConsole $false -Unattended $true -TerminalSession "abc" -HiddenChild "") -eq "show") -Message "Unattended mode keeps the console."
    Test-WinToolExpectation -Condition ((Get-WinToolConsoleMode -ShowConsole $false -Unattended $false -TerminalSession "abc" -HiddenChild "") -eq "relaunch") -Message "Windows Terminal starts WinTool in its own hidden console."
    Test-WinToolExpectation -Condition ((Get-WinToolConsoleMode -ShowConsole $false -Unattended $false -TerminalSession "abc" -HiddenChild "1") -eq "hide") -Message "The hidden relaunch does not relaunch again."
    $script:WinToolShowConsole = $false
    $saved = $env:WINTOOL_SHOW_CONSOLE
    try {
        $env:WINTOOL_SHOW_CONSOLE = "1"
        Test-WinToolExpectation -Condition (Test-WinToolShowConsole) -Message "WINTOOL_SHOW_CONSOLE=1 keeps the console."
    }
    finally {
        $env:WINTOOL_SHOW_CONSOLE = $saved
    }
    $source = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Start-WinTool.ps1"))
    Test-WinToolExpectation -Condition ($source.Contains('[switch]$ShowConsole')) -Message "Start-WinTool.ps1 accepts -ShowConsole."
    $entry = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Entry.ps1"))
    $hideAt = $entry.IndexOf("Hide-WinToolConsole")
    $showAt = $entry.IndexOf("Show-WinToolWindow")
    Test-WinToolExpectation -Condition ($hideAt -gt 0 -and $hideAt -lt $showAt) -Message "The console hides before the window is built."
    $launcher = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "wintool.ps1"))
    Test-WinToolExpectation -Condition ($launcher.Contains('[switch]$ShowConsole')) -Message "wintool.ps1 accepts -ShowConsole."
}

Invoke-WinToolCase -Name "UI collection adds do not leak indexes" -Body {
    $roots = @(
        (Join-Path $script:WinToolRoot "src"),
        (Join-Path $script:WinToolRoot "build"),
        (Join-Path $script:WinToolRoot "tests")
    )
    $pattern = '\.(Children|Items)\.Add\('
    foreach ($rootPath in $roots) {
        foreach ($file in (Get-ChildItem -LiteralPath $rootPath -Recurse -Filter *.ps1)) {
            $lineNumber = 0
            foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
                $lineNumber++
                if ($line -notmatch $pattern) {
                    continue
                }
                $suppressed = $line -match '\[void\]' -or $line -match '\$null\s*=' -or $line -match '\|\s*Out-Null'
                Test-WinToolExpectation -Condition $suppressed -Message ("Uncaptured collection Add in " + $file.Name + ":" + $lineNumber)
            }
        }
    }
}

Invoke-WinToolCase -Name "UI events reach WinTool state and survive errors" -Body {
    . (Join-Path $script:WinToolRoot "src/UI/Factory.ps1")
    if ($null -eq ("WinToolTestEventSource" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
public class WinToolTestEventSource
{
    public object Tag;
    public event EventHandler Fired;
    public void Raise() { if (Fired != null) { Fired(this, EventArgs.Empty); } }
}
"@
    }
    $script:WinToolUiQuiet = $true
    $script:WinToolUiErrors = $null
    $script:WinToolUiHandlers = $null
    $script:WinToolTerminalChoice = [pscustomobject]@{ prompt = "oh-my-posh"; schemeId = "wintool-night" }

    $card = New-Object WinToolTestEventSource
    Register-WinToolUiEvent -Control $card -EventName "Fired" -Name "Test: choose prompt" -Data "starship" -Action {
        param($source, $eventData, $promptId)
        $null = $eventData
        $script:WinToolTerminalChoice.prompt = $promptId
        $source.Tag = "seen"
    }
    $card.Raise()
    $uiErrors = Get-WinToolUiError
    Test-WinToolExpectation -Condition ($uiErrors.Count -eq 0) -Message ("A UI handler failed: " + (($uiErrors | ForEach-Object { $_.Message }) -join " | "))
    Test-WinToolExpectation -Condition ([string]$script:WinToolTerminalChoice.prompt -eq "starship") -Message "A UI handler could not update script state."
    Test-WinToolExpectation -Condition ([string]$card.Tag -eq "seen") -Message "A UI handler did not receive its sender."

    $broken = New-Object WinToolTestEventSource
    Register-WinToolUiEvent -Control $broken -EventName "Fired" -Name "Test: broken" -Action { throw "boom" }
    $broken.Raise()
    $uiErrors = Get-WinToolUiError
    Test-WinToolExpectation -Condition ($uiErrors.Count -eq 1 -and [string]$uiErrors[0].Name -eq "Test: broken") -Message "A failing UI handler was not caught and recorded."
    $script:WinToolUiErrors = $null
    $script:WinToolUiHandlers = $null
}

Invoke-WinToolCase -Name "UI handlers do not use closures or direct event adds" -Body {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $script:WinToolRoot "src/UI") -Filter *.ps1)
    $files += Get-Item -LiteralPath (Join-Path $script:WinToolRoot "src/Private/Theme.ps1")
    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
            $lineNumber++
            if ($line.TrimStart().StartsWith("#")) {
                continue
            }
            $bad = $line -match '\.GetNewClosure\(' -or $line -match '\.Add_[A-Za-z]+\('
            Test-WinToolExpectation -Condition (-not $bad) -Message ("Use Register-WinToolUiEvent in " + $file.Name + ":" + $lineNumber)
        }
    }
}

Invoke-WinToolCase -Name "Process output is queued without a runspace" -Body {
    $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $file = "/bin/sh"
    $arguments = @("-c", "echo one; echo two 1>&2")
    if (Test-WinToolWindows) {
        $file = Join-Path $env:SystemRoot "System32\cmd.exe"
        $arguments = @("/c", "echo one & echo two 1>&2")
    }
    $process = Start-WinToolAsyncProcess -FilePath $file -ArgumentList $arguments -LineQueue $queue
    $process.WaitForExit()
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($queue.Count -lt 2 -and [DateTime]::UtcNow -lt $deadline) {
        [System.Threading.Thread]::Sleep(50)
    }
    Test-WinToolExpectation -Condition ($queue.Count -eq 2) -Message ("Expected two queued output lines, got " + $queue.Count)
}

Invoke-WinToolCase -Name "The single-file build embeds the catalogs" -Body {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-build-" + [guid]::NewGuid().ToString() + ".ps1")
    try {
        & (Join-Path $script:WinToolRoot "build/Build-WinTool.ps1") -OutputPath $temp
        $built = [System.IO.File]::ReadAllText($temp)
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($temp, [ref]$tokens, [ref]$parseErrors)
        Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message "The built launcher does not parse."
        Test-WinToolExpectation -Condition ($built.Contains("Start-WinTool") -and $built.Contains("https://raw.githubusercontent.com/Hinrikao/WinTool/main/wintool.ps1")) -Message "The launcher keeps the published command and entry point."
        foreach ($pair in @{ Apps = "data/apps.json"; Tweaks = "data/tweaks.json"; Xaml = "assets/MainWindow.xaml"; Wsl = "data/wsl-setup.sh" }.GetEnumerator()) {
            $match = [regex]::Match($built, [regex]::Escape($pair.Key) + " = @'([\s\S]*?)'@")
            Test-WinToolExpectation -Condition $match.Success -Message ("Missing payload " + $pair.Key)
            if ($match.Success) {
                $clean = $match.Groups[1].Value -replace '\s', ''
                $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
                $source = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot $pair.Value)).Replace("`r`n", "`n").Replace("`r", "`n")
                Test-WinToolExpectation -Condition ($decoded -eq $source) -Message ("Payload drifted: " + $pair.Key)
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Every plan step type has a runner" -Body {
    # Builds plans from every tab and checks that each step is either run in
    # WinTool (local handler) or turns into a command, the same check the
    # window's runner and the unattended runner make.
    $savedTemp = $env:TEMP
    $savedRoot = $env:SystemRoot
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP = [System.IO.Path]::GetTempPath() }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) { $env:SystemRoot = $env:TEMP }
    try {
        $plans = New-Object System.Collections.Generic.List[object]
        $app = [pscustomobject]@{ name = "7-Zip"; wingetId = "7zip.7zip" }
        foreach ($action in @("install", "upgrade", "uninstall")) {
            $plans.Add(@{ Name = "apps $action"; Steps = @(Get-WinToolAppPlan -App @($app) -Action $action) })
        }
        $plans.Add(@{ Name = "upgrade all"; Steps = @(Get-WinToolUpgradeAllPlan) })
        foreach ($fix in @(Get-WinToolNote -Object (Get-WinToolFixCatalog) -Name "fixes" -Default @())) {
            $plans.Add(@{ Name = ("fix " + [string]$fix.id); Steps = @(Get-WinToolFixPlan -Fix $fix) })
        }
        $features = @(Get-WinToolNote -Object (Get-WinToolFeatureCatalog) -Name "features" -Default @())
        $plans.Add(@{ Name = "features"; Steps = @(Get-WinToolFeaturePlan -Enable $features -Disable $features) })
        foreach ($mode in @(Get-WinToolNote -Object (Get-WinToolUpdateCatalog) -Name "modes" -Default @())) {
            $plans.Add(@{ Name = ("update mode " + [string]$mode.id); Steps = @(Get-WinToolUpdateModePlan -ModeId ([string]$mode.id)) })
        }
        $system = Get-WinToolSystemCatalog
        $adapter = [pscustomobject]@{ Index = 3; Name = "Ethernet"; Description = "NIC"; Servers = @() }
        foreach ($provider in @(Get-WinToolDnsProvider -Catalog $system)) {
            $plans.Add(@{ Name = ("dns " + [string]$provider.id); Steps = @(Get-WinToolDnsPlan -Adapter $adapter -Provider $provider) })
        }
        foreach ($action in @("add", "remove")) {
            $plans.Add(@{ Name = "power $action"; Steps = @(Get-WinToolPowerPlanPlan -Action $action) })
        }
        $plans.Add(@{ Name = "config export"; Steps = @([pscustomobject]@{ Type = "process"; Label = "Export"; FilePath = "winget"; Arguments = @("export", "-o", "x.json") }) })
        $terminal = Get-WinToolTerminalCatalog
        $fonts = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())
        $fontPicks = @(
            @($fonts | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $_ -Name "asset" -Default "")) })[0],
            @($fonts | Where-Object { $null -ne (Get-WinToolNote -Object $_ -Name "github") })[0],
            @($fonts | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $_ -Name "wingetId" -Default "")) })[0]
        )
        $preset = @(Get-WinToolNote -Object $terminal -Name "starshipPresets" -Default @())[0]
        if ($preset -isnot [string]) { $preset = [string](Get-WinToolNote -Object $preset -Name "id" -Default "") }
        $scheme = [string]@(Get-WinToolNote -Object $terminal -Name "schemes" -Default @())[0].id
        foreach ($prompt in @(Get-WinToolNote -Object $terminal -Name "prompts" -Default @())) {
            foreach ($font in $fontPicks) {
                $selection = [pscustomobject]@{ prompt = [string]$prompt.id; promptStyle = $preset; fontId = [string]$font.id; schemeId = $scheme; terminalIcons = $true; psReadLine = $true; zoxide = $true; fzf = $true; wsl = $true; zsh = $true }
                $plans.Add(@{ Name = ("terminal " + [string]$prompt.id + " " + [string]$font.id); Steps = @(Get-WinToolTerminalPlan -Selection $selection) })
            }
        }
        $seen = @{}
        foreach ($plan in $plans) {
            foreach ($step in @($plan.Steps)) {
                $type = [string]$step.Type
                $seen[$type] = $true
                if (Test-WinToolLocalStepType -Type $type) {
                    $handler = [string]$script:WinToolLocalStepHandlers[$type]
                    Test-WinToolExpectation -Condition ($null -ne (Get-Command -Name $handler -ErrorAction SilentlyContinue)) -Message ("Local step '" + $type + "' has no handler.")
                    continue
                }
                $command = $null
                try {
                    $command = Get-WinToolPlanCommand -Step $step
                }
                catch {
                    Test-WinToolExpectation -Condition $false -Message ("Step '" + $type + "' from " + $plan.Name + " failed: " + $_.Exception.Message)
                    continue
                }
                Test-WinToolExpectation -Condition ($null -ne $command) -Message ("Step '" + $type + "' from " + $plan.Name + " has no command.")
            }
        }
        foreach ($type in @("winget", "process", "module", "fix-script", "inline-script", "wsl-install", "font-download", "tool-download", "wsl-shell", "font", "profile", "scheme", "starship-preset", "wsl-profile")) {
            Test-WinToolExpectation -Condition ($seen.ContainsKey($type)) -Message ("No plan produced step type '" + $type + "', so the coverage check is incomplete.")
        }
        Test-WinToolExpectation -Condition (Test-WinToolLocalStepType -Type "scheme") -Message "The color scheme step runs inside WinTool."
        $threw = $false
        try { Get-WinToolPlanCommand -Step ([pscustomobject]@{ Type = "no-such-step" }) | Out-Null } catch { $threw = $true }
        Test-WinToolExpectation -Condition $threw -Message "An unknown step type is still an error."

        $tweakDefinition = (Get-Command -Name Invoke-WinToolTweakStep).Definition
        $tweakTypes = @{}
        foreach ($tweak in @(Get-WinToolNote -Object (Get-WinToolTweakCatalog) -Name "tweaks" -Default @())) {
            foreach ($direction in @("Apply", "Undo")) {
                foreach ($step in @(Get-WinToolTweakStep -Tweak $tweak -Direction $direction)) {
                    $tweakTypes[[string]$step.Type] = $true
                }
            }
        }
        foreach ($type in $tweakTypes.Keys) {
            Test-WinToolExpectation -Condition ($tweakDefinition.Contains('"' + $type + '"')) -Message ("Tweak step '" + $type + "' has no handler.")
        }
        Test-WinToolExpectation -Condition ($tweakTypes.Count -ge 4) -Message "The tweak catalog produced too few step types."
    }
    finally {
        $env:TEMP = $savedTemp
        $env:SystemRoot = $savedRoot
    }
}

Invoke-WinToolCase -Name "Font sources and the installed-font check" -Body {
    $fonts = @(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())
    $checked = @("SourceFoundry.HackFonts")
    foreach ($font in $fonts) {
        $wingetId = [string](Get-WinToolNote -Object $font -Name "wingetId" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($wingetId)) {
            Test-WinToolExpectation -Condition ($checked -contains $wingetId) -Message ("Font winget id " + $wingetId + " was not checked against winget-pkgs.")
        }
        if ([string](Get-WinToolNote -Object $font -Name "source" -Default "") -eq "nerd-fonts") {
            Test-WinToolExpectation -Condition ([string]$font.asset -match '^[A-Za-z0-9-]+\.zip$') -Message ("Nerd Font " + [string]$font.id + " needs a release zip.")
        }
    }
    $cascadia = @($fonts | Where-Object { [string]$_.id -eq "cascadia-code" })[0]
    $steps = @(Get-WinToolFontInstallStep -Font $cascadia)
    Test-WinToolExpectation -Condition ($steps.Count -eq 1 -and $steps[0].Type -eq "font-download" -and $steps[0].Repo -eq "microsoft/cascadia-code") -Message "Cascadia Code downloads from its GitHub release."
    $nerdFont = @($fonts | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $_ -Name "asset" -Default "")) })[0]
    $nerdStep = @(Get-WinToolFontInstallStep -Font $nerdFont)[0]
    Test-WinToolExpectation -Condition ($nerdStep.Type -eq "font-download" -and $nerdStep.Release -eq "v3.5.1") -Message "Nerd Fonts download from the pinned release."
    foreach ($step in @($steps[0], $nerdStep)) {
        $script = Get-WinToolFontDownloadScript -Step $step
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$parseErrors)
        Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message "The font download script parses."
    }
    $entries = @(
        [pscustomobject]@{ Name = "CaskaydiaCoveNerdFontPropo-Regular (TrueType)"; Data = "C:\f\CaskaydiaCoveNerdFontPropo-Regular.ttf" },
        [pscustomobject]@{ Name = "CaskaydiaCoveNerdFont-Bold (TrueType)"; Data = "C:\f\CaskaydiaCoveNerdFont-Bold.ttf" },
        [pscustomobject]@{ Name = "CaskaydiaCoveNerdFont-Regular (TrueType)"; Data = "C:\f\CaskaydiaCoveNerdFont-Regular.ttf" }
    )
    $found = Find-WinToolInstalledFontFile -Token "CaskaydiaCove Nerd Font" -Entry $entries
    Test-WinToolExpectation -Condition ($null -ne $found -and $found.Name -eq "CaskaydiaCoveNerdFont-Regular (TrueType)") -Message "The installed-font check prefers the regular file."
    Test-WinToolExpectation -Condition ($null -eq (Find-WinToolInstalledFontFile -Token "FiraCodeNerdFont" -Entry $entries)) -Message "A missing font is reported as missing."
}

Invoke-WinToolCase -Name "Color schemes carry all 16 colors" -Body {
    $schemes = @(Get-WinToolNote -Object (Get-WinToolTerminalCatalog) -Name "schemes" -Default @())
    Test-WinToolExpectation -Condition ($schemes.Count -ge 1) -Message "The Terminal catalog has color schemes."
    foreach ($scheme in $schemes) {
        $settings = ConvertFrom-WinToolJsonText -Text '{"profiles":{"defaults":{},"list":[]},"schemes":[{"name":"Campbell","background":"#0C0C0C"}]}'
        Add-WinToolTerminalScheme -Settings $settings -Scheme $scheme | Out-Null
        $written = ConvertFrom-WinToolJsonText -Text (ConvertTo-WinToolJsonText -Value $settings)
        $entry = @($written.schemes | Where-Object { [string]$_.name -eq [string]$written.profiles.defaults.colorScheme })
        Test-WinToolExpectation -Condition ($entry.Count -eq 1) -Message ("colorScheme " + [string]$scheme.name + " must name a scheme in schemes.")
        $colors = 0
        foreach ($key in $script:WinToolSchemeColorKeys) {
            if ([string](Get-WinToolNote -Object $entry[0] -Name $key -Default "") -match '^#[0-9A-Fa-f]{6}$') { $colors++ }
        }
        Test-WinToolExpectation -Condition ($colors -eq 16) -Message ("Scheme " + [string]$scheme.name + " has " + $colors + " of the 16 colors Windows Terminal requires.")
        Test-WinToolExpectation -Condition (@($written.schemes | Where-Object { [string]$_.name -eq "Campbell" }).Count -eq 1) -Message "Other schemes are kept."
    }
    $settings = ConvertFrom-WinToolJsonText -Text '{"profiles":{"defaults":{}}}'
    Add-WinToolTerminalScheme -Settings $settings -Scheme $schemes[0] | Out-Null
    Add-WinToolTerminalScheme -Settings $settings -Scheme $schemes[0] | Out-Null
    Test-WinToolExpectation -Condition (@($settings.schemes).Count -eq 1) -Message "Running the scheme step twice keeps one copy."
}

Invoke-WinToolCase -Name "Prompt preview follows the theme colors" -Body {
    $json = '{"palette":{"blue":"#3B78FF"},"blocks":[{"type":"prompt","alignment":"left","segments":[{"type":"session","style":"diamond","leading_diamond":"<","trailing_diamond":">","foreground":"#ffffff","background":"#c386f1"},{"type":"path","style":"powerline","powerline_symbol":"X","foreground":"#100e23","background":"p:blue"},{"type":"git","style":"powerline","powerline_symbol":"X","foreground":"#193549","background":"#95ffa4"},{"type":"text","style":"plain","foreground":"red","template":"{{ .Var }}"},{"type":"text","style":"plain","foreground":"#abc","template":" $ "}]},{"type":"prompt","alignment":"right","segments":[{"type":"time","style":"plain"}]}]}'
    $theme = ConvertFrom-WinToolJsonText -Text $json
    $segments = @(Get-WinToolOmpPreviewSegment -Theme $theme)
    $texts = ($segments | ForEach-Object { [string]$_.Text }) -join "|"
    Test-WinToolExpectation -Condition ($texts -eq "<| henrique |>| ~/src |X| main |X|$ ") -Message ("Unexpected preview segments: " + $texts)
    Test-WinToolExpectation -Condition ($segments[3].Background -eq "#3B78FF" -and $segments[3].Foreground -eq "#100E23") -Message "Palette colors are resolved."
    Test-WinToolExpectation -Condition ($segments[4].Foreground -eq "#3B78FF" -and $segments[4].Background -eq "#95FFA4") -Message "A powerline arrow takes the next segment background."
    Test-WinToolExpectation -Condition ($segments[6].Foreground -eq "#95FFA4" -and $null -eq $segments[6].Background) -Message "The last arrow ends on the terminal background."
    Test-WinToolExpectation -Condition ($segments[7].Foreground -eq "#AABBCC" -and $null -eq $segments[7].Background) -Message "Plain segments have no background."
}

Invoke-WinToolCase -Name "Every prompt has a preview" -Body {
    $catalog = Get-WinToolTerminalCatalog
    foreach ($prompt in @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @())) {
        $segments = @(Get-WinToolPromptPreview -PromptId ([string]$prompt.id) -PromptStyle "" -Theme $null)
        Test-WinToolExpectation -Condition ($segments.Count -gt 0) -Message ("No preview for " + [string]$prompt.id)
    }
    foreach ($preset in @(Get-WinToolNote -Object $catalog -Name "starshipPresets" -Default @())) {
        $segments = @(Get-WinToolPromptPreview -PromptId "starship" -PromptStyle ([string]$preset.id) -Theme $null)
        Test-WinToolExpectation -Condition ($segments.Count -gt 0 -and $null -ne $segments[0].Foreground) -Message ("No preview for the Starship preset " + [string]$preset.id)
    }
    $agnoster = @(Get-WinToolPromptPreview -PromptId "oh-my-zsh" -PromptStyle "agnoster" -Theme $null)
    Test-WinToolExpectation -Condition ($null -ne $agnoster[0].Background) -Message "agnoster has a powerline preview."
    Test-WinToolExpectation -Condition ((Get-WinToolOmpThemeFileName -ThemeId "atomic" -Themes @()) -eq "atomic.omp.json") -Message "Theme file names default to <id>.omp.json."
    Test-WinToolExpectation -Condition ($null -eq (ConvertTo-WinToolPreviewColor -Value "transparent" -Palette $null)) -Message "Unknown colors are ignored."
}

Invoke-WinToolCase -Name "Generated PowerShell profiles never throw" -Body {
    $catalog = Get-WinToolTerminalCatalog
    $hostPath = (Get-Process -Id $PID).Path
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-profile-" + [guid]::NewGuid().ToString("N") + ".ps1")
    try {
        foreach ($prompt in @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @())) {
            $text = Get-WinToolPromptScript -PromptId ([string]$prompt.id) -TerminalIcons $true -PromptStyle "jandedobbeleer" -PsReadLine $true -Zoxide $true
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
            Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message ("The " + [string]$prompt.id + " profile does not parse.")
            Test-WinToolExpectation -Condition (-not $text.Contains('Join-Path $env:POSH_THEMES_PATH')) -Message "The profile must not join a possibly missing POSH_THEMES_PATH."
            Test-WinToolExpectation -Condition ($text.Contains('ContainsKey("PredictionSource")') -and $text.Contains('ContainsKey("PredictionViewStyle")')) -Message "PSReadLine options are only set when the module has them."
            [System.IO.File]::WriteAllText($temp, $text)
            $command = 'Remove-Item Env:POSH_THEMES_PATH -ErrorAction Ignore; $Error.Clear(); . ''' + $temp + '''; foreach ($e in $Error) { "ERR: " + $e }; "WINTOOL-OK"'
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
            $output = & $hostPath -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
            $joined = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
            Test-WinToolExpectation -Condition ($joined.Contains("WINTOOL-OK") -and -not $joined.Contains("ERR:")) -Message ("The " + [string]$prompt.id + " profile wrote errors: " + $joined)
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "WSL shell setup for an existing distro" -Body {
    $plan = @(Get-WinToolWslShellPlan -Distro "Ubuntu")
    Test-WinToolExpectation -Condition ((@($plan | ForEach-Object { $_.Type }) -join ",") -eq "wsl-shell,wsl-profile") -Message "The WSL-only plan does not reinstall the distro."
    Test-WinToolExpectation -Condition ($plan[0].Distro -eq "Ubuntu" -and $plan[0].Variant -eq "oh-my-posh" -and $plan[0].PromptStyle -eq "jandedobbeleer") -Message "The WSL-only plan defaults to Oh My Posh in Ubuntu."
    $withInstall = @(Get-WinToolWslShellPlan -Distro "Ubuntu-24.04" -Install)
    Test-WinToolExpectation -Condition ($withInstall[0].Type -eq "wsl-install" -and $withInstall[0].Distro -eq "Ubuntu-24.04") -Message "-Install adds the install step for that distro."
    $threw = $false
    try { Get-WinToolWslDistroName -Step ([pscustomobject]@{ Distro = "Ubuntu; rm -rf" }) | Out-Null } catch { $threw = $true }
    Test-WinToolExpectation -Condition $threw -Message "Distro names are checked."

    $bash = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "oh-my-posh"; PromptStyle = "jandedobbeleer'`$(x)"; OmzTheme = "" })
    $lines = $bash -split "`n"
    Test-WinToolExpectation -Condition ($lines[0] -eq "#!/bin/bash" -and $lines[1] -eq "export WINTOOL_SHELL_PROMPT='oh-my-posh'" -and $lines[2] -eq "export WINTOOL_PROMPT_STYLE='jandedobbeleerx'") -Message "The setup script keeps its shebang and gets clean exports."
    Test-WinToolExpectation -Condition (-not $bash.Contains("`r") -and $bash.Contains("chsh -s") -and -not ($bash -match '(?m)^\s*sudo ')) -Message "The setup script uses LF, changes the shell as root, and needs no sudo."
    $bashCommand = Get-Command -Name bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $bashCommand -and -not (Test-WinToolWindows)) {
        $file = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-wsl-" + [guid]::NewGuid().ToString("N") + ".sh")
        [System.IO.File]::WriteAllText($file, $bash)
        & $bashCommand.Source -n $file
        Test-WinToolExpectation -Condition ($LASTEXITCODE -eq 0) -Message "bash -n rejects the WSL setup script."
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    foreach ($text in @((Get-WinToolWslInstallScript -Distro "Ubuntu"), (Get-WinToolWslShellScript -Distro "Ubuntu" -ScriptPath "C:\Temp\WinTool-wsl-setup.sh"))) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
        Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message "A WSL launcher script does not parse."
        Test-WinToolExpectation -Condition ($text.Contains("DistributionName")) -Message "WSL launchers look the distro up before using it."
    }
    $shell = Get-WinToolWslShellScript -Distro "Ubuntu" -ScriptPath "C:\Temp\x.sh"
    Test-WinToolExpectation -Condition ($shell.Contains('-u root --') -and $shell.Contains('WINTOOL_UID=')) -Message "The shell setup runs as root and passes the default uid."
    Test-WinToolExpectation -Condition ((Get-WinToolWslInstallScript -Distro "Ubuntu").Contains("kept as it is")) -Message "An existing distro is not reinstalled."

    $settings = ConvertFrom-WinToolJsonText -Text '{"profiles":{"defaults":{"font":{"face":"X"}},"list":[{"name":"Windows PowerShell"},{"name":"Ubuntu","source":"Microsoft.WSL","fontFace":"Consolas","font":{"size":11}},{"name":"Debian","source":"Windows.Terminal.Wsl"}]}}'
    $count = Set-WinToolWslProfileFont -Settings $settings -Distro "Ubuntu" -Face "CaskaydiaCove Nerd Font"
    $ubuntu = @($settings.profiles.list | Where-Object { $_.name -eq "Ubuntu" })[0]
    Test-WinToolExpectation -Condition ($count -eq 1 -and $ubuntu.font.face -eq "CaskaydiaCove Nerd Font" -and $ubuntu.font.size -eq 11 -and $null -eq $ubuntu.PSObject.Properties["fontFace"]) -Message "The Ubuntu profile gets the Nerd Font and keeps its size."
    Test-WinToolExpectation -Condition ($null -eq $settings.profiles.list[0].PSObject.Properties["font"] -and $null -eq $settings.profiles.list[2].PSObject.Properties["font"]) -Message "Other profiles are left alone."
}

if ($script:WinToolFailures.Count -gt 0) {
    Write-Output ""
    Write-Output ("{0} test(s) failed." -f $script:WinToolFailures.Count)
    exit 1
}

Write-Output ""
Write-Output "All WinTool tests passed."
exit 0
