# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Get-WinToolModuleScript {
    param(
        [string]$Name = "Terminal-Icons"
    )
    if ($Name -notmatch '^[A-Za-z0-9.-]+$') {
        throw "Unexpected module name '$Name'."
    }
    # PowerShellGet 1.0 (Windows PowerShell 5.1) lacks some switches, so they
    # are only passed when this Install-Module has them.
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
$options = @{ Name = "__MODULE__"; Scope = "CurrentUser"; Force = $true }
$installer = Get-Command -Name Install-Module
if ($installer.Parameters.ContainsKey("AllowClobber")) { $options["AllowClobber"] = $true }
if ($installer.Parameters.ContainsKey("SkipPublisherCheck")) { $options["SkipPublisherCheck"] = $true }
Install-Module @options
$installed = Get-Module -ListAvailable -Name "__MODULE__" | Sort-Object Version -Descending | Select-Object -First 1
Write-Output ("__MODULE__ " + [string]$installed.Version + " installed.")
'@
    return $scriptText.Replace("__MODULE__", $Name)
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
    if (Test-WinToolLocalStepType -Type $type) {
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
        $moduleName = [string](Get-WinToolNote -Object $Step -Name "Module" -Default "Terminal-Icons")
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("WinTool-module-" + $moduleName + ".ps1")
        Write-WinToolUtf8File -Path $scriptPath -Text (Get-WinToolModuleScript -Name $moduleName)
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
        $distro = Get-WinToolWslDistroName -Step $Step
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-wsl-install.ps1"
        Write-WinToolUtf8File -Path $scriptPath -Text (Get-WinToolWslInstallScript -Distro $distro)
        return [pscustomobject]@{
            FilePath = (Get-WinToolSystemFile -RelativePath "System32\WindowsPowerShell\v1.0\powershell.exe")
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    if ($type -eq "font-download") {
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-font-download.ps1"
        $body = Get-WinToolFontDownloadScript -Step $Step
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
        $distro = Get-WinToolWslDistroName -Step $Step
        $bashPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-wsl-setup.sh"
        Write-WinToolUtf8File -Path $bashPath -Text (Get-WinToolWslSetupText -Step $Step)
        $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "WinTool-wsl-shell.ps1"
        Write-WinToolUtf8File -Path $scriptPath -Text (Get-WinToolWslShellScript -Distro $distro -ScriptPath $bashPath)
        return [pscustomobject]@{
            FilePath = (Get-WinToolSystemFile -RelativePath "System32\WindowsPowerShell\v1.0\powershell.exe")
            ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
        }
    }
    throw "Unknown plan step '$type'."
}

# Steps that run inside WinTool instead of as a separate program. Both the
# window's runner and Invoke-WinToolPlan ask Get-WinToolPlanCommand first; a
# $null answer means "run it here", so every type listed here needs a handler.
$script:WinToolLocalStepHandlers = [ordered]@{
    "font" = "Invoke-WinToolFontStep"
    "profile" = "Invoke-WinToolProfileStep"
    "scheme" = "Invoke-WinToolSchemeStep"
    "starship-preset" = "Invoke-WinToolStarshipPresetStep"
    "wsl-profile" = "Invoke-WinToolWslProfileStep"
}

function Test-WinToolLocalStepType {
    param(
        [string]$Type
    )
    return $script:WinToolLocalStepHandlers.Contains([string]$Type)
}

function Invoke-WinToolFontStep {
    param($Step)
    Invoke-WinToolTerminalFont -Face ([string]$Step.Face) -Match ([string]$Step.Match)
}

function Invoke-WinToolProfileStep {
    param($Step)
    Write-WinToolShellProfile -PromptId ([string]$Step.Prompt) -TerminalIcons ([bool]$Step.TerminalIcons) -PromptStyle ([string]$Step.PromptStyle) -PsReadLine ([bool]$Step.PsReadLine) -Zoxide ([bool]$Step.Zoxide)
}

function Invoke-WinToolSchemeStep {
    param($Step)
    Invoke-WinToolTerminalScheme -SchemeId ([string]$Step.SchemeId)
}

function Invoke-WinToolStarshipPresetStep {
    param($Step)
    Invoke-WinToolStarshipPreset -Preset ([string]$Step.Preset)
}

function Invoke-WinToolWslProfileStep {
    param($Step)
    Invoke-WinToolWslTerminalProfile -Distro (Get-WinToolWslDistroName -Step $Step) -Face ([string]$Step.Face) -Match ([string]$Step.Match)
}

function Invoke-WinToolLocalStep {
    param(
        [Parameter(Mandatory = $true)]$Step
    )
    $type = [string]$Step.Type
    if (-not (Test-WinToolLocalStepType -Type $type)) {
        throw "Step '$type' is not a local step."
    }
    & ([string]$script:WinToolLocalStepHandlers[$type]) -Step $Step
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
