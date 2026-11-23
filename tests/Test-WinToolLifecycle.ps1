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
    is still alive. A second launch matches the owner's command (WindowStyle
    Hidden, -File, no WINTOOL_HIDDEN and no redirected handles) and fails if a
    taskbar window or a new process appears after Close, or if powershell.exe
    is still running a few seconds later.
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

if ($null -eq ("WinToolCloseWatch" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class WinToolCloseWatch
{
    public delegate void WinEventProc(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint threadId, uint time);

    [StructLayout(LayoutKind.Sequential)]
    public struct WinToolMsg
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ProcessEntry
    {
        public uint dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExeFile;
    }

    public delegate bool EnumProc(IntPtr handle, IntPtr param);

    [DllImport("user32.dll")]
    static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module, WinEventProc callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")]
    static extern bool UnhookWinEvent(IntPtr hook);

    [DllImport("user32.dll")]
    static extern bool PeekMessage(out WinToolMsg message, IntPtr hwnd, uint min, uint max, uint remove);

    [DllImport("user32.dll")]
    static extern bool TranslateMessage(ref WinToolMsg message);

    [DllImport("user32.dll")]
    static extern IntPtr DispatchMessage(ref WinToolMsg message);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumProc callback, IntPtr param);

    [DllImport("user32.dll")]
    static extern bool IsWindowVisible(IntPtr handle);

    [DllImport("user32.dll")]
    static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr handle, StringBuilder buffer, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetWindowText(IntPtr handle, StringBuilder buffer, int maxCount);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "Process32FirstW")]
    static extern bool Process32First(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, EntryPoint = "Process32NextW")]
    static extern bool Process32Next(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);

    static readonly object Gate = new object();
    static readonly HashSet<int> Watch = new HashSet<int>();
    static readonly List<string> Shown = new List<string>();
    static WinEventProc keep;
    static IntPtr showHook;
    static IntPtr uncloakHook;

    public static void Start()
    {
        if (keep != null) { return; }
        keep = OnEvent;
        showHook = SetWinEventHook(0x8002, 0x8002, IntPtr.Zero, keep, 0, 0, 0);
        uncloakHook = SetWinEventHook(0x8018, 0x8018, IntPtr.Zero, keep, 0, 0, 0);
    }

    public static void Stop()
    {
        if (showHook != IntPtr.Zero) { UnhookWinEvent(showHook); showHook = IntPtr.Zero; }
        if (uncloakHook != IntPtr.Zero) { UnhookWinEvent(uncloakHook); uncloakHook = IntPtr.Zero; }
        keep = null;
    }

    public static void AddPid(int processId)
    {
        lock (Gate) { Watch.Add(processId); }
    }

    public static string[] TakeShown()
    {
        lock (Gate)
        {
            string[] copy = Shown.ToArray();
            Shown.Clear();
            return copy;
        }
    }

    public static void Pump()
    {
        WinToolMsg message;
        while (PeekMessage(out message, IntPtr.Zero, 0, 0, 1))
        {
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
    }

    static int ParentOf(int processId)
    {
        IntPtr snapshot = CreateToolhelp32Snapshot(2, 0);
        if (snapshot == IntPtr.Zero || snapshot == new IntPtr(-1)) { return -1; }
        try
        {
            ProcessEntry entry = new ProcessEntry();
            entry.dwSize = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            if (!Process32First(snapshot, ref entry)) { return -1; }
            do
            {
                if ((int)entry.th32ProcessID == processId) { return (int)entry.th32ParentProcessID; }
            }
            while (Process32Next(snapshot, ref entry));
        }
        finally
        {
            CloseHandle(snapshot);
        }
        return -1;
    }

    static void OnEvent(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint threadId, uint time)
    {
        if (hwnd == IntPtr.Zero || idObject != 0) { return; }
        try
        {
            uint pidValue;
            GetWindowThreadProcessId(hwnd, out pidValue);
            int pid = (int)pidValue;
            StringBuilder cls = new StringBuilder(256);
            if (GetClassName(hwnd, cls, cls.Capacity) <= 0) { return; }
            string name = cls.ToString();
            bool console = name == "ConsoleWindowClass" || name == "CASCADIA_HOSTING_WINDOW_CLASS";
            bool dialog = name == "#32770";
            bool wpf = name.StartsWith("HwndWrapper", StringComparison.Ordinal);
            if (!console && !dialog && !wpf) { return; }
            bool watched;
            lock (Gate) { watched = Watch.Contains(pid); }
            if (!watched && (console || dialog))
            {
                int parent = ParentOf(pid);
                lock (Gate) { watched = Watch.Contains(parent); }
            }
            if (!watched || !IsWindowVisible(hwnd)) { return; }
            StringBuilder title = new StringBuilder(256);
            GetWindowText(hwnd, title, title.Capacity);
            string line = pid.ToString() + "|" + name + "|" + title.ToString();
            lock (Gate) { Shown.Add(line); }
        }
        catch
        {
        }
    }

    public static string[] VisibleWindows(int[] processIds)
    {
        HashSet<int> wanted = new HashSet<int>();
        if (processIds != null)
        {
            foreach (int id in processIds) { wanted.Add(id); }
        }
        List<string> list = new List<string>();
        EnumWindows(delegate(IntPtr handle, IntPtr param)
        {
            if (!IsWindowVisible(handle)) { return true; }
            uint pidValue;
            GetWindowThreadProcessId(handle, out pidValue);
            if (!wanted.Contains((int)pidValue)) { return true; }
            StringBuilder cls = new StringBuilder(256);
            StringBuilder title = new StringBuilder(256);
            GetClassName(handle, cls, cls.Capacity);
            GetWindowText(handle, title, title.Capacity);
            list.Add(((int)pidValue).ToString() + "|" + cls.ToString() + "|" + title.ToString());
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
}
'@ -ErrorAction Stop
}

function Start-LifecycleHost {
    param(
        [string]$Name,
        [int]$CloseAfter,
        [switch]$OwnedHost,
        [switch]$CloseAfterShown,
        [switch]$KeepConsole
    )
    $marker = Join-Path $work ($Name + ".shown")
    $log = Join-Path $work ($Name + ".log")
    $owned = ""
    if ($OwnedHost) { $owned = " -OwnedHost" }
    $shown = ""
    if ($CloseAfterShown) { $shown = " -CloseAfterShown" }
    $arguments = '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Marker "{1}" -CloseAfterSeconds {2} -Log "{3}"{4}{5}' -f $hostScript, $marker, $CloseAfter, $log, $owned, $shown
    $stdout = Join-Path $work ($Name + ".out")
    $stderr = Join-Path $work ($Name + ".err")
    if ($KeepConsole) {
        # No redirected handles: powershell.exe keeps the hidden console the
        # owner gets from Start-Process -WindowStyle Hidden.
        $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    }
    else {
        $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    }
    $null = $process.Handle
    return [pscustomobject]@{ Name = $Name; Process = $process; Marker = $marker; Log = $log }
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
    foreach ($suffix in @(".out", ".err", ".log")) {
        $path = Join-Path $work ($Item.Name + $suffix)
        if (Test-Path -LiteralPath $path) {
            Write-Output ("--- " + $Item.Name + $suffix)
            Get-Content -LiteralPath $path | Write-Output
        }
    }
}

function Get-LifecycleWindowPart {
    param([string]$Record)
    $parts = $Record.Split("|")
    $class = ""
    $title = ""
    if ($parts.Length -ge 2) { $class = [string]$parts[1] }
    if ($parts.Length -ge 3) {
        $title = [string]::Join("|", $parts[2..($parts.Length - 1)])
    }
    return [pscustomobject]@{ Class = $class; Title = $title }
}

function Test-LifecycleWinToolWindow {
    param([string]$Record)
    $part = Get-LifecycleWindowPart -Record $Record
    return ($part.Title -eq "WinTool" -and $part.Class.StartsWith("HwndWrapper"))
}

function Test-LifecycleIgnoredWindow {
    param([string]$Class)
    if ([string]::IsNullOrWhiteSpace($Class)) { return $true }
    foreach ($name in @("IME", "MSCTFIME UI", "CiceroUIWndFrame", "GDI+ Hook Window Class", ".NET-BroadcastEventWindow", "OleDdeWndClass", "SystemResourceNotifyWindow", "tooltips_class32", "SysShadow", "DropShadow")) {
        if ($Class -eq $name) { return $true }
    }
    if ($Class.StartsWith("Cicero")) { return $true }
    return $false
}

function Format-LifecycleCloseProblem {
    param($Flashes, $Spawned)
    $parts = New-Object System.Collections.Generic.List[string]
    if (@($Flashes).Count -gt 0) {
        $parts.Add("window: " + ((@($Flashes) | Select-Object -Unique) -join "; "))
    }
    if ($Spawned.Count -gt 0) {
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($id in @($Spawned.Keys)) {
            $names.Add(("{0} ({1})" -f $Spawned[$id], $id))
        }
        $parts.Add("process: " + ($names -join ", "))
    }
    return ($parts -join " | ")
}

function Invoke-LifecycleCloseWatch {
    param(
        $Item,
        [datetime]$Deadline,
        [int]$ExitAfterCloseSeconds = 5,
        [int]$ExitAfterSeenSeconds = 0
    )
    [WinToolCloseWatch]::Start()
    [WinToolCloseWatch]::AddPid([int]$Item.Process.Id)
    $seen = $false
    $seenAt = $null
    $closedAt = $null
    $gonePolls = 0
    $baseline = @{}
    $ever = @{}
    $spawned = @{}
    $flashes = New-Object System.Collections.Generic.List[string]
    $nextTree = [datetime]::MinValue
    $desc = @()
    try {
        while (-not $Item.Process.HasExited) {
            [WinToolCloseWatch]::Pump()
            $now = [DateTime]::UtcNow
            if ($now -ge $nextTree) {
                try { $desc = @(Get-LifecycleDescendant -ParentId $Item.Process.Id) } catch { $desc = @() }
                foreach ($child in $desc) {
                    [WinToolCloseWatch]::AddPid([int]$child.Id)
                    $ever[[int]$child.Id] = [string]$child.Name
                }
                $nextTree = $now.AddMilliseconds(200)
            }
            $ids = New-Object System.Collections.Generic.List[int]
            $ids.Add([int]$Item.Process.Id)
            foreach ($child in $desc) { $ids.Add([int]$child.Id) }
            $windows = @([WinToolCloseWatch]::VisibleWindows([int[]]$ids.ToArray()))
            $up = $false
            foreach ($record in $windows) {
                if (Test-LifecycleWinToolWindow -Record $record) { $up = $true }
            }
            if ($up) { $gonePolls = 0 }
            else { $gonePolls++ }
            # One missed sample is not a close. Three quiet polls are.
            if ($up -and $null -eq $closedAt) {
                $seen = $true
                if ($null -eq $seenAt) { $seenAt = $now }
                $baseline = @{}
                foreach ($child in $desc) { $baseline[[int]$child.Id] = [string]$child.Name }
                $null = [WinToolCloseWatch]::TakeShown()
            }
            elseif ($seen -and $gonePolls -ge 3) {
                if ($null -eq $closedAt) { $closedAt = $now }
                foreach ($record in $windows) {
                    if (Test-LifecycleWinToolWindow -Record $record) {
                        if (-not $flashes.Contains("WinTool returned")) { $flashes.Add("WinTool returned") }
                        continue
                    }
                    $part = Get-LifecycleWindowPart -Record $record
                    if (-not (Test-LifecycleIgnoredWindow -Class $part.Class)) {
                        if (-not $flashes.Contains($record)) { $flashes.Add($record) }
                    }
                }
                foreach ($child in $desc) {
                    $childId = [int]$child.Id
                    if (-not $baseline.ContainsKey($childId) -and -not $spawned.ContainsKey($childId)) {
                        $spawned[$childId] = [string]$child.Name
                    }
                }
                foreach ($record in @([WinToolCloseWatch]::TakeShown())) {
                    if (Test-LifecycleWinToolWindow -Record $record) { continue }
                    $part = Get-LifecycleWindowPart -Record $record
                    if (-not (Test-LifecycleIgnoredWindow -Class $part.Class)) {
                        $labeled = "event " + $record
                        if (-not $flashes.Contains($labeled)) { $flashes.Add($labeled) }
                    }
                }
                if (($now - $closedAt).TotalSeconds -gt $ExitAfterCloseSeconds) {
                    $problem = Format-LifecycleCloseProblem -Flashes $flashes -Spawned $spawned
                    throw ("WinTool was still running {0:N1}s after its window closed. {1}" -f ($now - $closedAt).TotalSeconds, $problem)
                }
            }
            if ($seen -and $ExitAfterSeenSeconds -gt 0 -and $null -ne $seenAt -and ($now - $seenAt).TotalSeconds -gt $ExitAfterSeenSeconds) {
                $problem = Format-LifecycleCloseProblem -Flashes $flashes -Spawned $spawned
                throw ("WinTool was still running {0:N1}s after its window opened. {1}" -f ($now - $seenAt).TotalSeconds, $problem)
            }
            if ($now -gt $Deadline) {
                throw "WinTool did not close before the deadline."
            }
            Start-Sleep -Milliseconds 25
        }
        [WinToolCloseWatch]::Pump()
        Start-Sleep -Milliseconds 50
        [WinToolCloseWatch]::Pump()
        try { $desc = @(Get-LifecycleDescendant -ParentId $Item.Process.Id) } catch { $null = $_.Exception.Message; $desc = @() }
        foreach ($child in $desc) {
            $childId = [int]$child.Id
            $ever[$childId] = [string]$child.Name
            if (-not $baseline.ContainsKey($childId) -and -not $spawned.ContainsKey($childId)) {
                $spawned[$childId] = [string]$child.Name
            }
        }
        foreach ($record in @([WinToolCloseWatch]::TakeShown())) {
            if (Test-LifecycleWinToolWindow -Record $record) { continue }
            $part = Get-LifecycleWindowPart -Record $record
            if (-not (Test-LifecycleIgnoredWindow -Class $part.Class)) {
                $labeled = "event " + $record
                if (-not $flashes.Contains($labeled)) { $flashes.Add($labeled) }
            }
        }
    }
    finally {
        [WinToolCloseWatch]::Stop()
    }
    $null = $Item.Process.WaitForExit()
    $elapsed = $null
    if ($null -ne $closedAt) {
        $elapsed = ([DateTime]::UtcNow - $closedAt).TotalSeconds
    }
    return [pscustomobject]@{
        Seen = $seen
        Flashes = @($flashes)
        Spawned = $spawned
        Ever = $ever
        Elapsed = $elapsed
    }
}

function Test-LifecycleLeftover {
    param($Ever)
    $left = @()
    foreach ($id in @($Ever.Keys)) {
        $alive = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($null -ne $alive -and [string]$Ever[$id] -ne "conhost.exe") {
            $left += ("{0} ({1})" -f $Ever[$id], $id)
        }
    }
    return @($left)
}

$first = Start-LifecycleHost -Name "first" -CloseAfter 25 -OwnedHost
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
$second = Start-LifecycleHost -Name "second" -CloseAfter 2 -OwnedHost
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

$firstWatch = Invoke-LifecycleCloseWatch -Item $first -Deadline ([DateTime]::UtcNow.AddSeconds(90)) -ExitAfterCloseSeconds 5
$first.Process.WaitForExit()
if (-not $firstWatch.Seen) {
    if (-not ($first.Process.HasExited -and $first.Process.ExitCode -eq 0)) {
        Show-LifecycleOutput -Item $first
        throw "The first WinTool window disappeared before the close watch started."
    }
    Write-Output "Hidden relaunch closed before the watch sampled the window."
}
if ($first.Process.ExitCode -ne 0) {
    Show-LifecycleOutput -Item $first
    throw ("WinTool exited with code {0} after its window closed." -f $first.Process.ExitCode)
}
$firstProblem = Format-LifecycleCloseProblem -Flashes $firstWatch.Flashes -Spawned $firstWatch.Spawned
if (-not [string]::IsNullOrWhiteSpace($firstProblem)) {
    Show-LifecycleOutput -Item $first
    throw ("The hidden relaunch left something on screen after Close. " + $firstProblem)
}
Start-Sleep -Seconds 2
$firstLeft = @(Test-LifecycleLeftover -Ever $firstWatch.Ever)
if ($firstLeft.Count -gt 0) {
    throw ("Processes started by WinTool are still running after it closed: " + ($firstLeft -join ", "))
}
$firstSeconds = "with the window"
if ($null -ne $firstWatch.Elapsed) { $firstSeconds = ("{0:N1}s after the window closed" -f $firstWatch.Elapsed) }
Write-Output ("Hidden relaunch closed cleanly: exit code 0, {0}." -f $firstSeconds)

# The owner's command: a hidden console, -File, and no WINTOOL_HIDDEN. Closing
# used to show that console, which put a taskbar button up and then took it away.
$owner = Start-LifecycleHost -Name "owner" -CloseAfter 2 -CloseAfterShown -KeepConsole
$ownerDeadline = [DateTime]::UtcNow.AddSeconds(90)
while (-not (Test-Path -LiteralPath $owner.Marker)) {
    if ($owner.Process.HasExited) {
        Show-LifecycleOutput -Item $owner
        throw ("The owner-style WinTool exited before its window opened (exit code {0})." -f $owner.Process.ExitCode)
    }
    if ([DateTime]::UtcNow -gt $ownerDeadline) {
        Show-LifecycleOutput -Item $owner
        throw "The owner-style WinTool window did not open within 90 seconds."
    }
    Start-Sleep -Milliseconds 250
}
Write-Output "Owner-style window is open."
$ownerWatch = Invoke-LifecycleCloseWatch -Item $owner -Deadline ([DateTime]::UtcNow.AddSeconds(30)) -ExitAfterCloseSeconds 5 -ExitAfterSeenSeconds 15
$owner.Process.WaitForExit()
if (-not $ownerWatch.Seen) {
    Show-LifecycleOutput -Item $owner
    throw "The owner-style WinTool window was not seen."
}
if ($owner.Process.ExitCode -ne 0) {
    Show-LifecycleOutput -Item $owner
    throw ("The owner-style WinTool exited with code {0}." -f $owner.Process.ExitCode)
}
$ownerProblem = Format-LifecycleCloseProblem -Flashes $ownerWatch.Flashes -Spawned $ownerWatch.Spawned
if (-not [string]::IsNullOrWhiteSpace($ownerProblem)) {
    Show-LifecycleOutput -Item $owner
    throw ("Closing WinTool showed a window or started a process. " + $ownerProblem)
}
Start-Sleep -Seconds 2
$ownerLeft = @(Test-LifecycleLeftover -Ever $ownerWatch.Ever)
if ($ownerLeft.Count -gt 0) {
    throw ("Processes started by the owner-style WinTool are still running: " + ($ownerLeft -join ", "))
}
$ownerSeconds = "with the window"
if ($null -ne $ownerWatch.Elapsed) { $ownerSeconds = ("{0:N1}s after the window closed" -f $ownerWatch.Elapsed) }
Write-Output ("Owner-style close was clean: no taskbar window, no new process, powershell exited {0}." -f $ownerSeconds)
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
exit 0
