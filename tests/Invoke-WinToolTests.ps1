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

Initialize-WinToolLocale -Language en -Force | Out-Null

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
    $palette = Get-WinToolPalette
    Test-WinToolExpectation -Condition ($palette["BrushCanvas"] -eq "#1B2230" -and $palette["BrushAccent"] -eq "#6C9BFF" -and $palette["BrushBad"] -eq "#F07178") -Message "The fixed dark palette carries the canvas, accent, and alert colors."
    $xamlText = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "assets/MainWindow.xaml"))
    Test-WinToolExpectation -Condition ($xamlText -notmatch 'x:Name="ThemePicker"' -and $xamlText -notmatch 'x:Name="AccentSwatches"') -Message "Sidebar appearance controls are removed from the window markup."
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
    Test-WinToolExpectation -Condition ($hiddenLine.StartsWith("-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ")) -Message "Get-WinToolHostArgument still accepts a hidden window style."
    $guiChild = New-WinToolGuiChildStartInfo -FileName "pwsh.exe" -Argument @(Get-WinToolHostArgument -LauncherPath "C:\Temp\relaunch.ps1" -Hidden $false)
    Test-WinToolExpectation -Condition ($guiChild.CreateNoWindow -eq $true -and $guiChild.UseShellExecute -eq $false) -Message "The GUI child starts with no window and without ShellExecute."
    Test-WinToolExpectation -Condition ($guiChild.ArgumentText -notlike "*-WindowStyle Hidden*") -Message "The GUI child command line does not use -WindowStyle Hidden."
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
    $pinned = "https://raw.githubusercontent.com/Hinrikao/WinTool/4d649686f452163812c3ff098149115f30cad3fa/wintool.ps1"
    $pinnedScript = New-WinToolRelaunchScript -WorkingDirectory "C:\Temp" -EntryPath "" -ApplyProfile "" -Unattended $false -LaunchUrl $pinned -Hidden $false -ShowConsole $false
    Test-WinToolExpectation -Condition ($pinnedScript.Contains('$env:WINTOOL_URL =') -and $pinnedScript.Contains($pinned) -and $pinnedScript.Contains("Invoke-RestMethod")) -Message "A piped relaunch keeps the pinned WINTOOL_URL."
    $elevateOption = Get-WinToolRelaunchHostOption -Elevate -ShowConsole $false -Unattended $false
    Test-WinToolExpectation -Condition ($elevateOption.WindowStyle -eq "Normal" -and $elevateOption.Hidden -eq $false) -Message "Elevation uses a visible window so the UAC prompt can appear."
    Test-WinToolExpectation -Condition ($elevateOption.HideConsole -eq $true) -Message "The elevated stub still hides the console after the UAC prompt."
    $elevateScript = New-WinToolRelaunchScript -WorkingDirectory "C:\Temp" -EntryPath "C:\Temp\wintool.ps1" -ApplyProfile "" -Unattended $false -LaunchUrl "" -Hidden $false -HideConsole $true -ShowConsole $false
    $hideAt = $elevateScript.IndexOf("ShowWindow")
    $runAt = $elevateScript.IndexOf("& 'C:\Temp\wintool.ps1'")
    Test-WinToolExpectation -Condition ($elevateScript.Contains('$env:WINTOOL_HIDDEN = "1"') -and $hideAt -ge 0 -and $runAt -gt $hideAt) -Message "The elevated stub hides the console before the launcher is parsed."
    $hiddenOption = Get-WinToolRelaunchHostOption -ShowConsole $false -Unattended $false
    Test-WinToolExpectation -Condition ($hiddenOption.Hidden -eq $true -and $hiddenOption.HideConsole -eq $true) -Message "A non-elevated relaunch still marks the child as a hidden owned host."
    $elevationSource = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/Elevation.ps1"))
    Test-WinToolExpectation -Condition ($elevationSource.Contains("Start-WinToolGuiChildProcess") -and $elevationSource.Contains("Get-WinToolPreferredGuiHostPath") -and $elevationSource.Contains("-Verb RunAs") -and $elevationSource.Contains('-WindowStyle $style') -and -not $elevationSource.Contains('-WindowStyle Hidden -Verb RunAs') -and -not $elevationSource.Contains('-Verb RunAs -WindowStyle Hidden')) -Message "The detached launch uses a no-window child and never hides the UAC prompt."
    $helperSource = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/ElevatedHelper.ps1"))
    Test-WinToolExpectation -Condition ($helperSource.Contains('System32\WindowsPowerShell\v1.0\powershell.exe') -and $helperSource.Contains('-Verb RunAs') -and $helperSource.Contains('-WindowStyle Normal') -and ($helperSource -notmatch 'Start-Process[^`r`n]*-WindowStyle Hidden')) -Message "The elevated helper stays on Windows PowerShell 5.1 and keeps the UAC prompt visible."
    $canceled = $null
    try { throw (New-Object System.ComponentModel.Win32Exception 1223) } catch { $canceled = Get-WinToolElevationFailureText -ErrorRecord $_ }
    Test-WinToolExpectation -Condition ($canceled.Contains("canceled") -and $canceled.Contains("administrator")) -Message "A canceled UAC prompt has a clear message."
    $failed = $null
    try { throw (New-Object System.ComponentModel.Win32Exception 5) } catch { $failed = Get-WinToolElevationFailureText -ErrorRecord $_ }
    Test-WinToolExpectation -Condition ($failed.Contains("could not request administrator approval") -and $failed.Contains("5")) -Message "A failed elevation request names the Windows error."
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
    $savedShow = $script:WinToolShowConsole
    $savedUnattended = $script:WinToolUnattended
    $savedRestore = $script:WinToolConsoleRestore
    $savedHiddenFlag = $env:WINTOOL_HIDDEN
    $savedShowFlag = $env:WINTOOL_SHOW_CONSOLE
    $savedTerminal = $env:WT_SESSION
    try {
        $script:WinToolShowConsole = $false
        $script:WinToolUnattended = $false
        $env:WINTOOL_SHOW_CONSOLE = $null
        $env:WT_SESSION = $null
        $env:WINTOOL_HIDDEN = $null
        $script:WinToolConsoleRestore = $false
        Test-WinToolExpectation -Condition (-not (Test-WinToolConsoleShouldRestore)) -Message "A console that started hidden is not shown on close."
        $script:WinToolConsoleRestore = $true
        Test-WinToolExpectation -Condition (Test-WinToolConsoleShouldRestore) -Message "A console the user could see is restored on close."
        $env:WINTOOL_HIDDEN = "1"
        Test-WinToolExpectation -Condition (-not (Test-WinToolConsoleShouldRestore)) -Message "A hidden relaunch does not show a console on close."
        $script:WinToolShowConsole = $true
        $env:WINTOOL_HIDDEN = $null
        Test-WinToolExpectation -Condition (-not (Test-WinToolConsoleShouldRestore)) -Message "-ShowConsole is left alone on close."
    }
    finally {
        $script:WinToolShowConsole = $savedShow
        $script:WinToolUnattended = $savedUnattended
        $script:WinToolConsoleRestore = $savedRestore
        $env:WINTOOL_HIDDEN = $savedHiddenFlag
        $env:WINTOOL_SHOW_CONSOLE = $savedShowFlag
        $env:WT_SESSION = $savedTerminal
    }
    $shell = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/UI/Shell.ps1"))
    Test-WinToolExpectation -Condition ($shell.Contains("Remove-WinToolHiddenConsole") -and $shell.Contains("WinToolShuttingDown")) -Message "Close detaches a hidden console and ignores queued UI work."
    Test-WinToolExpectation -Condition (-not $shell.Contains('if ($script:WinToolConsoleHidden)')) -Message "Close does not show the console just because it was hidden."
    $launcher = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "wintool.ps1"))
    Test-WinToolExpectation -Condition ($launcher.Contains('[switch]$ShowConsole')) -Message "wintool.ps1 accepts -ShowConsole."
}

Invoke-WinToolCase -Name "A normal launch detaches without UAC and opens a helper on demand" -Body {
    Test-WinToolExpectation -Condition (Test-WinToolShouldDetachHost -ShowConsole $false -Unattended $false -HiddenChild "") -Message "A normal terminal detaches so the prompt returns immediately."
    Test-WinToolExpectation -Condition (Test-WinToolShouldDetachHost -ShowConsole $false -Unattended $false -HiddenChild "" -and -not (Test-WinToolShouldDetachHost -ShowConsole $false -Unattended $false -HiddenChild "1")) -Message "A hidden child does not detach again."
    Test-WinToolExpectation -Condition (-not (Test-WinToolShouldDetachHost -ShowConsole $true -Unattended $false -HiddenChild "")) -Message "-ShowConsole stays in this terminal."
    Test-WinToolExpectation -Condition (-not (Test-WinToolShouldDetachHost -ShowConsole $false -Unattended $true -HiddenChild "")) -Message "Unattended mode stays in this terminal."
    $saved = $env:WINTOOL_ELEVATE_AT_START
    try {
        $env:WINTOOL_ELEVATE_AT_START = $null
        Test-WinToolExpectation -Condition (-not (Test-WinToolElevateAtStart)) -Message "Elevation at start is off by default."
        $env:WINTOOL_ELEVATE_AT_START = "1"
        Test-WinToolExpectation -Condition (Test-WinToolElevateAtStart) -Message "WINTOOL_ELEVATE_AT_START=1 keeps the previous launch flow."
    }
    finally {
        $env:WINTOOL_ELEVATE_AT_START = $saved
    }
    $entry = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Entry.ps1"))
    Test-WinToolExpectation -Condition ($entry.Contains("Test-WinToolElevateAtStart") -and $entry.Contains("Test-WinToolCurrentShouldDetachHost") -and $entry.Contains('WINTOOL_HELPER')) -Message "Start-WinTool detaches by default, elevates only when asked, and can host the helper."
    Test-WinToolExpectation -Condition ($entry.Contains("Test-WinToolElevateAtStart") -and $entry.Contains("Request-WinToolAdministrator")) -Message "The previous elevate-at-start path is still available."
    Test-WinToolExpectation -Condition ($entry.IndexOf("Test-WinToolElevateAtStart") -lt $entry.IndexOf("Request-WinToolAdministrator")) -Message "Administrator approval at start is gated on WINTOOL_ELEVATE_AT_START."
    $elevation = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/Elevation.ps1"))
    Test-WinToolExpectation -Condition ($elevation.Contains("Get-WinToolLaunchHostSnapshot") -and $elevation.Contains("Wait-WinToolLaunchReady") -and $elevation.Contains("Write-WinToolLaunchCloseSummary")) -Message "The parent waits to morph, hide, or close only the launching tab."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "conhost" -TabCount 1) -eq "hide-conhost") -Message "A classic console hides and is restored later."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "windows-terminal" -TabCount 1) -eq "morph-wt") -Message "A single Windows Terminal tab morphs into the WinTool window."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "windows-terminal" -TabCount 3) -eq "exit-tab") -Message "A Windows Terminal window with other tabs only closes the launching tab."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "windows-terminal" -TabCount $null) -eq "exit-tab") -Message "An unknown tab count is treated as a multi-tab window."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "windows-terminal" -TabCount 1 -ShowConsole $true) -eq "none") -Message "-ShowConsole does not swap the host window."
    Test-WinToolExpectation -Condition ((Get-WinToolLaunchSwapMode -Kind "unknown" -TabCount 1) -eq "none") -Message "An unknown host is left alone."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $true -PowerShell7Installed $false -WindowsTerminalInstalled $false) -eq $true) -Message "Windows PowerShell 5.1 without PowerShell 7 or Windows Terminal sees the offer."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $true -PowerShell7Installed $true -WindowsTerminalInstalled $false) -eq $true) -Message "The offer still appears when only Windows Terminal is missing."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $true -PowerShell7Installed $false -WindowsTerminalInstalled $true) -eq $true) -Message "The offer still appears when only PowerShell 7 is missing."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $true -PowerShell7Installed $true -WindowsTerminalInstalled $true) -eq $false) -Message "The offer is hidden when both modern hosts are already installed."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $true -PowerShell7Installed $false -WindowsTerminalInstalled $false -Dismissed $true) -eq $false) -Message "A dismissed offer stays out of the way."
    Test-WinToolExpectation -Condition ((Test-WinToolModernHostOffer -IsWindowsPowerShell $false -PowerShell7Installed $false -WindowsTerminalInstalled $false) -eq $false) -Message "PowerShell 7 does not show the 5.1 install offer."
    $launchHost = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/LaunchHost.ps1"))
    Test-WinToolExpectation -Condition ($launchHost.Contains("Get-WinToolPowerShell7Path") -and $launchHost.Contains('WindowsPowerShell\v1.0\powershell.exe')) -Message "The GUI prefers PowerShell 7 and falls back to Windows PowerShell 5.1."
    $shellUi = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/UI/Shell.ps1"))
    Test-WinToolExpectation -Condition ($shellUi.Contains("Complete-WinToolLaunchSwap") -and $shellUi.Contains("Complete-WinToolLaunchHostRestore") -and $shellUi.Contains("Show-WinToolModernHostOffer")) -Message "The window swaps the host after the first frame, restores it on close, and can show the offer."
    $signal = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-launch-test-" + [guid]::NewGuid().ToString("N") + ".signal")
    try {
        Write-WinToolLaunchSignal -SignalPath $signal -State "ready" -Swap "morph-wt"
        Test-WinToolExpectation -Condition ((Test-WinToolLaunchSignalReady -SignalPath $signal) -and (Get-WinToolLaunchSignalSwap -SignalPath $signal) -eq "morph-wt") -Message "The ready signal records the host swap."
        Write-WinToolLaunchSignal -SignalPath $signal -State "closed" -Swap "morph-wt" -Summary "WinTool closed."
        Test-WinToolExpectation -Condition ((Get-WinToolLaunchCloseSummary -SignalPath $signal) -eq "WinTool closed.") -Message "The close signal carries the summary line."
    }
    finally {
        Remove-Item -LiteralPath $signal -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($signal + ".tmp") -Force -ErrorAction SilentlyContinue
    }
    Test-WinToolExpectation -Condition ((Get-WinToolText "shell.closed") -eq "WinTool closed.") -Message "shell.closed has English text."
    Test-WinToolExpectation -Condition ((Get-WinToolText "shell.hostOffer.stay") -eq "Continue on 5.1") -Message "The stay action is 'Continue on 5.1'."
    $savedLang = $script:WinToolLocale
    try {
        Initialize-WinToolLocale -Language "pt-BR" -Force | Out-Null
        Test-WinToolExpectation -Condition ((Get-WinToolText "shell.closed") -eq "WinTool fechado.") -Message "pt-BR close text is 'WinTool fechado.'"
        Test-WinToolExpectation -Condition ((Get-WinToolText "shell.hostOffer.stay") -eq "Continuar no 5.1") -Message "pt-BR stay action is 'Continuar no 5.1'."
        $needs = Get-WinToolText "shell.needsAdmin"
        Test-WinToolExpectation -Condition ($needs.Contains("Aprove o aviso") -and -not $needs.Contains("Aproveite")) -Message "pt-BR asks to approve the Windows prompt, not 'Aproveite'."
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace([string]$savedLang)) {
            Initialize-WinToolLocale -Language $savedLang -Force | Out-Null
        }
        else {
            Initialize-WinToolLocale -Language en -Force | Out-Null
        }
    }
}

Invoke-WinToolCase -Name "Admin actions are marked and the helper pipe round-trips" -Body {
    $fixes = @(Get-WinToolNote -Object (Get-WinToolFixCatalog) -Name "fixes" -Default @())
    Test-WinToolExpectation -Condition ($fixes.Count -ge 4) -Message "The fix catalog is loaded for admin coverage."
    $adminTweaks = @()
    $userTweaks = @()
    foreach ($tweak in @((Get-WinToolTweakCatalog).tweaks)) {
        if (Test-WinToolTweakNeedsAdmin -Tweak $tweak) { $adminTweaks += [string]$tweak.id }
        else { $userTweaks += [string]$tweak.id }
    }
    Test-WinToolExpectation -Condition ($adminTweaks -contains "enable-long-paths") -Message "HKLM tweaks need administrator approval."
    Test-WinToolExpectation -Condition ($userTweaks -contains "show-file-extensions") -Message "HKCU tweaks can run without administrator approval."
    $fixPlan = Get-WinToolFixPlan -Fix ($fixes | Where-Object { [string]$_.id -eq "system-file-repair" } | Select-Object -First 1)
    Test-WinToolExpectation -Condition (Test-WinToolPlanNeedsAdmin -Step $fixPlan) -Message "Repairing system files is an admin plan."
    $features = @(Get-WinToolNote -Object (Get-WinToolFeatureCatalog) -Name "features" -Default @())
    $featurePlan = Get-WinToolFeaturePlan -Enable @($features[0]) -Disable @()
    Test-WinToolExpectation -Condition (Test-WinToolPlanNeedsAdmin -Step $featurePlan) -Message "Changing Windows features is an admin plan."
    Test-WinToolExpectation -Condition ((Get-WinToolHelperAllowedFactory) -contains "Get-WinToolDriverBackupScript") -Message "Driver backup runs through the helper allow-list."
    $ping = $null
    $memory = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.StreamWriter($memory, [System.Text.Encoding]::UTF8, 4096, $true)
    $writer.AutoFlush = $true
    $null = Invoke-WinToolHelperHostCommand -Message @{ id = "t1"; op = "ping" } -Writer $writer
    $writer.Flush()
    $bytes = $memory.ToArray()
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    Test-WinToolExpectation -Condition ($text -match "pong") -Message ("The helper ping command replies with pong, got: " + $text.Trim())
    if (Test-WinToolWindows) {
        $ping = Invoke-WinToolHelperRoundTrip
        Test-WinToolExpectation -Condition ($null -ne $ping -and [bool]$ping.Ok -and [string]$ping.Result -eq "pong") -Message "The helper named pipe round-trips a ping."
    }
}

