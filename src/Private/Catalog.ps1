# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolCachedPayloadObject {
    param([Parameter(Mandatory = $true)][string]$Name)
    # Parsed catalogs are immutable after load. Re-parsing Apps, Terminal, or
    # Oh My Posh themes on every click stalls the UI thread.
    if ($null -eq $script:WinToolPayloadObject) { $script:WinToolPayloadObject = @{} }
    if ($script:WinToolPayloadObject.ContainsKey($Name)) { return $script:WinToolPayloadObject[$Name] }
    $stamp = Get-Date
    $value = ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name $Name)
    if (Get-Command -Name Set-WinToolCatalogLocale -ErrorAction SilentlyContinue) {
        Set-WinToolCatalogLocale -Catalog $value -Kind $Name | Out-Null
    }
    $script:WinToolPayloadObject[$Name] = $value
    Write-WinToolStartupMark -Name ("catalog." + $Name) -Started $stamp
    return $value
}

function Get-WinToolAppCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Apps")
}

function Get-WinToolTweakCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Tweaks")
}

function Start-WinToolTweakCatalogPrefetch {
    if ($null -eq $script:WinToolPayloadObject) { $script:WinToolPayloadObject = @{} }
    if ($script:WinToolPayloadObject.ContainsKey("Tweaks")) { return }
    if ($null -ne $script:WinToolTweakCatalogPrefetch) { return }
    $payload = $null
    $path = $null
    if ($null -ne $script:WinToolEmbedded -and $script:WinToolEmbedded.ContainsKey("Tweaks")) {
        $payload = $script:WinToolEmbedded["Tweaks"]
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
        $path = Join-Path $script:WinToolRoot "data/tweaks.json"
    }
    else {
        return
    }
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $sync = [hashtable]::Synchronized(@{ Done = $false; Data = $null; Error = $null })
    [void]$powershell.AddScript({
            param($Sync, $Payload, $Path, $LocaleText, $EnglishText)
            try {
                if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
                    $text = [System.IO.File]::ReadAllText($Path)
                }
                else {
                    $clean = ([string]$Payload) -replace '\s', ''
                    $bytes = [Convert]::FromBase64String($clean)
                    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x1F -and $bytes[1] -eq 0x8B) {
                        $sourceStream = New-Object System.IO.MemoryStream(,$bytes)
                        $gzip = New-Object System.IO.Compression.GzipStream($sourceStream, [System.IO.Compression.CompressionMode]::Decompress)
                        try {
                            $output = New-Object System.IO.MemoryStream
                            $gzip.CopyTo($output)
                            $text = [System.Text.Encoding]::UTF8.GetString($output.ToArray())
                        }
                        finally {
                            $gzip.Dispose()
                            $sourceStream.Dispose()
                        }
                    }
                    else {
                        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
                    }
                }
                $value = $text | ConvertFrom-Json
                $localeTable = $LocaleText
                $englishTable = $EnglishText
                $lookup = {
                    param($Key)
                    if ($null -ne $localeTable -and $localeTable.ContainsKey($Key)) { return [string]$localeTable[$Key] }
                    if ($null -ne $englishTable -and $englishTable.ContainsKey($Key)) { return [string]$englishTable[$Key] }
                    return $null
                }
                foreach ($preset in @($value.presets)) {
                    $presetId = [string]$preset.id
                    $name = & $lookup ("catalog.tweaks.preset.$presetId.name")
                    if (-not [string]::IsNullOrEmpty($name)) { $preset.name = $name }
                    $description = & $lookup ("catalog.tweaks.preset.$presetId.description")
                    if (-not [string]::IsNullOrEmpty($description)) { $preset.description = $description }
                }
                foreach ($tweak in @($value.tweaks)) {
                    $tid = [string]$tweak.id
                    $name = & $lookup ("catalog.tweaks.$tid.name")
                    if (-not [string]::IsNullOrEmpty($name)) { $tweak.name = $name }
                    $description = & $lookup ("catalog.tweaks.$tid.description")
                    if (-not [string]::IsNullOrEmpty($description)) { $tweak.description = $description }
                    $category = [string]$tweak.category
                    if (-not [string]::IsNullOrWhiteSpace($category)) {
                        $slug = ($category.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim("-")
                        $label = & $lookup ("catalog.tweaks.category.$slug")
                        if (-not [string]::IsNullOrEmpty($label)) { $tweak.category = $label }
                    }
                }
                $Sync.Data = $value
            }
            catch {
                $Sync.Error = $_.Exception.Message
            }
            finally {
                $Sync.Done = $true
            }
        }).AddArgument($sync).AddArgument($payload).AddArgument($path).AddArgument($script:WinToolText).AddArgument($script:WinToolEnglishText)
    [void]$powershell.BeginInvoke()
    $script:WinToolTweakCatalogPrefetch = @{ PowerShell = $powershell; Runspace = $runspace; Sync = $sync }
}

