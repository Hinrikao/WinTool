# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

function Test-WinToolIsWindowsPowerShell {
    return ($PSVersionTable.PSEdition -ne "Core")
}

function Get-WinToolPowerShell7Path {
    Sync-WinToolProcessPath
    $command = Get-Command -Name "pwsh.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and (Test-Path -LiteralPath ([string]$command.Source))) {
        return [string]$command.Source
    }
    foreach ($candidate in @(
            ([string]$env:ProgramFiles + "\PowerShell\7\pwsh.exe"),
            ([string]$env:LOCALAPPDATA + "\Programs\PowerShell\7\pwsh.exe"),
            ([string]$env:LOCALAPPDATA + "\Microsoft\WindowsApps\pwsh.exe")
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Test-WinToolPowerShell7Installed {
    return -not [string]::IsNullOrWhiteSpace((Get-WinToolPowerShell7Path))
}

function Test-WinToolWindowsTerminalInstalled {
    if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
        return $true
    }
    $command = Get-Command -Name "wt.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return $true
    }
    foreach ($candidate in @(
            ([string]$env:LOCALAPPDATA + "\Microsoft\WindowsApps\wt.exe"),
            ([string]$env:ProgramFiles + "\Windows Terminal\wt.exe")
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $true
        }
    }
    return $false
}

function Test-WinToolIsPowerShell7 {
    return ([int]$PSVersionTable.PSVersion.Major -ge 7)
}

function Get-WinToolPreferredGuiHostPath {
    return (Get-WinToolPowerShell7Path)
}

function Get-WinToolLaunchSwapMode {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        $TabCount,
        [bool]$ShowConsole = $false,
        [bool]$Unattended = $false
    )
    if ($ShowConsole -or $Unattended) {
        return "none"
    }
    if ($Kind -eq "conhost") {
        return "hide-conhost"
    }
    if ($Kind -eq "windows-terminal") {
        if ($TabCount -is [int] -and $TabCount -eq 1) {
            return "morph-wt"
        }
        return "exit-tab"
    }
    return "none"
}

function Get-WinToolWindowClassName {
    param($Handle)
    if (-not (Initialize-WinToolConsoleApi)) {
        return ""
    }
    try {
        if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
            return ""
        }
        return [string][WinToolConsoleApi]::GetWindowClassName($Handle)
    }
    catch {
        $null = $_.Exception.Message
        return ""
    }
}

function Get-WinToolWindowRectText {
    param($Handle)
    if (-not (Initialize-WinToolConsoleApi)) {
        return ""
    }
    try {
        if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
            return ""
        }
        return [string][WinToolConsoleApi]::GetWindowRectText($Handle)
    }
    catch {
        $null = $_.Exception.Message
        return ""
    }
}

function ConvertFrom-WinToolWindowRectText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    $parts = @($Text.Split(","))
    if ($parts.Count -ne 4) {
        return $null
    }
    try {
        return [pscustomobject]@{
            Left   = [int]$parts[0]
            Top    = [int]$parts[1]
            Right  = [int]$parts[2]
            Bottom = [int]$parts[3]
        }
    }
    catch {
        $null = $_.Exception.Message
        return $null
    }
}

function ConvertTo-WinToolHandleValue {
    param($Handle)
    if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
        return "0"
    }
    return ([IntPtr]$Handle).ToInt64().ToString()
}

function ConvertFrom-WinToolHandleValue {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [IntPtr]::Zero
    }
    try {
        return New-Object IntPtr ([int64]$Text)
    }
    catch {
        $null = $_.Exception.Message
        return [IntPtr]::Zero
    }
}

function Get-WinToolWindowsTerminalTabCount {
    param($Handle)
    if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
        return $null
    }
    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($Handle)
        if ($null -eq $element) {
            return $null
        }
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabs = $element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        if ($null -eq $tabs) {
            return $null
        }
        $count = [int]$tabs.Count
        if ($count -le 0) {
            return $null
        }
        return $count
    }
    catch {
        $null = $_.Exception.Message
        return $null
    }
}