Invoke-WinToolCase -Name "Home analysis works without administrator rights" -Body {
    $saved = $script:WinToolPretendNonAdmin
    $script:WinToolPretendNonAdmin = $true
    try {
        Test-WinToolExpectation -Condition (-not (Test-WinToolAdministrator)) -Message "The non-admin hook reports no administrator rights."
        $homeSource = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/UI/HomeView.ps1")) + [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/Private/Home.ps1"))
        Test-WinToolExpectation -Condition ($homeSource -notmatch "Request-WinToolAdministrator") -Message "Home analysis does not relaunch the window as administrator."
        foreach ($id in @("junk", "tweaks", "startup", "drivers", "disk", "info")) {
            $text = Get-WinToolHomeCheckScript -Id $id
            $parseErrors = $null
            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
            Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message ("The {0} check still parses without admin." -f $id)
        }
        $failed = ConvertTo-WinToolHomeResult -Id "disk" -ErrorMessage "Access denied"
        Test-WinToolExpectation -Condition ($failed.Status -eq "unknown" -and $failed.Text -eq "Could not check") -Message "A check that needs more rights degrades to 'Could not check'."
        $stub = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-junk-na-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $stub -Force | Out-Null
        try {
            $old = Join-Path $stub "old.tmp"
            [System.IO.File]::WriteAllBytes($old, (New-Object byte[] 4096))
            [System.IO.File]::SetLastWriteTime($old, (Get-Date).AddDays(-3))
            $sync = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; Error = $null; Data = $null })
            $location = [pscustomobject]@{ Id = "temp"; Name = "Stub"; Path = $stub; Filter = "*"; Recurse = $true; MinAgeHours = 24 }
            & ([scriptblock]::Create((Get-WinToolHomeCheckScript -Id "junk"))) $sync @($location)
            Test-WinToolExpectation -Condition ($sync.Done -and $sync.Ok) -Message "The junk check still runs without administrator rights."
        }
        finally {
            Remove-Item -LiteralPath $stub -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    finally {
        $script:WinToolPretendNonAdmin = $saved
    }
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

Invoke-WinToolCase -Name "Responsive columns and balanced Tweaks masonry" -Body {
    . (Join-Path $script:WinToolRoot "src/UI/InstallView.ps1")
    . (Join-Path $script:WinToolRoot "src/UI/TweaksView.ps1")
    # Install: 185 px cards plus 10 px gaps; width = list width minus the scroll bar.
    foreach ($case in @(@(726, 3), @(982, 5), @(966, 5), @(1622, 8))) {
        $got = Get-WinToolColumnCount -Width ([double]$case[0]) -MinWidth 185 -Gap 10
        Test-WinToolExpectation -Condition ($got -eq [int]$case[1]) -Message ("Install at " + $case[0] + " px: " + $got + " columns")
    }
    $counts = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($tweak in @((Get-WinToolTweakCatalog).tweaks)) {
        $name = [string]$tweak.category
        if (-not $counts.ContainsKey($name)) { $counts[$name] = 0; $order.Add($name) }
        $counts[$name]++
    }
    $rows = [int[]]@($order.ToArray() | ForEach-Object { $counts[$_] })
    $tallest = 0
    foreach ($count in $rows) { $tallest = [Math]::Max($tallest, (Get-WinToolTweakCardHeight -Rows $count)) }
    foreach ($columns in @(1, 2, 3, 4, 5)) {
        $plan = Get-WinToolTweakMasonryPlan -Rows $rows -Columns $columns
        $placed = 0
        foreach ($piece in @($plan.Pieces)) { $placed += $piece.Count }
        $heights = @($plan.Heights)
        $spread = ($heights | Measure-Object -Maximum).Maximum - ($heights | Measure-Object -Minimum).Minimum
        $line = ($heights | ForEach-Object { [int]$_ }) -join "/"
        Write-Output ("  " + $columns + " columns: heights " + $line + ", " + @($plan.Pieces).Count + " cards")
        Test-WinToolExpectation -Condition ($placed -eq ($rows | Measure-Object -Sum).Sum) -Message ("Every tweak row is placed with " + $columns + " columns.")
        Test-WinToolExpectation -Condition (@($heights | Where-Object { $_ -le 0 }).Count -eq 0) -Message ("No empty column with " + $columns + " columns.")
        if ($columns -ge 2) {
            Test-WinToolExpectation -Condition ($spread -le 0.6 * $tallest) -Message ("Columns are unbalanced with " + $columns + " columns: " + $line)
        }
    }
    $split = Get-WinToolTweakMasonryPlan -Rows @(30, 2, 2) -Columns 3
    $parts = @($split.Pieces | Where-Object { $_.Group -eq 0 })
    Test-WinToolExpectation -Condition ($parts.Count -ge 2 -and $parts[1].Start -eq $parts[0].Count) -Message "A very long category is split into continuation cards in order."
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
        foreach ($type in @("winget", "process", "module", "fix-script", "inline-script", "wsl-install", "font-download", "tool-download", "wsl-shell", "font", "ligatures", "banner", "profile", "scheme", "starship-preset", "wsl-profile")) {
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
    $monoEntries = @($entries) + @([pscustomobject]@{ Name = "CaskaydiaCoveNerdFontMono-Regular (TrueType)"; Data = "C:\f\CaskaydiaCoveNerdFontMono-Regular.ttf" })
    $mono = Find-WinToolInstalledFontFile -Token "CaskaydiaCove Nerd Font" -Entry $monoEntries
    Test-WinToolExpectation -Condition ($null -ne $mono -and $mono.Name -eq "CaskaydiaCoveNerdFontMono-Regular (TrueType)") -Message "The installed-font check prefers the Mono file."
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

Invoke-WinToolCase -Name "Tweak state is read from the apply steps" -Body {
    $script:FakeRegistry = @{
        "HKCU:\A|One" = 1
        "HKCU:\A|Two" = "x"
        "HKCU:\B|Big" = -1
    }
    $script:FakeKeys = @{ "HKCU:\Key" = $true }
    $probe = @{
        ReadValue = { param($Path, $Name) $key = $Path + "|" + $Name; if ($script:FakeRegistry.ContainsKey($key)) { return $script:FakeRegistry[$key] }; return $null }
        KeyExists = { param($Path) return $script:FakeKeys.ContainsKey($Path) }
        ServiceStart = { param($Name) if ($Name -eq "gone") { return $null }; return "Disabled" }
        TaskState = { param($TaskPath, $TaskName) $null = $TaskPath; if ($TaskName -eq "off") { return "Disabled" }; return "Ready" }
        AppxInstalled = { param($Name) return ($Name -eq "Still.Here") }
    }
    function New-TestTweak {
        param($Apply)
        return (ConvertFrom-WinToolJsonText -Text ('{"id":"t","name":"T","apply":' + $Apply + ',"undo":{"type":"registry","entries":[]}}'))
    }
    $cases = @(
        @('{"type":"registry","entries":[{"path":"HKCU:\\A","name":"One","value":1,"kind":"DWord"},{"path":"HKCU:\\A","name":"Two","value":"x","kind":"String"}]}', "on"),
        @('{"type":"registry","entries":[{"path":"HKCU:\\A","name":"One","value":0,"kind":"DWord"}]}', "off"),
        @('{"type":"registry","entries":[{"path":"HKCU:\\A","name":"Missing","value":0,"kind":"DWord"}]}', "off"),
        @('{"type":"registry","entries":[{"path":"HKCU:\\B","name":"Big","value":4294967295,"kind":"DWord"}]}', "on"),
        @('{"type":"registry-remove","entries":[{"path":"HKCU:\\A","name":"Missing"}]}', "on"),
        @('{"type":"registry-remove","entries":[{"path":"HKCU:\\A","name":"One"}]}', "off"),
        @('{"type":"registry-key","operation":"create","path":"HKCU:\\Key"}', "on"),
        @('{"type":"registry-key","operation":"remove","path":"HKCU:\\Key"}', "off"),
        @('{"type":"service","name":"DiagTrack","startupType":"Disabled","stop":true}', "on"),
        @('{"type":"service","name":"gone","startupType":"Disabled"}', "unknown"),
        @('{"type":"scheduled-task","taskPath":"\\","taskName":"off","state":"Disabled"}', "on"),
        @('{"type":"scheduled-task","taskPath":"\\","taskName":"on","state":"Disabled"}', "off"),
        @('{"type":"appx","packages":["Gone.App"]}', "on"),
        @('{"type":"appx","packages":["Gone.App","Still.Here"]}', "off"),
        @('{"type":"group","actions":[{"type":"registry","entries":[{"path":"HKCU:\\A","name":"One","value":1,"kind":"DWord"}]},{"type":"service","name":"gone","startupType":"Disabled"}]}', "unknown")
    )
    foreach ($case in $cases) {
        $state = Get-WinToolTweakState -Tweak (New-TestTweak -Apply $case[0]) -Probe $probe
        Test-WinToolExpectation -Condition ($state -eq $case[1]) -Message ("Tweak state for " + $case[0] + " was " + $state + ", expected " + $case[1])
    }
    $broken = @{ ReadValue = { throw "no registry" } }
    $state = Get-WinToolTweakState -Tweak (New-TestTweak -Apply $cases[0][0]) -Probe $broken
    Test-WinToolExpectation -Condition ($state -eq "unknown") -Message "A probe that fails gives unknown."
    $catalog = Get-WinToolTweakCatalog
    $registryOnly = 0
    foreach ($tweak in @(Get-WinToolNote -Object $catalog -Name "tweaks" -Default @())) {
        $state = Get-WinToolTweakState -Tweak $tweak -Probe $probe
        Test-WinToolExpectation -Condition (@("on", "off", "unknown") -contains $state) -Message ("No state for " + [string]$tweak.id)
        if ([string]$tweak.apply.type -eq "registry") { $registryOnly++ }
    }
    Test-WinToolExpectation -Condition ($registryOnly -gt 40) -Message "Most tweaks can be read from the registry."
    foreach ($presetId in @("minimal", "recommended", "gaming", "privacy")) {
        Test-WinToolExpectation -Condition (@(Get-WinToolPresetTweak -Catalog $catalog -PresetId $presetId).Count -ge 3) -Message ("The " + $presetId + " preset has too few tweaks.")
    }
}

Invoke-WinToolCase -Name "Tweak switches apply, undo, and go back on failure" -Body {
    $probe = @{
        ReadValue = { param($Path, $Name) $null = $Path, $Name; return $script:FakeValue }
        KeyExists = { param($Path) $null = $Path; return $false }
        ServiceStart = { param($Name) $null = $Name; return $null }
        TaskState = { param($TaskPath, $TaskName) $null = $TaskPath, $TaskName; return $null }
        AppxInstalled = { param($Name) $null = $Name; return $false }
    }
    $tweak = ConvertFrom-WinToolJsonText -Text '{"id":"t","name":"Test tweak","refresh":"explorer","apply":{"type":"registry","entries":[{"path":"HKCU:\\A","name":"V","value":1,"kind":"DWord"}]},"undo":{"type":"registry","entries":[{"path":"HKCU:\\A","name":"V","value":0,"kind":"DWord"}]}}'
    $row = [pscustomobject]@{ Tweak = $tweak; State = "off"; Checkbox = [pscustomobject]@{ IsChecked = $true; IsEnabled = $false } }
    $script:Ran = New-Object System.Collections.Generic.List[string]
    $runner = { param($Tweak, $Direction) $script:Ran.Add(([string]$Tweak.id + ":" + $Direction)); if ($Direction -eq "Apply") { $script:FakeValue = 1 } else { $script:FakeValue = 0 } }
    $script:FakeValue = 0
    $explorer = Invoke-WinToolTweakItem -Item @([pscustomobject]@{ Row = $row; Direction = "Apply"; Previous = $false }) -Probe $probe -Runner $runner
    Test-WinToolExpectation -Condition ($script:Ran[0] -eq "t:Apply" -and $row.Checkbox.IsChecked -eq $true -and $row.State -eq "on" -and $row.Checkbox.IsEnabled) -Message "Turning a switch on applies the tweak and keeps it on."
    Test-WinToolExpectation -Condition ($explorer -eq $true) -Message "An Explorer tweak asks for an Explorer restart."
    $row.Checkbox.IsChecked = $false
    $null = Invoke-WinToolTweakItem -Item @([pscustomobject]@{ Row = $row; Direction = "Undo"; Previous = $true }) -Probe $probe -Runner $runner
    Test-WinToolExpectation -Condition ($script:Ran[1] -eq "t:Undo" -and $row.Checkbox.IsChecked -eq $false -and $row.State -eq "off") -Message "Turning a switch off runs the undo."
    $failing = { param($Tweak, $Direction) $null = $Tweak, $Direction; throw "access denied" }
    $row.Checkbox.IsChecked = $true
    $null = Invoke-WinToolTweakItem -Item @([pscustomobject]@{ Row = $row; Direction = "Apply"; Previous = $false }) -Probe $probe -Runner $failing
    Test-WinToolExpectation -Condition ($row.Checkbox.IsChecked -eq $false -and $row.Checkbox.IsEnabled) -Message "A failed change puts the switch back."
    $unknownProbe = @{ ReadValue = { throw "no registry" } }
    $row.Checkbox.IsChecked = $true
    $null = Invoke-WinToolTweakItem -Item @([pscustomobject]@{ Row = $row; Direction = "Apply"; Previous = $false }) -Probe $unknownProbe -Runner $runner
    Test-WinToolExpectation -Condition ($row.Checkbox.IsChecked -eq $true -and $row.State -eq "unknown") -Message "When the state cannot be read after a change, the switch shows what was asked."
    if (-not (Test-WinToolWindows)) {
        $row.Checkbox.IsChecked = $true
        $null = Invoke-WinToolTweakItem -Item @([pscustomobject]@{ Row = $row; Direction = "Apply"; Previous = $false }) -Probe $probe
        Test-WinToolExpectation -Condition ($row.Checkbox.IsChecked -eq $false) -Message "The real runner refuses off Windows and the switch goes back."
    }
}

Invoke-WinToolCase -Name "App cards: Start menu entry, icon color, and initial" -Body {
    $start = @("Google Chrome`tChrome", "Mozilla Firefox`t308046B0AF4A39CB", "Uninstall Firefox`tX", "Visual Studio Code`tMicrosoft.VisualStudioCode", "7-Zip File Manager`tF:\7zFM.exe")
    Test-WinToolExpectation -Condition ((Resolve-WinToolAppLaunchId -Name "Google Chrome" -StartApp $start) -eq "Chrome") -Message "Exact Start menu names match."
    Test-WinToolExpectation -Condition ((Resolve-WinToolAppLaunchId -Name "Firefox" -DetectName @("Mozilla Firefox") -StartApp $start) -eq "308046B0AF4A39CB") -Message "Detect names match Start menu entries."
    Test-WinToolExpectation -Condition ((Resolve-WinToolAppLaunchId -Name "7-Zip" -StartApp $start) -eq "F:\7zFM.exe") -Message "A Start menu name that starts with the app name matches."
    Test-WinToolExpectation -Condition ($null -eq (Resolve-WinToolAppLaunchId -Name "Brave" -StartApp $start)) -Message "Apps without a Start menu entry have no Open button."
    Test-WinToolExpectation -Condition ((Get-WinToolAppIconColor -Id "firefox") -eq (Get-WinToolAppIconColor -Id "firefox") -and (Get-WinToolAppIconColor -Id "firefox") -match '^#[0-9A-F]{6}$') -Message "Icon colors are steady per app."
    Test-WinToolExpectation -Condition ((Get-WinToolAppInitial -Name "7-Zip") -eq "7" -and (Get-WinToolAppInitial -Name "vlc") -eq "V") -Message "Icon initials come from the name."
    foreach ($category in @(Get-WinToolNote -Object (Get-WinToolAppCatalog) -Name "categories" -Default @())) {
        Test-WinToolExpectation -Condition (-not [string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $category -Name "chip" -Default ""))) -Message ("Category " + [string]$category.id + " has no chip name.")
    }
}

Invoke-WinToolCase -Name "Prompt preview follows the theme colors" -Body {
    $json = '{"palette":{"blue":"#3B78FF"},"blocks":[{"type":"prompt","alignment":"left","segments":[{"type":"session","style":"diamond","leading_diamond":"<","trailing_diamond":">","foreground":"#ffffff","background":"#c386f1"},{"type":"path","style":"powerline","powerline_symbol":"X","foreground":"#100e23","background":"p:blue"},{"type":"git","style":"powerline","powerline_symbol":"X","foreground":"#193549","background":"#95ffa4"},{"type":"text","style":"plain","foreground":"red","template":"{{ .Var }}"},{"type":"text","style":"plain","foreground":"#abc","template":" $ "}]},{"type":"prompt","alignment":"right","segments":[{"type":"time","style":"plain"}]}]}'
    $theme = ConvertFrom-WinToolJsonText -Text $json
    $segments = @(Get-WinToolOmpPreviewSegment -Theme $theme)
    $texts = ($segments | ForEach-Object { [string]$_.Text }) -join "|"
    Test-WinToolExpectation -Condition ($texts -eq "<| user |>| ~/src |X| main |X|$ ") -Message ("Unexpected preview segments: " + $texts)
    Test-WinToolExpectation -Condition ($segments[3].Background -eq "#3B78FF" -and $segments[3].Foreground -eq "#100E23") -Message "Palette colors are resolved."
    Test-WinToolExpectation -Condition ($segments[4].Foreground -eq "#3B78FF" -and $segments[4].Background -eq "#95FFA4") -Message "A powerline arrow takes the next segment background."
    Test-WinToolExpectation -Condition ($segments[6].Foreground -eq "#95FFA4" -and $null -eq $segments[6].Background) -Message "The last arrow ends on the terminal background."
    Test-WinToolExpectation -Condition ($segments[7].Foreground -eq "#AABBCC" -and $null -eq $segments[7].Background) -Message "Plain segments have no background."
}

Invoke-WinToolCase -Name "Prompt glyphs have an ASCII fallback" -Body {
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolGlyphFallback -Code 0xE0B0) -eq ">") -Message "A powerline arrow falls back to >."
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolGlyphFallback -Code 0xF418) -eq "git") -Message "A git icon falls back to git."
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolGlyphFallback -Code 0xF07B) -eq "/") -Message "A folder icon falls back to /."
    Test-WinToolExpectation -Condition ((ConvertTo-WinToolGlyphFallback -Code 0x2261) -eq "=") -Message "A triple bar falls back to =."
    Test-WinToolExpectation -Condition ((@(Get-WinToolTextCode -Text ([string][char]0xD83D + [string][char]0xDE00))).Count -eq 1) -Message "An emoji is one codepoint."
    $samples = @(Get-WinToolPreviewSampleText)
    $joined = $samples -join ""
    Test-WinToolExpectation -Condition ($joined.Contains([string][char]0xE0B0) -and $joined.Contains([string][char]0xF418)) -Message "Preview samples include Nerd Font icons."
    foreach ($code in @(Get-WinToolTextCode -Text $joined)) {
        if ($code -lt 128) { continue }
        $fallback = [string](ConvertTo-WinToolGlyphFallback -Code $code)
        $plain = -not [string]::IsNullOrEmpty($fallback)
        foreach ($char in $fallback.ToCharArray()) {
            if ([int]$char -gt 127) { $plain = $false }
        }
        Test-WinToolExpectation -Condition $plain -Message ("No ASCII fallback for U+{0:X4}." -f $code)
    }
}

Invoke-WinToolCase -Name "Font folder URIs end with a slash" -Body {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-font-check.ttf"
    $uri = Get-WinToolFontFolderUri -Path $path
    Test-WinToolExpectation -Condition ($null -ne $uri -and $uri.IsAbsoluteUri) -Message "The font folder URI is absolute."
    Test-WinToolExpectation -Condition ($uri.AbsoluteUri.EndsWith("/")) -Message "The font folder URI ends with a slash."
}

