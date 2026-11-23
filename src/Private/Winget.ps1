# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# winget returns 0x8A15002B when the package is already installed and no upgrade applies.
$script:WinToolWingetAlreadyInstalled = -1978335189

function Sync-WinToolProcessPath {
    if (-not (Test-WinToolWindows)) {
        return
    }
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($machine)) {
        $env:Path = [string]$user
        return
    }
    if ([string]::IsNullOrWhiteSpace($user)) {
        $env:Path = [string]$machine
        return
    }
    $env:Path = "$machine;$user"
}

function Get-WinToolWingetPath {
    if (-not (Test-WinToolWindows)) {
        return $null
    }
    Sync-WinToolProcessPath
    $command = Get-Command -Name "winget.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return [string]$command.Source
    }
    $fallback = Join-Path $env:LOCALAPPDATA "Microsoft/WindowsApps/winget.exe"
    if (Test-Path -LiteralPath $fallback) {
        return $fallback
    }
    return $null
}

function Get-WinToolWingetArgument {
    param(
        [string]$Id,
        [string]$Scope,
        [ValidateSet("install", "upgrade", "uninstall", "upgrade-all")][string]$Action = "install"
    )
    $arguments = New-Object System.Collections.Generic.List[string]
    if ($Action -eq "upgrade-all") {
        $arguments.Add("upgrade")
        $arguments.Add("--all")
        $arguments.Add("--source")
        $arguments.Add("winget")
        $arguments.Add("--accept-package-agreements")
        $arguments.Add("--accept-source-agreements")
        $arguments.Add("--disable-interactivity")
        return $arguments.ToArray()
    }
    if ([string]::IsNullOrWhiteSpace($Id)) {
        throw "A winget id is needed for $Action."
    }
    $arguments.Add($Action)
    $arguments.Add("--id")
    $arguments.Add($Id)
    $arguments.Add("--exact")
    $arguments.Add("--source")
    $arguments.Add("winget")
    if ($Action -ne "uninstall") {
        $arguments.Add("--accept-package-agreements")
    }
    $arguments.Add("--accept-source-agreements")
    $arguments.Add("--disable-interactivity")
    if ($Action -eq "install" -and -not [string]::IsNullOrWhiteSpace($Scope)) {
        $arguments.Add("--scope")
        $arguments.Add($Scope)
    }
    return $arguments.ToArray()
}

function Get-WinToolWingetActionLabel {
    param(
        [string]$Action,
        [string]$Name
    )
    switch ($Action) {
        "upgrade" { return "Update $Name" }
        "uninstall" { return "Uninstall $Name" }
        "upgrade-all" { return "Update every app winget can update" }
        default { return "Install $Name" }
    }
}

function Get-WinToolWingetOutcomeText {
    param(
        [string]$Action,
        [string]$Status
    )
    if ($Status -eq "AlreadyInstalled") {
        if ($Action -eq "upgrade" -or $Action -eq "upgrade-all") {
            return "already up to date"
        }
        return "already installed"
    }
    return "done"
}

# Detecting installed apps runs in a background runspace so the window stays
# responsive. "winget export" gives exact package ids. The upgrade table is
# read by matching known catalog ids, because its column widths vary.
function Get-WinToolAppDetectionScript {
    $scriptText = @'
param($Sync, $Winget, $ExportPath)
$ErrorActionPreference = "Stop"
try {
    if (Test-Path -LiteralPath $ExportPath) {
        Remove-Item -LiteralPath $ExportPath -Force
    }
    $null = & $Winget export --output $ExportPath --source winget --accept-source-agreements --disable-interactivity 2>&1
    $ids = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ExportPath) {
        $data = [System.IO.File]::ReadAllText($ExportPath) | ConvertFrom-Json
        foreach ($source in @($data.Sources)) {
            foreach ($package in @($source.Packages)) {
                $ids.Add([string]$package.PackageIdentifier)
            }
        }
        Remove-Item -LiteralPath $ExportPath -Force -ErrorAction SilentlyContinue
    }
    $Sync.Installed = $ids.ToArray()
    $Sync.UpgradeText = (& $Winget upgrade --source winget --accept-source-agreements --disable-interactivity 2>&1 | Out-String)
    $Sync.Ok = $true
}
catch {
    $Sync.Error = $_.Exception.Message
}
finally {
    $Sync.Done = $true
}
'@
    return $scriptText
}