function Complete-WinToolTweakCatalogPrefetch {
    if ($null -ne $script:WinToolPayloadObject -and $script:WinToolPayloadObject.ContainsKey("Tweaks")) {
        return $true
    }
    $job = $script:WinToolTweakCatalogPrefetch
    if ($null -eq $job) { return $true }
    if (-not $job.Sync.Done) { return $false }
    if ($null -ne $job.Sync.Data) {
        $value = $job.Sync.Data
        if ($null -eq $script:WinToolPayloadObject) { $script:WinToolPayloadObject = @{} }
        $script:WinToolPayloadObject["Tweaks"] = $value
        Write-WinToolStartupMark -Name "catalog.Tweaks"
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$job.Sync.Error)) {
        Write-WinToolLog -Message ([string]$job.Sync.Error) -Level "warn"
    }
    try { $job.PowerShell.Dispose() } catch { $null = $_.Exception.Message }
    try { $job.Runspace.Dispose() } catch { $null = $_.Exception.Message }
    $script:WinToolTweakCatalogPrefetch = $null
    return $true
}

function Stop-WinToolTweakCatalogPrefetch {
    $job = $script:WinToolTweakCatalogPrefetch
    if ($null -eq $job) { return }
    try { $null = $job.PowerShell.BeginStop($null, $null) } catch { $null = $_.Exception.Message }
    try { $null = $job.Runspace.CloseAsync() } catch { $null = $_.Exception.Message }
    $script:WinToolTweakCatalogPrefetch = $null
}

function Get-WinToolTerminalCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Terminal")
}

function Get-WinToolUpdateCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Updates")
}

function Get-WinToolPresetTweak {
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$PresetId
    )
    $matched = New-Object System.Collections.Generic.List[object]
    foreach ($tweak in @($Catalog.tweaks)) {
        $presets = @(Get-WinToolNote -Object $tweak -Name "presets" -Default @())
        if ($presets -contains $PresetId) {
            $matched.Add($tweak)
        }
    }
    return $matched.ToArray()
}

function Test-WinToolWingetId {
    param(
        [string]$Id
    )
    if ([string]::IsNullOrWhiteSpace($Id)) {
        return $false
    }
    return ($Id -match '^[A-Za-z0-9][A-Za-z0-9._+-]*\.[A-Za-z0-9][A-Za-z0-9._+-]*$')
}

function Add-WinToolDataError {
    param(
        $Errors,
        [string]$Message
    )
    $Errors.Add($Message)
}

