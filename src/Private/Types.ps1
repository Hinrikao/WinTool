# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

function Get-WinToolCSharpReference {
    param([type[]]$Type)
    $refs = New-Object System.Collections.Generic.List[string]
    $core = ($PSVersionTable.PSEdition -eq "Core")
    if ($core) {
        foreach ($name in @(
                "System.Runtime",
                "System.Collections",
                "System.Collections.Concurrent",
                "System.ComponentModel.Primitives",
                "System.ObjectModel",
                "netstandard",
                "System.Diagnostics.Process"
            )) {
            [void]$refs.Add($name)
        }
    }
    $types = New-Object System.Collections.Generic.List[type]
    if (-not $core) {
        [void]$types.Add([object])
        [void]$types.Add([System.ComponentModel.INotifyPropertyChanged])
    }
    foreach ($item in @($Type)) {
        if ($null -ne $item -and -not $types.Contains($item)) {
            [void]$types.Add($item)
        }
    }
    foreach ($item in $types) {
        try {
            $name = [string]$item.Assembly.GetName().Name
            if ($name -eq "System.Private.CoreLib" -or $name -eq "mscorlib") {
                if (-not $core) {
                    $location = [string]$item.Assembly.Location
                    if (-not [string]::IsNullOrWhiteSpace($location) -and (Test-Path -LiteralPath $location) -and -not $refs.Contains($location)) {
                        [void]$refs.Add($location)
                    }
                }
                continue
            }
            $location = [string]$item.Assembly.Location
            if (-not [string]::IsNullOrWhiteSpace($location) -and (Test-Path -LiteralPath $location)) {
                if (-not $refs.Contains($location)) {
                    [void]$refs.Add($location)
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($name) -and -not $refs.Contains($name)) {
                [void]$refs.Add($name)
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    return @($refs.ToArray())
}

function Add-WinToolCSharpType {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$TypeDefinition,
        [type[]]$ReferenceType
    )
    if ($null -ne ($Name -as [type])) {
        return $true
    }
    $stamp = Get-Date
    try {
        $refs = @(Get-WinToolCSharpReference -Type $ReferenceType)
        $cacheDir = $null
        $cachePath = $null
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $cacheDir = Join-Path $env:LOCALAPPDATA "WinTool\cache\types"
            $hash = [System.Security.Cryptography.SHA256]::Create()
            try {
                $payload = $Name + "`n" + [string]$PSVersionTable.PSVersion + "`n" + ($refs -join "`n") + "`n" + $TypeDefinition
                $bytes = $hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
                $id = ([System.BitConverter]::ToString($bytes) -replace "-", "").ToLowerInvariant()
                $cachePath = Join-Path $cacheDir ($id + ".dll")
            }
            finally {
                $hash.Dispose()
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($cachePath) -and (Test-Path -LiteralPath $cachePath)) {
            Add-Type -Path $cachePath -ErrorAction Stop
            Write-WinToolStartupMark -Name ("addType." + $Name) -Started $stamp
            return $true
        }
        if ($refs.Count -gt 0) {
            if (-not [string]::IsNullOrWhiteSpace($cachePath)) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                }
                Add-Type -TypeDefinition $TypeDefinition -ReferencedAssemblies $refs -Language CSharp -OutputAssembly $cachePath -ErrorAction Stop
            }
            else {
                Add-Type -TypeDefinition $TypeDefinition -ReferencedAssemblies $refs -Language CSharp -ErrorAction Stop
            }
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace($cachePath)) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                }
                Add-Type -TypeDefinition $TypeDefinition -Language CSharp -OutputAssembly $cachePath -ErrorAction Stop
            }
            else {
                Add-Type -TypeDefinition $TypeDefinition -Language CSharp -ErrorAction Stop
            }
        }
        Write-WinToolStartupMark -Name ("addType." + $Name) -Started $stamp
        return $true
    }
    catch {
        $null = $_.Exception.Message
        try {
            Write-WinToolLog -Message ((Get-WinToolText "msg.could-not-compile-n-n") -f $Name, $_.Exception.Message) -Level "warn"
        }
        catch {
            $null = $_.Exception.Message
        }
        Write-WinToolStartupMark -Name ("addType." + $Name + ".failed") -Started $stamp
        return $false
    }
}

