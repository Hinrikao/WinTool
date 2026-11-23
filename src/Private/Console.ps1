# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# WinTool is a window app, so the PowerShell console that starts it is hidden
# once the window is on screen. -ShowConsole (or WINTOOL_SHOW_CONSOLE=1) keeps
# it visible for debugging. Startup errors always bring the console back.

function Test-WinToolShowConsole {
    if ($script:WinToolShowConsole) {
        return $true
    }
    return ($env:WINTOOL_SHOW_CONSOLE -eq "1")
}

function Get-WinToolConsoleMode {
    param(
        [bool]$ShowConsole,
        [bool]$Unattended,
        [string]$TerminalSession,
        [string]$HiddenChild
    )
    # show: leave the console alone.
    # hide: hide this console while the window is open.
    # relaunch: the console belongs to Windows Terminal, which cannot be hidden
    #           from here, so WinTool starts again in its own hidden console.
    if ($ShowConsole -or $Unattended) {
        return "show"
    }
    if ($HiddenChild -eq "1") {
        return "hide"
    }
    if (-not [string]::IsNullOrWhiteSpace($TerminalSession)) {
        return "relaunch"
    }
    return "hide"
}

function Get-WinToolCurrentConsoleMode {
    return Get-WinToolConsoleMode -ShowConsole (Test-WinToolShowConsole) -Unattended ([bool]$script:WinToolUnattended) -TerminalSession ([string]$env:WT_SESSION) -HiddenChild ([string]$env:WINTOOL_HIDDEN)
}

function Initialize-WinToolConsoleApi {
    if ($null -ne ("WinToolConsoleApi" -as [type])) {
        return $true
    }
    if (-not (Test-WinToolWindows)) {
        return $false
    }
    try {
        Add-Type -TypeDefinition (Get-WinToolConsoleApiSource) -Language CSharp -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-WinToolConsoleApiSource {
    return @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WinToolConsoleApi
{
    public delegate bool EnumWindowsProc(IntPtr handle, IntPtr param);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr handle);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr handle);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr handle);

    [DllImport("user32.dll")]
    public static extern bool AllowSetForegroundWindow(int processId);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr param);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr handle, StringBuilder buffer, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr handle, StringBuilder buffer, int maxCount);

    public static IntPtr FindWinToolWindow()
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr handle, IntPtr param)
        {
            if (!IsWindowVisible(handle)) { return true; }
            StringBuilder title = new StringBuilder(64);
            if (GetWindowText(handle, title, title.Capacity) <= 0) { return true; }
            if (!string.Equals(title.ToString(), "WinTool", StringComparison.Ordinal)) { return true; }
            StringBuilder cls = new StringBuilder(128);
            if (GetClassName(handle, cls, cls.Capacity) <= 0) { return true; }
            if (!cls.ToString().StartsWith("HwndWrapper[", StringComparison.Ordinal)) { return true; }
            found = handle;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    public static bool FocusWinToolWindow()
    {
        IntPtr handle = FindWinToolWindow();
        if (handle == IntPtr.Zero) { return false; }
        if (IsIconic(handle)) { ShowWindow(handle, 9); }
        else { ShowWindow(handle, 5); }
        SetForegroundWindow(handle);
        return true;
    }
}
"@
}

function Set-WinToolConsoleVisible {
    param(
        [Parameter(Mandatory = $true)][bool]$Visible
    )
    if (-not (Initialize-WinToolConsoleApi)) {
        return $false
    }
    try {
        $handle = [WinToolConsoleApi]::GetConsoleWindow()
        if ($handle -eq [IntPtr]::Zero) {
            return $false
        }
        $command = 0
        if ($Visible) {
            $command = 5
        }
        $null = [WinToolConsoleApi]::ShowWindow($handle, $command)
        $script:WinToolConsoleHidden = -not $Visible
        return $true
    }
    catch {
        return $false
    }
}

function Hide-WinToolConsole {
    if ((Get-WinToolCurrentConsoleMode) -eq "show") {
        return
    }
    $null = Set-WinToolConsoleVisible -Visible $false
}

function Show-WinToolConsole {
    if ($script:WinToolConsoleHidden -or $env:WINTOOL_HIDDEN -eq "1") {
        $null = Set-WinToolConsoleVisible -Visible $true
    }
}
