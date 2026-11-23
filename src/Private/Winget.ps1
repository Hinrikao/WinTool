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

function Get-WinToolWingetCandidate {
    # Every winget.exe this PC might have, best first. The per-user alias in
    # WindowsApps is what a normal shell runs, but an elevated process can
    # fail to start it ("The file cannot be accessed by the system"), so the
    # real file inside the App Installer package is kept as a fallback.
    if (-not (Test-WinToolWindows)) {
        return @()
    }
    Sync-WinToolProcessPath
    $list = New-Object System.Collections.Generic.List[string]
    $command = Get-Command -Name "winget.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        $list.Add([string]$command.Source)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $alias = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
        if (Test-Path -LiteralPath $alias) {
            $list.Add($alias)
        }
    }
    try {
        foreach ($package in @(Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop | Sort-Object -Property Version -Descending)) {
            $file = Join-Path ([string]$package.InstallLocation) "winget.exe"
            if (Test-Path -LiteralPath $file) {
                $list.Add($file)
            }
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    $pattern = Join-Path $env:ProgramFiles "WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe"
    foreach ($item in @(Resolve-Path -Path $pattern -ErrorAction SilentlyContinue | Sort-Object -Property Path -Descending)) {
        $list.Add([string]$item.Path)
    }
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($path in $list) {
        $key = $path.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $unique.Add($path)
        }
    }
    return $unique.ToArray()
}

function Get-WinToolWingetPath {
    if ($null -ne $script:WinToolWingetWorking -and (Test-Path -LiteralPath $script:WinToolWingetWorking)) {
        return $script:WinToolWingetWorking
    }
    $candidates = @(Get-WinToolWingetCandidate)
    if ($candidates.Count -eq 0) {
        return $null
    }
    return $candidates[0]
}

function ConvertFrom-WinToolWingetExport {
    param(
        [AllowEmptyString()][string]$Text
    )
    # The file winget export writes: Sources[].Packages[].PackageIdentifier.
    $ids = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $ids.ToArray()
    }
    $data = ConvertFrom-Json -InputObject $Text.TrimStart([char]0xFEFF)
    foreach ($source in @(Get-WinToolNote -Object $data -Name "Sources" -Default @())) {
        foreach ($package in @(Get-WinToolNote -Object $source -Name "Packages" -Default @())) {
            $id = [string](Get-WinToolNote -Object $package -Name "PackageIdentifier" -Default "")
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $ids.Add($id)
            }
        }
    }
    return $ids.ToArray()
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
    # Runs in a background runspace on Windows PowerShell 5.1. It does not use
    # ErrorActionPreference Stop around winget: on 5.1 any line winget writes
    # to stderr would then abort the whole check. Every step is written to
    # $Sync.Log so the window can put it in the log files.
    $scriptText = @'
