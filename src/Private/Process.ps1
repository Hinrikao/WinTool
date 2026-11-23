# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function Invoke-WinToolCapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList
    )
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList (ConvertTo-WinToolArgumentLine -ArgumentList $ArgumentList) -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $output = ""
        if (Test-Path -LiteralPath $stdout) {
            $output = [System.IO.File]::ReadAllText($stdout)
        }
        if (Test-Path -LiteralPath $stderr) {
            $errorText = [System.IO.File]::ReadAllText($stderr)
            if (-not [string]::IsNullOrWhiteSpace($errorText)) {
                $output = $output.TrimEnd() + [Environment]::NewLine + $errorText
            }
        }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output = $output.Trim()
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-WinToolProcessPipe {
    if ($null -ne ("WinToolProcessPipe" -as [type])) {
        return
    }
    $source = @"
using System.Collections.Concurrent;
using System.Diagnostics;

public static class WinToolProcessPipe
{
    public static void Attach(Process process, ConcurrentQueue<string> queue)
    {
        process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
        {
            if (e.Data != null) { queue.Enqueue(e.Data); }
        };
        process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
        {
            if (e.Data != null) { queue.Enqueue(e.Data); }
        };
    }
}
"@
    Add-Type -TypeDefinition $source -Language CSharp
}

function Start-WinToolAsyncProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList,
        [Parameter(Mandatory = $true)]$LineQueue
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = (ConvertTo-WinToolArgumentLine -ArgumentList $ArgumentList)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $process.EnableRaisingEvents = $true
    # The output events fire on thread-pool threads that have no PowerShell
    # runspace. A scriptblock handler there throws "There is no Runspace
    # available" and ends the whole process, so a small compiled handler fills
    # the queue instead. The log pump timer reads it on the UI thread.
    Initialize-WinToolProcessPipe
    [WinToolProcessPipe]::Attach($process, $LineQueue)
    $started = $process.Start()
    if (-not $started) {
        throw "The process did not start: $FilePath"
    }
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    return $process
}
