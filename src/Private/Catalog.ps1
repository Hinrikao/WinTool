# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolAppCatalog {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Apps"))
}

function Get-WinToolTweakCatalog {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Tweaks"))
}

function Get-WinToolTerminalCatalog {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Terminal"))
}

function Get-WinToolUpdateCatalog {
    return (ConvertFrom-WinToolJsonText -Text (Get-WinToolPayloadText -Name "Updates"))
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
            Add-WinToolDataError -Errors $Errors -Message "$Label group has no actions."
        }
        foreach ($child in $nested) {
            Test-WinToolRegistryAction -Action $child -Label $Label -Errors $Errors
        }
        return
    }
    if ($type -eq "registry" -or $type -eq "registry-remove") {
        $entries = @(Get-WinToolNote -Object $Action -Name "entries" -Default @())
        if ($entries.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message "$Label has no registry entries."
        }
        foreach ($entry in $entries) {
            $path = [string](Get-WinToolNote -Object $entry -Name "path" -Default "")
            if ($path -notmatch '^(HKCU|HKLM):\\') {
                Add-WinToolDataError -Errors $Errors -Message "$Label has a registry path that is not HKCU or HKLM."
            }
            $nameProperty = $entry.PSObject.Properties["name"]
            if ($null -eq $nameProperty) {
                Add-WinToolDataError -Errors $Errors -Message "$Label is missing a registry value name."
            }
            if ($type -eq "registry") {
                $kind = [string](Get-WinToolNote -Object $entry -Name "kind" -Default "")
                if (@("DWord", "QWord", "String", "ExpandString", "MultiString") -notcontains $kind) {
                    Add-WinToolDataError -Errors $Errors -Message "$Label uses an unknown registry kind '$kind'."
                }
                if ($null -eq $entry.PSObject.Properties["value"]) {
                    Add-WinToolDataError -Errors $Errors -Message "$Label is missing a registry value."
                }
            }
        }
        return
    }
    if ($type -eq "registry-key") {
        $path = [string](Get-WinToolNote -Object $Action -Name "path" -Default "")
        $operation = [string](Get-WinToolNote -Object $Action -Name "operation" -Default "")
        if ($path -notmatch '^(HKCU|HKLM):\\') {
            Add-WinToolDataError -Errors $Errors -Message "$Label has a registry key outside HKCU or HKLM."
        }
        if (@("add", "remove") -notcontains $operation) {
            Add-WinToolDataError -Errors $Errors -Message "$Label registry key operation must be add or remove."
        }
        return
    }
    if ($type -eq "service") {
        $name = [string](Get-WinToolNote -Object $Action -Name "name" -Default "")
        $startup = [string](Get-WinToolNote -Object $Action -Name "startupType" -Default "")
        if ([string]::IsNullOrWhiteSpace($name)) {
            Add-WinToolDataError -Errors $Errors -Message "$Label is missing a service name."
        }
        if (@("Automatic", "Manual", "Disabled") -notcontains $startup) {
            Add-WinToolDataError -Errors $Errors -Message "$Label has an unknown service startup type."
        }
        return
    }
    if ($type -eq "scheduled-task") {
        $taskName = [string](Get-WinToolNote -Object $Action -Name "taskName" -Default "")
        $taskPath = [string](Get-WinToolNote -Object $Action -Name "taskPath" -Default "")
        $state = [string](Get-WinToolNote -Object $Action -Name "state" -Default "")
        if ([string]::IsNullOrWhiteSpace($taskName) -or [string]::IsNullOrWhiteSpace($taskPath)) {
            Add-WinToolDataError -Errors $Errors -Message "$Label is missing a scheduled task name or path."
        }
        if (@("Enabled", "Disabled") -notcontains $state) {
            Add-WinToolDataError -Errors $Errors -Message "$Label has an unknown scheduled task state."
        }
        return
    }
    if ($type -eq "appx") {
        $packages = @(Get-WinToolNote -Object $Action -Name "packages" -Default @())
        if ($packages.Count -eq 0) {
            Add-WinToolDataError -Errors $Errors -Message "$Label does not list any inbox apps."
        }
        foreach ($package in $packages) {
            if ([string]$package -match 'WindowsStore|SecHealthUI') {
                Add-WinToolDataError -Errors $Errors -Message "$Label tries to remove a protected inbox app."
            }
        }
        return
    }
    if ($type -eq "appx-restore") {
        return
    }
    Add-WinToolDataError -Errors $Errors -Message "$Label uses an unknown action type '$type'."
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
            Add-WinToolDataError -Errors $errors -Message "A category is missing an id or name."
        }
        foreach ($app in @(Get-WinToolNote -Object $category -Name "apps" -Default @())) {
            $id = [string](Get-WinToolNote -Object $app -Name "id" -Default "")
            $name = [string](Get-WinToolNote -Object $app -Name "name" -Default "")
            $description = [string](Get-WinToolNote -Object $app -Name "description" -Default "")
            $wingetId = [string](Get-WinToolNote -Object $app -Name "wingetId" -Default "")
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($description)) {
                Add-WinToolDataError -Errors $errors -Message "An app in '$categoryId' is missing an id, name, or description."
            }
            if ($appIds.ContainsKey($id)) {
                Add-WinToolDataError -Errors $errors -Message "Duplicate app id '$id'."
            }
            else {
                $appIds[$id] = $true
            }
            if (-not (Test-WinToolWingetId -Id $wingetId)) {
                Add-WinToolDataError -Errors $errors -Message "App '$id' has an unexpected winget id '$wingetId'."
            }
            $scope = [string](Get-WinToolNote -Object $app -Name "scope" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($scope) -and @("user", "machine") -notcontains $scope) {
                Add-WinToolDataError -Errors $errors -Message "App '$id' has an unknown scope."
            }
            $icon = [string](Get-WinToolNote -Object $app -Name "icon" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($icon)) {
                if (-not (Test-WinToolAppIconName -FileName $icon)) {
                    Add-WinToolDataError -Errors $errors -Message "App '$id' has an icon name that is not a PNG file name."
                }
                elseif (-not [string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
                    $iconPath = Join-Path $script:WinToolRoot ("assets/icons/" + $icon)
                    if (-not (Test-Path -LiteralPath $iconPath)) {
                        Add-WinToolDataError -Errors $errors -Message "App '$id' icon '$icon' is not in assets/icons."
                    }
                }
            }
            foreach ($detectName in @(Get-WinToolNote -Object $app -Name "detectNames" -Default @())) {
                if ([string]::IsNullOrWhiteSpace([string]$detectName) -or [string]$detectName -match '[\r\n]') {
                    Add-WinToolDataError -Errors $errors -Message "App '$id' has an empty or multi-line detect name."
                }
            }
        }
    }

    $presetIds = @{}
    foreach ($preset in @(Get-WinToolNote -Object $tweaks -Name "presets" -Default @())) {
        $presetId = [string](Get-WinToolNote -Object $preset -Name "id" -Default "")
        $presetName = [string](Get-WinToolNote -Object $preset -Name "name" -Default "")
        if ([string]::IsNullOrWhiteSpace($presetId) -or [string]::IsNullOrWhiteSpace($presetName)) {
            Add-WinToolDataError -Errors $errors -Message "A preset is missing an id or name."
            continue
        }
        if ($presetIds.ContainsKey($presetId)) {
            Add-WinToolDataError -Errors $errors -Message "Duplicate preset id '$presetId'."
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
            Add-WinToolDataError -Errors $errors -Message "A tweak is missing an id, name, or description."
        }
        if ($tweakIds.ContainsKey($id)) {
            Add-WinToolDataError -Errors $errors -Message "Duplicate tweak id '$id'."
        }
        else {
            $tweakIds[$id] = $true
        }
        if (@("safe", "caution") -notcontains $risk) {
            Add-WinToolDataError -Errors $errors -Message "Tweak '$id' has an unknown risk."
        }
        if (@("none", "theme", "explorer") -notcontains $refresh) {
            Add-WinToolDataError -Errors $errors -Message "Tweak '$id' has an unknown refresh value."
        }
        foreach ($presetId in @(Get-WinToolNote -Object $tweak -Name "presets" -Default @())) {
            if (-not $presetIds.ContainsKey([string]$presetId)) {
                Add-WinToolDataError -Errors $errors -Message "Tweak '$id' uses an unknown preset '$presetId'."
            }
        }
        $apply = Get-WinToolNote -Object $tweak -Name "apply"
        $undo = Get-WinToolNote -Object $tweak -Name "undo"
        if ($null -eq $apply -or $null -eq $undo) {
            Add-WinToolDataError -Errors $errors -Message "Tweak '$id' needs both apply and undo."
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
            Add-WinToolDataError -Errors $errors -Message "A terminal prompt is missing an id or shell."
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetId) -and -not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $errors -Message "Terminal prompt '$id' has an unexpected winget id."
        }
    }
    foreach ($scheme in @(Get-WinToolNote -Object $terminal -Name "schemes" -Default @())) {
        # Windows Terminal drops a scheme without all 16 colors, and then any
        # profile that names it shows an "invalid colorScheme" warning.
        $palette = Get-WinToolNote -Object $scheme -Name "palette"
        foreach ($key in $script:WinToolSchemeColorKeys) {
            $value = [string](Get-WinToolNote -Object $palette -Name $key -Default "")
            if ($value -notmatch '^#[0-9A-Fa-f]{6}$') {
                Add-WinToolDataError -Errors $errors -Message ("Color scheme '" + [string]$scheme.id + "' needs a " + $key + " color.")
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
            Add-WinToolDataError -Errors $errors -Message "A terminal font is missing an id, face, or match token."
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetId) -and -not (Test-WinToolWingetId -Id $wingetId)) {
            Add-WinToolDataError -Errors $errors -Message "Terminal font '$id' has an unexpected winget id."
        }
        $asset = [string](Get-WinToolNote -Object $font -Name "asset" -Default "")
        $github = Get-WinToolNote -Object $font -Name "github"
        $sources = 0
        if (-not [string]::IsNullOrWhiteSpace($wingetId)) { $sources++ }
        if (-not [string]::IsNullOrWhiteSpace($asset)) { $sources++ }
        if ($null -ne $github) { $sources++ }
        if ($sources -ne 1) {
            Add-WinToolDataError -Errors $errors -Message "Terminal font '$id' needs exactly one source: a Nerd Fonts asset, a GitHub release, or a checked winget id."
        }
        if ([string](Get-WinToolNote -Object $font -Name "source" -Default "") -eq "nerd-fonts" -and [string]::IsNullOrWhiteSpace($asset)) {
            Add-WinToolDataError -Errors $errors -Message "Nerd Font '$id' must come from the Nerd Fonts release."
        }
        if ($null -ne $github) {
            $repo = [string](Get-WinToolNote -Object $github -Name "repo" -Default "")
            $pattern = [string](Get-WinToolNote -Object $github -Name "asset" -Default "")
            if ($repo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$' -or [string]::IsNullOrWhiteSpace($pattern) -or @(Get-WinToolNote -Object $github -Name "files" -Default @()).Count -eq 0) {
                Add-WinToolDataError -Errors $errors -Message "Terminal font '$id' has an incomplete GitHub source."
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
            Add-WinToolDataError -Errors $errors -Message "An Oh My Posh theme is missing an id or file name."
        }
    }

    foreach ($vendor in @(Get-WinToolNote -Object $updates -Name "vendors" -Default @())) {
        $id = [string](Get-WinToolNote -Object $vendor -Name "id" -Default "")
        $url = [string](Get-WinToolNote -Object $vendor -Name "url" -Default "")
        $match = @(Get-WinToolNote -Object $vendor -Name "match" -Default @())
        if ([string]::IsNullOrWhiteSpace($id) -or $match.Count -eq 0) {
            Add-WinToolDataError -Errors $errors -Message "A graphics vendor is missing an id or match list."
        }
        if ($url -notmatch '^https://') {
            Add-WinToolDataError -Errors $errors -Message "Vendor '$id' must use an https link."
        }
    }

    Test-WinToolFixCatalog -Catalog (Get-WinToolFixCatalog) -Errors $errors
    Test-WinToolFeatureCatalog -Catalog (Get-WinToolFeatureCatalog) -Errors $errors
    Test-WinToolUpdateModeCatalog -Catalog $updates -Errors $errors
    Test-WinToolSystemCatalog -Catalog (Get-WinToolSystemCatalog) -Errors $errors

    return $errors.ToArray()
}
