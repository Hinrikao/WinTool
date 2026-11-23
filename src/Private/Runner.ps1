# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolModuleScript {
    $scriptText = @'
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
if ($null -eq $nuget) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
$gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if ($null -eq $gallery) {
    Register-PSRepository -Default
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -AllowClobber
Write-Output "Terminal-Icons installed."
'@
    return $scriptText
}

function Get-WinToolWingetStepAction {
    param($Step)
    $action = [string](Get-WinToolNote -Object $Step -Name "Action" -Default "install")
    if ([string]::IsNullOrWhiteSpace($action)) {
        $action = "install"
    }
    return $action
}

function Test-WinToolStepSuccess {
    param(
        [Parameter(Mandatory = $true)]$Step,
        [int]$ExitCode
    )
    $codes = @(Get-WinToolNote -Object $Step -Name "SuccessCodes" -Default @(0))
    foreach ($code in $codes) {
        if ([int]$code -eq $ExitCode) {
            return $true
        }
    }
    return $false
}

function Get-WinToolPlanCommand {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    $type = [string]$Step.Type
    if ($type -eq "font" -or $type -eq "profile") {
        return $null
    }
    if ($type -eq "winget") {
        return [pscustomobject]@{
            FilePath = Get-WinToolWingetPath
            ArgumentList = @(Get-WinToolWingetArgument -Id ([string]$Step.WingetId) -Scope ([string]$Step.Scope) -Action (Get-WinToolWingetStepAction -Step $Step))
        }
    }
    if ($type -eq "process") {
        return [pscustomobject]@{
            FilePath = [string]$Step.FilePath
            ArgumentList = @($Step.Arguments)
        }
    }
    if ($type -eq "module") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-terminal-icons.ps1"
        Write-WinToolUtf8File -Path $scriptPath -Text (Get-WinToolModuleScript)
        $hostPath = $null
        if ([string]$Step.Host -eq "pwsh") {
            Sync-WinToolProcessPath
            $command = Get-Command -Name "pwsh.exe" -ErrorAction SilentlyContinue
            if ($null -ne $command) {
                $hostPath = [string]$command.Source
            }
        }
        else {
            $hostPath = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"
        }
        return [pscustomobject]@{
            FilePath = $hostPath
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "fix-script") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-fix-" + [string]$Step.Script + ".ps1")
        Write-WinToolUtf8File -Path $scriptPath -Text (Get-WinToolFixScript -Name ([string]$Step.Script))
        return [pscustomobject]@{
            FilePath = (Get-WinToolSystemFile -RelativePath "System32\WindowsPowerShell\v1.0\powershell.exe")
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "inline-script") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-" + [string]$Step.Name + ".ps1")
        Write-WinToolUtf8File -Path $scriptPath -Text ([string]$Step.Text)
        return [pscustomobject]@{
            FilePath = (Get-WinToolSystemFile -RelativePath "System32\WindowsPowerShell\v1.0\powershell.exe")
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "wsl-install") {
        return [pscustomobject]@{
            FilePath = (Join-Path $env:SystemRoot "System32/wsl.exe")
            ArgumentList = @("--install", "-d", "Ubuntu", "--no-launch")
        }
    }
    if ($type -eq "font-download") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-font-download.ps1"
        $body = Get-WinToolFontDownloadScript -Release ([string]$Step.Release) -Asset ([string]$Step.Asset)
        Write-WinToolUtf8File -Path $scriptPath -Text $body
        $hostPath = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"
        return [pscustomobject]@{
            FilePath = $hostPath
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "tool-download") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-tool-download.ps1"
        $body = Get-WinToolToolDownloadScript -Url ([string]$Step.Url) -FileName ([string]$Step.FileName)
        Write-WinToolUtf8File -Path $scriptPath -Text $body
        $hostPath = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"
        return [pscustomobject]@{
            FilePath = $hostPath
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "wsl-shell") {
        $wsl = Join-Path $env:SystemRoot "System32/wsl.exe"
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-wsl-setup.sh"
        $bash = Get-WinToolPayloadText -Name "Wsl"
        $bash = $bash -replace "`r`n", "`n" -replace "`r", "`n"
        $variant = [string](Get-WinToolNote -Object $Step -Name "Variant" -Default "")
        $omzTheme = [string](Get-WinToolNote -Object $Step -Name "OmzTheme" -Default "robbyrussell")
        if ([string]::IsNullOrWhiteSpace($omzTheme)) { $omzTheme = "robbyrussell" }
        if (-not [string]::IsNullOrWhiteSpace($variant)) {
            $bash = "export WINTOOL_SHELL_PROMPT=" + $variant + "`nexport WINTOOL_OMZ_THEME=" + $omzTheme + "`n" + $bash
        }
        Write-WinToolUtf8File -Path $scriptPath -Text $bash
        $unix = $scriptPath
        if (Test-Path -LiteralPath $wsl) {
            $converted = & $wsl wslpath -a $scriptPath
            if ($converted -is [System.Array]) {
                $converted = $converted[-1]
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$converted)) {
                $unix = ([string]$converted).Trim()
            }
        }
        return [pscustomobject]@{
            FilePath = $wsl
            ArgumentList = @("-d", "Ubuntu", "--", "bash", $unix)
        }
    }
    throw "Unknown plan step '$type'."
}

