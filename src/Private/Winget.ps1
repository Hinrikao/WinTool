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
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Scope
    )
    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("install")
    $arguments.Add("--id")
    $arguments.Add($Id)
    $arguments.Add("--exact")
    $arguments.Add("--source")
    $arguments.Add("winget")
    $arguments.Add("--accept-package-agreements")
    $arguments.Add("--accept-source-agreements")
    $arguments.Add("--disable-interactivity")
    if (-not [string]::IsNullOrWhiteSpace($Scope)) {
        $arguments.Add("--scope")
        $arguments.Add($Scope)
    }
    return $arguments.ToArray()
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
        $App
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
            Label = "Install $name"
            WingetId = [string]$wingetId
            Scope = [string]$scope
        })
    }
    return $steps.ToArray()
}