Invoke-WinToolCase -Name "Prompt styles: preview, WSL setup, and powerline-go flags" -Body {
    $catalog = Get-WinToolTerminalCatalog
    foreach ($property in @((Get-WinToolNote -Object $catalog -Name "promptVariants").PSObject.Properties)) {
        foreach ($row in @($property.Value)) {
            $segments = @(Get-WinToolPromptPreview -PromptId $property.Name -PromptStyle ([string]$row.id) -Theme $null)
            Test-WinToolExpectation -Condition ($segments.Count -gt 0 -and [string]$segments[0].Text -eq [string]$row.preview[0].text) -Message ("The preview for " + $property.Name + " " + [string]$row.id + " does not use its style.")
        }
    }
    $rainbow = @(Get-WinToolPromptPreview -PromptId "powerlevel10k" -PromptStyle "rainbow" -Theme $null)
    Test-WinToolExpectation -Condition ($rainbow[0].Background -eq "#0037DA") -Message "Rainbow keeps its colored blocks."
    $first = Get-WinToolPromptVariant -PromptId "tide" -PromptStyle "no-such-style"
    Test-WinToolExpectation -Condition ([string]$first.id -eq "lean") -Message "An unknown style falls back to the first one."
    Test-WinToolExpectation -Condition ($null -eq (Get-WinToolPromptVariant -PromptId "oh-my-zsh" -PromptStyle "agnoster")) -Message "Prompts without styles have no variant."

    $pastel = @(Get-WinToolPromptPreview -PromptId "starship" -PromptStyle "pastel-powerline" -Theme $null)
    Test-WinToolExpectation -Condition (@($pastel | Where-Object { $null -ne $_.Background }).Count -ge 2) -Message "Starship powerline presets draw colored blocks."
    $made = @(Add-WinToolPreviewSeparator -Segments @(
        (New-WinToolPreviewSegment -Text " a " -Foreground "#FFFFFF" -Background "#112233"),
        (New-WinToolPreviewSegment -Text " b " -Foreground "#FFFFFF" -Background "#445566"),
        (New-WinToolPreviewSegment -Text " c" -Foreground "#AABBCC")))
    Test-WinToolExpectation -Condition ($made.Count -eq 5 -and [int][char]$made[1].Text -eq 0xE0B0 -and $made[1].Foreground -eq "#112233" -and $made[1].Background -eq "#445566" -and $made[3].Foreground -eq "#445566" -and $null -eq $made[3].Background) -Message "A Powerline arrow goes between blocks of different colors."
    $kept = @(Add-WinToolPreviewSeparator -Segments @(
        (New-WinToolPreviewSegment -Text " a " -Foreground "#FFFFFF" -Background "#112233"),
        (New-WinToolPreviewSegment -Text ([string][char]0xE0B0) -Foreground "#112233")))
    Test-WinToolExpectation -Condition ($kept.Count -eq 2) -Message "Arrows already in the data are not doubled."

    $p10k = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "powerlevel10k"; PromptStyle = "rainbow"; OmzTheme = "rainbow" })
    Test-WinToolExpectation -Condition ($p10k.Contains("export WINTOOL_PROMPT_STYLE='rainbow'") -and $p10k.Contains("export WINTOOL_STYLE_FILE='config/p10k-rainbow.zsh'")) -Message "The Powerlevel10k style reaches the WSL script."
    $tide = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "tide"; PromptStyle = "classic-16color"; OmzTheme = "" })
    Test-WinToolExpectation -Condition ($tide.Contains("export WINTOOL_PROMPT_STYLE='classic-16color'")) -Message "The Tide style reaches the WSL script."
    $pure = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "pure"; PromptStyle = "git-stash"; OmzTheme = "" })
    Test-WinToolExpectation -Condition ($pure.Contains("export WINTOOL_STYLE_SETTINGS='zstyle :prompt:pure:git:stash show yes'")) -Message "Pure settings reach the WSL script."
    $odd = Get-WinToolPromptVariantSetting -Variant ([pscustomobject]@{ settings = @("A=1", "x'; rm -rf /", "zstyle :a:b show yes") })
    Test-WinToolExpectation -Condition (@($odd).Count -eq 2 -and -not (($odd -join " ").Contains("rm"))) -Message "Unsafe setting lines are dropped."
    $label = @(Get-WinToolWslStep -Distro "Ubuntu" -PromptId "tide" -PromptStyle "rainbow" -Install $false -Shell $true)[0].Label
    Test-WinToolExpectation -Condition ($label -eq "Install Fish and Tide in Ubuntu (Rainbow style)") -Message ("Step label: " + $label)

    $goScript = Get-WinToolPromptScript -PromptId "powerline-go" -PromptStyle "gruvbox"
    Test-WinToolExpectation -Condition ($goScript.Contains("-shell bare '-theme' 'gruvbox')")) -Message "powerline-go gets the style flags."
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($goScript, [ref]$tokens, [ref]$errors)
    Test-WinToolExpectation -Condition (@($errors).Count -eq 0) -Message "The powerline-go profile parses."
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
    $rows = @(Get-WinToolSummaryRow -Line @("a", "b", "c", "d", "e", "f", "g", "h", "i", "j") -Count 3)
    Test-WinToolExpectation -Condition ($rows.Count -eq 3 -and $rows[0].StartsWith("a ") -and $rows[2].EndsWith(" j")) -Message ("Summary rows: " + ($rows -join " | "))
}

