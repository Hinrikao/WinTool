# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolTweakStep {
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [Parameter(Mandatory = $true)][ValidateSet("Apply", "Undo")][string]$Direction
    )
    $block = $null
    if ($Direction -eq "Apply") {
        $block = Get-WinToolNote -Object $Tweak -Name "apply"
    }
    else {
        $block = Get-WinToolNote -Object $Tweak -Name "undo"
    }
    $steps = New-Object System.Collections.Generic.List[object]
    if ($null -eq $block) {
        return $steps.ToArray()
    }
    Add-WinToolActionStep -Action $block -Tweak $Tweak -Steps $steps
    return $steps.ToArray()
}

function Add-WinToolActionStep {
    param(
        $Action,
        $Tweak,
        $Steps
    )
    $type = [string](Get-WinToolNote -Object $Action -Name "type" -Default "")
    if ($type -eq "group") {
        foreach ($child in @(Get-WinToolNote -Object $Action -Name "actions" -Default @())) {
            Add-WinToolActionStep -Action $child -Tweak $Tweak -Steps $Steps
        }
        return
    }
    if ($type -eq "registry") {
        foreach ($entry in @(Get-WinToolNote -Object $Action -Name "entries" -Default @())) {
            $Steps.Add([pscustomobject]@{
                Type = "registry-set"
                Path = [string](Get-WinToolNote -Object $entry -Name "path" -Default "")
                Name = [string](Get-WinToolNote -Object $entry -Name "name" -Default "")
                Value = Get-WinToolNote -Object $entry -Name "value"
                Kind = [string](Get-WinToolNote -Object $entry -Name "kind" -Default "DWord")
            })
        }
        return
    }
    if ($type -eq "registry-remove") {
        foreach ($entry in @(Get-WinToolNote -Object $Action -Name "entries" -Default @())) {
            $Steps.Add([pscustomobject]@{
                Type = "registry-remove-value"
                Path = [string](Get-WinToolNote -Object $entry -Name "path" -Default "")
                Name = [string](Get-WinToolNote -Object $entry -Name "name" -Default "")
            })
        }
        return
    }
    if ($type -eq "registry-key") {
        $Steps.Add([pscustomobject]@{
            Type = "registry-key"
            Operation = [string](Get-WinToolNote -Object $Action -Name "operation" -Default "")
            Path = [string](Get-WinToolNote -Object $Action -Name "path" -Default "")
            DefaultValue = Get-WinToolNote -Object $Action -Name "defaultValue" -Default $null
        })
        return
    }
    if ($type -eq "service") {
        $Steps.Add([pscustomobject]@{
            Type = "service"
            Name = [string](Get-WinToolNote -Object $Action -Name "name" -Default "")
            StartupType = [string](Get-WinToolNote -Object $Action -Name "startupType" -Default "Manual")
            Stop = [bool](Get-WinToolNote -Object $Action -Name "stop" -Default $false)
        })
        return
    }
    if ($type -eq "scheduled-task") {
        $Steps.Add([pscustomobject]@{
            Type = "scheduled-task"
            TaskName = [string](Get-WinToolNote -Object $Action -Name "taskName" -Default "")
            TaskPath = [string](Get-WinToolNote -Object $Action -Name "taskPath" -Default "")
            State = [string](Get-WinToolNote -Object $Action -Name "state" -Default "Enabled")
        })
        return
    }
    if ($type -eq "appx") {
        $packages = New-Object System.Collections.Generic.List[string]
        foreach ($package in @(Get-WinToolNote -Object $Action -Name "packages" -Default @())) {
            $packages.Add([string]$package)
        }
        $Steps.Add([pscustomobject]@{
            Type = "appx-remove"
            Packages = $packages.ToArray()
        })
        return
    }
    if ($type -eq "appx-restore") {
        $apply = Get-WinToolNote -Object $Tweak -Name "apply"
        $packages = New-Object System.Collections.Generic.List[string]
        foreach ($package in @(Get-WinToolNote -Object $apply -Name "packages" -Default @())) {
            $packages.Add([string]$package)
        }
        $Steps.Add([pscustomobject]@{
            Type = "appx-restore"
            Packages = $packages.ToArray()
        })
        return
    }
    throw "WinTool does not know how to run the tweak action '$type'."
}

