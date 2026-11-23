# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

$script:WinToolPublishedUrl = "https://raw.githubusercontent.com/Hinrikao/WinTool/main/wintool.ps1"
$script:WinToolProfileBegin = "# >>> WinTool terminal setup >>>"
$script:WinToolProfileEnd = "# <<< WinTool terminal setup <<<"

if ([string]::IsNullOrWhiteSpace($script:WinToolVersion)) {
    $script:WinToolVersion = "1.0.0"
}

function Get-WinToolNote {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }
    return $property.Value
}

function Test-WinToolWindows {
    return ($env:OS -eq "Windows_NT")
}

function Test-WinToolTextMatch {
    param(
        [string]$Haystack,
        [string]$Query
    )
    if ([string]::IsNullOrWhiteSpace($Query)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Haystack)) {
        return $false
    }
    return ($Haystack.IndexOf($Query.Trim(), [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-WinToolPayloadText {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    $embedded = $script:WinToolEmbedded
    if ($null -ne $embedded -and $embedded.ContainsKey($Name)) {
        $clean = ([string]$embedded[$Name]) -replace '\s', ''
        $bytes = [Convert]::FromBase64String($clean)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    if ([string]::IsNullOrWhiteSpace($script:WinToolRoot)) {
        throw "WinTool payload '$Name' is not embedded and no source folder is set."
    }

    $relative = @{
        Apps = "data/apps.json"
        Tweaks = "data/tweaks.json"
        Terminal = "data/terminal.json"
        Fonts = "data/fonts.json"
        OmpThemes = "data/omp-themes.json"
        Updates = "data/updates.json"
        Fixes = "data/fixes.json"
        Features = "data/features.json"
        Xaml = "assets/MainWindow.xaml"
        Wsl = "data/wsl-setup.sh"
    }
    if (-not $relative.ContainsKey($Name)) {
        throw "Unknown WinTool payload '$Name'."
    }

    $path = Join-Path $script:WinToolRoot $relative[$Name]
    return [System.IO.File]::ReadAllText($path)
}

function Get-WinToolLogPath {
    if (-not [string]::IsNullOrWhiteSpace($script:WinToolLogFile)) {
        return $script:WinToolLogFile
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $null
    }
    $directory = Join-Path $env:LOCALAPPDATA "WinTool/logs"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $name = "wintool-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log"
    $script:WinToolLogFile = Join-Path $directory $name
    return $script:WinToolLogFile
}

function Add-WinToolLogLine {
    param(
        [Parameter(Mandatory = $true)][string]$Line
    )
    $path = Get-WinToolLogPath
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        try {
            Add-Content -LiteralPath $path -Value $Line -Encoding UTF8
        }
        catch {
            $null = $_.Exception.Message
        }
    }

    if ($null -eq $script:WinToolLogBox) {
        Write-Host $Line
        return
    }

    $box = $script:WinToolLogBox
    $write = {
        $box.AppendText($Line + [Environment]::NewLine)
        $box.ScrollToEnd()
    }.GetNewClosure()

    if ($box.Dispatcher.CheckAccess()) {
        & $write
    }
    else {
        $box.Dispatcher.BeginInvoke([System.Action]$write) | Out-Null
    }
}

function Write-WinToolLog {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [ValidateSet("info", "ok", "warn", "error")]
        [string]$Level = "info"
    )
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }
    $prefix = "INFO"
    if ($Level -eq "ok") { $prefix = " OK " }
    elseif ($Level -eq "warn") { $prefix = "WARN" }
    elseif ($Level -eq "error") { $prefix = "FAIL" }
    $stamp = Get-Date -Format "HH:mm:ss"
    $line = "{0}  {1}  {2}" -f $stamp, $prefix, $Message
    Add-WinToolLogLine -Line $line
}

function ConvertTo-WinToolArgumentLine {
    param(
        [string[]]$ArgumentList
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($argument in @($ArgumentList)) {
        if ($null -eq $argument) {
            continue
        }
        $text = [string]$argument
        if ($text -match '[\s"]') {
            $escaped = $text.Replace('"', '\"')
            $parts.Add('"' + $escaped + '"')
        }
        else {
            $parts.Add($text)
        }
    }
    return ($parts -join " ")
}

function Format-WinToolErrorText {
    param(
        $ErrorRecord,
        [string]$Title = "WinTool could not start."
    )
    if ($null -eq $ErrorRecord) {
        return $Title
    }
    $body = ""
    try {
        $body = ($ErrorRecord | Out-String).Trim()
    }
    catch {
        $body = [string]$ErrorRecord
    }
    if ([string]::IsNullOrWhiteSpace($body) -and $null -ne $ErrorRecord.Exception) {
        $body = [string]$ErrorRecord.Exception.Message
    }
    $text = $Title + "`r`n`r`n" + $body
    $stack = [string]$ErrorRecord.ScriptStackTrace
    if (-not [string]::IsNullOrWhiteSpace($stack)) {
        $text += "`r`n`r`n" + $stack
    }
    return $text
}

function Write-WinToolFailureLog {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $directory = Join-Path $env:TEMP "WinTool"
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $Path = Join-Path $directory "wintool.log"
    }
    else {
        $directory = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
    $stamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $block = "==== $stamp ====`r`n" + $Text + "`r`n"
    Add-Content -LiteralPath $Path -Value $block -Encoding UTF8
    return $Path
}

function Show-WinToolFailure {
    param(
        $ErrorRecord
    )
    try {
        Show-WinToolConsole
    }
    catch {
        $null = $_.Exception.Message
    }
    $text = Format-WinToolErrorText -ErrorRecord $ErrorRecord
    $path = $null
    try {
        $path = Write-WinToolFailureLog -Text $text
    }
    catch {
        $path = $null
    }
    Write-Host ""
    Write-Host $text
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        Write-Host ""
        Write-Host "Log: $path"
    }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        $dialog = $text
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $dialog += "`r`n`r`nLog: $path"
        }
        if ($dialog.Length -gt 3500) {
            $dialog = $dialog.Substring(0, 3500) + "..."
        }
        [System.Windows.MessageBox]::Show($dialog, "WinTool") | Out-Null
    }
    catch {
        Write-Host $_.Exception.Message
    }
    if ($env:WINTOOL_PAUSE_ON_ERROR -eq "1") {
        Write-Host ""
        Write-Host "Press Enter to close this window."
        Read-Host | Out-Null
        exit 1
    }
}

function Write-WinToolUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}