Invoke-WinToolCase -Name "Terminal style catalogs are complete" -Body {
    $catalog = Get-WinToolTerminalCatalog
    $hex = '^#[0-9A-Fa-f]{6}$'
    $font = [string]@(Get-WinToolNote -Object (Get-WinToolFontDocument) -Name "fonts" -Default @())[0].id
    $scheme = [string]@(Get-WinToolNote -Object $catalog -Name "schemes" -Default @())[0].id

    # Starship: every official preset, by the name "starship preset <id>" takes.
    $presets = @(Get-WinToolNote -Object $catalog -Name "starshipPresets" -Default @())
    $presetIds = @($presets | ForEach-Object { [string]$_.id })
    foreach ($id in @("nerd-font-symbols", "no-nerd-font", "bracketed-segments", "plain-text-symbols", "no-runtime-versions", "no-empty-icons", "pure-preset", "pastel-powerline", "tokyo-night", "gruvbox-rainbow", "jetpack", "catppuccin-powerline")) {
        Test-WinToolExpectation -Condition ($presetIds -contains $id) -Message ("The Starship preset " + $id + " is missing.")
    }
    Test-WinToolExpectation -Condition (@($presetIds | Select-Object -Unique).Count -eq $presetIds.Count) -Message "Starship preset ids are unique."
    foreach ($preset in $presets) {
        $id = [string]$preset.id
        Test-WinToolExpectation -Condition ($id -match '^[a-z0-9-]+$' -and -not [string]::IsNullOrWhiteSpace([string]$preset.name)) -Message ("Starship preset '" + $id + "' needs a plain id and a name.")
        foreach ($item in @(Get-WinToolNote -Object $preset -Name "preview" -Default @())) {
            $bg = [string](Get-WinToolNote -Object $item -Name "bg" -Default "")
            Test-WinToolExpectation -Condition ([string]$item.color -match $hex -and ([string]::IsNullOrEmpty($bg) -or $bg -match $hex)) -Message ("Starship preset '" + $id + "' has a bad preview color.")
        }
        $steps = @(Get-WinToolTerminalPlan -Selection ([pscustomobject]@{ prompt = "starship"; promptStyle = $id; fontId = $font; schemeId = $scheme }))
        Test-WinToolExpectation -Condition (@($steps | Where-Object { $_.Type -eq "starship-preset" -and $_.Preset -eq $id }).Count -eq 1) -Message ("The plan does not apply the Starship preset " + $id)
    }

    # Oh My Zsh: the bundled themes, each a name that reaches bash unchanged.
    $omz = @(Get-WinToolNote -Object $catalog -Name "omzThemes" -Default @() | ForEach-Object { [string]$_ })
    Test-WinToolExpectation -Condition ($omz.Count -ge 140 -and $omz -contains "robbyrussell" -and $omz -contains "agnoster") -Message ("Oh My Zsh lists " + $omz.Count + " themes.")
    Test-WinToolExpectation -Condition (@($omz | Select-Object -Unique).Count -eq $omz.Count) -Message "Oh My Zsh theme names are unique."
    foreach ($name in $omz) {
        Test-WinToolExpectation -Condition ((ConvertTo-WinToolShellWord -Text $name) -eq $name) -Message ("The Oh My Zsh theme '" + $name + "' would be changed on its way to bash.")
    }
    $previews = Get-WinToolNote -Object $catalog -Name "previews"
    foreach ($property in @($previews.PSObject.Properties | Where-Object { $_.Name -like "oh-my-zsh:*" })) {
        $theme = $property.Name.Substring(10)
        Test-WinToolExpectation -Condition ($omz -contains $theme) -Message ("The preview " + $property.Name + " is for a theme that is not listed.")
        $segments = @(Get-WinToolPromptPreview -PromptId "oh-my-zsh" -PromptStyle $theme -Theme $null)
        Test-WinToolExpectation -Condition ($segments.Count -gt 0 -and $segments[0].Foreground -match $hex) -Message ("No preview for the Oh My Zsh theme " + $theme)
    }
    $omzPlan = @(Get-WinToolTerminalPlan -Selection ([pscustomobject]@{ prompt = "oh-my-zsh"; promptStyle = "af-magic"; fontId = $font; schemeId = $scheme }))
    Test-WinToolExpectation -Condition (@($omzPlan | Where-Object { $_.Type -eq "wsl-shell" -and $_.OmzTheme -eq "af-magic" }).Count -eq 1) -Message "The plan passes the Oh My Zsh theme to the WSL setup."

    # Oh My Posh: the official .omp.json themes, one row each.
    $themes = @(Get-WinToolNote -Object (Get-WinToolOhMyPoshDocument) -Name "themes" -Default @())
    $themeIds = @($themes | ForEach-Object { [string]$_.id })
    Test-WinToolExpectation -Condition ($themes.Count -ge 120 -and $themeIds -contains "jandedobbeleer") -Message ("Oh My Posh lists " + $themes.Count + " themes.")
    Test-WinToolExpectation -Condition (@($themeIds | Select-Object -Unique).Count -eq $themeIds.Count) -Message "Oh My Posh theme ids are unique."
    foreach ($theme in $themes) {
        $file = Get-WinToolOmpThemeFileName -ThemeId ([string]$theme.id) -Themes $themes
        Test-WinToolExpectation -Condition ($file -eq ([string]$theme.id + ".omp.json") -and $file -match '^[A-Za-z0-9._-]+$') -Message ("The Oh My Posh theme '" + [string]$theme.id + "' has an unexpected file name.")
    }

    # Styles of the other prompts, each with a preview in the "previews" format.
    $promptIds = @(Get-WinToolNote -Object $catalog -Name "prompts" -Default @() | ForEach-Object { [string]$_.id })
    $variants = Get-WinToolNote -Object $catalog -Name "promptVariants"
    foreach ($promptId in @("powerlevel10k", "tide", "spaceship", "pure", "powerline-go")) {
        $rows = @(Get-WinToolNote -Object $variants -Name $promptId -Default @())
        Test-WinToolExpectation -Condition ($rows.Count -ge 2) -Message ("No styles listed for " + $promptId)
    }
    $p10k = @(Get-WinToolNote -Object $variants -Name "powerlevel10k" -Default @() | ForEach-Object { [string]$_.id })
    foreach ($style in @("lean", "classic", "rainbow", "pure")) {
        Test-WinToolExpectation -Condition ($p10k -contains $style) -Message ("The Powerlevel10k style " + $style + " is missing.")
    }
    foreach ($property in @($variants.PSObject.Properties)) {
        Test-WinToolExpectation -Condition ($promptIds -contains $property.Name) -Message ("Styles are listed for an unknown prompt " + $property.Name)
        $ids = @($property.Value | ForEach-Object { [string]$_.id })
        Test-WinToolExpectation -Condition (@($ids | Select-Object -Unique).Count -eq $ids.Count) -Message ("Style ids for " + $property.Name + " are unique.")
        foreach ($row in @($property.Value)) {
            $preview = @(Get-WinToolNote -Object $row -Name "preview" -Default @())
            Test-WinToolExpectation -Condition ([string]$row.id -match '^[a-z0-9-]+$' -and -not [string]::IsNullOrWhiteSpace([string]$row.name) -and $preview.Count -gt 0) -Message ("The " + $property.Name + " style '" + [string]$row.id + "' needs an id, a name, and a preview.")
            foreach ($item in $preview) {
                $bg = [string](Get-WinToolNote -Object $item -Name "bg" -Default "")
                Test-WinToolExpectation -Condition ([string]$item.fg -match $hex -and ([string]::IsNullOrEmpty($bg) -or $bg -match $hex)) -Message ("The " + $property.Name + " style '" + [string]$row.id + "' has a bad preview color.")
            }
        }
    }
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

Invoke-WinToolCase -Name "Profile init: empty output, dumb terminals, and script hosts" -Body {
    # Stub oh-my-posh, starship, and zoxide on PATH. WINTOOL_STUB_MODE=empty
    # makes them print nothing, the way oh-my-posh 33 does for TERM=dumb or a
    # non-interactive host; "code" makes them print a line of PowerShell.
    $hostPath = (Get-Process -Id $PID).Path
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-stub-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        foreach ($tool in @("oh-my-posh", "starship", "zoxide")) {
            if (Test-WinToolWindows) {
                $stubText = "@echo off`r`necho %~n0>>""%WINTOOL_STUB_LOG%""`r`nif ""%WINTOOL_STUB_MODE%""==""code"" echo `$global:WinToolStubRan += 1`r`n"
                [System.IO.File]::WriteAllText((Join-Path $work ($tool + ".cmd")), $stubText)
            }
            else {
                $stubPath = Join-Path $work $tool
                $stubText = "#!/bin/sh`necho ""`$(basename ""`$0"")"" >> ""`$WINTOOL_STUB_LOG""`nif [ ""`$WINTOOL_STUB_MODE"" = ""code"" ]; then echo '`$global:WinToolStubRan += 1'; fi`n"
                [System.IO.File]::WriteAllText($stubPath, $stubText)
                & chmod +x $stubPath
            }
        }
        # A theme file, so Oh My Posh takes the --config branch.
        [System.IO.File]::WriteAllText((Join-Path $work "jandedobbeleer.omp.json"), "{}")
        $separator = [string][System.IO.Path]::PathSeparator
        foreach ($promptId in @("oh-my-posh", "starship", "powerline-go")) {
            $text = Get-WinToolPromptScript -PromptId $promptId -TerminalIcons $false -PromptStyle "jandedobbeleer" -PsReadLine $false -Zoxide $true
            Test-WinToolExpectation -Condition ($text.Contains('IsNullOrWhiteSpace($wintoolInit)') -and $text.Contains('$wintoolInteractive')) -Message ("The " + $promptId + " profile should check the init output and the host.")
            $profileFile = Join-Path $work ($promptId + ".ps1")
            [System.IO.File]::WriteAllText($profileFile, $text)
            foreach ($case in @(
                    @{ Mode = "empty"; Term = "xterm-256color"; Ran = 0; Called = $true },
                    @{ Mode = "code"; Term = "xterm-256color"; Ran = -1; Called = $true },
                    @{ Mode = "code"; Term = "dumb"; Ran = 0; Called = $false })) {
                $log = Join-Path $work ("calls-" + [guid]::NewGuid().ToString("N") + ".txt")
                $setup = @(
                    ('$env:PATH = "{0}" + $env:PATH' -f ($work + $separator)),
                    ('$env:POSH_THEMES_PATH = "{0}"' -f $work),
                    ('$env:TERM = "{0}"' -f $case.Term),
                    ('$env:WINTOOL_STUB_MODE = "{0}"' -f $case.Mode),
                    ('$env:WINTOOL_STUB_LOG = "{0}"' -f $log),
                    '$global:WinToolStubRan = 0',
                    '$Error.Clear()',
                    ('. "{0}"' -f $profileFile),
                    'foreach ($e in $Error) { "ERR: " + $e }',
                    '"RAN=" + $global:WinToolStubRan',
                    '"WINTOOL-OK"'
                )
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($setup -join "`n")))
                $output = & $hostPath -NoProfile -EncodedCommand $encoded 2>&1
                $joined = (@($output) | ForEach-Object { [string]$_ }) -join "`n"
                $label = $promptId + " with " + $case.Mode + " output and TERM=" + $case.Term
                Test-WinToolExpectation -Condition ($joined.Contains("WINTOOL-OK") -and -not $joined.Contains("ERR:")) -Message ($label + " wrote errors: " + $joined)
                $calls = @()
                if (Test-Path -LiteralPath $log) { $calls = @(Get-Content -LiteralPath $log | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                $expected = @("zoxide")
                if ($promptId -ne "powerline-go") { $expected += $promptId }
                if ($case.Called) {
                    foreach ($name in $expected) { Test-WinToolExpectation -Condition ($calls -contains $name) -Message ($label + ": " + $name + " init should run; calls: " + ($calls -join ",")) }
                    if ($case.Ran -lt 0) { Test-WinToolExpectation -Condition ($joined.Contains("RAN=" + $expected.Count)) -Message ($label + ": the init output should run once per tool: " + $joined) }
                    else { Test-WinToolExpectation -Condition ($joined.Contains("RAN=0")) -Message ($label + ": empty init output should run nothing: " + $joined) }
                }
                else {
                    Test-WinToolExpectation -Condition ($calls.Count -eq 0 -and $joined.Contains("RAN=0")) -Message ($label + ": TERM=dumb should skip every init; calls: " + ($calls -join ","))
                }
            }
        }
        $text = Get-WinToolPromptScript -PromptId "oh-my-posh" -TerminalIcons $false -PromptStyle "jandedobbeleer" -PsReadLine $false -Zoxide $true
        Test-WinToolExpectation -Condition ($text.Contains('@("ConsoleHost", "Visual Studio Code Host") -contains [string]$Host.Name') -and $text.Contains('[Environment]::UserInteractive')) -Message "The profile skips init in script hosts and non-interactive sessions."
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
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

Invoke-WinToolCase -Name "Advanced Terminal page: engines, theme rows, filters, and action chips" -Body {
    $catalog = Get-WinToolTerminalCatalog
    $groups = @{}
    foreach ($prompt in @($catalog.prompts)) {
        $info = Get-WinToolPromptEngineInfo -Prompt $prompt
        $groups[[string]$prompt.id] = [string]$info.Group
        Test-WinToolExpectation -Condition (-not [string]::IsNullOrWhiteSpace([string]$info.Sub) -and [string]$info.Color -match '^#[0-9A-F]{6}$') -Message ("Engine " + [string]$prompt.id + " needs a sub line and a color.")
        $rows = @(Get-WinToolThemeRow -PromptId ([string]$prompt.id))
        Test-WinToolExpectation -Condition ($rows.Count -gt 0) -Message ("Engine " + [string]$prompt.id + " has no themes or styles.")
        $title = Get-WinToolThemeTitle -PromptId ([string]$prompt.id)
        Test-WinToolExpectation -Condition (-not [string]::IsNullOrWhiteSpace([string]$title.Title)) -Message ("Engine " + [string]$prompt.id + " has no theme column title.")
    }
    Test-WinToolExpectation -Condition ($groups["oh-my-posh"] -eq "PowerShell" -and $groups["starship"] -eq "PowerShell" -and $groups["powerline-go"] -eq "PowerShell") -Message "PowerShell engines are grouped together."
    Test-WinToolExpectation -Condition ($groups["powerlevel10k"] -eq "WSL Ubuntu" -and $groups["tide"] -eq "WSL Ubuntu" -and $groups["oh-my-zsh"] -eq "WSL Ubuntu") -Message "WSL engines are grouped together."

    # Every Oh My Posh theme has a sample in the catalog, so the list and the
    # preview show colors before any theme file is downloaded.
    $omp = @(Get-WinToolThemeRow -PromptId "oh-my-posh")
    Test-WinToolExpectation -Condition (@($omp | Where-Object { @($_.Preview).Count -eq 0 }).Count -eq 0) -Message "Every Oh My Posh theme row has a sample."
    foreach ($row in $omp) {
        foreach ($segment in @($row.Preview)) {
            $sampleText = [string]$segment.Text
            $raw = ($sampleText.Contains("<#") -or $sampleText.Contains("</>") -or $sampleText.Contains("<transparent") -or $sampleText.Contains("{{"))
            Test-WinToolExpectation -Condition (-not $raw) -Message ("The Oh My Posh sample for " + [string]$row.Id + " shows raw markup: " + $sampleText)
        }
    }
    $split = @(Split-WinToolOmpMarkup -Text "a<#FF0000> b</><transparent,#26BDBB>c</>" -Foreground "#FFFFFF" -Background "")
    Test-WinToolExpectation -Condition ($split.Count -eq 3 -and $split[1].Foreground -eq "#FF0000" -and $split[1].Text -eq " b" -and $split[2].Background -eq "#26BDBB" -and $split[2].Text -eq "c") -Message "Oh My Posh color tags become separate colored segments."
    $themed = @(Get-WinToolOmpPreviewSegment -Theme (ConvertFrom-WinToolJsonText -Text '{"blocks":[{"type":"prompt","alignment":"left","segments":[{"type":"path","style":"diamond","leading_diamond":"<transparent,background>\ue0b0</>","trailing_diamond":"\ue0b4","foreground":"#ffffff","background":"#ff479c"},{"type":"text","style":"plain","template":"<#ff0000> x</> ","foreground":"#ffffff"}]}]}'))
    Test-WinToolExpectation -Condition (@($themed | Where-Object { ([string]$_.Text).Contains("<") }).Count -eq 0 -and @($themed | Where-Object { $_.Background -eq "#FF479C" }).Count -ge 2) -Message "Diamonds with markup use the segment background."
    $plain = @(Get-WinToolPromptPreview -PromptId "oh-my-posh" -PromptStyle "jandedobbeleer" -Theme $null)
    Test-WinToolExpectation -Condition (@($plain | Where-Object { $null -ne $_.Background }).Count -ge 2) -Message "The Oh My Posh preview uses the catalog sample without the theme file."

    $starship = @(Get-WinToolThemeRow -PromptId "starship")
    $power = @(Select-WinToolThemeRow -Row $starship -Filter "powerline")
    $minimal = @(Select-WinToolThemeRow -Row $starship -Filter "minimal")
    $noNerd = @(Select-WinToolThemeRow -Row $starship -Filter "no-nerd")
    Test-WinToolExpectation -Condition ($power.Count -ge 2 -and ($power.Count + $minimal.Count) -eq $starship.Count) -Message "Powerline and Minimal split the Starship presets."
    Test-WinToolExpectation -Condition (@($power | Where-Object { $_.Id -eq "tokyo-night" }).Count -eq 1) -Message "Tokyo Night is a Powerline preset."
    Test-WinToolExpectation -Condition (@($noNerd | Where-Object { $_.Id -eq "no-nerd-font" }).Count -eq 1 -and @($noNerd | Where-Object { $_.Id -eq "nerd-font-symbols" }).Count -eq 0) -Message "No Nerd Font needed follows the preset flag."
    Test-WinToolExpectation -Condition (@(Select-WinToolThemeRow -Row $starship -Query "tokyo").Count -eq 1) -Message "Search narrows the theme rows."
    $tokyo = @($starship | Where-Object { $_.Id -eq "tokyo-night" })[0]
    Test-WinToolExpectation -Condition (@($tokyo.Preview | Where-Object { $null -ne $_.Background }).Count -ge 2) -Message "The Tokyo Night row draws colored blocks."
    Test-WinToolExpectation -Condition ((Test-WinToolNerdGlyph -Text ([string][char]0xE0B0)) -and -not (Test-WinToolNerdGlyph -Text "~/src main >")) -Message "Nerd Font glyphs are detected."

    $choice = Get-WinToolSimpleTerminalChoice
    $choice.prompt = "starship"
    $choice.promptStyle = "tokyo-night"
    $choice.zoxide = $true
    $choice.fontSize = 13
    $steps = @(Get-WinToolTerminalPlan -Selection $choice)
    $fontStep = @($steps | Where-Object { $_.Type -eq "font" })[0]
    Test-WinToolExpectation -Condition ([int]$fontStep.Size -eq 13 -and [string]$fontStep.Label -like "*13 pt") -Message "The font size goes into the font step."
    Reset-WinToolPackageCache | Out-Null
    $chips = @(Get-WinToolSummaryChip -Step $steps)
    $adds = @($chips | Where-Object { $_.Kind -eq "add" } | ForEach-Object { [string]$_.Text })
    $changes = @($chips | Where-Object { $_.Kind -eq "change" } | ForEach-Object { [string]$_.Text })
    Test-WinToolExpectation -Condition ($adds -contains "Windows Terminal" -and $adds -contains "Starship" -and $adds -contains "zoxide" -and $adds -contains "Terminal-Icons") -Message ("Install chips: " + ($adds -join ", "))
    Test-WinToolExpectation -Condition (@($adds | Where-Object { $_ -eq "Terminal-Icons" }).Count -eq 1) -Message "Terminal-Icons shows once."
    Test-WinToolExpectation -Condition ($changes -contains "Starship preset tokyo-night" -and $changes -contains "Scheme Night" -and $changes -contains "Terminal font 13 pt" -and $changes -contains "Startup banner hidden") -Message ("Change chips: " + ($changes -join ", "))
    $bannerOff = Get-WinToolSimpleTerminalChoice
    $bannerOff.hideStartupBanner = $false
    $offChips = @(Get-WinToolSummaryChip -Step @(Get-WinToolTerminalPlan -Selection $bannerOff) | Where-Object { $_.Text -eq "Startup banner shown" })
    Test-WinToolExpectation -Condition ($offChips.Count -eq 1) -Message "Turning the banner extra off shows a restore chip."
    $wslChips = @(Get-WinToolSummaryChip -Step @(Get-WinToolTerminalPlan -Selection ([pscustomobject]@{ prompt = "powerlevel10k"; promptStyle = "rainbow"; fontId = $choice.fontId; schemeId = $choice.schemeId })))
    Test-WinToolExpectation -Condition (@($wslChips | Where-Object { $_.Text -eq "Rainbow style" -and $_.Kind -eq "change" }).Count -eq 1) -Message "The chosen WSL style shows as a change."

    $font = 12
    $simple = Get-WinToolSimpleTerminalChoice
    Test-WinToolExpectation -Condition ([int]$simple.fontSize -eq $font) -Message "The recommended setup uses 12 pt."
}

Invoke-WinToolCase -Name "Terminal setup always turns on font ligatures for every profile" -Body {
    $text = @'
{
  // user comment
  "profiles": {
    "defaults": { "font": { "face": "Fira Code", "weight": "light", "features": { "ss01": 1, "calt": 0, "zero": 1 } } },
    "list": [
      { "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" },
      { "name": "Windows PowerShell", "font": { "size": 11 } },
      { "name": "Ubuntu", "source": "Windows.Terminal.Wsl", "font": { "face": "Hack", "features": { "ss02": 1, "liga": 0 } } },
      { "name": "Command Prompt", "commandline": "cmd.exe" }
    ]
  }
}
'@
    $settings = ConvertFrom-WinToolJsonText -Text $text
    $own = Add-WinToolTerminalLigature -Settings $settings
    $features = $settings.profiles.defaults.font.features
    Test-WinToolExpectation -Condition ([int]$features.calt -eq 1 -and [int]$features.liga -eq 1) -Message "Defaults get calt=1 and liga=1."
    Test-WinToolExpectation -Condition ([int]$features.ss01 -eq 1 -and [int]$features.zero -eq 1) -Message "Other default font features are kept."
    Test-WinToolExpectation -Condition ($settings.profiles.defaults.font.face -eq "Fira Code" -and $settings.profiles.defaults.font.weight -eq "light") -Message "The default font face and weight are kept."
    $ubuntu = @($settings.profiles.list | Where-Object { $_.name -eq "Ubuntu" })[0]
    Test-WinToolExpectation -Condition ($own -eq 1 -and [int]$ubuntu.font.features.calt -eq 1 -and [int]$ubuntu.font.features.liga -eq 1 -and [int]$ubuntu.font.features.ss02 -eq 1) -Message "A profile with its own features list also gets ligatures and keeps its features."
    $windowsPs = @($settings.profiles.list | Where-Object { $_.name -eq "Windows PowerShell" })[0]
    Test-WinToolExpectation -Condition ($null -eq $windowsPs.font.PSObject.Properties["features"] -and [int]$windowsPs.font.size -eq 11) -Message "Profiles without their own features inherit the defaults untouched."
    $cmd = @($settings.profiles.list | Where-Object { $_.name -eq "Command Prompt" })[0]
    Test-WinToolExpectation -Condition ($null -eq $cmd.PSObject.Properties["font"]) -Message "Command Prompt inherits the default ligatures."
    $again = ConvertFrom-WinToolJsonText -Text (ConvertTo-WinToolJsonText -Value $settings)
    Add-WinToolTerminalLigature -Settings $again | Out-Null
    Test-WinToolExpectation -Condition (@($again.profiles.defaults.font.features.PSObject.Properties).Count -eq 4) -Message "Running it again does not add duplicate features."

    Add-WinToolTerminalFont -Settings $settings -Face "JetBrainsMono Nerd Font" -Size 14 | Out-Null
    $font = $settings.profiles.defaults.font
    Test-WinToolExpectation -Condition ($font.face -eq "JetBrainsMono Nerd Font" -and [int]$font.size -eq 14 -and [int]$font.features.liga -eq 1 -and [int]$font.features.ss01 -eq 1) -Message "Setting the font keeps the font features."

    $empty = [pscustomobject]@{}
    Add-WinToolTerminalLigature -Settings $empty | Out-Null
    Test-WinToolExpectation -Condition ([int]$empty.profiles.defaults.font.features.calt -eq 1 -and [int]$empty.profiles.defaults.font.features.liga -eq 1) -Message "Ligatures are added to empty settings."
    $legacy = ConvertFrom-WinToolJsonText -Text '{ "profiles": [ { "name": "cmd" } ] }'
    Add-WinToolTerminalLigature -Settings $legacy | Out-Null
    Test-WinToolExpectation -Condition ([int]$legacy.profiles.defaults.font.features.liga -eq 1 -and @($legacy.profiles.list).Count -eq 1) -Message "Old list-style profiles move under profiles.list."

    $choices = @((Get-WinToolSimpleTerminalChoice))
    $wslChoice = Get-WinToolSimpleTerminalChoice
    $wslChoice.prompt = "powerlevel10k"
    $wslChoice.promptStyle = "rainbow"
    $choices += $wslChoice
    foreach ($item in $choices) {
        $plan = @(Get-WinToolTerminalPlan -Selection $item)
        $steps = @($plan | Where-Object { $_.Type -eq "ligatures" })
        Test-WinToolExpectation -Condition ($steps.Count -eq 1) -Message ("The " + [string]$item.prompt + " plan turns on ligatures once.")
        $chips = @(Get-WinToolSummaryChip -Step $plan | Where-Object { $_.Kind -eq "change" -and $_.Text -eq "Font ligatures on" })
        Test-WinToolExpectation -Condition ($chips.Count -eq 1) -Message ("The " + [string]$item.prompt + " plan shows a Font ligatures on chip.")
        Test-WinToolExpectation -Condition ($null -eq (Get-WinToolPlanCommand -Step $steps[0])) -Message "The ligature step runs inside WinTool."
    }
    Test-WinToolExpectation -Condition (Test-WinToolLocalStepType -Type "ligatures") -Message "The ligature step has a local handler."

    $oldLocal = $env:LOCALAPPDATA
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-wt-" + [guid]::NewGuid().ToString())
    try {
        $folder = Join-Path $root "Microsoft/Windows Terminal"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $path = Join-Path $folder "settings.json"
        [System.IO.File]::WriteAllText($path, $text)
        $env:LOCALAPPDATA = $root
        $null = Invoke-WinToolLocalStep -Step ([pscustomobject]@{ Type = "ligatures"; Label = "Turn on font ligatures" })
        $written = ConvertFrom-WinToolJsonText -Text ([System.IO.File]::ReadAllText($path))
        $saved = $written.profiles.defaults.font.features
        Test-WinToolExpectation -Condition ([int]$saved.calt -eq 1 -and [int]$saved.liga -eq 1 -and [int]$saved.ss01 -eq 1 -and @($written.profiles.list).Count -eq 4) -Message "The ligature step writes settings.json and keeps the profiles."
        Test-WinToolExpectation -Condition (Test-Path -LiteralPath ($path + ".wintool-backup")) -Message "The ligature step backs up settings.json first."
    }
    finally {
        $env:LOCALAPPDATA = $oldLocal
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Terminal page follows the 14 px text standard" -Body {
    $xaml = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "assets/MainWindow.xaml"))
    $start = $xaml.IndexOf('x:Name="ViewTerminal"')
    $end = $xaml.IndexOf('x:Name="ViewDrivers"')
    Test-WinToolExpectation -Condition ($start -gt 0 -and $end -gt $start) -Message "The Terminal view is in the window markup."
    $terminal = $xaml.Substring($start, $end - $start)
    $literal = @([regex]::Matches($terminal, 'FontSize"?\s*(=|Value=)\s*"[0-9.]+"') | ForEach-Object { $_.Value })
    Test-WinToolExpectation -Condition ($literal.Count -eq 0) -Message ("Terminal markup uses the shared text sizes, not numbers: " + ($literal -join ", "))
    $titles = @([regex]::Matches($terminal, 'FontSizeTitle')).Count
    Test-WinToolExpectation -Condition ($titles -eq 1) -Message "Only the Terminal page title uses FontSizeTitle."
    Test-WinToolExpectation -Condition ($terminal -notmatch 'SwitchToggle' -and $terminal -notmatch 'LayoutTransform') -Message "Terminal checkboxes use the shared rounded checkbox, unscaled."
    Test-WinToolExpectation -Condition ($terminal -notmatch '<Style[^>]*TargetType="CheckBox"') -Message "The Terminal page does not define its own checkbox style."
    $view = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/UI/TerminalView.ps1"))
    $sizes = @([regex]::Matches($view, '(FontSize\s*=\s*[0-9]|-Size\s+[0-9])') | ForEach-Object { $_.Value })
    Test-WinToolExpectation -Condition ($sizes.Count -eq 0) -Message ("Terminal code uses FontSizeBody, not fixed sizes: " + ($sizes -join ", "))
    Test-WinToolExpectation -Condition ($view -notmatch 'SwitchToggle') -Message "Terminal extras use the shared rounded checkbox."
    # The live sample is the one exception: it follows the chosen terminal font size.
    Test-WinToolExpectation -Condition ($view -match '\$sample\.FontSize = \[Math\]::Round\(\$size') -Message "The live preview follows the chosen terminal font size."
}

Invoke-WinToolCase -Name "Home checks parse stubbed results" -Body {
    $order = @(Get-WinToolHomeCheckList | ForEach-Object { $_.Id }) -join ","
    Test-WinToolExpectation -Condition ($order -eq "junk,tweaks,startup,drivers,disk") -Message "Home checks keep their fixed order, got $order."

    $junk = ConvertTo-WinToolHomeResult -Id "junk" -Data @(
        [pscustomobject]@{ Id = "temp"; Name = "Your temporary files"; Bytes = [double]12GB },
        [pscustomobject]@{ Id = "recycle"; Name = "Recycle Bin"; Bytes = [double]6.7GB },
        [pscustomobject]@{ Id = "thumbs"; Name = "Thumbnail cache"; Bytes = [double]0 })
    Test-WinToolExpectation -Condition ($junk.Status -eq "bad" -and $junk.Text -eq "18.7 GB can be deleted" -and $junk.Action -eq "fix" -and $junk.Fixable) -Message ("Junk over 1 GB is a red Fix row, got {0} '{1}' {2}." -f $junk.Status, $junk.Text, $junk.Action)
    $clean = ConvertTo-WinToolHomeJunkResult -Data @([pscustomobject]@{ Name = "Temp"; Bytes = [double]10MB })
    Test-WinToolExpectation -Condition ($clean.Status -eq "ok" -and $clean.Action -eq "none" -and $clean.Penalty -eq 0) -Message "A few MB of junk needs no Fix."

    $tweakData = @()
    for ($i = 0; $i -lt 10; $i++) {
        $state = "on"
        if ($i -lt 8) { $state = "off" }
        $tweakData += [pscustomobject]@{ Id = "t$i"; Name = "Tweak $i"; State = $state }
    }
    $tweakData += [pscustomobject]@{ Id = "u"; Name = "Unknown"; State = "unknown" }
    $tweaks = ConvertTo-WinToolHomeResult -Id "tweaks" -Data $tweakData
    Test-WinToolExpectation -Condition ($tweaks.Status -eq "warn" -and $tweaks.Text -eq "8 tweaks not applied yet" -and $tweaks.Action -eq "fix" -and $tweaks.Penalty -eq 16) -Message ("Eight off tweaks show a Fix row, got '{0}' penalty {1}." -f $tweaks.Text, $tweaks.Penalty)
    $allOn = ConvertTo-WinToolHomeTweakResult -Data @([pscustomobject]@{ Id = "a"; Name = "A"; State = "on" })
    Test-WinToolExpectation -Condition ($allOn.Status -eq "ok" -and -not $allOn.Fixable) -Message "All tweaks on is a green row without Fix."
    $unread = ConvertTo-WinToolHomeTweakResult -Data @([pscustomobject]@{ Id = "a"; Name = "A"; State = "unknown" })
    Test-WinToolExpectation -Condition ($unread.Status -eq "unknown") -Message "Unreadable tweaks are reported as unknown."

    $startup = ConvertTo-WinToolHomeResult -Id "startup" -Data @(
        [pscustomobject]@{ Name = "OneDrive"; Source = "Run, this user"; Approved = -1 },
        [pscustomobject]@{ Name = "Discord"; Source = "Run, this user"; Approved = 2 },
        [pscustomobject]@{ Name = "Spotify"; Source = "Run, this user"; Approved = 3 },
        [pscustomobject]@{ Name = "Steam"; Source = "Run, this user"; Approved = 6 },
        [pscustomobject]@{ Name = "Teams"; Source = "Startup folder"; Approved = 7 },
        [pscustomobject]@{ Name = "Notes"; Source = "Startup folder"; Approved = -1 },
        [pscustomobject]@{ Name = "OneDrive"; Source = "Run, this user"; Approved = -1 })
    Test-WinToolExpectation -Condition ($startup.Status -eq "ok" -and $startup.Text -eq "4 programs start with Windows" -and $startup.Action -eq "review") -Message ("Disabled StartupApproved entries are not counted, got '{0}'." -f $startup.Text)
    $many = ConvertTo-WinToolHomeStartupResult -Data @(1..10 | ForEach-Object { [pscustomobject]@{ Name = "App$_"; Source = "Run"; Approved = -1 } })
    Test-WinToolExpectation -Condition ($many.Status -eq "warn" -and $many.Penalty -gt 0) -Message "Ten startup programs are a warning."

    $drivers = ConvertTo-WinToolHomeResult -Id "drivers" -Data @()
    Test-WinToolExpectation -Condition ($drivers.Status -eq "ok" -and $drivers.Text -eq "No device with problems" -and $drivers.Action -eq "none") -Message "No problem devices is a green row with a hidden slot."
    $broken = ConvertTo-WinToolHomeResult -Id "drivers" -Data @([pscustomobject]@{ Name = "PCI Device"; Class = "System"; Status = "Error" })
    Test-WinToolExpectation -Condition ($broken.Status -eq "bad" -and $broken.Text -eq "1 device has a problem" -and $broken.Action -eq "review") -Message "A device in error is a red Review row."

    $disk = ConvertTo-WinToolHomeResult -Id "disk" -Data @(
        [pscustomobject]@{ Name = "NVMe SSD"; MediaType = "SSD"; Health = "Healthy" },
        [pscustomobject]@{ Name = "Backup HDD"; MediaType = "HDD"; Health = "Healthy" })
    Test-WinToolExpectation -Condition ($disk.Status -eq "ok" -and $disk.Text -eq "All drives report healthy") -Message "Healthy drives read as healthy."
    $failing = ConvertTo-WinToolHomeDiskResult -Data @([pscustomobject]@{ Name = "Old HDD"; MediaType = "HDD"; Health = "Warning" })
    Test-WinToolExpectation -Condition ($failing.Status -eq "bad" -and $failing.Penalty -eq 30 -and $failing.Text -eq "Old HDD reports warning") -Message ("A warning drive is red, got '{0}'." -f $failing.Text)
    $none = ConvertTo-WinToolHomeDiskResult -Data @()
    Test-WinToolExpectation -Condition ($none.Status -eq "unknown") -Message "No disk data is unknown, not healthy."

    $failed = ConvertTo-WinToolHomeResult -Id "disk" -ErrorMessage "Access denied"
    Test-WinToolExpectation -Condition ($failed.Status -eq "unknown" -and $failed.Text -eq "Could not check" -and $failed.Penalty -eq 0) -Message "A failed check shows Could not check."

    $score = Get-WinToolHomeScore -Result @($junk, $tweaks, $startup, $drivers, $disk)
    Test-WinToolExpectation -Condition ($score -eq 72) -Message "The mockup results score 72, got $score."
    $verdict = Get-WinToolHomeVerdict -Score $score
    Test-WinToolExpectation -Condition ($verdict.Text -eq "Needs attention" -and $verdict.Tone -eq "warn") -Message "Score 72 needs attention."
    Test-WinToolExpectation -Condition ((Get-WinToolHomeVerdict -Score 95).Text -eq "Healthy") -Message "Score 95 is healthy."
    $lead = Get-WinToolHomeLead -Result @($junk, $tweaks, $startup, $drivers, $disk)
    Test-WinToolExpectation -Condition ($lead -eq (Get-WinToolCountText "msg.items-can-be-fixed-nothing-changed" 2)) -Message "The lead counts fixable items, got '$lead'."

    $now = [datetime]::new(2026, 11, 23, 20, 0, 0)
    Test-WinToolExpectation -Condition ((Format-WinToolHomeWhen -Time ([datetime]::new(2026, 11, 23, 19, 31, 0)) -Now $now) -eq "today 19:31") -Message "Same-day analyses read 'today'."
    Test-WinToolExpectation -Condition ((Format-WinToolHomeWhen -Time ([datetime]::new(2026, 11, 22, 8, 5, 0)) -Now $now) -eq "yesterday 08:05") -Message "Yesterday's analyses read 'yesterday'."
    $meta = Format-WinToolHomeMeta -Last ([pscustomobject]@{ Time = [datetime]::new(2026, 11, 23, 19, 31, 0); Score = 72 }) -Now $now
    Test-WinToolExpectation -Condition ($meta -eq ("Last analysis: today 19:31 " + [char]0x00B7 + " Score 72")) -Message "The meta line names time and score, got '$meta'."

    Test-WinToolExpectation -Condition ((Test-WinToolStartupApproved -FirstByte 2) -and -not (Test-WinToolStartupApproved -FirstByte 3) -and (Test-WinToolStartupApproved -FirstByte $null)) -Message "StartupApproved bytes decode."
    Test-WinToolExpectation -Condition ((Get-WinToolMemoryTypeName -Code 34) -eq "DDR5" -and (Get-WinToolMemoryTypeName -Code 26) -eq "DDR4") -Message "SMBIOS memory types decode."
    $cpu = Format-WinToolCpuName -Name "AMD Ryzen 7 7700 8-Core Processor           "
    Test-WinToolExpectation -Condition ($cpu -eq "AMD Ryzen 7 7700") -Message "CPU names are shortened, got '$cpu'."
    $intel = Format-WinToolCpuName -Name "Intel(R) Core(TM) i7-8700 CPU @ 3.20GHz"
    Test-WinToolExpectation -Condition ($intel -eq "Intel Core i7-8700") -Message "Intel names are shortened, got '$intel'."
    Test-WinToolExpectation -Condition ((Get-WinToolHomeDiskTone -FreePercent 29) -eq "warn" -and (Get-WinToolHomeDiskTone -FreePercent 45) -eq "ok") -Message "Disk free tones match the mockup."

    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-home-" + [guid]::NewGuid().ToString("N"))
    $historyPath = Join-Path $folder "home-history.json"
    try {
        for ($i = 0; $i -lt 22; $i++) { Add-WinToolHomeHistory -Time $now.AddMinutes($i) -Score (50 + $i) -Seconds 30 -Path $historyPath }
        $history = @(Read-WinToolHomeHistory -Path $historyPath)
        Test-WinToolExpectation -Condition ($history.Count -eq 20 -and $history[-1].Score -eq 71 -and $history[-1].Time -eq $now.AddMinutes(21)) -Message "History keeps the last 20 analyses with their time."
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($id in @("junk", "clean", "tweaks", "startup", "drivers", "disk", "info", "sampler")) {
        $text = Get-WinToolHomeCheckScript -Id $id
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
        Test-WinToolExpectation -Condition (@($parseErrors).Count -eq 0) -Message ("The {0} check script parses: {1}" -f $id, (@($parseErrors) -join "; "))
    }
    # The junk collector runs anywhere: a stub folder with an old and a new file.
    $stub = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-junk-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stub -Force | Out-Null
    try {
        $old = Join-Path $stub "old.tmp"
        [System.IO.File]::WriteAllBytes($old, (New-Object byte[] 4096))
        [System.IO.File]::SetLastWriteTime($old, (Get-Date).AddDays(-3))
        [System.IO.File]::WriteAllBytes((Join-Path $stub "new.tmp"), (New-Object byte[] 1024))
        $sync = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; Error = $null; Data = $null })
        $location = [pscustomobject]@{ Id = "temp"; Name = "Stub"; Path = $stub; Filter = "*"; Recurse = $true; MinAgeHours = 24 }
        & ([scriptblock]::Create((Get-WinToolHomeCheckScript -Id "junk"))) $sync @($location)
        $measured = @($sync.Data)
        Test-WinToolExpectation -Condition ($sync.Done -and $sync.Ok -and $measured.Count -eq 1 -and [double]$measured[0].Bytes -eq 4096) -Message ("The junk check counts only files older than a day, got {0}." -f (@($measured | ForEach-Object { $_.Bytes }) -join ","))
    }
    finally {
        Remove-Item -LiteralPath $stub -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Home page follows the text standard and fixed slots" -Body {
    $xaml = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "assets/MainWindow.xaml"))
    $start = $xaml.IndexOf('x:Name="ViewHome"')
    $end = $xaml.IndexOf('x:Name="ViewInstall"')
    Test-WinToolExpectation -Condition ($start -gt 0 -and $end -gt $start) -Message "The Home view is in the window markup."
    $homeXaml = $xaml.Substring($start, $end - $start)
    $literal = @([regex]::Matches($homeXaml, 'FontSize"?\s*(=|Value=)\s*"[0-9.]+"') | ForEach-Object { $_.Value })
    Test-WinToolExpectation -Condition ($literal.Count -eq 0) -Message ("Home markup uses the shared text sizes: " + ($literal -join ", "))
    $nav = $xaml.IndexOf('x:Name="NavHome"')
    Test-WinToolExpectation -Condition ($nav -gt 0 -and $nav -lt $xaml.IndexOf('x:Name="NavInstall"')) -Message "Home is the first sidebar item."
    Test-WinToolExpectation -Condition ($xaml -match 'x:Name="NavHome"[^>]*IsChecked="True"' -and $xaml -notmatch 'x:Name="NavInstall"[^>]*IsChecked="True"') -Message "Home is the default page."
    $view = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "src/UI/HomeView.ps1"))
    Test-WinToolExpectation -Condition ($view -notmatch 'FontSize\s*=') -Message "Home code does not set font sizes."
    Test-WinToolExpectation -Condition ($view -match '\$button\.Visibility = "Hidden"') -Message "Home rows hide buttons with Hidden so their slot stays."
}

