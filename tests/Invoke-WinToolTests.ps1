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

if ($script:WinToolFailures.Count -gt 0) {
    Write-Output ""
    Write-Output ("{0} test(s) failed." -f $script:WinToolFailures.Count)
    exit 1
}

Write-Output ""
Write-Output "All WinTool tests passed."
exit 0