function Initialize-WinToolCompiledType {
    param([switch]$CoreOnly)
    $stamp = Get-Date
    try { $null = Initialize-WinToolConsoleApi } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolThemeEntryType } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolNativeMethod } catch { $null = $_.Exception.Message }
    if ($CoreOnly) {
        Write-WinToolStartupMark -Name "compiledTypes" -Started $stamp
        return
    }
    try { $null = Initialize-WinToolGlyphMap } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolGlyphDraw } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolProcessPipe } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolFontLoader } catch { $null = $_.Exception.Message }
    $mark = "compiledTypes"
    if ($null -ne $script:WinToolStartupMarks -and $script:WinToolStartupMarks.Contains("compiledTypes")) {
        $mark = "compiledTypes.deferred"
    }
    Write-WinToolStartupMark -Name $mark -Started $stamp
}

function Start-WinToolIdleWork {
    param([Parameter(Mandatory = $true)][string]$Expression)
    if ($null -eq $script:WinToolWindow) { return }
    $callback = [scriptblock]::Create($Expression)
    $null = $script:WinToolWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle, [System.Action]$callback)
}

function Start-WinToolPostRenderHeartbeat {
    Start-WinToolDispatcherHeartbeat
    if ($null -ne $script:WinToolDispatcherBeat) {
        $script:WinToolDispatcherBeat.Restart()
        $script:WinToolDispatcherLastMs = 0
    }
}

function Write-WinToolStartupMark {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [datetime]$Started
    )
    if ($null -eq $script:WinToolStartupMarks) {
        $script:WinToolStartupMarks = [ordered]@{}
    }
    $elapsed = $null
    if ($null -ne $Started) {
        $elapsed = [int]((Get-Date) - $Started).TotalMilliseconds
    }
    elseif ($null -ne $script:WinToolStartupStamp) {
        $elapsed = [int]$script:WinToolStartupStamp.ElapsedMilliseconds
    }
    $script:WinToolStartupMarks[$Name] = $elapsed
}

function Write-WinToolStartupLog {
    $path = [string]$env:WINTOOL_STARTUP_LOG
    if ([string]::IsNullOrWhiteSpace($path) -or $null -eq $script:WinToolStartupMarks) {
        return
    }
    try {
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($key in @($script:WinToolStartupMarks.Keys)) {
            [void]$lines.Add(("{0}={1}" -f $key, $script:WinToolStartupMarks[$key]))
        }
        [System.IO.File]::WriteAllLines($path, $lines.ToArray())
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Enter-WinToolUiWork {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $script:WinToolUiWorkStack) {
        $script:WinToolUiWorkStack = New-Object System.Collections.Generic.List[string]
    }
    [void]$script:WinToolUiWorkStack.Add($Name)
    $script:WinToolUiWork = $Name
}

function Exit-WinToolUiWork {
    param([datetime]$Started, [string]$Name)
    if ($null -ne $Started -and -not [string]::IsNullOrWhiteSpace($Name)) {
        $elapsed = [int]((Get-Date) - $Started).TotalMilliseconds
        if ($Name.StartsWith("ui.") -and $elapsed -lt 50) {
            # Frequent UI ticks would drown the phase table.
        }
        else {
            Write-WinToolStartupMark -Name $Name -Started $Started
        }
    }
    if ($null -ne $script:WinToolUiWorkStack -and $script:WinToolUiWorkStack.Count -gt 0) {
        $script:WinToolUiWorkStack.RemoveAt($script:WinToolUiWorkStack.Count - 1)
        if ($script:WinToolUiWorkStack.Count -gt 0) {
            $script:WinToolUiWork = $script:WinToolUiWorkStack[$script:WinToolUiWorkStack.Count - 1]
        }
        else {
            $script:WinToolUiWork = $null
        }
    }
    else {
        $script:WinToolUiWork = $null
    }
}

function Invoke-WinToolMeasuredWork {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )
    $started = Get-Date
    Enter-WinToolUiWork -Name $Name
    try {
        return (& $Script)
    }
    finally {
        Exit-WinToolUiWork -Started $started -Name $Name
    }
}