function Invoke-WinToolLocalStep {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    $type = [string]$Step.Type
    if ($type -eq "font") {
        Invoke-WinToolTerminalFont -Face ([string]$Step.Face) -Match ([string]$Step.Match)
        return
    }
    if ($type -eq "profile") {
        Write-WinToolShellProfile -PromptId ([string]$Step.Prompt) -TerminalIcons ([bool]$Step.TerminalIcons) -PromptStyle ([string]$Step.PromptStyle) -PsReadLine ([bool]$Step.PsReadLine) -Zoxide ([bool]$Step.Zoxide)
        return
    }
    if ($type -eq "scheme") {
        Invoke-WinToolTerminalScheme -SchemeId ([string]$Step.SchemeId)
        return
    }
    if ($type -eq "starship-preset") {
        Invoke-WinToolStarshipPreset -Preset ([string]$Step.Preset)
        return
    }
    throw "Step '$type' is not a local step."
}

function Invoke-WinToolPlan {
    param(
        $Step
    )
    $steps = @($Step)
    $index = 0
    $skipZsh = $false
    foreach ($item in $steps) {
        $index++
        if ([string]$item.Type -eq "wsl-shell" -and $skipZsh) {
            Write-WinToolLog -Message "Zsh setup is waiting on a reboot. Run terminal setup again after Windows restarts." -Level "warn"
            continue
        }
        Write-WinToolLog -Message ("[{0}/{1}] {2}" -f $index, $steps.Count, [string]$item.Label) -Level "info"
        $command = Get-WinToolPlanCommand -Step $item
        if ($null -eq $command) {
            try {
                Invoke-WinToolLocalStep -Step $item
            }
            catch {
                Write-WinToolLog -Message ("{0} failed. {1}" -f [string]$item.Label, $_.Exception.Message) -Level "error"
            }
            continue
        }
        if ([string]::IsNullOrWhiteSpace([string]$command.FilePath) -or -not (Test-Path -LiteralPath ([string]$command.FilePath))) {
            Write-WinToolLog -Message ("Skipped {0} because the program was not found." -f [string]$item.Label) -Level "warn"
            continue
        }
        $result = Invoke-WinToolCapturedProcess -FilePath ([string]$command.FilePath) -ArgumentList @($command.ArgumentList)
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
            foreach ($line in ($result.Output -split '\r?\n')) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-WinToolLog -Message $line.Trim() -Level "info"
                }
            }
        }
        if ([string]$item.Type -eq "winget") {
            $outcome = ConvertTo-WinToolWingetResult -ExitCode $result.ExitCode -Output $result.Output
            if ($outcome.Status -eq "Failed") {
                Write-WinToolLog -Message ("{0} failed (exit {1})." -f [string]$item.Label, $result.ExitCode) -Level "error"
            }
            elseif ($outcome.Status -eq "AlreadyInstalled") {
                Write-WinToolLog -Message ("{0}: {1}." -f [string]$item.Label, (Get-WinToolWingetOutcomeText -Action (Get-WinToolWingetStepAction -Step $item) -Status $outcome.Status)) -Level "ok"
            }
            else {
                Write-WinToolLog -Message ("{0}: done." -f [string]$item.Label) -Level "ok"
            }
        }
        elseif (-not (Test-WinToolStepSuccess -Step $item -ExitCode $result.ExitCode)) {
            Write-WinToolLog -Message ("{0} exited with code {1}." -f [string]$item.Label, $result.ExitCode) -Level "error"
        }
        else {
            Write-WinToolLog -Message ("{0}: done." -f [string]$item.Label) -Level "ok"
        }
        if ([string]$item.Type -eq "wsl-install" -and $result.Output -match "(?i)reboot") {
            $skipZsh = $true
            Write-WinToolLog -Message "Windows asked for a reboot before WSL can finish." -Level "warn"
        }
    }
}

function Start-WinToolScriptJob {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [object[]]$Argument
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
    [void]$powershell.AddScript($ScriptText)
    [void]$powershell.AddArgument($sync)
    foreach ($item in @($Argument)) {
        [void]$powershell.AddArgument($item)
    }
    [void]$powershell.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $powershell
        Handle = $null
        Sync = $sync
        Runspace = $runspace
    }
}