Invoke-WinToolCase -Name "Driver codes, Home history sync, profile BOM, non-zero init guard, and PS 5.1 fixes" -Body {
    $disabledOnly = ConvertTo-WinToolHomeResult -Id "drivers" -Data @(
        [pscustomobject]@{ Name = "Disabled Camera"; Class = "Camera"; Status = "Error"; Problem = 22 },
        [pscustomobject]@{ Name = "Unplugged USB"; Class = "USB"; Status = "Unknown"; Problem = 45 }
    )
    Test-WinToolExpectation -Condition ($disabledOnly.Status -eq "ok" -and $disabledOnly.Text -eq "No device with problems") -Message "Disabled (22) and disconnected (45) devices should not warn."

    $missingDriver = ConvertTo-WinToolHomeResult -Id "drivers" -Data @(
        [pscustomobject]@{ Name = ""; InstanceId = "PCI\VEN_10DE"; Class = "Display"; Status = "Error"; Problem = 28 }
    )
    Test-WinToolExpectation -Condition ($missingDriver.Status -eq "bad" -and $missingDriver.Detail[0].Contains("PCI\VEN_10DE") -and $missingDriver.Detail[0].Contains("driver not installed (code 28)")) -Message ("Driver details should explain code 28 and fall back to InstanceId: " + ($missingDriver.Detail -join "; "))

    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-sync-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    try {
        $historyFile = Join-Path $folder "home-history.json"
        Add-WinToolHomeHistory -Time ([datetime]::UtcNow) -Score 72 -Seconds 15 -Path $historyFile
        Set-WinToolHomeLatestHistory -Score 88 -Path $historyFile
        $entries = @(Read-WinToolHomeHistory -Path $historyFile)
        Test-WinToolExpectation -Condition ($entries.Count -eq 1 -and [int]$entries[0].Score -eq 88) -Message "Set-WinToolHomeLatestHistory should update the latest saved score in place."

        $bomFile = Join-Path $folder "with-bom.ps1"
        $plainFile = Join-Path $folder "no-bom.json"
        Write-WinToolUtf8File -Path $bomFile -Text "Write-Output 'ok'" -Bom
        Write-WinToolUtf8File -Path $plainFile -Text "{}"
        $bomBytes = [System.IO.File]::ReadAllBytes($bomFile)
        $plainBytes = [System.IO.File]::ReadAllBytes($plainFile)
        Test-WinToolExpectation -Condition ($bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF) -Message "Write-WinToolUtf8File -Bom should write a UTF-8 BOM for Windows PowerShell 5.1."
        Test-WinToolExpectation -Condition ($plainBytes[0] -ne 0xEF) -Message "Write-WinToolUtf8File without -Bom should write UTF-8 without BOM."

        $settingsFile = Join-Path $folder "settings.json"
        Write-WinToolUtf8File -Path $settingsFile -Text '{"orig":1}'
        Backup-WinToolTerminalSetting -Path $settingsFile
        Write-WinToolUtf8File -Path $settingsFile -Text '{"orig":2}'
        Backup-WinToolTerminalSetting -Path $settingsFile
        $backupText = [System.IO.File]::ReadAllText(($settingsFile + ".wintool-backup"))
        Test-WinToolExpectation -Condition ($backupText -eq '{"orig":1}') -Message "Backup-WinToolTerminalSetting keeps the original settings.json backup."

        # Junk collector skips locked files and symlinks, and clean measures actual freed bytes.
        $junkRoot = Join-Path $folder "junk"
        $outside = Join-Path $folder "outside"
        New-Item -ItemType Directory -Path $junkRoot, $outside -Force | Out-Null
        $outsideFile = Join-Path $outside "keep.txt"
        [System.IO.File]::WriteAllBytes($outsideFile, (New-Object byte[] 2048))
        [System.IO.File]::SetLastWriteTime($outsideFile, (Get-Date).AddDays(-5))
        $deletableFile = Join-Path $junkRoot "old.tmp"
        [System.IO.File]::WriteAllBytes($deletableFile, (New-Object byte[] 4096))
        [System.IO.File]::SetLastWriteTime($deletableFile, (Get-Date).AddDays(-5))
        $lockedFile = Join-Path $junkRoot "locked.tmp"
        [System.IO.File]::WriteAllBytes($lockedFile, (New-Object byte[] 8192))
        [System.IO.File]::SetLastWriteTime($lockedFile, (Get-Date).AddDays(-5))
        $linkDir = Join-Path $junkRoot "linked"
        try { New-Item -ItemType SymbolicLink -Path $linkDir -Target $outside -ErrorAction Stop | Out-Null } catch { $null = $_ }
        $lockStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $loc = [pscustomobject]@{ Id = "temp"; Name = "Stub"; Path = $junkRoot; Filter = "*"; Recurse = $true; MinAgeHours = 24 }
            $junkSync = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; Error = $null; Data = $null })
            & ([scriptblock]::Create((Get-WinToolHomeCheckScript -Id "junk"))) $junkSync @($loc)
            Test-WinToolExpectation -Condition ($junkSync.Ok -and [double]$junkSync.Data[0].Bytes -eq 4096) -Message ("Locked and symlinked files must not be counted as deletable, got " + [double]$junkSync.Data[0].Bytes)

            $cleanSync = [hashtable]::Synchronized(@{ Done = $false; Ok = $false; Error = $null; Data = $null })
            & ([scriptblock]::Create((Get-WinToolHomeCheckScript -Id "clean"))) $cleanSync @($loc)
            Test-WinToolExpectation -Condition ($cleanSync.Ok -and [double]$cleanSync.Data -eq 4096 -and -not (Test-Path -LiteralPath $deletableFile) -and (Test-Path -LiteralPath $outsideFile)) -Message "Home clean frees only unlocked non-reparse files and reports exact freed bytes."
        }
        finally {
            $lockStream.Dispose()
        }

        # Non-zero exit from prompt tools must not pass stdout error text into Invoke-Expression.
        $hostPath = (Get-Process -Id $PID).Path
        foreach ($tool in @("oh-my-posh", "starship", "zoxide")) {
            if (Test-WinToolWindows) {
                [System.IO.File]::WriteAllText((Join-Path $folder ($tool + ".cmd")), "@echo off`r`necho THIS IS NOT VALID POWERSHELL {{`r`nexit /b 1`r`n")
            }
            else {
                $stub = Join-Path $folder $tool
                [System.IO.File]::WriteAllText($stub, "#!/bin/sh`necho 'THIS IS NOT VALID POWERSHELL {{'`nexit 1`n")
                & chmod +x $stub
            }
        }
        $badProfile = Join-Path $folder "failing-init.ps1"
        Write-WinToolUtf8File -Path $badProfile -Text (Get-WinToolPromptScript -PromptId "oh-my-posh" -TerminalIcons $false -PromptStyle "jandedobbeleer" -PsReadLine $false -Zoxide $true) -Bom
        $sep = [string][System.IO.Path]::PathSeparator
        $probeLines = @(
            ('$env:PATH = "{0}" + $env:PATH' -f ($folder + $sep)),
            '$env:TERM = "xterm-256color"',
            '$Error.Clear()',
            ('. "{0}"' -f $badProfile),
            'foreach ($e in $Error) { "ERR: " + $e }',
            '"WINTOOL-NONZERO-OK"'
        )
        $encodedProbe = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes(($probeLines -join "`n")))
        $probeOut = ((& $hostPath -NoProfile -EncodedCommand $encodedProbe 2>&1) | ForEach-Object { [string]$_ }) -join "`n"
        Test-WinToolExpectation -Condition ($probeOut.Contains("WINTOOL-NONZERO-OK") -and -not $probeOut.Contains("ERR:")) -Message ("Non-zero tool exit caused profile errors: " + $probeOut)
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    $repairScript = Get-WinToolFixScript -Name "winget-repair"
    Test-WinToolExpectation -Condition ($repairScript.Contains('ContainsKey("AllowClobber")') -and -not $repairScript.Contains('-Force -AllowClobber')) -Message "winget-repair checks PowerShellGet parameters before passing AllowClobber on PS 5.1."

    $xaml = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "assets/MainWindow.xaml"))
    Test-WinToolExpectation -Condition ($xaml -match 'x:Name="DnsAdapter"[^>]*Style="\{StaticResource TerminalCombo\}"' -and $xaml -match 'x:Name="DnsProvider"[^>]*Style="\{StaticResource TerminalCombo\}"') -Message "Config ComboBoxes use the dark 34 px TerminalCombo style."
    $builder = [System.IO.File]::ReadAllText((Join-Path $script:WinToolRoot "build/Build-WinTool.ps1"))
    Test-WinToolExpectation -Condition ($builder.Contains('$script:WinToolSelfText = [string]$MyInvocation.MyCommand.ScriptBlock')) -Message "Built wintool.ps1 saves its own ScriptBlock text for irm | iex relaunches."
    Test-WinToolExpectation -Condition ($builder.Contains('$script:WinToolIcons')) -Message "The single-file build embeds the app icons."
}

Invoke-WinToolCase -Name "App icons are optional PNG files, never paths" -Body {
    $icons = 0
    $fallback = 0
    foreach ($category in @((Get-WinToolAppCatalog).categories)) {
        foreach ($app in @($category.apps)) {
            $icon = [string](Get-WinToolNote -Object $app -Name "icon" -Default "")
            if ([string]::IsNullOrWhiteSpace($icon)) {
                $fallback++
                continue
            }
            $icons++
            $data = Get-WinToolAppIconData -FileName $icon
            $png = ($null -ne $data -and $data.Length -gt 24 -and $data[0] -eq 137 -and $data[1] -eq 80 -and $data[2] -eq 78 -and $data[3] -eq 71)
            Test-WinToolExpectation -Condition $png -Message ("Icon " + $icon + " should be a PNG.")
        }
    }
    Test-WinToolExpectation -Condition ($icons -ge 100 -and $fallback -ge 1) -Message ("Expected mapped icons and letter tiles, got " + $icons + " icons and " + $fallback + " tiles.")
    Test-WinToolExpectation -Condition ($null -eq (Get-WinToolAppIconData -FileName "../apps.json")) -Message "Icon names cannot be paths."
    Test-WinToolExpectation -Condition ($null -eq (Get-WinToolAppIconData -FileName "missing.png")) -Message "A missing icon falls back to the letter tile."
    $savedRoot = $script:WinToolRoot
    $savedIcons = $script:WinToolIcons
    try {
        $script:WinToolRoot = $null
        $payload = [Convert]::ToBase64String([byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A))
        $script:WinToolIcons = @{ "embedded.png" = $payload }
        $embedded = Get-WinToolAppIconData -FileName "embedded.png"
        Test-WinToolExpectation -Condition ($null -ne $embedded -and $embedded.Length -eq 8 -and $embedded[0] -eq 137) -Message "Embedded icon bytes decode without the repo beside the script."
    }
    finally {
        $script:WinToolRoot = $savedRoot
        $script:WinToolIcons = $savedIcons
    }
}


