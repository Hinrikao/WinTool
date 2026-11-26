# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# Fixes are listed in data/fixes.json. A step is either a program under
# %SystemRoot% with fixed arguments, or one of the named scripts below. The
# catalog cannot carry its own script text.

function Get-WinToolFixCatalog {
    return (Get-WinToolCachedPayloadObject -Name "Fixes")
}

function Get-WinToolSystemRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        return $env:SystemRoot
    }
    return "C:\Windows"
}

function Get-WinToolSystemFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    return ((Get-WinToolSystemRoot).TrimEnd('\') + "\" + $RelativePath.TrimStart('\'))
}

function Get-WinToolFixScriptName {
    return @("windows-update-reset", "winget-repair")
}

function Get-WinToolFixScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    switch ($Name) {
        "windows-update-reset" {
            return @'
$ErrorActionPreference = "Continue"
$services = @("wuauserv", "usosvc", "bits", "cryptsvc", "msiserver")
foreach ($name in $services) {
    $service = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -ne "Stopped") {
        Write-Output ("Stopping " + $name)
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    }
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$folders = @(
    (Join-Path $env:SystemRoot "SoftwareDistribution"),
    (Join-Path $env:SystemRoot "System32\catroot2")
)
foreach ($folder in $folders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        continue
    }
    $newName = (Split-Path -Leaf $folder) + ".wintool-" + $stamp
    try {
        Rename-Item -LiteralPath $folder -NewName $newName -ErrorAction Stop
        Write-Output ("Renamed " + $folder + " to " + $newName)
    }
    catch {
        Write-Output ("Could not rename " + $folder + ": " + $_.Exception.Message)
    }
}
foreach ($name in @("cryptsvc", "bits", "wuauserv")) {
    Write-Output ("Starting " + $name)
    Start-Service -Name $name -ErrorAction SilentlyContinue
}
Write-Output "Windows Update components were reset. Restart the PC, then check for updates."
'@
        }
        "winget-repair" {
            return @'
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try {
    $nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
    if ($null -eq $nuget) {
        Write-Output "Installing the NuGet package provider."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($null -eq $gallery) {
        Register-PSRepository -Default
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-Output "Installing the Microsoft.WinGet.Client module."
    $options = @{ Name = "Microsoft.WinGet.Client"; Scope = "AllUsers"; Repository = "PSGallery"; Force = $true }
    $installer = Get-Command -Name Install-Module
    if ($installer.Parameters.ContainsKey("AllowClobber")) { $options["AllowClobber"] = $true }
    if ($installer.Parameters.ContainsKey("SkipPublisherCheck")) { $options["SkipPublisherCheck"] = $true }
    Install-Module @options
    Import-Module Microsoft.WinGet.Client
    Write-Output "Repairing winget. This downloads App Installer and its dependencies."
    Repair-WinGetPackageManager -AllUsers -Force -Latest
    Write-Output "winget was repaired."
}
catch {
    Write-Output ("The module repair did not work: " + $_.Exception.Message)
    Write-Output "Registering App Installer again from the copy Windows has."
    Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    Write-Output "App Installer was registered again. Open a new window and try winget."
}
'@
        }
        default {
            throw (Get-WinToolText "msg.unknown-fix-script-n" $Name)
        }
    }
}

function Get-WinToolFixPlan {
    param(
        [Parameter(Mandatory = $true)]$Fix
    )
    $steps = New-Object System.Collections.Generic.List[object]
    foreach ($step in @(Get-WinToolNote -Object $Fix -Name "steps" -Default @())) {
        $type = [string](Get-WinToolNote -Object $step -Name "type" -Default "")
        $label = [string](Get-WinToolNote -Object $step -Name "label" -Default ([string]$Fix.name))
        if ($type -eq "process") {
            $steps.Add([pscustomobject]@{
                Type = "process"
                Label = $label
                FilePath = (Get-WinToolSystemFile -RelativePath ([string]$step.file))
                Arguments = @(Get-WinToolNote -Object $step -Name "args" -Default @())
            })
        }
        elseif ($type -eq "script") {
            $steps.Add([pscustomobject]@{
                Type = "fix-script"
                Label = $label
                Script = [string]$step.script
            })
        }
        else {
            throw (Get-WinToolText "msg.fix-n-has-an-unknown-step-type-n" $([string]$Fix.id) $type)
        }
    }
    return $steps.ToArray()
}

function Test-WinToolFixCatalog {
    param(
        $Catalog,
        $Errors
    )
    if ([int](Get-WinToolNote -Object $Catalog -Name "schemaVersion" -Default 0) -ne 1) {
        $Errors.Add("fixes.json schemaVersion must be 1.")
    }
    $ids = @{}
    $known = Get-WinToolFixScriptName
    foreach ($fix in @(Get-WinToolNote -Object $Catalog -Name "fixes" -Default @())) {
        $id = [string](Get-WinToolNote -Object $fix -Name "id" -Default "")
        if ([string]::IsNullOrWhiteSpace($id) -or $ids.ContainsKey($id)) {
            $Errors.Add("A fix is missing an id or uses one twice: '$id'.")
        }
        $ids[$id] = $true
        foreach ($field in @("name", "description")) {
            if ([string]::IsNullOrWhiteSpace([string](Get-WinToolNote -Object $fix -Name $field -Default ""))) {
                $Errors.Add("Fix '$id' needs a $field.")
            }
        }
        $steps = @(Get-WinToolNote -Object $fix -Name "steps" -Default @())
        if ($steps.Count -eq 0) {
            $Errors.Add("Fix '$id' has no steps.")
        }
        foreach ($step in $steps) {
            $type = [string](Get-WinToolNote -Object $step -Name "type" -Default "")
            if ($type -eq "process") {
                $file = [string](Get-WinToolNote -Object $step -Name "file" -Default "")
                if ($file -notmatch '^System32\\[A-Za-z0-9]+\.exe$') {
                    $Errors.Add("Fix '$id' runs '$file'. Use a program under System32.")
                }
            }
            elseif ($type -eq "script") {
                if ($known -notcontains [string](Get-WinToolNote -Object $step -Name "script" -Default "")) {
                    $Errors.Add("Fix '$id' names a script WinTool does not have.")
                }
            }
            else {
                $Errors.Add("Fix '$id' has an unknown step type '$type'.")
            }
        }
    }
    if ($ids.Count -lt 4) {
        $Errors.Add("fixes.json should list the four built-in fixes.")
    }
}