function Test-WinToolRegistryAction {
    param(
        $Action,
        [string]$Label,
        $Errors
    )
    $type = [string](Get-WinToolNote -Object $Action -Name "type" -Default "")
    if ($type -eq "group") {
        $nested = @(Get-WinToolNote -Object $Action -Name "actions" -Default @())
        if ($nested.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-group-has-no-actions" $Label)
        }
        foreach ($child in $nested) {
            Test-WinToolRegistryAction -Action $child -Label $Label -Errors $Errors
        }
        return
    }
    if ($type -eq "registry" -or $type -eq "registry-remove") {
        $entries = @(Get-WinToolNote -Object $Action -Name "entries" -Default @())
        if ($entries.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-has-no-registry-entries" $Label)
        }
        foreach ($entry in $entries) {
            $path = [string](Get-WinToolNote -Object $entry -Name "path" -Default "")
            if ($path -notmatch '^(HKCU|HKLM):\\') {
                Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-has-a-registry-path-that-is-not-hkcu-or-hklm" $Label)
            }
            $nameProperty = $entry.PSObject.Properties["name"]
            if ($null -eq $nameProperty) {
                Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-is-missing-a-registry-value-name" $Label)
            }
            if ($type -eq "registry") {
                $kind = [string](Get-WinToolNote -Object $entry -Name "kind" -Default "")
                if (@("DWord", "QWord", "String", "ExpandString", "MultiString") -notcontains $kind) {
                    Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-uses-an-unknown-registry-kind-n" $Label $kind)
                }
                if ($null -eq $entry.PSObject.Properties["value"]) {
                    Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-is-missing-a-registry-value" $Label)
                }
            }
        }
        return
    }
    if ($type -eq "registry-key") {
        $path = [string](Get-WinToolNote -Object $Action -Name "path" -Default "")
        $operation = [string](Get-WinToolNote -Object $Action -Name "operation" -Default "")
        if ($path -notmatch '^(HKCU|HKLM):\\') {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-has-a-registry-key-outside-hkcu-or-hklm" $Label)
        }
        if (@("add", "remove") -notcontains $operation) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-registry-key-operation-must-be-add-or-remove" $Label)
        }
        return
    }
    if ($type -eq "service") {
        $name = [string](Get-WinToolNote -Object $Action -Name "name" -Default "")
        $startup = [string](Get-WinToolNote -Object $Action -Name "startupType" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-is-missing-a-service-name" $Label)
        }
        if (@("Automatic", "Manual", "Disabled") -notcontains $startup) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-has-an-unknown-service-startup-type" $Label)
        }
        return
    }
    if ($type -eq "scheduled-task") {
        $taskName = [string](Get-WinToolNote -Object $Action -Name "taskName" -Default "")
        $taskPath = [string](Get-WinToolNote -Object $Action -Name "taskPath" -Default "")
        $state = [string](Get-WinToolNote -Object $Action -Name "state" -Default "")
        if ([string]::IsNullOrWhiteSpace($taskName) -or [string]::IsNullOrWhiteSpace($taskPath)) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-is-missing-a-scheduled-task-name-or-path" $Label)
        }
        if (@("Enabled", "Disabled") -notcontains $state) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-has-an-unknown-scheduled-task-state" $Label)
        }
        return
    }
    if ($type -eq "appx") {
        $packages = @(Get-WinToolNote -Object $Action -Name "packages" -Default @())
        if ($packages.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-does-not-list-any-inbox-apps" $Label)
        }
        foreach ($package in $packages) {
            if ([string]$package -match 'WindowsStore|SecHealthUI') {
                Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-tries-to-remove-a-protected-inbox-app" $Label)
            }
        }
        return
    }
    if ($type -eq "appx-restore") {
        return
    }
    Add-WinToolDataError -Errors $Errors -Message (Get-WinToolText "msg.n-uses-an-unknown-action-type-n" $Label $type)
}

