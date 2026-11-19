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

function Get-WinToolLaunchArgument {
    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add("-STA")
    $arguments.Add("-NoProfile")
    $arguments.Add("-ExecutionPolicy")
    $arguments.Add("Bypass")
    $path = $PSCommandPath
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $arguments.Add("-File")
        $arguments.Add($path)
        if (-not [string]::IsNullOrWhiteSpace($script:WinToolApplyProfile)) {
            $arguments.Add("-ApplyProfile")
            $arguments.Add($script:WinToolApplyProfile)
        }
        if ($script:WinToolUnattended) {
            $arguments.Add("-Unattended")
        }
        return $arguments.ToArray()
    }

    $url = $script:WinToolPublishedUrl
    if (-not [string]::IsNullOrWhiteSpace($env:WINTOOL_URL)) {
        $url = $env:WINTOOL_URL
    }
    $arguments.Add("-Command")
    $arguments.Add("irm '$url' | iex")
    return $arguments.ToArray()
}

function Request-WinToolAdministrator {
    Write-Host "WinTool needs administrator approval. Accept the Windows prompt to continue."
    $executable = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"
    $line = ConvertTo-WinToolArgumentLine -ArgumentList @(Get-WinToolLaunchArgument)
    try {
        Start-Process -FilePath $executable -ArgumentList $line -Verb RunAs | Out-Null
    }
    catch {
        Write-Host "WinTool was not started. Administrator approval was declined."
    }
}

function Request-WinToolStaHost {
    Write-Host "WinTool is opening in Windows PowerShell so the window can run."
    $executable = Join-Path $env:SystemRoot "System32/WindowsPowerShell/v1.0/powershell.exe"
    $line = ConvertTo-WinToolArgumentLine -ArgumentList @(Get-WinToolLaunchArgument)
    Start-Process -FilePath $executable -ArgumentList $line | Out-Null
}