function Get-WinToolRestorePointScript {
    $scriptText = @'
param($Sync, $Description)
$ErrorActionPreference = "Stop"
try {
    $drive = $env:SystemDrive + "\"
    Enable-ComputerRestore -Drive $drive
    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $hadFrequency = $false
    $previousFrequency = 0
    if (Test-Path -LiteralPath $key) {
        $item = Get-ItemProperty -LiteralPath $key -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            $hadFrequency = $true
            $previousFrequency = [int]$item.SystemRestorePointCreationFrequency
        }
    }
    else {
        New-Item -Path $key -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $key -Name "SystemRestorePointCreationFrequency" -PropertyType DWord -Value 0 -Force | Out-Null
    try {
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS
    }
    finally {
        if ($hadFrequency) {
            New-ItemProperty -LiteralPath $key -Name "SystemRestorePointCreationFrequency" -PropertyType DWord -Value $previousFrequency -Force | Out-Null
        }
        else {
            Remove-ItemProperty -LiteralPath $key -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue
        }
    }
    $Sync.Ok = $true
}
catch {
    $Sync.Ok = $false
    $Sync.Error = $_.Exception.Message
}
$Sync.Done = $true
'@
    return $scriptText
}

function Invoke-WinToolRestorePoint {
    param(
        [string]$Description = "WinTool before tweaks"
    )
    if (-not (Test-WinToolWindows)) {
        throw "Restore points can only be created on Windows."
    }
    $sync = @{
        Done = $false
        Ok = $false
        Error = $null
    }
    $body = [scriptblock]::Create((Get-WinToolRestorePointScript))
    & $body $sync $Description
    if (-not $sync.Ok) {
        $reason = [string]$sync.Error
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $reason = "No details were returned."
        }
        throw "Restore point was not created. $reason"
    }
}

function Start-WinToolRestorePointJob {
    param(
        [string]$Description = "WinTool before tweaks"
    )
    $sync = [hashtable]::Synchronized(@{
        Done = $false
        Ok = $false
        Error = $null
    })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript((Get-WinToolRestorePointScript))
    [void]$powershell.AddArgument($sync)
    [void]$powershell.AddArgument($Description)
    [void]$powershell.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $powershell
        Handle = $null
        Sync = $sync
        Runspace = $runspace
    }
}

function Stop-WinToolThread {
    param($Job)
    if ($null -eq $Job) {
        return
    }
    try { $Job.PowerShell.Stop() } catch { $null = $_.Exception.Message }
    try { $Job.PowerShell.Dispose() } catch { $null = $_.Exception.Message }
    try { $Job.Runspace.Close() } catch { $null = $_.Exception.Message }
    try { $Job.Runspace.Dispose() } catch { $null = $_.Exception.Message }
}

function Send-WinToolSettingChange {
    if (-not (Test-WinToolWindows)) {
        return
    }
    if (-not ("WinTool.NativeMethods" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace WinTool {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, int Msg, IntPtr wParam, string lParam,
            int fuFlags, int uTimeout, out IntPtr lpdwResult);
    }
}
"@
    }
    $result = [IntPtr]::Zero
    [WinTool.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, "ImmersiveColorSet", 2, 200, [ref]$result) | Out-Null
    [WinTool.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, "Policy", 2, 200, [ref]$result) | Out-Null
}

function Restart-WinToolExplorer {
    if (-not (Test-WinToolWindows)) {
        return
    }
    Write-WinToolLog -Message "Restarting File Explorer so the changes show up." -Level "info"
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
}

