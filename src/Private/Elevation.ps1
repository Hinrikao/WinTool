# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Test-WinToolAdministrator {
    if (-not (Test-WinToolWindows)) {
        return $false
    }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-WinToolLiteral {
    param(
        [AllowEmptyString()][string]$Text
    )
    if ($null -eq $Text) {
        $Text = ""
    }
    return "'" + ($Text.Replace("'", "''")) + "'"
}

function Resolve-WinToolEntryPath {
    param(
        [string]$EntryPath,
        [string]$CommandPath
    )
    if (-not [string]::IsNullOrWhiteSpace($EntryPath)) {
        return $EntryPath
    }
    if (-not [string]::IsNullOrWhiteSpace($CommandPath)) {
        return $CommandPath
    }
    return $null
}

function Get-WinToolPublishedLaunchUrl {
    if (-not [string]::IsNullOrWhiteSpace($env:WINTOOL_URL)) {
        return $env:WINTOOL_URL
    }
    if (-not [string]::IsNullOrWhiteSpace($script:WinToolPublishedUrl)) {
        return $script:WinToolPublishedUrl
    }
    return "https://raw.githubusercontent.com/Hinrikao/WinTool/main/wintool.ps1"
}

function New-WinToolRelaunchScript {
    param(
        [string]$WorkingDirectory,
        [string]$EntryPath,
        [string]$ApplyProfile,
        [bool]$Unattended,
        [string]$LaunchUrl,
        [bool]$Hidden,
        [bool]$ShowConsole
    )
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('$ErrorActionPreference = "Stop"')
    [void]$lines.Add('$env:WINTOOL_PAUSE_ON_ERROR = "1"')
    if ($Hidden) {
        [void]$lines.Add('$env:WINTOOL_HIDDEN = "1"')
    }
    else {
        [void]$lines.Add('$env:WINTOOL_HIDDEN = $null')
    }
    if ($ShowConsole) {
        [void]$lines.Add('$env:WINTOOL_SHOW_CONSOLE = "1"')
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        [void]$lines.Add("Set-Location -LiteralPath " + (ConvertTo-WinToolLiteral -Text $WorkingDirectory))
    }
    [void]$lines.Add("try {")
    if (-not [string]::IsNullOrWhiteSpace($EntryPath)) {
        $call = "    & " + (ConvertTo-WinToolLiteral -Text $EntryPath)
        if (-not [string]::IsNullOrWhiteSpace($ApplyProfile)) {
            $call += " -ApplyProfile " + (ConvertTo-WinToolLiteral -Text $ApplyProfile)
        }
        if ($Unattended) {
            $call += " -Unattended"
        }
        if ($ShowConsole) {
            $call += " -ShowConsole"
        }
        [void]$lines.Add($call)
    }
    else {
        if ([string]::IsNullOrWhiteSpace($LaunchUrl)) {
            $LaunchUrl = Get-WinToolPublishedLaunchUrl
        }
        $download = "    Invoke-Expression (Invoke-RestMethod -Uri " + (ConvertTo-WinToolLiteral -Text $LaunchUrl) + ")"
        [void]$lines.Add($download)
    }
    [void]$lines.Add("}")
    [void]$lines.Add("catch {")
    [void]$lines.Add('    $text = ($_ | Out-String)')
    if ($Hidden) {
        # Bring the hidden console back so the error and the Enter prompt are visible.
        [void]$lines.Add('    try {')
        [void]$lines.Add('        if ($null -eq ("WinToolConsoleApi" -as [type])) {')
        [void]$lines.Add("            Add-Type -TypeDefinition @'")
        foreach ($sourceLine in ((Get-WinToolConsoleApiSource) -split "`r?`n")) {
            [void]$lines.Add($sourceLine)
        }
        [void]$lines.Add("'@")
        [void]$lines.Add('        }')
        [void]$lines.Add('        $null = [WinToolConsoleApi]::ShowWindow([WinToolConsoleApi]::GetConsoleWindow(), 5)')
        [void]$lines.Add('    }')
        [void]$lines.Add('    catch {')
        [void]$lines.Add('        $null = $_.Exception.Message')
        [void]$lines.Add('    }')
    }
    [void]$lines.Add('    $logDir = Join-Path $env:TEMP "WinTool"')
    [void]$lines.Add('    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }')
    [void]$lines.Add('    $logPath = Join-Path $logDir "wintool.log"')
    [void]$lines.Add('    Add-Content -LiteralPath $logPath -Value ("==== " + (Get-Date).ToString("o") + " ====") -Encoding UTF8')
    [void]$lines.Add('    Add-Content -LiteralPath $logPath -Value $text -Encoding UTF8')
    [void]$lines.Add('    Write-Host $text')
    [void]$lines.Add('    Write-Host ("Log: " + $logPath)')
    [void]$lines.Add("    try {")
    [void]$lines.Add("        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop")
    [void]$lines.Add('        [System.Windows.MessageBox]::Show($text, "WinTool") | Out-Null')
    [void]$lines.Add("    }")
    [void]$lines.Add("    catch {")
    [void]$lines.Add('        Write-Host $_.Exception.Message')
    [void]$lines.Add("    }")
    [void]$lines.Add('    Write-Host "Press Enter to close this window."')
    [void]$lines.Add("    Read-Host | Out-Null")
    [void]$lines.Add("    exit 1")
    [void]$lines.Add("}")
    return ($lines.ToArray() -join "`r`n") + "`r`n"
}