Invoke-WinToolCase -Name "Hide startup banner patches every known terminal and can be undone" -Body {
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "PowerShell" -Source "Windows.Terminal.PowershellCore" -Commandline "") -eq "pwsh") -Message "Dynamic PowerShell 7 profiles are classified as pwsh."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Windows PowerShell" -Source "" -Commandline "powershell.exe") -eq "powershell") -Message "Windows PowerShell is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Command Prompt" -Source "" -Commandline "cmd.exe") -eq "cmd") -Message "Command Prompt is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Git Bash" -Source "" -Commandline "C:\Program Files\Git\bin\bash.exe -l -i") -eq "gitbash") -Message "Git Bash is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Developer Command Prompt" -Source "" -Commandline 'cmd.exe /k "C:\BuildTools\Common7\Tools\VsDevCmd.bat"') -eq "vsdev-cmd") -Message "The VS Developer Command Prompt is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Developer PowerShell" -Source "" -Commandline "powershell.exe -NoExit -Command Import-Module") -eq "vsdev-ps") -Message "The VS Developer PowerShell is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Ubuntu" -Source "Windows.Terminal.Wsl" -Commandline "") -eq "wsl") -Message "WSL profiles are classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Azure Cloud Shell" -Source "Windows.Terminal.Azure" -Commandline "") -eq "azure") -Message "Azure Cloud Shell is classified."
    Test-WinToolExpectation -Condition ((Get-WinToolTerminalBannerKind -Name "Python" -Source "" -Commandline "py.exe") -eq "other") -Message "Unknown profiles stay in the other bucket."
    Test-WinToolExpectation -Condition ((Add-WinToolCommandToken -Commandline "pwsh.exe -NoExit" -Token "-NoLogo") -eq "pwsh.exe -NoLogo -NoExit") -Message "-NoLogo is inserted after the executable."
    Test-WinToolExpectation -Condition ((Add-WinToolCommandToken -Commandline "pwsh.exe -NoLogo" -Token "-NoLogo") -eq "pwsh.exe -NoLogo") -Message "Adding -NoLogo a second time is a no-op."
    Test-WinToolExpectation -Condition ((Add-WinToolCmdClearCommand -Commandline "cmd.exe") -eq "cmd.exe /k cls") -Message "cmd.exe gets /k cls."
    Test-WinToolExpectation -Condition ((Add-WinToolCmdClearCommand -Commandline "cmd.exe /k echo hi") -eq "cmd.exe /k cls & echo hi") -Message "An existing /k command keeps running after cls."
    Test-WinToolExpectation -Condition ((Add-WinToolCmdClearCommand -Commandline "cmd.exe /k cls") -eq "cmd.exe /k cls") -Message "cmd.exe /k cls is left as is."
    $vs = Add-WinToolVsDevNoLogo -Commandline 'cmd.exe /k "C:\BuildTools\Common7\Tools\VsDevCmd.bat"'
    Test-WinToolExpectation -Condition ($vs -eq 'cmd.exe /k "C:\BuildTools\Common7\Tools\VsDevCmd.bat -no_logo"') -Message "VsDevCmd.bat gets -no_logo inside its quoted command."

    $text = @'
{
  // user comment
  "profiles": {
    "defaults": { "font": { "face": "Fira Code" } },
    "list": [
      { "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" },
      { "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell", "commandline": "powershell.exe" },
      { "name": "Ubuntu", "source": "Windows.Terminal.Wsl" },
      { "name": "Command Prompt", "commandline": "cmd.exe" },
      { "name": "Git Bash", "commandline": "C:\\Program Files\\Git\\bin\\bash.exe -l -i" },
      { "name": "Developer Command Prompt", "commandline": "cmd.exe /k \"C:\\BuildTools\\Common7\\Tools\\VsDevCmd.bat\"" },
      { "name": "Developer PowerShell", "commandline": "powershell.exe -NoExit -Command \"Import-Module Foo\"" },
      { "name": "Azure Cloud Shell", "source": "Windows.Terminal.Azure" },
      { "name": "Python", "commandline": "py.exe" },
      { "name": "Already quiet", "commandline": "pwsh.exe -NoLogo -NoExit" }
    ]
  }
}
'@
    $first = Update-WinToolTerminalBannerText -Text $text
    Test-WinToolExpectation -Condition ($first.Text.Contains("// user comment")) -Message "Comments in settings.json are kept."
    Test-WinToolExpectation -Condition ($first.Changed -eq $true) -Message "The first apply changes settings.json."
    $settings = ConvertFrom-WinToolJsonText -Text $first.Text
    $list = @($settings.profiles.list)
    $byName = @{}
    foreach ($item in $list) { $byName[[string]$item.name] = $item }
    Test-WinToolExpectation -Condition ([string]$byName["PowerShell"].commandline -eq "pwsh.exe -NoLogo") -Message "A dynamic PowerShell 7 profile gets pwsh.exe -NoLogo."
    Test-WinToolExpectation -Condition ([string]$byName["Windows PowerShell"].commandline -eq "powershell.exe -NoLogo") -Message "Windows PowerShell gets -NoLogo."
    Test-WinToolExpectation -Condition ($null -eq $byName["Ubuntu"].PSObject.Properties["commandline"]) -Message "WSL profiles do not get a commandline override."
    Test-WinToolExpectation -Condition ([string]$byName["Command Prompt"].commandline -eq "cmd.exe /k cls") -Message "Command Prompt starts with cls."
    Test-WinToolExpectation -Condition ([string]$byName["Git Bash"].commandline -eq "C:\Program Files\Git\bin\bash.exe -l -i") -Message "Git Bash keeps its command line."
    Test-WinToolExpectation -Condition ([string]$byName["Developer Command Prompt"].commandline -like "*VsDevCmd.bat -no_logo*") -Message "The VS Developer Command Prompt gets -no_logo."
    Test-WinToolExpectation -Condition ([string]$byName["Developer PowerShell"].commandline -like "powershell.exe -NoLogo*") -Message "The VS Developer PowerShell gets -NoLogo."
    Test-WinToolExpectation -Condition ($null -eq $byName["Azure Cloud Shell"].PSObject.Properties["commandline"]) -Message "Azure Cloud Shell is not given a command line."
    Test-WinToolExpectation -Condition ([string]$byName["Python"].commandline -eq "py.exe") -Message "Unknown profiles are left unchanged."
    Test-WinToolExpectation -Condition ([string]$byName["Already quiet"].commandline -eq "pwsh.exe -NoLogo -NoExit") -Message "A profile that already has -NoLogo is left as is."
    $log = @($first.Log)
    Test-WinToolExpectation -Condition (@($log | Where-Object { $_ -match "Azure Cloud Shell" }).Count -ge 1) -Message "Azure Cloud Shell is mentioned in the log."
    Test-WinToolExpectation -Condition (@($log | Where-Object { $_ -match "Python" }).Count -ge 1) -Message "Unknown profiles are mentioned in the log."
    $second = Update-WinToolTerminalBannerText -Text $first.Text
    Test-WinToolExpectation -Condition ($second.Changed -eq $false -and $second.Text -eq $first.Text) -Message "A second apply is a no-op and keeps the same text."
    $undone = Update-WinToolTerminalBannerText -Text $first.Text -Undo -Change $first.Change
    Test-WinToolExpectation -Condition ($undone.Text.Contains("// user comment")) -Message "Undo keeps comments."
    $restored = ConvertFrom-WinToolJsonText -Text $undone.Text
    $restoredList = @{}
    foreach ($item in @($restored.profiles.list)) { $restoredList[[string]$item.name] = $item }
    Test-WinToolExpectation -Condition ($null -eq $restoredList["PowerShell"].PSObject.Properties["commandline"]) -Message "Undo removes a commandline WinTool added."
    Test-WinToolExpectation -Condition ([string]$restoredList["Windows PowerShell"].commandline -eq "powershell.exe") -Message "Undo restores the previous PowerShell command line."
    Test-WinToolExpectation -Condition ([string]$restoredList["Command Prompt"].commandline -eq "cmd.exe") -Message "Undo restores Command Prompt."
    Test-WinToolExpectation -Condition ([string]$restoredList["Python"].commandline -eq "py.exe") -Message "Undo leaves unknown profiles alone."

    $empty = @'
{
  // only defaults
  "profiles": { "defaults": {}, "list": [] }
}
'@
    $added = Update-WinToolTerminalBannerText -Text $empty
    Test-WinToolExpectation -Condition ($added.Text.Contains("// only defaults") -and $added.Text.Contains("Windows.Terminal.PowershellCore") -and $added.Text.Contains("Windows.Terminal.WindowsPowerShell")) -Message "Missing PowerShell profiles get source overrides and comments stay."
    $addedBack = Update-WinToolTerminalBannerText -Text $added.Text -Undo -Change $added.Change
    $addedSettings = ConvertFrom-WinToolJsonText -Text $addedBack.Text
    Test-WinToolExpectation -Condition (@($addedSettings.profiles.list).Count -eq 0) -Message "Undo removes source overrides WinTool added."

    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-banner-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    try {
        $settingsFile = Join-Path $folder "settings.json"
        $stateFile = Join-Path $folder "banner-state.json"
        $profileHome = Join-Path $folder "home"
        New-Item -ItemType Directory -Path $profileHome -Force | Out-Null
        Write-WinToolUtf8File -Path $settingsFile -Text $text
        Invoke-WinToolTerminalBanner -SettingsPath @($settingsFile) -StatePath $stateFile -HomePath $profileHome -SkipShortcuts -SkipWsl
        $onDisk = [System.IO.File]::ReadAllText($settingsFile)
        Test-WinToolExpectation -Condition ($onDisk.Contains("powershell.exe -NoLogo") -and $onDisk.Contains("// user comment")) -Message "Invoke-WinToolTerminalBanner writes a JSONC-preserving settings.json."
        Test-WinToolExpectation -Condition (Test-Path -LiteralPath (Join-Path $profileHome ".hushlogin")) -Message "A .hushlogin file is created in the user profile."
        Invoke-WinToolTerminalBanner -SettingsPath @($settingsFile) -StatePath $stateFile -HomePath $profileHome -SkipShortcuts -SkipWsl
        Test-WinToolExpectation -Condition ([System.IO.File]::ReadAllText($settingsFile) -eq $onDisk) -Message "A second file apply does not rewrite settings.json."
        Invoke-WinToolTerminalBanner -Undo -SettingsPath @($settingsFile) -StatePath $stateFile -HomePath $profileHome -SkipShortcuts -SkipWsl
        $afterUndo = [System.IO.File]::ReadAllText($settingsFile)
        $afterSettings = ConvertFrom-WinToolJsonText -Text $afterUndo
        $cmd = @($afterSettings.profiles.list | Where-Object { $_.name -eq "Command Prompt" })[0]
        Test-WinToolExpectation -Condition ([string]$cmd.commandline -eq "cmd.exe" -and $afterUndo.Contains("// user comment")) -Message "A file undo restores command lines and keeps comments."
        Test-WinToolExpectation -Condition (-not (Test-Path -LiteralPath (Join-Path $profileHome ".hushlogin"))) -Message "Undo removes a .hushlogin file WinTool created."
        New-Item -ItemType File -Path (Join-Path $profileHome ".hushlogin") -Force | Out-Null
        Invoke-WinToolTerminalBanner -SettingsPath @($settingsFile) -StatePath $stateFile -HomePath $profileHome -SkipShortcuts -SkipWsl
        Invoke-WinToolTerminalBanner -Undo -SettingsPath @($settingsFile) -StatePath $stateFile -HomePath $profileHome -SkipShortcuts -SkipWsl
        Test-WinToolExpectation -Condition (Test-Path -LiteralPath (Join-Path $profileHome ".hushlogin")) -Message "Undo leaves a pre-existing .hushlogin file alone."
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    $simple = Get-WinToolSimpleTerminalChoice
    Test-WinToolExpectation -Condition ($simple.hideStartupBanner -eq $true) -Message "The recommended setup hides the startup banner."
    $steps = @(Get-WinToolTerminalPlan -Selection $simple)
    Test-WinToolExpectation -Condition ((@($steps | Where-Object { $_.Type -eq "banner" -and -not $_.Undo }).Count) -eq 1) -Message "The terminal plan includes a banner step."
    $legacy = [pscustomobject]@{ prompt = "oh-my-posh"; promptStyle = "jandedobbeleer"; fontId = $simple.fontId; schemeId = $simple.schemeId }
    Test-WinToolExpectation -Condition ((Test-WinToolHideStartupBanner -Selection $legacy) -eq $true) -Message "An older saved profile that omits the flag still hides the banner."
    $quietOff = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "oh-my-posh"; PromptStyle = "jandedobbeleer"; HideStartupBanner = $false })
    Test-WinToolExpectation -Condition ($quietOff.Contains("export WINTOOL_HUSHLOGIN='0'")) -Message "WSL setup can turn off ~/.hushlogin."
    $quietOn = Get-WinToolWslSetupText -Step ([pscustomobject]@{ Variant = "oh-my-posh"; PromptStyle = "jandedobbeleer" })
    Test-WinToolExpectation -Condition ($quietOn.Contains("export WINTOOL_HUSHLOGIN='1'")) -Message "WSL setup hides the MOTD by default."
    Test-WinToolExpectation -Condition ((Get-WinToolShortcutBannerArgument -Kind "powershell" -Arguments "-NoExit") -eq "-NoLogo -NoExit") -Message "Start menu PowerShell shortcuts get -NoLogo."
    Test-WinToolExpectation -Condition ((Get-WinToolShortcutBannerArgument -Kind "cmd" -Arguments "") -eq "/k cls") -Message "Start menu Command Prompt shortcuts get /k cls."
}


Invoke-WinToolCase -Name "Package cache, chips, and apply skip already-installed steps" -Body {
    Reset-WinToolPackageCache | Out-Null
    $choice = Get-WinToolSimpleTerminalChoice
    $choice.zoxide = $true
    $choice.fzf = $true
    $choice.terminalIcons = $true
    $choice.psReadLine = $true
    $steps = @(Get-WinToolTerminalPlan -Selection $choice)
    $wt = @($steps | Where-Object { $_.Type -eq "winget" -and $_.Label -eq "Install Windows Terminal" })[0]
    $font = @($steps | Where-Object { $_.Type -eq "font-download" })[0]
    $icons = @($steps | Where-Object { $_.Type -eq "module" -and $_.Name -eq "Terminal-Icons" -and $_.Host -eq "powershell" })[0]
    $psrl = @($steps | Where-Object { $_.Type -eq "module" -and $_.Name -eq "PSReadLine" })[0]
    Test-WinToolExpectation -Condition (-not [string]::IsNullOrWhiteSpace([string]$wt.WingetId) -and -not [string]::IsNullOrWhiteSpace([string]$font.FontId)) -Message "Plan steps include winget ids and font ids."

    $pending = Get-WinToolPlanStepDecision -Step $wt -Cache (New-WinToolPackageCache)
    Test-WinToolExpectation -Condition ([bool]$pending.Run -and [string]$pending.Outcome -eq "install") -Message "A package is installed when detection has not finished."

    $cache = New-WinToolPackageCache
    $cache.WingetReady = $true
    $cache.InstalledId = New-WinToolIdSet -Id @([string]$wt.WingetId, "JanDeDobbeleer.OhMyPosh", "ajeetdsouza.zoxide")
    $cache.UpdateId = New-WinToolIdSet -Id @("ajeetdsouza.zoxide")
    $cache.Font = @{ ([string]$font.FontId.ToLowerInvariant()) = $true }
    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-modcache-" + [guid]::NewGuid().ToString("N"))
    $ps51 = Join-Path $folder "WindowsPowerShell\Modules"
    $pwsh = Join-Path $folder "PowerShell\Modules"
    New-Item -ItemType Directory -Path (Join-Path $ps51 "Terminal-Icons\0.3.0") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ps51 "Terminal-Icons\0.3.0\Terminal-Icons.psd1") -Value "@{ ModuleVersion = '0.3.0' }" -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $ps51 "PSReadLine\2.0.0") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $ps51 "PSReadLine\2.0.0\PSReadLine.psd1") -Value "@{ ModuleVersion = '2.0.0' }" -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $pwsh "Terminal-Icons\0.3.0") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pwsh "Terminal-Icons\0.3.0\Terminal-Icons.psd1") -Value "@{ ModuleVersion = '0.3.0' }" -Encoding UTF8
    $themeFolder = Join-Path $folder "themes"
    New-Item -ItemType Directory -Path $themeFolder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $themeFolder "jandedobbeleer.omp.json") -Value "{}" -Encoding UTF8
    try {
        Update-WinToolLocalPackageCache -ModuleRoot @(
            [pscustomobject]@{ Host = "powershell"; Path = $ps51 },
            [pscustomobject]@{ Host = "pwsh"; Path = $pwsh }
        ) -ThemeFolder $themeFolder | Out-Null
        $cache.Module = (Get-WinToolPackageCache).Module
        $cache.Theme = (Get-WinToolPackageCache).Theme
        Test-WinToolExpectation -Condition (Test-WinToolCachedModule -Name "Terminal-Icons" -HostName "powershell" -Cache $cache) -Message "Terminal-Icons 0.3 is present for Windows PowerShell."
        Test-WinToolExpectation -Condition (-not (Test-WinToolCachedModule -Name "PSReadLine" -HostName "powershell" -Cache $cache)) -Message "PSReadLine 2.0 is too old and still needs an update."
        New-Item -ItemType Directory -Path (Join-Path $ps51 "PSReadLine\2.3.6") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $ps51 "PSReadLine\2.3.6\PSReadLine.psd1") -Value "@{ ModuleVersion = '2.3.6' }" -Encoding UTF8
        Update-WinToolLocalPackageCache -ModuleRoot @([pscustomobject]@{ Host = "powershell"; Path = $ps51 }, [pscustomobject]@{ Host = "pwsh"; Path = $pwsh }) -ThemeFolder $themeFolder | Out-Null
        $cache.Module = (Get-WinToolPackageCache).Module
        Test-WinToolExpectation -Condition (Test-WinToolCachedModule -Name "PSReadLine" -HostName "powershell" -Cache $cache) -Message "PSReadLine 2.3.6 meets the minimum version."
        Test-WinToolExpectation -Condition (Test-WinToolCachedTheme -FileName "jandedobbeleer.omp.json" -Cache $cache) -Message "A saved Oh My Posh theme is visible in the cache."

        $skipWt = Get-WinToolPlanStepDecision -Step $wt -Cache $cache
        Test-WinToolExpectation -Condition ((-not [bool]$skipWt.Run) -and [string]$skipWt.Outcome -eq "already-had") -Message "Apply skips Windows Terminal when it is already installed."
        $zoxide = @($steps | Where-Object { $_.Type -eq "winget" -and $_.Label -eq "Install zoxide" })[0]
        $applyZ = Get-WinToolPlanStepDecision -Step $zoxide -Cache $cache
        $updateZ = Get-WinToolPlanStepDecision -Step $zoxide -Cache $cache -Update
        Test-WinToolExpectation -Condition ((-not [bool]$applyZ.Run) -and [bool]$updateZ.Run -and [string]$updateZ.Action -eq "upgrade") -Message "Update upgrades zoxide when winget lists a newer version."
        $skipFont = Get-WinToolPlanStepDecision -Step $font -Cache $cache
        $updateFont = Get-WinToolPlanStepDecision -Step $font -Cache $cache -Update
        Test-WinToolExpectation -Condition ((-not [bool]$skipFont.Run) -and (-not [bool]$updateFont.Run)) -Message "A present font is not re-downloaded on Apply or Update."
        $skipIcons = Get-WinToolPlanStepDecision -Step $icons -Cache $cache
        $updateIcons = Get-WinToolPlanStepDecision -Step $icons -Cache $cache -Update
        Test-WinToolExpectation -Condition ((-not [bool]$skipIcons.Run) -and [bool]$updateIcons.Run -and [string]$updateIcons.Outcome -eq "update") -Message "Apply skips Terminal-Icons; Update refreshes it."
        $skipPsrl = Get-WinToolPlanStepDecision -Step $psrl -Cache $cache
        Test-WinToolExpectation -Condition ((-not [bool]$skipPsrl.Run) -and [string]$skipPsrl.Outcome -eq "already-had") -Message "Apply skips PSReadLine once a new enough version is present."

        $chips = @(Get-WinToolSummaryChip -Step $steps -Cache $cache -ConfigNeed @{ font = $false; ligatures = $false; scheme = $false; banner = $true; profile = $false })
        $adds = @($chips | Where-Object { $_.Kind -eq "add" } | ForEach-Object { [string]$_.Text })
        $haves = @($chips | Where-Object { $_.Kind -eq "have" } | ForEach-Object { [string]$_.Text })
        $sets = @($chips | Where-Object { $_.Kind -eq "set" } | ForEach-Object { [string]$_.Text })
        $changes = @($chips | Where-Object { $_.Kind -eq "change" } | ForEach-Object { [string]$_.Text })
        Test-WinToolExpectation -Condition ($haves -contains "Windows Terminal" -and $haves -contains "zoxide" -and $haves -contains "Terminal-Icons" -and $adds -notcontains "Windows Terminal") -Message ("Already-installed chips: " + ($haves -join ", "))
        Test-WinToolExpectation -Condition ($adds -contains "PowerShell 7" -or $adds -contains "fzf") -Message ("Missing packages still show a + chip: " + ($adds -join ", "))
        Test-WinToolExpectation -Condition ($sets -contains "Terminal font" -and $sets -contains "Font ligatures on" -and $sets -contains "Scheme Night" -and $sets -contains "PowerShell `$PROFILE") -Message ("Already-set chips: " + ($sets -join ", "))
        Test-WinToolExpectation -Condition ($changes -contains "Startup banner hidden" -and $changes -notcontains "Scheme Night") -Message ("Change chips when some settings already match: " + ($changes -join ", "))

        $updateChips = @(Get-WinToolSummaryChip -Step $steps -Cache $cache -Update -ConfigNeed @{ font = $false; ligatures = $false; scheme = $false; banner = $true; profile = $false })
        $updates = @($updateChips | Where-Object { $_.Kind -eq "update" } | ForEach-Object { [string]$_.Text })
        Test-WinToolExpectation -Condition ($updates -contains "zoxide" -and $updates -contains "Terminal-Icons") -Message ("Update chips: " + ($updates -join ", "))
    }
    finally {
        Reset-WinToolPackageCache | Out-Null
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    $tally = New-WinToolPlanTally
    Add-WinToolPlanTally -Tally $tally -Bucket "Installed" -Name "PowerShell 7"
    Add-WinToolPlanTally -Tally $tally -Bucket "AlreadyHad" -Name "Windows Terminal"
    Add-WinToolPlanTally -Tally $tally -Bucket "AlreadyHad" -Name "Oh My Posh"
    Add-WinToolPlanTally -Tally $tally -Bucket "Updated" -Name "zoxide"
    Add-WinToolPlanTally -Tally $tally -Bucket "ConfigChanged" -Name "Scheme Night"
    Add-WinToolPlanTally -Tally $tally -Bucket "ConfigUnchanged" -Name "Font ligatures on"
    $summary = Format-WinToolPlanSummary -Tally $tally
    Test-WinToolExpectation -Condition ($summary -like "Installed PowerShell 7.*" -and $summary -like "*Already had Windows Terminal and Oh My Posh.*" -and $summary -like "*Updated zoxide.*" -and $summary -like "*Updated settings: Scheme Night.*" -and $summary -like "*Already set Font ligatures on.*") -Message ("Plan summary: " + $summary)

    $ids = @(Get-WinToolTerminalWingetId)
    Test-WinToolExpectation -Condition ($ids.Count -ge 3) -Message "Terminal component winget ids are listed for cache updates."
}