function Invoke-WinToolTweakStep {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    if (-not (Test-WinToolWindows)) {
        throw "Tweaks can only be applied on Windows."
    }
    $type = [string]$Step.Type
    if ($type -eq "registry-set") {
        if (-not (Test-Path -LiteralPath $Step.Path)) {
            New-Item -Path $Step.Path -Force | Out-Null
        }
        if ([string]::IsNullOrEmpty([string]$Step.Name)) {
            Set-Item -LiteralPath $Step.Path -Value $Step.Value
            return
        }
        New-ItemProperty -LiteralPath $Step.Path -Name $Step.Name -Value $Step.Value -PropertyType $Step.Kind -Force | Out-Null
        return
    }
    if ($type -eq "registry-remove-value") {
        if (Test-Path -LiteralPath $Step.Path) {
            Remove-ItemProperty -LiteralPath $Step.Path -Name $Step.Name -ErrorAction SilentlyContinue
        }
        return
    }
    if ($type -eq "registry-key") {
        if ($Step.Operation -eq "remove") {
            if (Test-Path -LiteralPath $Step.Path) {
                Remove-Item -LiteralPath $Step.Path -Recurse -Force
            }
            return
        }
        if (-not (Test-Path -LiteralPath $Step.Path)) {
            New-Item -Path $Step.Path -Force | Out-Null
        }
        if ($null -ne $Step.DefaultValue) {
            Set-Item -LiteralPath $Step.Path -Value ([string]$Step.DefaultValue)
        }
        return
    }
    if ($type -eq "service") {
        $service = Get-Service -Name $Step.Name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-WinToolLog -Message "Service $($Step.Name) is not on this PC. Skipped." -Level "warn"
            return
        }
        Set-Service -Name $Step.Name -StartupType $Step.StartupType
        if ($Step.Stop -and $Step.StartupType -eq "Disabled") {
            Stop-Service -Name $Step.Name -Force -ErrorAction SilentlyContinue
        }
        return
    }
    if ($type -eq "scheduled-task") {
        $task = Get-ScheduledTask -TaskName $Step.TaskName -TaskPath $Step.TaskPath -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            Write-WinToolLog -Message "Scheduled task $($Step.TaskName) was not found. Skipped." -Level "warn"
            return
        }
        if ($Step.State -eq "Disabled") {
            Disable-ScheduledTask -TaskName $Step.TaskName -TaskPath $Step.TaskPath | Out-Null
        }
        else {
            Enable-ScheduledTask -TaskName $Step.TaskName -TaskPath $Step.TaskPath | Out-Null
        }
        return
    }
    if ($type -eq "appx-remove") {
        foreach ($name in @($Step.Packages)) {
            $packages = @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)
            if ($packages.Count -eq 0) {
                Write-WinToolLog -Message "$name is not installed for this user. Skipped." -Level "info"
                continue
            }
            foreach ($package in $packages) {
                Remove-AppxPackage -Package $package.PackageFullName
                Write-WinToolLog -Message "Removed $($package.Name)." -Level "ok"
            }
        }
        return
    }
    if ($type -eq "appx-restore") {
        $provisioned = @(Get-AppxProvisionedPackage -Online)
        foreach ($name in @($Step.Packages)) {
            $match = $null
            foreach ($package in $provisioned) {
                if ([string]$package.DisplayName -eq $name) {
                    $match = $package
                    break
                }
            }
            if ($null -eq $match) {
                Write-WinToolLog -Message "Cannot restore $name because Windows no longer has a provisioned copy." -Level "warn"
                continue
            }
            $manifest = Join-Path ([string]$match.InstallLocation) "AppxManifest.xml"
            if (-not (Test-Path -LiteralPath $manifest)) {
                Write-WinToolLog -Message "Cannot restore $name because its manifest is missing." -Level "warn"
                continue
            }
            Add-AppxPackage -Register -DisableDevelopmentMode $manifest
            Write-WinToolLog -Message "Restored $name." -Level "ok"
        }
        return
    }
    throw "Unknown tweak step '$type'."
}