function Get-WinToolHostArgument {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [bool]$Hidden
    )
    $arguments = @("-STA", "-NoProfile", "-ExecutionPolicy", "Bypass")
    if ($Hidden) {
        $arguments += @("-WindowStyle", "Hidden")
    }
    return $arguments + @("-File", $LauncherPath)
}

function Get-WinToolWorkingDirectory {
    try {
        $current = Get-Location
        $path = [string]$current.ProviderPath
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Container)) {
            return $path
        }
    }
    catch {
        $null = $_.Exception.Message
    }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE) -and (Test-Path -LiteralPath $env:USERPROFILE)) {
        return $env:USERPROFILE
    }
    return [string]$env:SystemRoot
}

function Start-WinToolRelaunch {
    param(
        [switch]$Elevate
    )
    $executable = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $entry = Resolve-WinToolEntryPath -EntryPath $script:WinToolEntryPath -CommandPath ""
    if (-not [string]::IsNullOrWhiteSpace($entry) -and -not (Test-Path -LiteralPath $entry)) {
        $entry = $null
    }
    $directory = Get-WinToolWorkingDirectory
    $showConsole = Test-WinToolShowConsole
    $hidden = -not ($showConsole -or [bool]$script:WinToolUnattended)
    $scriptText = New-WinToolRelaunchScript -WorkingDirectory $directory -EntryPath $entry -ApplyProfile $script:WinToolApplyProfile -Unattended ([bool]$script:WinToolUnattended) -LaunchUrl (Get-WinToolPublishedLaunchUrl) -Hidden $hidden -ShowConsole $showConsole
    $launcherDirectory = Join-Path $env:TEMP "WinTool"
    if (-not (Test-Path -LiteralPath $launcherDirectory)) {
        New-Item -ItemType Directory -Path $launcherDirectory -Force | Out-Null
    }
    $launcherPath = Join-Path $launcherDirectory "relaunch.ps1"
    $encoding = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($launcherPath, $scriptText, $encoding)
    $line = ConvertTo-WinToolArgumentLine -ArgumentList @(Get-WinToolHostArgument -LauncherPath $launcherPath -Hidden $hidden)
    $style = "Normal"
    if ($hidden) {
        $style = "Hidden"
    }
    if ($Elevate) {
        Write-Host "WinTool needs administrator approval. Accept the Windows prompt to continue."
        try {
            Start-Process -FilePath $executable -ArgumentList $line -Verb RunAs -WindowStyle $style | Out-Null
        }
        catch {
            Write-Host "WinTool was not started. Administrator approval was declined."
        }
        Exit-WinToolOwnedHost
        return
    }
    Write-Host "WinTool is opening in its own window. You can close this terminal."
    Start-Process -FilePath $executable -ArgumentList $line -WindowStyle $style | Out-Null
    Exit-WinToolOwnedHost
}

function Test-WinToolOwnedHost {
    # True when this powershell.exe was started by WinTool itself (the hidden
    # relaunch). The user's own console is never closed by WinTool.
    return ($env:WINTOOL_HIDDEN -eq "1")
}

function Exit-WinToolOwnedHost {
    param([int]$Code = 0)
    if (Test-WinToolOwnedHost) {
        [Environment]::Exit($Code)
    }
}

function Request-WinToolAdministrator {
    Start-WinToolRelaunch -Elevate
}

function Request-WinToolStaHost {
    Start-WinToolRelaunch
}