function Get-WinToolLaunchHostSnapshot {
    $kind = "unknown"
    $handle = [IntPtr]::Zero
    $tabCount = $null
    $rect = ""
    if (Initialize-WinToolConsoleApi) {
        try {
            $console = [WinToolConsoleApi]::GetConsoleWindow()
            $consoleClass = Get-WinToolWindowClassName -Handle $console
            $root = [IntPtr]::Zero
            if ($console -ne [IntPtr]::Zero) {
                $root = [WinToolConsoleApi]::GetAncestor($console, 3)
            }
            $rootClass = Get-WinToolWindowClassName -Handle $root
            $inTerminal = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION) -or $consoleClass -eq "CASCADIA_HOSTING_WINDOW_CLASS" -or $rootClass -eq "CASCADIA_HOSTING_WINDOW_CLASS"
            if ($inTerminal) {
                $kind = "windows-terminal"
                if ($rootClass -eq "CASCADIA_HOSTING_WINDOW_CLASS") {
                    $handle = $root
                }
                elseif ($consoleClass -eq "CASCADIA_HOSTING_WINDOW_CLASS") {
                    $handle = $console
                }
                elseif ($root -ne [IntPtr]::Zero) {
                    $handle = $root
                }
                else {
                    $handle = $console
                }
                $tabCount = Get-WinToolWindowsTerminalTabCount -Handle $handle
            }
            elseif ($console -ne [IntPtr]::Zero) {
                $kind = "conhost"
                $handle = $console
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    if ($handle -ne [IntPtr]::Zero) {
        $rect = Get-WinToolWindowRectText -Handle $handle
    }
    $swap = Get-WinToolLaunchSwapMode -Kind $kind -TabCount $tabCount -ShowConsole ([bool]$script:WinToolShowConsole) -Unattended ([bool]$script:WinToolUnattended)
    return [pscustomobject]@{
        Kind       = $kind
        Handle     = $handle
        TabCount   = $tabCount
        Rect       = $rect
        Swap       = $swap
        ProcessId  = $PID
    }
}

function ConvertTo-WinToolProcessArgumentList {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Argument)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Argument)) {
        if ([string]::IsNullOrEmpty($item)) {
            [void]$parts.Add('""')
            continue
        }
        if ($item -notmatch '[\s"]') {
            [void]$parts.Add($item)
            continue
        }
        [void]$parts.Add('"' + ($item -replace '"', '\"') + '"')
    }
    return @($parts.ToArray()) -join " "
}

function New-WinToolGuiChildStartInfo {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Argument,
        [hashtable]$Environment
    )
    return [pscustomobject]@{
        FileName        = $FileName
        Argument        = @($Argument)
        ArgumentText    = (ConvertTo-WinToolProcessArgumentList -Argument $Argument)
        UseShellExecute = $false
        CreateNoWindow  = $true
        Environment     = $Environment
    }
}

function Get-WinToolGuiChildEnvironment {
    param($Snapshot, [string]$SignalPath)
    $values = @{
        WINTOOL_HIDDEN        = "1"
        WINTOOL_LAUNCH_PID    = [string]$Snapshot.ProcessId
        WINTOOL_LAUNCH_HWND   = (ConvertTo-WinToolHandleValue -Handle $Snapshot.Handle)
        WINTOOL_LAUNCH_KIND   = [string]$Snapshot.Kind
        WINTOOL_LAUNCH_SWAP   = [string]$Snapshot.Swap
        WINTOOL_LAUNCH_RECT   = [string]$Snapshot.Rect
        WINTOOL_LAUNCH_SIGNAL = [string]$SignalPath
        WINTOOL_SHOW_CONSOLE  = ""
        WINTOOL_LAUNCH_T0     = [string][DateTime]::UtcNow.Ticks
    }
    return $values
}