function Start-WinToolDispatcherHeartbeat {
    if ($null -ne $script:WinToolDispatcherHeartbeat) {
        return
    }
    if ($null -eq $script:WinToolDispatcherGaps) {
        $script:WinToolDispatcherGaps = New-Object System.Collections.Generic.List[object]
    }
    $script:WinToolDispatcherBeat = [System.Diagnostics.Stopwatch]::StartNew()
    $script:WinToolDispatcherLastMs = 0
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(50)
    Register-WinToolUiEvent -Control $timer -EventName "Tick" -Name "Dispatcher heartbeat" -Action {
        $now = 0
        if ($null -ne $script:WinToolDispatcherBeat) { $now = [int]$script:WinToolDispatcherBeat.ElapsedMilliseconds }
        $gap = $now - [int]$script:WinToolDispatcherLastMs
        $script:WinToolDispatcherLastMs = $now
        # A 50 ms timer naturally wakes at ~50 ms; only record extra stall.
        if ($gap -ge 100) {
            $work = [string]$script:WinToolUiWork
            if ($work -eq "Dispatcher heartbeat" -or [string]::IsNullOrWhiteSpace($work)) {
                $work = "(idle or unknown)"
            }
            if ($null -eq $script:WinToolDispatcherGaps) {
                $script:WinToolDispatcherGaps = New-Object System.Collections.Generic.List[object]
            }
            [void]$script:WinToolDispatcherGaps.Add([pscustomobject]@{
                    AtMs  = $now
                    GapMs = $gap
                    Work  = $work
                })
        }
    }
    $timer.Start()
    $script:WinToolDispatcherHeartbeat = $timer
}

function Stop-WinToolDispatcherHeartbeat {
    $timer = $script:WinToolDispatcherHeartbeat
    $script:WinToolDispatcherHeartbeat = $null
    if ($null -ne $timer) {
        try { $timer.Stop() } catch { $null = $_.Exception.Message }
    }
}

function Get-WinToolDispatcherGap {
    if ($null -eq $script:WinToolDispatcherGaps) {
        return , @()
    }
    return , $script:WinToolDispatcherGaps.ToArray()
}

function Write-WinToolStartupPhaseTable {
    Write-Output "----- startup phase table -----"
    Write-Output ("{0,-42} {1,8}" -f "Phase", "ms")
    if ($null -ne $script:WinToolStartupMarks) {
        foreach ($key in @($script:WinToolStartupMarks.Keys)) {
            Write-Output ("{0,-42} {1,8}" -f [string]$key, $script:WinToolStartupMarks[$key])
        }
    }
    Write-Output "----- dispatcher gaps of 100 ms or more -----"
    $gaps = @()
    if ($null -ne $script:WinToolDispatcherGaps) {
        $gaps = @($script:WinToolDispatcherGaps | Where-Object { $null -ne $_ })
    }
    if ($gaps.Count -eq 0) {
        Write-Output "(none)"
        return
    }
    Write-Output ("{0,8} {1,8}  {2}" -f "AtMs", "GapMs", "Work")
    $max = 0
    foreach ($gap in $gaps) {
        $at = [int]$gap.AtMs
        $ms = [int]$gap.GapMs
        $work = [string]$gap.Work
        if ($ms -gt $max) { $max = $ms }
        Write-Output ("{0,8} {1,8}  {2}" -f $at, $ms, $work)
    }
    Write-Output ("Dispatcher gap count: {0}; max: {1} ms." -f $gaps.Count, $max)
}

function Import-WinToolAppxModule {
    if ($script:WinToolAppxModuleReady) {
        return
    }
    if ($PSVersionTable.PSEdition -eq "Core") {
        try {
            Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
            $script:WinToolAppxModuleReady = $true
            return
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    try {
        Import-Module Appx -ErrorAction SilentlyContinue
    }
    catch {
        $null = $_.Exception.Message
    }
    $script:WinToolAppxModuleReady = $true
}

function Import-WinToolDismModule {
    if ($script:WinToolDismModuleReady) {
        return
    }
    if ($PSVersionTable.PSEdition -eq "Core") {
        try {
            Import-Module DISM -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
            $script:WinToolDismModuleReady = $true
            return
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    try {
        Import-Module DISM -ErrorAction SilentlyContinue
    }
    catch {
        $null = $_.Exception.Message
    }
    $script:WinToolDismModuleReady = $true
}

function Initialize-WinToolFontLoader {
    return (Add-WinToolCSharpType -Name "WinToolFontLoader" -ReferenceType @([object]) -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinToolFontLoader {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string file);
}
"@)
}