Invoke-WinToolCase -Name "JSONC writers keep comments and skip unchanged Terminal settings and profiles" -Body {
    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-jsonc-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $settingsFile = Join-Path $folder "settings.json"
    $profileFile = Join-Path $folder "Microsoft.PowerShell_profile.ps1"
    $source = @'
{
    // user comment
    "profiles": {
        "defaults": {
            "colorScheme": "Campbell"
        }
        // keep defaults
    },
    "schemes": [
        // keep schemes
    ]
}
'@
    [System.IO.File]::WriteAllText($settingsFile, $source)
    try {
        $fontChanged = Invoke-WinToolTerminalFont -Face "CaskaydiaCove Nerd Font" -Size 12 -SettingsPath @($settingsFile)
        $afterFont = [System.IO.File]::ReadAllText($settingsFile)
        $fontSettings = ConvertFrom-WinToolJsonText -Text $afterFont
        Test-WinToolExpectation -Condition ([bool]$fontChanged -and [string]$fontSettings.profiles.defaults.font.face -eq "CaskaydiaCove Nerd Font" -and [int]$fontSettings.profiles.defaults.font.size -eq 12) -Message "The font writer sets face and size."
        Test-WinToolExpectation -Condition ($afterFont.Contains("// user comment") -and $afterFont.Contains("// keep defaults")) -Message "The font writer keeps comments in settings.json."
        $fontAgain = Invoke-WinToolTerminalFont -Face "CaskaydiaCove Nerd Font" -Size 12 -SettingsPath @($settingsFile)
        Test-WinToolExpectation -Condition ((-not [bool]$fontAgain) -and [System.IO.File]::ReadAllText($settingsFile) -eq $afterFont) -Message "A second font apply does not rewrite settings.json."

        $ligaChanged = Invoke-WinToolTerminalLigature -SettingsPath @($settingsFile)
        $afterLiga = [System.IO.File]::ReadAllText($settingsFile)
        $ligaSettings = ConvertFrom-WinToolJsonText -Text $afterLiga
        Test-WinToolExpectation -Condition ([bool]$ligaChanged -and [int]$ligaSettings.profiles.defaults.font.features.calt -eq 1 -and [int]$ligaSettings.profiles.defaults.font.features.liga -eq 1) -Message "The ligature writer sets calt and liga."
        Test-WinToolExpectation -Condition ($afterLiga.Contains("// user comment") -and $afterLiga.Contains("// keep defaults")) -Message "The ligature writer keeps comments in settings.json."
        $ligaAgain = Invoke-WinToolTerminalLigature -SettingsPath @($settingsFile)
        Test-WinToolExpectation -Condition ((-not [bool]$ligaAgain) -and [System.IO.File]::ReadAllText($settingsFile) -eq $afterLiga) -Message "A second ligature apply does not rewrite settings.json."

        $schemeChanged = Invoke-WinToolTerminalScheme -SchemeId "wintool-night" -SettingsPath @($settingsFile)
        $afterScheme = [System.IO.File]::ReadAllText($settingsFile)
        $schemeSettings = ConvertFrom-WinToolJsonText -Text $afterScheme
        Test-WinToolExpectation -Condition ([bool]$schemeChanged -and [string]$schemeSettings.profiles.defaults.colorScheme -eq "Night") -Message "The scheme writer sets the default color scheme."
        Test-WinToolExpectation -Condition ($afterScheme.Contains("// user comment") -and $afterScheme.Contains("// keep schemes") -and $afterScheme.Contains("// keep defaults")) -Message "The scheme writer keeps comments in settings.json."
        $schemeAgain = Invoke-WinToolTerminalScheme -SchemeId "wintool-night" -SettingsPath @($settingsFile)
        Test-WinToolExpectation -Condition ((-not [bool]$schemeAgain) -and [System.IO.File]::ReadAllText($settingsFile) -eq $afterScheme) -Message "A second scheme apply does not rewrite settings.json."

        $empty = Join-Path $folder "empty.json"
        [System.IO.File]::WriteAllText($empty, "{`n    // only comment`n}`n")
        $fromEmpty = Invoke-WinToolTerminalScheme -SchemeId "wintool-night" -SettingsPath @($empty)
        $emptyText = [System.IO.File]::ReadAllText($empty)
        Test-WinToolExpectation -Condition ([bool]$fromEmpty -and $emptyText.Contains("// only comment") -and $emptyText.Contains('"colorScheme": "Night"')) -Message "A scheme can be added to a nearly empty settings file without dropping comments."

        $body = Get-WinToolPromptScript -PromptId "oh-my-posh" -TerminalIcons $true -PromptStyle "jandedobbeleer" -PsReadLine $true -Zoxide $true
        $first = Write-WinToolShellProfile -PromptId "starship" -TerminalIcons $false -PromptStyle "tokyo-night" -PsReadLine $false -Zoxide $false -ProfilePath @($profileFile)
        $written = [System.IO.File]::ReadAllText($profileFile)
        Test-WinToolExpectation -Condition ([bool]$first -and $written.Contains($script:WinToolProfileBegin) -and $written.Contains("starship")) -Message "The profile writer creates a managed block."
        $stamp = [System.IO.File]::GetLastWriteTimeUtc($profileFile)
        Start-Sleep -Milliseconds 20
        $second = Write-WinToolShellProfile -PromptId "starship" -TerminalIcons $false -PromptStyle "tokyo-night" -PsReadLine $false -Zoxide $false -ProfilePath @($profileFile)
        Test-WinToolExpectation -Condition ((-not [bool]$second) -and [System.IO.File]::ReadAllText($profileFile) -eq $written -and [System.IO.File]::GetLastWriteTimeUtc($profileFile) -eq $stamp) -Message "A second profile apply is a no-op when the managed block already matches."
        Test-WinToolExpectation -Condition (Test-WinToolTextNeedsManagedBlock -Text $written -Body $body) -Message "A different prompt body is detected as a needed profile change."
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-WinToolCase -Name "Install view bulk Install skips apps that are already installed" -Body {
    $pendingApp = [pscustomobject]@{ Name = "Firefox"; WingetId = "Mozilla.Firefox"; Installed = $false }
    $installedApp = [pscustomobject]@{ Name = "Visual Studio Code"; WingetId = "Microsoft.VisualStudioCode"; Installed = $true }
    $beforeDetect = Select-WinToolInstallApp -App @($pendingApp, $installedApp) -Detected $false
    Test-WinToolExpectation -Condition (@($beforeDetect.Pending).Count -eq 2 -and @($beforeDetect.Already).Count -eq 0) -Message "Before detection finishes, every selected app is still installed."
    $afterDetect = Select-WinToolInstallApp -App @($pendingApp, $installedApp) -Detected $true
    Test-WinToolExpectation -Condition (@($afterDetect.Pending).Count -eq 1 -and [string]$afterDetect.Pending[0].WingetId -eq "Mozilla.Firefox" -and @($afterDetect.Already).Count -eq 1) -Message "After detection, already installed apps are split out so Install can point the user to Update."
    $onlyInstalled = Select-WinToolInstallApp -App @($installedApp) -Detected $true
    Test-WinToolExpectation -Condition (@($onlyInstalled.Pending).Count -eq 0 -and @($onlyInstalled.Already).Count -eq 1) -Message "Install with only already-installed apps has nothing left to install."
}


Invoke-WinToolCase -Name "Driver hardware IDs match exactly and by a more general prefix" -Body {
    $deviceIds = @("PCI\VEN_10EC&DEV_8168&SUBSYS_1234ABCD&REV_15", "PCI\VEN_10EC&DEV_8168")
    Test-WinToolExpectation -Condition (Test-WinToolHardwareIdMatch -DeviceId $deviceIds -UpdateId @("PCI\VEN_10EC&DEV_8168")) -Message "A shorter Windows Update hardware ID matches the device."
    Test-WinToolExpectation -Condition (Test-WinToolHardwareIdMatch -DeviceId $deviceIds -UpdateId @("pci\ven_10ec&dev_8168&subsys_1234abcd&rev_15")) -Message "An exact hardware ID match is case-insensitive."
    Test-WinToolExpectation -Condition (-not (Test-WinToolHardwareIdMatch -DeviceId $deviceIds -UpdateId @("PCI\VEN_10EC&DEV_8169"))) -Message "A different device ID does not match."
    Test-WinToolExpectation -Condition (-not (Test-WinToolHardwareIdMatch -DeviceId @("PCI\VEN_10EC&DEV_8168") -UpdateId @("PCI\VEN_10EC&DEV_8168&SUBSYS_1234ABCD"))) -Message "A more specific update ID does not match a shorter device ID."
}

Invoke-WinToolCase -Name "Driver scan results are classified from mocked device and Windows Update data" -Body {
    $cache = New-WinToolPackageCache
    $outdated = New-WinToolDriverDeviceRecord -Name "Realtek Gaming 2.5GbE Family Controller" -Class "Net" -InstanceId "PCI\VEN_10EC&DEV_8168&SUBSYS_1234ABCD&REV_15" -Version "1.0.0.0" -Provider "Realtek" -Date ([datetime]"2023-01-15") -HardwareId @("PCI\VEN_10EC&DEV_8168&SUBSYS_1234ABCD&REV_15", "PCI\VEN_10EC&DEV_8168")
    $current = New-WinToolDriverDeviceRecord -Name "AMD Ryzen 5 5600X" -Class "Processor" -InstanceId "ACPI\ACPI0007\0" -Version "10.0.1.1" -Provider "Microsoft" -Date ([datetime]"2024-04-08") -HardwareId @("ACPI\ACPI0007")
    $missingCode = New-WinToolDriverDeviceRecord -Name "USB Audio Device" -Class "Media" -InstanceId "USB\VID_1234&PID_5678\1" -Problem 28 -HardwareId @("USB\VID_1234&PID_5678")
    $notConfigured = New-WinToolDriverDeviceRecord -Name "New PCI Device" -Class "Net" -InstanceId "PCI\VEN_8086&DEV_0001\1" -Problem 1 -HardwareId @("PCI\VEN_8086&DEV_0001")
    $noDriver = New-WinToolDriverDeviceRecord -Name "Generic NVMe Disk" -Class "SCSIAdapter" -InstanceId "NVME\VEN_15B7&DEV_500E\1" -HardwareId @("NVME\VEN_15B7&DEV_500E")
    $software = New-WinToolDriverDeviceRecord -Name "Microsoft Software Device" -Class "SoftwareDevice" -InstanceId "SWD\GENERIC\1"
    $rootDevice = New-WinToolDriverDeviceRecord -Name "Root enumerator" -Class "System" -InstanceId "ROOT\VOLMGR\0000"
    $disabled = New-WinToolDriverDeviceRecord -Name "Disabled NIC" -Class "Net" -InstanceId "PCI\VEN_10EC&DEV_0002\1" -Problem 22 -Version "1.0" -Provider "Realtek"
    $ghost = New-WinToolDriverDeviceRecord -Name "Old USB stick" -Class "USB" -InstanceId "USB\VID_AAAA&PID_BBBB\OLD" -Problem 45 -Present $false
    $failed = New-WinToolDriverDeviceRecord -Name "Broken display" -Class "Display" -InstanceId "PCI\VEN_1002&DEV_73FF\1" -Problem 43 -Version "1.0" -Provider "AMD" -HardwareId @("PCI\VEN_1002&DEV_73FF")
    $blocked = New-WinToolDriverDeviceRecord -Name "Unsigned gadget" -Class "USB" -InstanceId "USB\VID_1111&PID_2222\1" -Problem 52 -Version "1.0" -Provider "Contoso"
    $offer = New-WinToolDriverUpdateRecord -Title "Realtek Gaming 2.5GbE Family Controller - Network" -Model "Realtek Gaming 2.5GbE Family Controller" -Version "1.2.0.0" -Date ([datetime]"2024-04-08") -HardwareId @("PCI\VEN_10EC&DEV_8168")
    $same = New-WinToolDriverUpdateRecord -Title "Processor" -Version "10.0.1.1" -HardwareId @("ACPI\ACPI0007")

    Test-WinToolExpectation -Condition (Test-WinToolDriverMissing -Device $missingCode) -Message "Error code 28 is a missing driver."
    Test-WinToolExpectation -Condition (Test-WinToolDriverMissing -Device $notConfigured) -Message "Error code 1 is a missing driver."
    Test-WinToolExpectation -Condition (Test-WinToolDriverMissing -Device $noDriver) -Message "A likely hardware device with no signed driver is missing."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $software)) -Message "Software devices are not treated as missing."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $rootDevice)) -Message "ROOT devices are not treated as missing."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $disabled)) -Message "A disabled device is not treated as missing."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $ghost)) -Message "A device that is not present is not treated as missing."

    $rootCode28 = New-WinToolDriverDeviceRecord -Name "Volume manager" -Class "System" -InstanceId "ROOT\VOLMGR\0000" -Problem 28
    $swdCode1 = New-WinToolDriverDeviceRecord -Name "Audio endpoint" -Class "SoftwareDevice" -InstanceId "SWD\MMDEVAPI\{0.0.0.00000000}" -Problem 1
    $htree = New-WinToolDriverDeviceRecord -Name "Device tree" -Class "System" -InstanceId "HTREE\ROOT\0" -Problem 28
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $rootCode28)) -Message "A ROOT device with error code 28 is not treated as a missing driver."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $swdCode1)) -Message "A SWD software device with error code 1 is not treated as a missing driver."
    Test-WinToolExpectation -Condition (-not (Test-WinToolDriverMissing -Device $htree)) -Message "An HTREE leftover entry is not treated as a missing driver."
    Test-WinToolExpectation -Condition ([string](Get-WinToolDriverDeviceGroup -Device $rootCode28 -Update @()).Group -ne "missing") -Message "ROOT devices with a problem code stay out of the missing group."

    $outdatedGroup = Get-WinToolDriverDeviceGroup -Device $outdated -Update @($offer, $same)
    $currentGroup = Get-WinToolDriverDeviceGroup -Device $current -Update @($offer, $same)
    $ghostGroup = Get-WinToolDriverDeviceGroup -Device $ghost -Update @()
    Test-WinToolExpectation -Condition ([string]$outdatedGroup.Group -eq "outdated" -and [string]$outdatedGroup.Offer.Version -eq "1.2.0.0") -Message "A device with an older version is outdated and keeps the matched update."
    Test-WinToolExpectation -Condition ([string]$currentGroup.Group -eq "current") -Message "A device that already has the offered version is up to date."
    Test-WinToolExpectation -Condition ([string]$ghostGroup.Group -eq "ghost") -Message "A non-present device is classified as a leftover entry."

    $rows = @(Group-WinToolDriverRow -Device @($outdated, $current, $missingCode, $notConfigured, $noDriver, $software, $rootDevice, $disabled, $ghost, $failed, $blocked) -Update @($offer, $same) -Runtime @() -GpuName @() -Cache $cache)
    $byGroup = @{}
    foreach ($row in $rows) {
        $key = [string]$row.Group
        if (-not $byGroup.ContainsKey($key)) { $byGroup[$key] = 0 }
        $byGroup[$key] = [int]$byGroup[$key] + 1
    }
    Test-WinToolExpectation -Condition ($byGroup["outdated"] -eq 1) -Message "One device is grouped as outdated."
    Test-WinToolExpectation -Condition ($byGroup["missing"] -eq 3) -Message "Code 28, code 1, and a hardware device with no driver are missing."
    Test-WinToolExpectation -Condition ($byGroup.ContainsKey("ghost") -eq $false) -Message "Leftover entries are kept out of the scan groups."
    Test-WinToolExpectation -Condition ((@(Get-WinToolDriverGhostDevice -Device @($outdated, $ghost, $disabled))).Count -eq 1) -Message "The leftover-entry counter includes only non-present devices."
    Test-WinToolExpectation -Condition ((@(Get-WinToolDriverProblemDevice -Device @($missingCode, $disabled, $ghost, $failed))).Count -eq 3) -Message "The problem-code list includes present devices and skips leftover entries."
    Test-WinToolExpectation -Condition ((@(Get-WinToolDriverIncompatibleDevice -Device @($failed, $blocked, $missingCode) -MemoryIntegrity $true)).Count -eq 2) -Message "Incompatible drivers are the failed and blocked ones."
}