function Find-WinToolWingetIdInText {
    param(
        [AllowEmptyString()][string]$Text,
        [string[]]$KnownId
    )
    $found = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $found.ToArray()
    }
    $lookup = @{}
    foreach ($id in @($KnownId)) {
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $lookup[$id.ToLowerInvariant()] = $id
        }
    }
    $seen = @{}
    foreach ($line in ($Text -split '\r?\n')) {
        foreach ($token in ($line -split '\s+')) {
            if ([string]::IsNullOrWhiteSpace($token)) {
                continue
            }
            $key = $token.ToLowerInvariant()
            $match = $null
            if ($lookup.ContainsKey($key)) {
                $match = $lookup[$key]
            }
            elseif ($key.EndsWith([string][char]0x2026) -and $key.Length -gt 4) {
                # winget shortens long ids with an ellipsis. Accept a unique prefix.
                $prefix = $key.Substring(0, $key.Length - 1)
                $candidates = @($lookup.Keys | Where-Object { $_.StartsWith($prefix) })
                if ($candidates.Count -eq 1) {
                    $match = $lookup[$candidates[0]]
                }
            }
            if ($null -ne $match -and -not $seen.ContainsKey($match)) {
                $seen[$match] = $true
                $found.Add($match)
            }
        }
    }
    return $found.ToArray()
}

function Resolve-WinToolAppState {
    param(
        [string[]]$CatalogId,
        [string[]]$InstalledId,
        [AllowEmptyString()][string]$UpgradeText
    )
    $installed = @{}
    $known = @{}
    foreach ($id in @($CatalogId)) {
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $known[$id.ToLowerInvariant()] = $id
        }
    }
    foreach ($id in @($InstalledId)) {
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }
        $key = $id.ToLowerInvariant()
        if ($known.ContainsKey($key)) {
            $installed[$known[$key]] = $true
        }
    }
    $updates = @{}
    foreach ($id in @(Find-WinToolWingetIdInText -Text $UpgradeText -KnownId $CatalogId)) {
        $updates[$id] = $true
        $installed[$id] = $true
    }
    return [pscustomobject]@{
        Installed = $installed
        Updates = $updates
    }
}

function ConvertTo-WinToolWingetResult {
    param(
        [int]$ExitCode,
        [string]$Output
    )
    $status = "Failed"
    if ($ExitCode -eq 0) {
        $status = "Installed"
    }
    $already = $false
    if ($ExitCode -eq $script:WinToolWingetAlreadyInstalled) {
        $already = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Output) -and $Output -match '(?i)already installed|no available upgrade|no newer package version') {
        $already = $true
    }
    if ($already) {
        $status = "AlreadyInstalled"
    }
    return [pscustomobject]@{
        Status = $status
        ExitCode = $ExitCode
        Output = $Output
    }
}

function Get-WinToolAppPlan {
    param(
        $App,
        [ValidateSet("install", "upgrade", "uninstall")][string]$Action = "install"
    )
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($App)) {
        $name = Get-WinToolNote -Object $item -Name "Name"
        if ($null -eq $name) {
            $name = Get-WinToolNote -Object $item -Name "name" -Default "App"
        }
        $wingetId = Get-WinToolNote -Object $item -Name "WingetId"
        if ($null -eq $wingetId) {
            $wingetId = Get-WinToolNote -Object $item -Name "wingetId" -Default ""
        }
        $scope = Get-WinToolNote -Object $item -Name "Scope"
        if ($null -eq $scope) {
            $scope = Get-WinToolNote -Object $item -Name "scope" -Default ""
        }
        $steps.Add([pscustomobject]@{
            Type = "winget"
            Action = $Action
            Label = (Get-WinToolWingetActionLabel -Action $Action -Name ([string]$name))
            WingetId = [string]$wingetId
            Scope = [string]$scope
        })
    }
    return $steps.ToArray()
}

function Get-WinToolUpgradeAllPlan {
    return @([pscustomobject]@{
            Type = "winget"
            Action = "upgrade-all"
            Label = (Get-WinToolWingetActionLabel -Action "upgrade-all" -Name "")
            WingetId = ""
            Scope = ""
        })
}