function Invoke-WinToolTweakChange {
    param(
        $Tweak,
        [Parameter(Mandatory = $true)][ValidateSet("Apply", "Undo")][string]$Direction,
        [bool]$RestartExplorer = $false
    )
    $needsExplorer = $false
    $needsTheme = $false
    foreach ($item in @($Tweak)) {
        $name = [string](Get-WinToolNote -Object $item -Name "name" -Default "Tweak")
        Write-WinToolLog -Message ("{0}: {1}" -f $Direction, $name) -Level "info"
        $steps = @(Get-WinToolTweakStep -Tweak $item -Direction $Direction)
        foreach ($step in $steps) {
            Invoke-WinToolTweakStep -Step $step
        }
        $refresh = [string](Get-WinToolNote -Object $item -Name "refresh" -Default "none")
        if ($refresh -eq "explorer") {
            $needsExplorer = $true
        }
        if ($refresh -eq "theme") {
            $needsTheme = $true
        }
    }
    if ($needsTheme) {
        Send-WinToolSettingChange
    }
    if ($needsExplorer -and $RestartExplorer) {
        Restart-WinToolExplorer
    }
}

# Reading the current state of a tweak. A probe is a hashtable of script
# blocks that read Windows; tests pass a fake one.
function Get-WinToolTweakProbe {
    $script:WinToolAppxNames = $null
    return @{
        ReadValue = {
            param($Path, $Name)
            if (-not (Test-Path -LiteralPath $Path)) {
                return $null
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            return $key.GetValue([string]$Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        KeyExists = {
            param($Path)
            return (Test-Path -LiteralPath $Path)
        }
        ServiceStart = {
            param($Name)
            $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
            if ($null -eq $service) {
                return $null
            }
            return [string]$service.StartType
        }
        TaskState = {
            param($TaskPath, $TaskName)
            $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            if ($null -eq $task) {
                return $null
            }
            return [string]$task.State
        }
        AppxInstalled = {
            param($Name)
            if ($null -eq $script:WinToolAppxNames) {
                $names = @{}
                foreach ($package in @(Get-AppxPackage -ErrorAction Stop)) {
                    $names[[string]$package.Name] = $true
                }
                $script:WinToolAppxNames = $names
            }
            return $script:WinToolAppxNames.ContainsKey([string]$Name)
        }
    }
}

function Test-WinToolTweakStepState {
    # Returns "on", "off" or "unknown" for one apply step.
    param(
        [Parameter(Mandatory = $true)]$Step,
        [Parameter(Mandatory = $true)][hashtable]$Probe
    )
    try {
        switch ([string]$Step.Type) {
            "registry-set" {
                $current = & $Probe.ReadValue ([string]$Step.Path) ([string]$Step.Name)
                if ($null -eq $current) {
                    return "off"
                }
                $kind = [string]$Step.Kind
                if ($kind -eq "DWord" -or $kind -eq "QWord") {
                    $wantedNumber = [int64]0
                    $currentNumber = [int64]0
                    if (-not [int64]::TryParse([string]$Step.Value, [ref]$wantedNumber)) { return "unknown" }
                    if ($current -is [int] -or $current -is [long] -or $current -is [uint32] -or $current -is [uint64]) {
                        $currentNumber = [int64]$current
                    }
                    elseif (-not [int64]::TryParse([string]$current, [ref]$currentNumber)) {
                        return "off"
                    }
                    # DWORDs above 0x7FFFFFFF come back negative from the registry.
                    if ($kind -eq "DWord" -and $currentNumber -lt 0) { $currentNumber += 4294967296 }
                    if ($kind -eq "DWord" -and $wantedNumber -lt 0) { $wantedNumber += 4294967296 }
                    if ($currentNumber -eq $wantedNumber) { return "on" }
                    return "off"
                }
                if ($kind -eq "String" -or $kind -eq "ExpandString" -or [string]::IsNullOrEmpty($kind)) {
                    if ([string]$current -eq [string]$Step.Value) { return "on" }
                    return "off"
                }
                return "unknown"
            }
            "registry-remove-value" {
                $current = & $Probe.ReadValue ([string]$Step.Path) ([string]$Step.Name)
                if ($null -eq $current) { return "on" }
                return "off"
            }
            "registry-key" {
                $exists = [bool](& $Probe.KeyExists ([string]$Step.Path))
                if ([string]$Step.Operation -eq "remove") {
                    if ($exists) { return "off" }
                    return "on"
                }
                if ($exists) { return "on" }
                return "off"
            }
            "service" {
                $start = & $Probe.ServiceStart ([string]$Step.Name)
                if ($null -eq $start) { return "unknown" }
                if ([string]$start -eq [string]$Step.StartupType) { return "on" }
                return "off"
            }
            "scheduled-task" {
                $state = & $Probe.TaskState ([string]$Step.TaskPath) ([string]$Step.TaskName)
                if ($null -eq $state) { return "unknown" }
                $disabled = ([string]$state -eq "Disabled")
                if (([string]$Step.State -eq "Disabled") -eq $disabled) { return "on" }
                return "off"
            }
            "appx-remove" {
                foreach ($name in @($Step.Packages)) {
                    if ([bool](& $Probe.AppxInstalled ([string]$name))) { return "off" }
                }
                return "on"
            }
            default {
                return "unknown"
            }
        }
    }
    catch {
        return "unknown"
    }
}

function Get-WinToolTweakState {
    # "on" when every apply step is already in place, "off" when one is not,
    # "unknown" when the state cannot be read.
    param(
        [Parameter(Mandatory = $true)]$Tweak,
        [Parameter(Mandatory = $true)][hashtable]$Probe
    )
    $steps = @()
    try {
        $steps = @(Get-WinToolTweakStep -Tweak $Tweak -Direction "Apply")
    }
    catch {
        return "unknown"
    }
    if ($steps.Count -eq 0) {
        return "unknown"
    }
    $unknown = $false
    foreach ($step in $steps) {
        $state = Test-WinToolTweakStepState -Step $step -Probe $Probe
        if ($state -eq "off") {
            return "off"
        }
        if ($state -eq "unknown") {
            $unknown = $true
        }
    }
    if ($unknown) {
        return "unknown"
    }
    return "on"
}

function Set-WinToolTweakToggleState {
    # Puts a row's switch in line with a detected state. Unknown shows off.
    param(
        [Parameter(Mandatory = $true)]$Row,
        [Parameter(Mandatory = $true)][string]$State
    )
    $Row.State = $State
    $Row.Checkbox.IsChecked = ($State -eq "on")
}

function Invoke-WinToolTweakItem {
    # Runs the queued switch changes. Each item is @{ Row; Direction; Previous }.
    # A change that throws puts the switch back where it was. Returns $true
    # when File Explorer should be restarted.
    param(
        [object[]]$Item,
        [Parameter(Mandatory = $true)][hashtable]$Probe,
        [scriptblock]$Runner
    )
    if ($null -eq $Runner) {
        $Runner = {
            param($Tweak, $Direction)
            Invoke-WinToolTweakChange -Tweak $Tweak -Direction $Direction -RestartExplorer $false
        }
    }
    $needsExplorer = $false
    foreach ($entry in @($Item)) {
        $row = $entry.Row
        $name = [string](Get-WinToolNote -Object $row.Tweak -Name "name" -Default "Tweak")
        try {
            & $Runner $row.Tweak ([string]$entry.Direction)
            $state = Get-WinToolTweakState -Tweak $row.Tweak -Probe $Probe
            if ($state -eq "unknown") {
                $row.State = "unknown"
                $row.Checkbox.IsChecked = ([string]$entry.Direction -eq "Apply")
            }
            else {
                Set-WinToolTweakToggleState -Row $row -State $state
            }
            if ([string](Get-WinToolNote -Object $row.Tweak -Name "refresh" -Default "none") -eq "explorer") {
                $needsExplorer = $true
            }
            $verb = "Turned on"
            if ([string]$entry.Direction -eq "Undo") { $verb = "Turned off" }
            Write-WinToolLog -Message ("{0}: {1}." -f $verb, $name) -Level "ok"
        }
        catch {
            $row.Checkbox.IsChecked = [bool]$entry.Previous
            Write-WinToolLog -Message ("Could not change {0}, so the switch went back. {1}" -f $name, $_.Exception.Message) -Level "error"
        }
        $row.Checkbox.IsEnabled = $true
    }
    return $needsExplorer
}