param($Sync, $Candidates, $ExportPath)
$ErrorActionPreference = "Continue"
$log = New-Object System.Collections.Generic.List[string]
$Sync.Log = $log
try {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        $log.Add("Could not switch the console to UTF-8: " + $_.Exception.Message)
    }
    $winget = $null
    foreach ($candidate in @($Candidates)) {
        try {
            $version = (& $candidate --version 2>&1 | ForEach-Object { [string]$_ }) -join " "
            if ($LASTEXITCODE -eq 0) {
                $winget = $candidate
                $log.Add(("Using {0} ({1})" -f $candidate, $version.Trim()))
                break
            }
            $log.Add(("{0} exited with {1}: {2}" -f $candidate, $LASTEXITCODE, $version.Trim()))
        }
        catch {
            $log.Add(("{0} did not start: {1}" -f $candidate, $_.Exception.Message))
        }
    }
    if ($null -eq $winget) {
        throw "No winget.exe could be started."
    }
    $Sync.Winget = $winget
    $common = @("--source", "winget", "--accept-source-agreements", "--disable-interactivity")

    if (Test-Path -LiteralPath $ExportPath) {
        Remove-Item -LiteralPath $ExportPath -Force -ErrorAction SilentlyContinue
    }
    $exportArgs = @("export", "--output", $ExportPath) + $common
    $exportOut = (& $winget @exportArgs 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $log.Add(("winget export exited with {0}." -f $LASTEXITCODE))
    $Sync.ExportText = ""
    if (Test-Path -LiteralPath $ExportPath) {
        $Sync.ExportText = [System.IO.File]::ReadAllText($ExportPath)
        Remove-Item -LiteralPath $ExportPath -Force -ErrorAction SilentlyContinue
    }
    else {
        $log.Add("winget export wrote no file. Output: " + $exportOut.Trim())
    }

    $listArgs = @("list") + $common
    $Sync.ListText = (& $winget @listArgs 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $log.Add(("winget list exited with {0}." -f $LASTEXITCODE))

    # Names of everything in Apps and features plus Store packages, for apps
    # winget cannot match to its source.
    $names = New-Object System.Collections.Generic.List[string]
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $keys) {
        foreach ($entry in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
            $displayName = [string]$entry.DisplayName
            if (-not [string]::IsNullOrWhiteSpace($displayName)) {
                $names.Add($displayName)
            }
        }
    }
    try {
        foreach ($package in @(Get-AppxPackage -ErrorAction Stop)) {
            $names.Add([string]$package.Name)
        }
    }
    catch {
        $log.Add("Could not list Store apps: " + $_.Exception.Message)
    }
    $Sync.DisplayNames = $names.ToArray()
    $log.Add(("Read {0} names from Apps and features and the Store." -f $names.Count))

    $upgradeArgs = @("upgrade") + $common
    $Sync.UpgradeText = (& $winget @upgradeArgs 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $log.Add(("winget upgrade exited with {0}." -f $LASTEXITCODE))
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

$script:WinToolNameNoise = @("x64", "x86", "arm64", "amd64", "win64", "win32", "64", "32", "bit", "64bit", "32bit", "user", "machine", "version", "v")

function ConvertTo-WinToolAppNameKey {
    param(
        [AllowEmptyString()][string]$Text
    )
    # "WinRAR 7.01 (64-bit)" and "WinRAR" give the same key: lower-case words
    # with version numbers and architecture words dropped from the end.
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($token in ([regex]::Split(([string]$Text).ToLowerInvariant(), '[^\p{L}\p{N}]+'))) {
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $tokens.Add($token)
        }
    }
    while ($tokens.Count -gt 1) {
        $last = $tokens[$tokens.Count - 1]
        if ($last -match '^\d+$' -or $script:WinToolNameNoise -contains $last) {
            $tokens.RemoveAt($tokens.Count - 1)
            continue
        }
        break
    }
    return ($tokens.ToArray() -join " ")
}

function Find-WinToolAppByName {
    param(
        [string[]]$DisplayName,
        $App
    )
    # Apps installed outside winget (a vendor installer or the Store) are
    # missing from winget export. Match them by the name Windows lists in
    # Apps and features, or by the Store package name, against the catalog
    # name and its detectNames. Names must match as whole words.
    $seen = @{}
    foreach ($name in @($DisplayName)) {
        $key = ConvertTo-WinToolAppNameKey -Text $name
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $seen[$key] = $true
        }
    }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($App)) {
        $names = @([string]$item.Name) + @($item.DetectNames)
        foreach ($name in $names) {
            $key = ConvertTo-WinToolAppNameKey -Text ([string]$name)
            if (-not [string]::IsNullOrWhiteSpace($key) -and $seen.ContainsKey($key)) {
                $found.Add([string]$item.WingetId)
                break
            }
        }
    }
    return $found.ToArray()
}

function Resolve-WinToolAppState {
    param(
        [string[]]$CatalogId,
        [string[]]$InstalledId,
        [AllowEmptyString()][string]$UpgradeText,
        [AllowEmptyString()][string]$ListText
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
    # winget list catches packages that export leaves out.
    foreach ($id in @(Find-WinToolWingetIdInText -Text $ListText -KnownId $CatalogId)) {
        $installed[$id] = $true
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