Invoke-WinToolCase -Name "Driver result rows keep a Checkbox property for the results view" -Body {
    $device = New-WinToolDriverDeviceRecord -Name "Realtek Gaming 2.5GbE Family Controller" -Class "Net" -InstanceId "PCI\VEN_10EC&DEV_8168\1" -Version "1.0.0.0" -Provider "Realtek"
    $row = ConvertTo-WinToolDriverRow -Device $device -Group "outdated"
    Test-WinToolExpectation -Condition ($null -ne $row.PSObject.Properties["Checkbox"]) -Message "A device row is created with a Checkbox property so the results view can attach the control."

    $sentinel = New-Object psobject
    $assigned = $true
    try {
        $null = Set-WinToolDriverRowCheckbox -Row $row -Checkbox $sentinel
    }
    catch {
        $assigned = $false
    }
    Test-WinToolExpectation -Condition ($assigned -and [object]::ReferenceEquals($row.Checkbox, $sentinel)) -Message "Assigning Checkbox on a driver row does not throw."

    $bare = [pscustomobject]@{ Name = "Bare row"; Selected = $true }
    Test-WinToolExpectation -Condition ($null -eq $bare.PSObject.Properties["Checkbox"]) -Message "A bare PSCustomObject has no Checkbox property, which is the Log refresh failure after a Drivers scan on Windows PowerShell 5.1."
    $null = Set-WinToolDriverRowCheckbox -Row $bare -Checkbox $sentinel
    Test-WinToolExpectation -Condition ([object]::ReferenceEquals($bare.Checkbox, $sentinel)) -Message "Set-WinToolDriverRowCheckbox adds Checkbox when the property is missing."

    $cache = New-WinToolPackageCache
    $runtime = Get-WinToolDriverRuntimeRow -Runtime ([pscustomobject]@{ id = "openal"; name = "OpenAL"; wingetId = "OpenAL.OpenAL"; scope = "machine" }) -Cache $cache
    Test-WinToolExpectation -Condition ($null -ne $runtime.PSObject.Properties["Checkbox"]) -Message "A game runtime row is also created with a Checkbox property."
}


Invoke-WinToolCase -Name "Simple mode game runtimes only count recommended packages" -Body {
    $cache = New-WinToolPackageCache
    $cache.WingetReady = $true
    $recommended = Get-WinToolDriverRuntimeRow -Runtime ([pscustomobject]@{ id = "openal"; name = "OpenAL"; wingetId = "OpenAL.OpenAL"; scope = "machine"; attention = $true }) -Cache $cache
    $legacy = Get-WinToolDriverRuntimeRow -Runtime ([pscustomobject]@{ id = "vcredist-2008-x64"; name = "Microsoft Visual C++ 2008 Redistributable (x64)"; wingetId = "Microsoft.VCRedist.2008.x64"; scope = "machine"; attention = $false }) -Cache $cache
    $update = Get-WinToolDriverRuntimeRow -Runtime ([pscustomobject]@{ id = "vcredist-2013-x64"; name = "Microsoft Visual C++ 2013 Redistributable (x64)"; wingetId = "Microsoft.VCRedist.2013.x64"; scope = "machine"; attention = $false }) -Cache $cache
    $update.Group = "runtime"
    $update.AvailableVersion = Get-WinToolText "drivers.runtime.updateAvailable"
    Test-WinToolExpectation -Condition ($recommended.Group -eq "runtime" -and [bool]$recommended.Attention -and (Test-WinToolDriverRuntimeAttention -Row $recommended)) -Message "A recommended runtime that is not installed needs attention in Simple mode."
    Test-WinToolExpectation -Condition ($legacy.Group -eq "runtime" -and -not [bool]$legacy.Attention -and -not (Test-WinToolDriverRuntimeAttention -Row $legacy)) -Message "An optional legacy runtime that is not installed does not need attention in Simple mode."
    Test-WinToolExpectation -Condition (Test-WinToolDriverRuntimeAttention -Row $update) -Message "An already installed optional runtime with an update still needs attention."
    $counted = @(Get-WinToolDriverAttentionRuntime -Row @($recommended, $legacy, $update))
    Test-WinToolExpectation -Condition ($counted.Count -eq 2) -Message "Simple mode counts the recommended missing runtime and the optional update, not every legacy package."
    $header = Format-WinToolDriverHeader -Outdated 1 -Missing 1 -Runtime 2
    Test-WinToolExpectation -Condition ($header -eq (Format-WinToolDriverHeader -Outdated 1 -Missing 1 -Runtime 2) -and $header.Contains("2 game runtimes")) -Message "The header uses the tightened runtime count."
}

Invoke-WinToolCase -Name "Activity runs format a report and filter warnings" -Body {
    $script:WinToolState = @{}
    Initialize-WinToolActivityState
    Start-WinToolActivity -Title (Get-WinToolText "button.scanDrivers") | Out-Null
    Add-WinToolActivityStep -Status "ok" -Message (Get-WinToolText "drivers.scan.listed" 64) | Out-Null
    Add-WinToolActivityStep -Status "warn" -Message "OpenAL is not installed." | Out-Null
    $run = Complete-WinToolActivity -Summary (Format-WinToolDriverStatusSummary -Outdated 1 -Missing 0 -Runtime 1) -Status "ok"
    Test-WinToolExpectation -Condition ($null -ne $run -and $run.Warnings -eq 1 -and $run.Completed -eq 1) -Message "A finished activity run keeps completed and warning counts."
    $all = Format-WinToolActivityReport -Filter "all"
    $warnings = Format-WinToolActivityReport -Filter "warnings"
    Test-WinToolExpectation -Condition ($all.Contains((Get-WinToolText "button.scanDrivers")) -and $all.Contains("Listed 64 devices")) -Message "The full activity report includes the run title and a completed step."
    Test-WinToolExpectation -Condition ($warnings.Contains("OpenAL is not installed.") -and -not $warnings.Contains("Listed 64 devices")) -Message "The warnings filter keeps warning steps and hides completed ones."
    Test-WinToolExpectation -Condition ((Get-WinToolText "activity.count.warning.many" 3) -eq "3 warnings") -Message "Get-WinToolText formats English strings from the central table."
}

Invoke-WinToolCase -Name "Driver header, display advice, and runtime rows only count real results" -Body {
    Test-WinToolExpectation -Condition ((Format-WinToolDriverHeader -Outdated 0 -Missing 0 -Runtime 0) -eq "No outdated or missing drivers were found.") -Message "A completed scan with nothing to do has a clear header."
    Test-WinToolExpectation -Condition ((Format-WinToolDriverHeader -Outdated 1 -Missing 0 -Runtime 0) -eq "1 device driver is outdated.") -Message "A single outdated driver is singular."
    Test-WinToolExpectation -Condition ((Format-WinToolDriverHeader -Outdated 0 -Missing 1 -Runtime 0) -eq "1 device driver is missing.") -Message "A single missing driver is a complete sentence."
    Test-WinToolExpectation -Condition ((Format-WinToolDriverHeader -Outdated 0 -Missing 3 -Runtime 1) -eq "3 device drivers are missing. 1 game runtime needs attention.") -Message "A missing-only header still counts game runtimes."
    $header = Format-WinToolDriverHeader -Outdated 9 -Missing 1 -Runtime 5
    Test-WinToolExpectation -Condition ($header -eq "9 device drivers are outdated and 1 is missing. 5 game runtimes need attention.") -Message "The header lists outdated, missing, and game-runtime counts."

    $display = [pscustomobject]@{ Name = "Alienware AW2725QF"; Gpu = "AMD Radeon RX 6800 XT"; Width = 1920; Height = 1080; NativeWidth = 3840; NativeHeight = 2160 }
    $advice = Format-WinToolDisplayAdvice -Display $display
    Test-WinToolExpectation -Condition ($advice.Contains("1920") -and $advice.Contains("1080") -and $advice.Contains("3840") -and $advice.Contains("2160") -and $advice.Contains("AMD Radeon RX 6800 XT")) -Message "Display advice names the current and preferred resolution and the GPU."

    $info = [pscustomobject]@{ Os = "Windows 11 Pro"; Version = "25H2"; Cpu = "AMD Ryzen 5 5600X"; Gpu = "AMD Radeon RX 6800 XT"; Board = "TUF GAMING B550"; Memory = "16 GB"; Bios = "American Megatrends 1234" }
    $summary = Format-WinToolMachineSummary -Info $info
    Test-WinToolExpectation -Condition ($summary.Contains("Processor: AMD Ryzen 5 5600X") -and $summary.Contains("BIOS: American Megatrends 1234")) -Message "System information lists CPU and BIOS when they are present."
    Test-WinToolExpectation -Condition ((Format-WinToolMachineSummary -Info $null) -eq "System information is not available yet.") -Message "System information has no placeholder facts before a real read."

    $pendingCache = New-WinToolPackageCache
    $runtime = [pscustomobject]@{ id = "directx"; name = "DirectX End-User Runtime"; wingetId = "Microsoft.DirectX"; scope = "machine" }
    $pending = Get-WinToolDriverRuntimeRow -Runtime $runtime -Cache $pendingCache
    Test-WinToolExpectation -Condition ([string]$pending.Group -eq "runtime-pending" -and -not [bool]$pending.Selected -and [string]$pending.AvailableVersion -eq "") -Message "Game runtimes stay pending until the package cache is ready."

    $ready = Set-WinToolWingetPackageCache -InstalledId @("Microsoft.DirectX") -UpdateId @()
    $installed = Get-WinToolDriverRuntimeRow -Runtime $runtime -Cache $ready
    Test-WinToolExpectation -Condition ([string]$installed.Group -eq "runtime-current" -and [string]$installed.AvailableVersion -eq "") -Message "An installed game runtime is not marked as needing attention."

    $missingCache = Set-WinToolWingetPackageCache -InstalledId @() -UpdateId @()
    $needed = Get-WinToolDriverRuntimeRow -Runtime $runtime -Cache $missingCache
    Test-WinToolExpectation -Condition ([string]$needed.Group -eq "runtime" -and [bool]$needed.Selected -and [string]$needed.AvailableVersion -eq "Not installed") -Message "A missing game runtime is offered once the cache is ready."

    $updateCache = Set-WinToolWingetPackageCache -InstalledId @("Microsoft.DirectX") -UpdateId @("Microsoft.DirectX")
    $upgrade = Get-WinToolDriverRuntimeRow -Runtime $runtime -Cache $updateCache
    Test-WinToolExpectation -Condition ([string]$upgrade.Group -eq "runtime" -and [bool]$upgrade.Selected -and [string]$upgrade.AvailableVersion -eq "Update available") -Message "An installed game runtime with an update is offered once the cache is ready."

    $gpu = Get-WinToolDriverGpuRow -GpuName "NVIDIA GeForce RTX 4070" -Catalog (Get-WinToolDriverCatalog)
    Test-WinToolExpectation -Condition ($null -ne $gpu -and [string]$gpu.WingetId -eq "NVIDIA.NVIDIAApp") -Message "An NVIDIA GPU suggests the official NVIDIA App."

    $parsed = ConvertFrom-WinToolDriverScan -DeviceJson '[{"Name":"Demo NIC","Class":"Net","InstanceId":"PCI\\VEN_10EC&DEV_8168\\1","Problem":0,"Present":true,"Version":"1.0.0.0","Provider":"Realtek","Date":"2023-01-15T00:00:00","HardwareId":["PCI\\VEN_10EC&DEV_8168"]}]' -UpdateJson '[{"Title":"Demo NIC","Model":"Demo NIC","Version":"2.0.0.0","Date":"2024-04-08T00:00:00","HardwareId":["PCI\\VEN_10EC&DEV_8168"]}]'
    $group = Get-WinToolDriverDeviceGroup -Device $parsed.Device[0] -Update $parsed.Update
    Test-WinToolExpectation -Condition ([string]$group.Group -eq "outdated") -Message "JSON scan records can be classified after they are parsed."
}




Invoke-WinToolCase -Name "Locale detection follows the Windows display language and preferences" -Body {
    $originalPath = $script:WinToolPreferencesPath
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-i18n-test-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
        $script:WinToolPreferencesPath = $temp
        $script:WinToolLocalePackObject = $null
        $pt = Initialize-WinToolLocale -Language auto -UiCulture "pt-BR" -PreferredLanguages @() -Force
        Test-WinToolExpectation -Condition ($pt -eq "pt-BR") -Message ("pt-BR display language should resolve to pt-BR, got " + $pt)

        $ptPt = Initialize-WinToolLocale -Language auto -UiCulture "pt-PT" -PreferredLanguages @() -Force
        Test-WinToolExpectation -Condition ($ptPt -eq "pt-BR") -Message ("pt-PT should fall back to pt-BR, got " + $ptPt)

        $zh = Initialize-WinToolLocale -Language auto -UiCulture "zh-CN" -PreferredLanguages @() -Force
        Test-WinToolExpectation -Condition ($zh -eq "zh-Hans") -Message ("zh-CN should map to zh-Hans, got " + $zh)

        $unknown = Initialize-WinToolLocale -Language auto -UiCulture "xx-YY" -PreferredLanguages @() -Force
        Test-WinToolExpectation -Condition ($unknown -eq "en") -Message ("Unknown cultures should fall back to English, got " + $unknown)

        $preferred = Initialize-WinToolLocale -Language auto -UiCulture "xx-YY" -PreferredLanguages @("fr-FR") -Force
        $available = @(Get-WinToolAvailableLanguage)
        if ($available -contains "fr") {
            Test-WinToolExpectation -Condition ($preferred -eq "fr") -Message ("A preferred language of fr-FR should resolve to fr, got " + $preferred)
        }

        Initialize-WinToolLocale -Language "pt-BR" -Force | Out-Null
        $homeLabel = Get-WinToolText "ui.t.home.Text"
        $lang = Get-WinToolText "config.language.matchWindows"
        $scan = Get-WinToolText "button.scanDrivers"
        Test-WinToolExpectation -Condition ($homeLabel -eq "Início") -Message ("pt-BR Home should be Início, got " + $homeLabel)
        Test-WinToolExpectation -Condition ($lang -eq "Usar o idioma do Windows") -Message ("pt-BR Match Windows wording was wrong: " + $lang)
        Test-WinToolExpectation -Condition ($scan -eq "Verificar drivers") -Message ("pt-BR Scan drivers wording was wrong: " + $scan)
        $expected = @{
            "msg.windows-disk" = "Disco do Windows"
            "msg.startup-programs" = "Programas na inicialização"
            "msg.n-of-n-can-be-fixed" = "{0} de {1} podem ser corrigidos"
            "msg.finished-in-ns" = "Concluído em {0}s"
            "button.repairNetwork" = "Reparo de rede"
            "button.repairRuntimes" = "Reparar runtimes de jogos"
            "drivers.group.runtime" = "Runtimes de jogos"
            "drivers.group.gpu" = "App oficial da placa de vídeo"
            "drivers.group.ghost" = "Entradas restantes"
            "drivers.info.board" = "Placa-mãe"
            "catalog.fixes.network-reset.name" = "Redefinir rede"
            "catalog.fixes.winget-repair.name" = "Reparar winget"
            "catalog.fixes.windows-update-reset.description" = "Interrompe os serviços de atualização, renomeia as pastas SoftwareDistribution e catroot2 para o Windows recriá-las e, em seguida, inicia os serviços novamente. As pastas antigas ficam com o sufixo .WinTool-<date>."
            "ui.FeatureRefresh.Content" = "Atualizar"
            "ui.ProjectLinkText.Text" = "Projeto no GitHub"
            "ui.HomeHistoryLinkText.Text" = "Ver histórico"
            "catalog.apps.category.communication.chip" = "Chat"
            "catalog.apps.category.media.chip" = "Mídia"
            "catalog.apps.category.utilities.chip" = "Utilitários"
            "catalog.apps.category.runtimes.chip" = "Runtimes"
            "catalog.apps.waterfox.description" = "Um fork do Firefox focado em privacidade, sem telemetria."
            "msg.no-restart" = "Sem reinicialização"
            "msg.restart-needed" = "Reinicialização necessária"
            "msg.on" = "Ativado"
            "msg.off" = "Desativado"
        }
        foreach ($key in $expected.Keys) {
            $got = Get-WinToolText $key
            Test-WinToolExpectation -Condition ($got -eq $expected[$key]) -Message ("pt-BR " + $key + " should be '" + $expected[$key] + "', got '" + $got + "'")
        }
        $attention = New-WinToolHomeResult -Id "drivers" -Status "bad" -Text (Get-WinToolText "msg.n-devices-have-problems.one") -Action "review" -Penalty 10
        $lead = Get-WinToolHomeLead -Result @($attention)
        $reviewLead = Get-WinToolText "msg.review-items-that-need-attention-nothing-changed"
        Test-WinToolExpectation -Condition ($lead -eq $reviewLead) -Message ("A driver issue that cannot be auto-fixed should not say nothing needs fixing. Got: " + $lead)
        $okLead = Get-WinToolHomeLead -Result @((New-WinToolHomeResult -Id "junk" -Status "ok" -Text "ok"))
        Test-WinToolExpectation -Condition ($okLead -eq (Get-WinToolText "msg.nothing-needs-fixing-nothing-was-changed-during-the-anal")) -Message ("A healthy score should say nothing needs fixing. Got: " + $okLead)
        $prefs = Get-WinToolPreference
        $prefs.language = "pt-BR"
        Save-WinToolPreference -Preferences $prefs
        $loaded = Get-WinToolPreference
        Test-WinToolExpectation -Condition ($loaded.language -eq "pt-BR") -Message "The language override is saved in preferences.json."

        $forced = Initialize-WinToolLocale -Language "en" -UiCulture "pt-BR" -Force
        Test-WinToolExpectation -Condition ($forced -eq "en") -Message "An explicit English override should win over a Portuguese display language."

        $one = Get-WinToolCountText "activity.count.warning" 1
        $many = Get-WinToolCountText "activity.count.warning" 3
        Test-WinToolExpectation -Condition ($one -eq "1 warning" -and $many -eq "3 warnings") -Message "English plurals use one/many forms."
    }
    finally {
        $script:WinToolPreferencesPath = $originalPath
        $script:WinToolLocalePackObject = $null
        Initialize-WinToolLocale -Language en -Force | Out-Null
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

Invoke-WinToolCase -Name "The i18n scanner rejects hard-coded strings and checks placeholder parity" -Body {
    $python = $null
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { $python = [string]$cmd.Source; break }
    }
    Test-WinToolExpectation -Condition (-not [string]::IsNullOrWhiteSpace($python)) -Message "python3 is required for the hard-coded string scanner."
    if ([string]::IsNullOrWhiteSpace($python)) { return }
    $scanner = Join-Path $script:WinToolRoot "build/i18n/scan_hardcoded.py"
    $output = & $python $scanner 2>&1 | Out-String
    Test-WinToolExpectation -Condition ($LASTEXITCODE -eq 0) -Message ("i18n scanner failed:`n" + $output)
}


if ($script:WinToolFailures.Count -gt 0) {
    Write-Output ""
    Write-Output ("{0} test(s) failed." -f $script:WinToolFailures.Count)
    exit 1
}

Write-Output ""
Write-Output "All WinTool tests passed."
exit 0
