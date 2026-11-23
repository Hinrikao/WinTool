# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Open and close the real WinTool window and check that nothing is left running.
.DESCRIPTION
    Starts WinTool the way the hidden relaunch does, starts a second copy while
    the first is open (it must hand over and leave without a window), closes
    the first window, then fails if its powershell.exe or anything it started
    is still alive.
#>
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
    Write-Output "Skipping the lifecycle test: this test runs on Windows."
    exit 0
}

$hostScript = Join-Path $PSScriptRoot "WinToolLifecycleHost.ps1"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("wintool-life-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$powershellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Start-LifecycleHost {
    param([string]$Name, [int]$CloseAfter)
    $marker = Join-Path $work ($Name + ".shown")
    $arguments = '-STA -NoProfile -ExecutionPolicy Bypass -File "{0}" -Marker "{1}" -CloseAfterSeconds {2}' -f $hostScript, $marker, $CloseAfter
    $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $work ($Name + ".out")) -RedirectStandardError (Join-Path $work ($Name + ".err"))
    return [pscustomobject]@{ Name = $Name; Process = $process; Marker = $marker }
}

function Get-LifecycleDescendant {
    param([int]$ParentId)
    $found = @()
    foreach ($child in @(Get-CimInstance -ClassName Win32_Process -Filter ("ParentProcessId = {0}" -f $ParentId))) {
        $found += [pscustomobject]@{ Id = [int]$child.ProcessId; Name = [string]$child.Name }
        $found += @(Get-LifecycleDescendant -ParentId ([int]$child.ProcessId))
    }
    return $found
}

function Show-LifecycleOutput {
    param($Item)
    foreach ($suffix in @(".out", ".err")) {
        $path = Join-Path $work ($Item.Name + $suffix)
        if (Test-Path -LiteralPath $path) {
            Write-Output ("--- " + $Item.Name + $suffix)
            Get-Content -LiteralPath $path | Write-Output
        }
    }
}

$first = Start-LifecycleHost -Name "first" -CloseAfter 25
$seen = @{}
$deadline = [DateTime]::UtcNow.AddSeconds(90)
while (-not (Test-Path -LiteralPath $first.Marker)) {
    if ($first.Process.HasExited) {
        Show-LifecycleOutput -Item $first
        throw ("The first WinTool exited before its window opened (exit code {0})." -f $first.Process.ExitCode)
    }
    if ([DateTime]::UtcNow -gt $deadline) {
        Show-LifecycleOutput -Item $first
        throw "The first WinTool window did not open within 90 seconds."
    }
    Start-Sleep -Milliseconds 250
}
Write-Output "First window is open."

# A second launch must leave by itself, without a window of its own.
$second = Start-LifecycleHost -Name "second" -CloseAfter 2
if (-not $second.Process.WaitForExit(60000)) {
    Stop-Process -Id $second.Process.Id -Force
    throw "A second WinTool launch did not exit while the first was open."
}
if (Test-Path -LiteralPath $second.Marker) {
    Show-LifecycleOutput -Item $second
    throw "A second WinTool launch opened another window instead of handing over."
}
if ($second.Process.ExitCode -ne 0) {
    Show-LifecycleOutput -Item $second
    throw ("The second WinTool launch exited with code {0}." -f $second.Process.ExitCode)
}
Write-Output "Second launch handed over to the open window and exited."

# Watch what the first copy starts until it closes.
$deadline = [DateTime]::UtcNow.AddSeconds(120)
while (-not $first.Process.HasExited) {
    foreach ($item in @(Get-LifecycleDescendant -ParentId $first.Process.Id)) {
        $seen[$item.Id] = $item.Name
    }
    if ([DateTime]::UtcNow -gt $deadline) {
        Show-LifecycleOutput -Item $first
        Stop-Process -Id $first.Process.Id -Force
        throw "powershell.exe was still running 120 seconds after WinTool was started; the window closes at 25 seconds."
    }
    Start-Sleep -Milliseconds 500
}
$first.Process.WaitForExit()
if ($first.Process.ExitCode -ne 0) {
    Show-LifecycleOutput -Item $first
    throw ("WinTool exited with code {0} after its window closed." -f $first.Process.ExitCode)
}
Start-Sleep -Seconds 2
$left = @()
foreach ($id in @($seen.Keys)) {
    $alive = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -ne $alive -and [string]$seen[$id] -ne "conhost.exe") {
        $left += ("{0} ({1})" -f $seen[$id], $id)
    }
}
if ($left.Count -gt 0) {
    throw ("Processes started by WinTool are still running after it closed: " + ($left -join ", "))
}
Write-Output ("WinTool closed cleanly: exit code 0, {0} child process(es) seen, none left running." -f $seen.Count)
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
exit 0
