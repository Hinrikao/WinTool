# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# WinTool is a window app, so the PowerShell console that starts it is hidden
# once the window is on screen. -ShowConsole (or WINTOOL_SHOW_CONSOLE=1) keeps
# it visible for debugging. Startup errors always bring the console back.
# A console that was already hidden (powershell -WindowStyle Hidden -File, or
# the hidden relaunch) is detached on close. Showing it and then exiting paints
# a taskbar button for a moment. A console the user could already see, such as
# irm | iex, is shown again and left open.
$script:WinToolConsoleHidden = $false
$script:WinToolConsoleRestore = $false

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

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLongW(IntPtr handle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern int SetWindowLongW(IntPtr handle, int index, int value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr handle, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeConsole();

    const int ExStyleIndex = -20;
    const int ToolWindowStyle = 0x80;
    const int AppWindowStyle = 0x40000;
    const uint FrameChanged = 0x0037;
    static int savedExStyle;
    static bool savedExStyleReady;

    static void ApplyExStyle(IntPtr handle, int value)
    {
        SetWindowLongW(handle, ExStyleIndex, value);
        SetWindowPos(handle, IntPtr.Zero, 0, 0, 0, 0, FrameChanged);
    }

    public static void KeepOffTaskbar(IntPtr handle)
    {
        if (handle == IntPtr.Zero) { return; }
        int ex = GetWindowLongW(handle, ExStyleIndex);
        if (!savedExStyleReady)
        {
            savedExStyle = ex;
            savedExStyleReady = true;
        }
        int updated = (ex | ToolWindowStyle) & ~AppWindowStyle;
        if (updated != ex) { ApplyExStyle(handle, updated); }
    }

    public static void RestoreTaskbarStyle(IntPtr handle)
    {
        if (handle == IntPtr.Zero) { return; }
        int ex;
        if (savedExStyleReady) { ex = savedExStyle; }
        else
        {
            ex = GetWindowLongW(handle, ExStyleIndex);
            ex = (ex & ~ToolWindowStyle) | AppWindowStyle;
        }
        ApplyExStyle(handle, ex);
    }

    public static void DetachHiddenConsole()
    {
        FreeConsole();
        try
        {
            Console.SetOut(System.IO.TextWriter.Null);
            Console.SetError(System.IO.TextWriter.Null);
        }
        catch
        {
        }
    }

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

    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr handle, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    public struct WinToolRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr handle, out WinToolRect rect);

    public static string GetWindowClassName(IntPtr handle)
    {
        if (handle == IntPtr.Zero) { return ""; }
        StringBuilder name = new StringBuilder(256);
        if (GetClassName(handle, name, name.Capacity) <= 0) { return ""; }
        return name.ToString();
    }

    public static string GetWindowRectText(IntPtr handle)
    {
        WinToolRect rect;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out rect)) { return ""; }
        return rect.Left.ToString() + "," + rect.Top.ToString() + "," + rect.Right.ToString() + "," + rect.Bottom.ToString();
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

function Test-WinToolConsoleIsVisible {
    if (-not (Initialize-WinToolConsoleApi)) {
        return $false
    }
    try {
        $handle = [WinToolConsoleApi]::GetConsoleWindow()
        if ($handle -eq [IntPtr]::Zero) {
            return $false
        }
        return [bool][WinToolConsoleApi]::IsWindowVisible($handle)
    }
    catch {
        return $false
    }
}

function Test-WinToolConsoleShouldRestore {
    # Only a console the user was already looking at comes back. WinTool's own
    # hidden process exits instead, so restoring it would flash the taskbar.
    if ((Get-WinToolCurrentConsoleMode) -eq "show") {
        return $false
    }
    if (Test-WinToolOwnedHost) {
        return $false
    }
    return [bool]$script:WinToolConsoleRestore
}

function Set-WinToolConsoleVisible {
    param(
        [Parameter(Mandatory = $true)][bool]$Visible,
        [switch]$Force
    )
    if (-not (Initialize-WinToolConsoleApi)) {
        return $false
    }
    try {
        $handle = [WinToolConsoleApi]::GetConsoleWindow()
        if ($handle -eq [IntPtr]::Zero) {
            return $false
        }
        if ($Visible) {
            if (-not $Force -and -not (Test-WinToolConsoleShouldRestore)) {
                return $true
            }
            [WinToolConsoleApi]::RestoreTaskbarStyle($handle)
            $null = [WinToolConsoleApi]::ShowWindow($handle, 5)
            $script:WinToolConsoleHidden = $false
            return $true
        }
        # Remember a console that was actually on screen. A later hide, after
        # it is already hidden, must not clear that.
        if ([WinToolConsoleApi]::IsWindowVisible($handle)) {
            $script:WinToolConsoleRestore = $true
        }
        [WinToolConsoleApi]::KeepOffTaskbar($handle)
        $null = [WinToolConsoleApi]::ShowWindow($handle, 0)
        $script:WinToolConsoleHidden = $true
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
    # Errors must be readable even when the console started hidden.
    $null = Set-WinToolConsoleVisible -Visible $true -Force
}

function Remove-WinToolHiddenConsole {
    # Drop a console this process is about to destroy, while the WinTool
    # window is still up, so Windows cannot put it on the taskbar.
    if (Test-WinToolConsoleShouldRestore) {
        return
    }
    if ((Get-WinToolCurrentConsoleMode) -eq "show") {
        return
    }
    if (-not (Initialize-WinToolConsoleApi)) {
        return
    }
    try {
        $handle = [WinToolConsoleApi]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero) {
            [WinToolConsoleApi]::KeepOffTaskbar($handle)
            $null = [WinToolConsoleApi]::ShowWindow($handle, 0)
        }
        [WinToolConsoleApi]::DetachHiddenConsole()
    }
    catch {
        $null = $_.Exception.Message
    }
    $script:WinToolConsoleHidden = $false
}