function Test-WinToolDataFile {
    $errors = New-Object System.Collections.Generic.List[string]
    $apps = Get-WinToolAppCatalog
    $tweaks = Get-WinToolTweakCatalog
    $terminal = Get-WinToolTerminalCatalog
    $updates = Get-WinToolUpdateCatalog

    if ([int](Get-WinToolNote -Object $apps -Name "schemaVersion" -Default 0) -ne 1) {
        Add-WinToolDataError -Errors $errors -Message "apps.json schemaVersion must be 1."
    }
    if ([int](Get-WinToolNote -Object $tweaks -Name "schemaVersion" -Default 0) -ne 1) {
        Add-WinToolDataError -Errors $errors -Message "tweaks.json schemaVersion must be 1."
    }
    if ([int](Get-WinToolNote -Object $terminal -Name "schemaVersion" -Default 0) -ne 1) {
        Add-WinToolDataError -Errors $errors -Message "terminal.json schemaVersion must be 1."
    }
    if ([int](Get-WinToolNote -Object $updates -Name "schemaVersion" -Default 0) -ne 1) {
        Add-WinToolDataError -Errors $errors -Message "updates.json schemaVersion must be 1."
    }

    $appIds = @{}
    $categories = @(Get-WinToolNote -Object $apps -Name "categories" -Default @())
    if ($categories.Count -eq 0) {
        Add-WinToolDataError -Errors $errors -Message "apps.json has no categories."
    }
    foreach ($category in $categories) {
        $categoryId = [string](Get-WinToolNote -Object $category -Name "id" -Default "")
        $categoryName = [string](Get-WinToolNote -Object $category -Name "name" -Default "")
        if ([string]::IsNullOrWhiteSpace($categoryId) -or [string]::IsNullOrWhiteSpace($categoryName)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-category-is-missing-an-id-or-name")
        }
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $id = [string](Get-WinToolNote -Object $app -Name "id" -Default "")
            $name = [string](Get-WinToolNote -Object $app -Name "name" -Default "")
            $description = [string](Get-WinToolNote -Object $app -Name "description" -Default "")
            $wingetId = [string](Get-WinToolNote -Object $app -Name "wingetId" -Default "")
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.an-app-in-n-is-missing-an-id-name-or-description" $categoryId)
            }
            if ($appIds.ContainsKey($id)) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.duplicate-app-id-n" $id)
            }
            else {
                $appIds[$id] = $true
            }
            if (-not (Test-WinToolWingetId -Id $wingetId)) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.app-n-has-an-unexpected-winget-id-n" $id $wingetId)
            }
            $scope = [string](Get-WinToolNote -Object $app -Name "scope" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($scope) -and @("user", "machine") -notcontains $scope) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.app-n-has-an-unknown-scope" $id)
            }
            $icon = [string](Get-WinToolNote -Object $app -Name "icon" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($icon)) {
                if (-not (Test-WinToolAppIconName -FileName $icon)) {
                    Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.app-n-has-an-icon-name-that-is-not-a-png-file-name" $id)
                }
                elseif (-not [string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
                    $iconPath = Join-Path $script:WinToolRoot ("assets/icons/" + $icon)
                    if (-not (Test-Path -LiteralPath $iconPath)) {
                        Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.app-n-icon-n-is-not-in-assets-icons" $id $icon)
                    }
                }
            }
            foreach ($detectName in @(Get-WinToolNote -Object $app -Name "detectNames" -Default @())) {
                if ([string]::IsNullOrWhiteSpace([string]$detectName) -or [string]$detectName -match '[\r\n]') {
                    Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.app-n-has-an-empty-or-multi-line-detect-name" $id)
                }
            }
        }
    }

    $presetIds = @{}
    foreach ($preset in @(Get-WinToolNote -Object $tweaks -Name "presets" -Default @())) {
        $presetId = [string](Get-WinToolNote -Object $preset -Name "id" -Default "")
        $presetName = [string](Get-WinToolNote -Object $preset -Name "name" -Default "")
        if ([string]::IsNullOrWhiteSpace($presetId) -or [string]::IsNullOrWhiteSpace($presetName)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-preset-is-missing-an-id-or-name")
            continue
        }
        if ($presetIds.ContainsKey($presetId)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.duplicate-preset-id-n" $presetId)
        }
        $presetIds[$presetId] = $true
    }

    $tweakIds = @{}
    foreach ($tweak in @(Get-WinToolNote -Object $tweaks -Name "tweaks" -Default @())) {
        $id = [string](Get-WinToolNote -Object $tweak -Name "id" -Default "")
        $name = [string](Get-WinToolNote -Object $tweak -Name "name" -Default "")
        $description = [string](Get-WinToolNote -Object $tweak -Name "description" -Default "")
        $risk = [string](Get-WinToolNote -Object $tweak -Name "risk" -Default "")
        $refresh = [string](Get-WinToolNote -Object $tweak -Name "refresh" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-tweak-is-missing-an-id-name-or-description")
        }
        if ($tweakIds.ContainsKey($id)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.duplicate-tweak-id-n" $id)
        }
        else {
            $tweakIds[$id] = $true
        }
        if (@("safe", "caution") -notcontains $risk) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.tweak-n-has-an-unknown-risk" $id)
        }
        if (@("none", "theme", "explorer") -notcontains $refresh) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.tweak-n-has-an-unknown-refresh-value" $id)
        }
        foreach ($presetId in @(Get-WinToolNote -Object $tweak -Name "presets" -Default @())) {
            if (-not $presetIds.ContainsKey([string]$presetId)) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.tweak-n-uses-an-unknown-preset-n" $id $presetId)
            }
        }
        $apply = Get-WinToolNote -Object $tweak -Name "apply"
        $undo = Get-WinToolNote -Object $tweak -Name "undo"
        if ($null -eq $apply -or $null -eq $undo) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.tweak-n-needs-both-apply-and-undo" $id)
            continue
        }
        Test-WinToolRegistryAction -Action $apply -Label "Tweak '$id' apply" -Errors $errors
        Test-WinToolRegistryAction -Action $undo -Label "Tweak '$id' undo" -Errors $errors
    }

    foreach ($prompt in @(Get-WinToolNote -Object $terminal -Name "prompts" -Default @())) {
        $id = [string](Get-WinToolNote -Object $prompt -Name "id" -Default "")
        $wingetId = [string](Get-WinToolNote -Object $prompt -Name "wingetId" -Default "")
        $shell = [string](Get-WinToolNote -Object $prompt -Name "shell" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($shell)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-terminal-prompt-is-missing-an-id-or-shell")
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetId) -and -not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.terminal-prompt-n-has-an-unexpected-winget-id" $id)
        }
    }
    foreach ($scheme in @(Get-WinToolNote -Object $terminal -Name "schemes" -Default @())) {
        # Windows Terminal drops a scheme without all 16 colors, and then any
        # profile that names it shows an "invalid colorScheme" warning.
        $palette = Get-WinToolNote -Object $scheme -Name "palette"
        foreach ($key in $script:WinToolSchemeColorKeys) {
            $value = [string](Get-WinToolNote -Object $palette -Name $key -Default "")
            if ($value -notmatch '^#[0-9A-Fa-f]{6}$') {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.color-scheme-n-needs-a-n-color" $scheme.id $key)
            }
        }
    }
    if (@(Get-WinToolNote -Object $terminal -Name "prompts" -Default @()).Count -lt 8) {
        Add-WinToolDataError -Errors $errors -Message "terminal.json should list the prompt engines."
    }
    $fontDoc = ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Fonts")
    $fontRows = @(Get-WinToolNote -Object $fontDoc -Name "fonts" -Default @())
    if ($fontRows.Count -lt 60) {
        Add-WinToolDataError -Errors $errors -Message "fonts.json should include the Nerd Fonts catalog."
    }
    foreach ($font in $fontRows) {
        $id = [string](Get-WinToolNote -Object $font -Name "id" -Default "")
        $face = [string](Get-WinToolNote -Object $font -Name "face" -Default "")
        $match = [string](Get-WinToolNote -Object $font -Name "match" -Default "")
        $wingetId = [string](Get-WinToolNote -Object $font -Name "wingetId" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($face) -or [string]::IsNullOrWhiteSpace($match)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-terminal-font-is-missing-an-id-face-or-match-token")
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetId) -and -not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.terminal-font-n-has-an-unexpected-winget-id" $id)
        }
        $asset = [string](Get-WinToolNote -Object $font -Name "asset" -Default "")
        $github = Get-WinToolNote -Object $font -Name "github"
        $sources = 0
        if (-not [string]::IsNullOrWhiteSpace($wingetId)) { $sources++ }
        if (-not [string]::IsNullOrWhiteSpace($asset)) { $sources++ }
        if ($null -ne $github) { $sources++ }
        if ($sources -ne 1) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.terminal-font-n-needs-exactly-one-source-a-nerd-fonts-as" $id)
        }
        if ([string](Get-WinToolNote -Object $font -Name "source" -Default "") -eq "nerd-fonts" -and [string]::IsNullOrWhiteSpace($asset)) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.nerd-font-n-must-come-from-the-nerd-fonts-release" $id)
        }
        if ($null -ne $github) {
            $repo = [string](Get-WinToolNote -Object $github -Name "repo" -Default "")
            $pattern = [string](Get-WinToolNote -Object $github -Name "asset" -Default "")
            if ($repo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$' -or [string]::IsNullOrWhiteSpace($pattern) -or @(Get-WinToolNote -Object $github -Name "files" -Default @()).Count -eq 0) {
                Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.terminal-font-n-has-an-incomplete-github-source" $id)
            }
        }
    }
    $themeDoc = ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "OmpThemes")
    $themeRows = @(Get-WinToolNote -Object $themeDoc -Name "themes" -Default @())
    if ($themeRows.Count -lt 80) {
        Add-WinToolDataError -Errors $errors -Message "omp-themes.json should include the official Oh My Posh themes."
    }
    foreach ($theme in $themeRows) {
        $themeId = [string](Get-WinToolNote -Object $theme -Name "id" -Default "")
        $themeFile = [string](Get-WinToolNote -Object $theme -Name "file" -Default "")
        if ([string]::IsNullOrWhiteSpace($themeId) -or -not $themeFile.EndsWith(".omp.json")) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.an-oh-my-posh-theme-is-missing-an-id-or-file-name")
        }
    }

    foreach ($vendor in @(Get-WinToolNote -Object $updates -Name "vendors" -Default @())) {
        $id = [string](Get-WinToolNote -Object $vendor -Name "id" -Default "")
        $url = [string](Get-WinToolNote -Object $vendor -Name "url" -Default "")
        $match = @(Get-WinToolNote -Object $vendor -Name "match" -Default @())
        if ([string]::IsNullOrWhiteSpace($id) -or $match.Count -eq 0) {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.a-graphics-vendor-is-missing-an-id-or-match-list")
        }
        if ($url -notmatch '^https://') {
            Add-WinToolDataError -Errors $errors -Message (Get-WinToolText "msg.vendor-n-must-use-an-https-link" $id)
        }
    }

    Test-WinToolTextTable -Errors $errors
    Test-WinToolDriverCatalog -Catalog (Get-WinToolDriverCatalog) -Errors $errors
    Test-WinToolFixCatalog -Catalog (Get-WinToolFixCatalog) -Errors $errors
    Test-WinToolFeatureCatalog -Catalog (Get-WinToolFeatureCatalog) -Errors $errors
    Test-WinToolUpdateModeCatalog -Catalog $updates -Errors $errors
    Test-WinToolSystemCatalog -Catalog (Get-WinToolSystemCatalog) -Errors $errors

    return $errors.ToArray()
}