function Start-WinToolGuiChildProcess {
    param(
        [Parameter(Mandatory = $true)]$StartInfo
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = [string]$StartInfo.FileName
    if ($StartInfo.PSObject.Properties["ArgumentText"] -and -not [string]::IsNullOrWhiteSpace([string]$StartInfo.ArgumentText)) {
        $psi.Arguments = [string]$StartInfo.ArgumentText
    }
    elseif ($StartInfo.PSObject.Properties["Argument"]) {
        $psi.Arguments = ConvertTo-WinToolProcessArgumentList -Argument @($StartInfo.Argument)
    }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $environment = $StartInfo.Environment
    if ($null -ne $environment) {
        foreach ($key in @($environment.Keys)) {
            $psi.EnvironmentVariables[$key] = [string]$environment[$key]
        }
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $null = $process.Start()
    return $process
}

function Wait-WinToolLaunchReady {
    param(
        [Parameter(Mandatory = $true)][string]$SignalPath,
        $Process,
        [int]$TimeoutSeconds = 180
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-WinToolLaunchSignalReady -SignalPath $SignalPath) {
            return $true
        }
        if ($null -ne $Process) {
            try {
                if ($Process.HasExited) {
                    return (Test-WinToolLaunchSignalReady -SignalPath $SignalPath)
                }
            }
            catch {
                $null = $_.Exception.Message
            }
        }
        Start-Sleep -Milliseconds 200
    }
    return (Test-WinToolLaunchSignalReady -SignalPath $SignalPath)
}

function Test-WinToolLaunchSignalReady {
    param([Parameter(Mandatory = $true)][string]$SignalPath)
    if ([string]::IsNullOrWhiteSpace($SignalPath) -or -not (Test-Path -LiteralPath $SignalPath)) {
        return $false
    }
    try {
        $text = [System.IO.File]::ReadAllText($SignalPath)
        return $text -match "(?m)^ready"
    }
    catch {
        $null = $_.Exception.Message
        return $false
    }
}

function Get-WinToolLaunchSignalSwap {
    param([string]$SignalPath)
    if ([string]::IsNullOrWhiteSpace($SignalPath) -or -not (Test-Path -LiteralPath $SignalPath)) {
        return "none"
    }
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($SignalPath)) {
            if ($line.StartsWith("swap=")) {
                $swap = $line.Substring(5).Trim()
                if (-not [string]::IsNullOrWhiteSpace($swap)) {
                    return $swap
                }
            }
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    return "none"
}

function Write-WinToolLaunchSignal {
    param(
        [Parameter(Mandatory = $true)][string]$SignalPath,
        [Parameter(Mandatory = $true)][string]$State,
        [string]$Swap = "",
        [string]$Summary = ""
    )
    if ([string]::IsNullOrWhiteSpace($SignalPath)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($Swap) -and (Test-Path -LiteralPath $SignalPath)) {
        $Swap = Get-WinToolLaunchSignalSwap -SignalPath $SignalPath
    }
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("ready")
    if (-not [string]::IsNullOrWhiteSpace($Swap)) {
        [void]$lines.Add("swap=" + $Swap)
    }
    if ($State -eq "closed") {
        [void]$lines.Add("closed")
        if (-not [string]::IsNullOrWhiteSpace($Summary)) {
            [void]$lines.Add($Summary)
        }
    }
    $directory = Split-Path -Parent $SignalPath
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = $SignalPath + ".tmp"
    [System.IO.File]::WriteAllLines($temporary, $lines.ToArray())
    Move-Item -LiteralPath $temporary -Destination $SignalPath -Force
}

function Get-WinToolLaunchCloseSummary {
    param([string]$SignalPath)
    if ([string]::IsNullOrWhiteSpace($SignalPath) -or -not (Test-Path -LiteralPath $SignalPath)) {
        return (Get-WinToolText "shell.closed")
    }
    try {
        foreach ($line in [System.IO.File]::ReadAllLines($SignalPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -eq "ready" -or $line -eq "closed" -or $line.StartsWith("swap=")) { continue }
            return [string]$line
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    return (Get-WinToolText "shell.closed")
}

function Write-WinToolLaunchCloseSummary {
    param([string]$SignalPath)
    $summary = Get-WinToolLaunchCloseSummary -SignalPath $SignalPath
    if (-not [string]::IsNullOrWhiteSpace($summary)) {
        Write-Host $summary
    }
}

function Set-WinToolWindowHandleVisible {
    param(
        $Handle,
        [Parameter(Mandatory = $true)][bool]$Visible
    )
    if (-not (Initialize-WinToolConsoleApi)) {
        return $false
    }
    if ($null -eq $Handle -or $Handle -eq [IntPtr]::Zero) {
        return $false
    }
    try {
        if ($Visible) {
            [WinToolConsoleApi]::RestoreTaskbarStyle($Handle)
            $null = [WinToolConsoleApi]::ShowWindow($Handle, 9)
        }
        else {
            [WinToolConsoleApi]::KeepOffTaskbar($Handle)
            $null = [WinToolConsoleApi]::ShowWindow($Handle, 0)
        }
        return $true
    }
    catch {
        $null = $_.Exception.Message
        return $false
    }
}

function Set-WinToolWindowToLaunchRect {
    param(
        $Window,
        [string]$RectText
    )
    if ($null -eq $Window) {
        return
    }
    $rect = ConvertFrom-WinToolWindowRectText -Text $RectText
    if ($null -eq $rect) {
        return
    }
    try {
        $source = [System.Windows.PresentationSource]::FromVisual($Window)
        $left = [double]$rect.Left
        $top = [double]$rect.Top
        $width = [double]($rect.Right - $rect.Left)
        $height = [double]($rect.Bottom - $rect.Top)
        if ($null -ne $source -and $null -ne $source.CompositionTarget) {
            $fromDevice = $source.CompositionTarget.TransformFromDevice
            $topLeft = $fromDevice.Transform((New-Object System.Windows.Point $rect.Left, $rect.Top))
            $bottomRight = $fromDevice.Transform((New-Object System.Windows.Point $rect.Right, $rect.Bottom))
            $left = $topLeft.X
            $top = $topLeft.Y
            $width = $bottomRight.X - $topLeft.X
            $height = $bottomRight.Y - $topLeft.Y
        }
        if ($width -lt 480) { $width = 480 }
        if ($height -lt 320) { $height = 320 }
        $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $Window.Left = $left
        $Window.Top = $top
        $Window.Width = $width
        $Window.Height = $height
    }
    catch {
        $null = $_.Exception.Message
    }
}

function Resolve-WinToolCurrentLaunchSwap {
    $kind = [string]$env:WINTOOL_LAUNCH_KIND
    $handle = ConvertFrom-WinToolHandleValue -Text ([string]$env:WINTOOL_LAUNCH_HWND)
    $tabCount = $null
    if ([string]::IsNullOrWhiteSpace($kind) -and [string]::IsNullOrWhiteSpace($env:WINTOOL_LAUNCH_HWND) -and [string]::IsNullOrWhiteSpace($env:WINTOOL_LAUNCH_SIGNAL)) {
        return "none"
    }
    if ($kind -eq "windows-terminal") {
        $tabCount = Get-WinToolWindowsTerminalTabCount -Handle $handle
    }
    $swap = Get-WinToolLaunchSwapMode -Kind $kind -TabCount $tabCount -ShowConsole ([bool]$script:WinToolShowConsole) -Unattended ([bool]$script:WinToolUnattended)
    $env:WINTOOL_LAUNCH_SWAP = $swap
    return $swap
}

function Get-WinToolCurrentLaunchSwap {
    $swap = [string]$env:WINTOOL_LAUNCH_SWAP
    if ([string]::IsNullOrWhiteSpace($swap)) {
        return "none"
    }
    return $swap
}

function Complete-WinToolLaunchSwap {
    $signal = [string]$env:WINTOOL_LAUNCH_SIGNAL
    $hwndText = [string]$env:WINTOOL_LAUNCH_HWND
    $kind = [string]$env:WINTOOL_LAUNCH_KIND
    # Lifecycle hosts call Show-WinToolWindow directly, with no launch parent.
    if ([string]::IsNullOrWhiteSpace($signal) -and [string]::IsNullOrWhiteSpace($hwndText) -and [string]::IsNullOrWhiteSpace($kind)) {
        return
    }
    $swap = Resolve-WinToolCurrentLaunchSwap
    $handle = ConvertFrom-WinToolHandleValue -Text $hwndText
    if ($swap -eq "morph-wt" -or $swap -eq "hide-conhost") {
        Set-WinToolWindowToLaunchRect -Window $script:WinToolWindow -RectText ([string]$env:WINTOOL_LAUNCH_RECT)
        $null = Set-WinToolWindowHandleVisible -Handle $handle -Visible $false
    }
    if (-not [string]::IsNullOrWhiteSpace($signal)) {
        Write-WinToolLaunchSignal -SignalPath $signal -State "ready" -Swap $swap
    }
}

function Complete-WinToolLaunchHostRestore {
    if ($script:WinToolLaunchHostCompleted) {
        return
    }
    $swap = Get-WinToolCurrentLaunchSwap
    if ($swap -eq "none" -or [string]::IsNullOrWhiteSpace($swap)) {
        return
    }
    $script:WinToolLaunchHostCompleted = $true
    $signal = [string]$env:WINTOOL_LAUNCH_SIGNAL
    if (-not [string]::IsNullOrWhiteSpace($signal)) {
        Write-WinToolLaunchSignal -SignalPath $signal -State "closed" -Swap $swap -Summary (Get-WinToolText "shell.closed")
    }
    if ($swap -eq "morph-wt" -or $swap -eq "hide-conhost") {
        $handle = ConvertFrom-WinToolHandleValue -Text ([string]$env:WINTOOL_LAUNCH_HWND)
        $null = Set-WinToolWindowHandleVisible -Handle $handle -Visible $true
    }
}

function Get-WinToolPowerShell7MsiUri {
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -Headers @{ "User-Agent" = "WinTool" }
        foreach ($asset in @($release.assets)) {
            $name = [string]$asset.name
            if ($name -match "PowerShell-.*-win-x64\.msi$") {
                return [string]$asset.browser_download_url
            }
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    return $null
}

function Install-WinToolPowerShell7IfMissing {
    $existing = Get-WinToolPowerShell7Path
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return $true
    }
    Write-Host (Get-WinToolText "shell.installingPowerShell7")
    $winget = Get-WinToolWingetPath
    if (-not [string]::IsNullOrWhiteSpace($winget)) {
        try {
            $null = & $winget @("install", "--id", "Microsoft.PowerShell", "-e", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity")
        }
        catch {
            $null = $_.Exception.Message
        }
        Sync-WinToolProcessPath
        $existing = Get-WinToolPowerShell7Path
        if (-not [string]::IsNullOrWhiteSpace($existing)) {
            Write-Host (Get-WinToolText "shell.installedPowerShell7")
            return $true
        }
    }
    $uri = Get-WinToolPowerShell7MsiUri
    if ([string]::IsNullOrWhiteSpace($uri)) {
        return $false
    }
    Write-Host (Get-WinToolText "shell.downloadingPowerShell7")
    $msi = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-PowerShell7-" + [guid]::NewGuid().ToString("N") + ".msi")
    try {
        $client = New-Object System.Net.WebClient
        $client.Headers["User-Agent"] = "WinTool"
        $client.DownloadFile($uri, $msi)
        $msiexec = Join-Path $env:SystemRoot "System32\msiexec.exe"
        $install = Start-Process -FilePath $msiexec -ArgumentList @("/i", $msi, "/qn", "/norestart") -Wait -PassThru -WindowStyle Normal
        $null = $install
    }
    catch {
        $null = $_.Exception.Message
        return $false
    }
    finally {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
    Sync-WinToolProcessPath
    $existing = Get-WinToolPowerShell7Path
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Write-Host (Get-WinToolText "shell.installedPowerShell7")
        return $true
    }
    return $false
}

function Invoke-WinToolPowerShell7Handoff {
    if (-not (Install-WinToolPowerShell7IfMissing)) {
        throw (Get-WinToolText "shell.installPowerShell7Failed")
    }
    if ([string]::IsNullOrWhiteSpace((Get-WinToolPreferredGuiHostPath))) {
        throw (Get-WinToolText "shell.installPowerShell7Failed")
    }
    Write-Host (Get-WinToolText "shell.openingWindow")
    Start-WinToolRelaunch
}
