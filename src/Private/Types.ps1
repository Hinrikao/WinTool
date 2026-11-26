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
        if ($refs.Count -gt 0) {
            Add-Type -TypeDefinition $TypeDefinition -ReferencedAssemblies $refs -Language CSharp -ErrorAction Stop
        }
        else {
            Add-Type -TypeDefinition $TypeDefinition -Language CSharp -ErrorAction Stop
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
    $stamp = Get-Date
    try { $null = Initialize-WinToolConsoleApi } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolThemeEntryType } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolGlyphMap } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolGlyphDraw } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolProcessPipe } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolNativeMethod } catch { $null = $_.Exception.Message }
    try { $null = Initialize-WinToolFontLoader } catch { $null = $_.Exception.Message }
    Write-WinToolStartupMark -Name "compiledTypes" -Started $stamp
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
