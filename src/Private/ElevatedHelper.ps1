# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

# A hidden elevated helper talks to the (possibly non-admin) WinTool window
# over a named pipe. The GUI starts it on the first action that needs
# administrator approval, keeps it for the session, and stops it on close.
# A non-admin process cannot elevate itself in place; this helper is the new
# process Windows creates at UAC, kept out of sight.

$script:WinToolHelperClient = $null
$script:WinToolHelperProcess = $null
$script:WinToolHelperPipeName = $null
$script:WinToolHelperLogCallback = $null

function Test-WinToolElevateAtStart {
    return ($env:WINTOOL_ELEVATE_AT_START -eq "1")
}

function Test-WinToolShouldDetachHost {
    param(
        [bool]$ShowConsole,
        [bool]$Unattended,
        [string]$HiddenChild
    )
    if ($ShowConsole -or $Unattended) {
        return $false
    }
    if ($HiddenChild -eq "1") {
        return $false
    }
    return $true
}

function Test-WinToolCurrentShouldDetachHost {
    return (Test-WinToolShouldDetachHost -ShowConsole (Test-WinToolShowConsole) -Unattended ([bool]$script:WinToolUnattended) -HiddenChild ([string]$env:WINTOOL_HIDDEN))
}

function Get-WinToolSameUserSddl {
    if (-not (Test-WinToolWindows)) {
        return $null
    }
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    # Full control for this user, medium mandatory label so a normal and an
    # elevated copy of the same account can both open the object.
    return ("D:(A;;GA;;;{0})S:(ML;;NW;;;ME)" -f $sid)
}

function Get-WinToolHelperAllowedFactory {
    return @(
        "Get-WinToolRestorePointScript",
        "Get-WinToolDriverBackupScript",
        "Get-WinToolDriverOfflineScript",
        "Get-WinToolDriverAudioScript",
        "Get-WinToolDriverNetworkScript",
        "Get-WinToolDriverRemoveScript",
        "Get-WinToolDriverRescanScript",
        "Get-WinToolDriverToggleScript",
        "Get-WinToolUpdateInstallScript",
        "Get-WinToolDriverRollbackScript"
    )
}

function Test-WinToolHelperFactoryAllowed {
    param([string]$Name)
    return ((Get-WinToolHelperAllowedFactory) -contains [string]$Name)
}

function Test-WinToolTweakStepNeedsAdmin {
    param($Step)
    if ($null -eq $Step) {
        return $false
    }
    $type = [string](Get-WinToolNote -Object $Step -Name "type" -Default "")
    if ($type -in @("service", "scheduled-task", "appx")) {
        return $true
    }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(Get-WinToolNote -Object $Step -Name "entries" -Default @())) {
        $paths.Add([string](Get-WinToolNote -Object $entry -Name "path" -Default ""))
    }
    $paths.Add([string](Get-WinToolNote -Object $Step -Name "path" -Default ""))
    foreach ($path in $paths) {
        if ($path -match '^(HKLM|HKEY_LOCAL_MACHINE|HKCR|HKEY_CLASSES_ROOT):') {
            return $true
        }
    }
    return $false
}

function Test-WinToolTweakNeedsAdmin {
    param($Tweak)
    if ($null -eq $Tweak) {
        return $false
    }
    foreach ($name in @("apply", "undo")) {
        if (Test-WinToolTweakStepNeedsAdmin -Step (Get-WinToolNote -Object $Tweak -Name $name)) {
            return $true
        }
    }
    return $false
}

function Test-WinToolPlanNeedsAdmin {
    param($Step)
    foreach ($item in @($Step)) {
        if ($null -eq $item) { continue }
        $type = [string](Get-WinToolNote -Object $item -Name "Type" -Default (Get-WinToolNote -Object $item -Name "type" -Default ""))
        if ($type -in @("fix-script", "wsl-install")) {
            return $true
        }
        $file = [string](Get-WinToolNote -Object $item -Name "FilePath" -Default (Get-WinToolNote -Object $item -Name "file" -Default ""))
        if ($file -match '(?i)(Dism|sfc|netsh|pnputil|bcdedit)\.exe$') {
            return $true
        }
        $scope = [string](Get-WinToolNote -Object $item -Name "Scope" -Default "")
        if ($type -eq "winget" -and $scope -match '(?i)machine|allusers') {
            return $true
        }
    }
    return $false
}

function Get-WinToolHelperPipeName {
    if (-not [string]::IsNullOrWhiteSpace($script:WinToolHelperPipeName)) {
        return $script:WinToolHelperPipeName
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WINTOOL_HELPER_PIPE)) {
        return [string]$env:WINTOOL_HELPER_PIPE
    }
    return $null
}

function New-WinToolHelperPipeSecurity {
    if (-not (Test-WinToolWindows)) {
        return $null
    }
    $security = New-Object System.IO.Pipes.PipeSecurity
    $sddl = Get-WinToolSameUserSddl
    if (-not [string]::IsNullOrWhiteSpace($sddl)) {
        try {
            $security.SetSecurityDescriptorSddlForm($sddl)
            return $security
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = New-Object System.IO.Pipes.PipeAccessRule($sid, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($rule)
    return $security
}

function New-WinToolHelperServerPipe {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    $security = New-WinToolHelperPipeSecurity
    return New-Object System.IO.Pipes.NamedPipeServerStream(
        $Name,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous,
        65536,
        65536,
        $security
    )
}

function New-WinToolHelperClientPipe {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )
    return New-Object System.IO.Pipes.NamedPipeClientStream(
        ".",
        $Name,
        [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::Asynchronous
    )
}

function Write-WinToolHelperLine {
    param(
        [Parameter(Mandatory = $true)][System.IO.StreamWriter]$Writer,
        $Value
    )
    $json = ConvertTo-WinToolJsonText -Value $Value
    $one = (($json -replace "\r?\n", " ") -replace "\s+", " ").Trim()
    $Writer.WriteLine($one)
    $Writer.Flush()
}

function Read-WinToolHelperLine {
    param(
        [Parameter(Mandatory = $true)][System.IO.StreamReader]$Reader
    )
    $line = $Reader.ReadLine()
    if ($null -eq $line) {
        return $null
    }
    return (ConvertFrom-WinToolJsonText -Text $line)
}

function Get-WinToolHelperIsolatedSendScript {
    return {
        param($Client, $Operation, $Payload, $TimeoutSeconds)
        if ($null -eq $TimeoutSeconds -or [int]$TimeoutSeconds -le 0) { $TimeoutSeconds = 600 }
        $id = [guid]::NewGuid().ToString("N")
        $message = @{ id = $id; op = [string]$Operation }
        if ($null -ne $Payload) {
            foreach ($key in @($Payload.Keys)) { $message[$key] = $Payload[$key] }
        }
        $json = $message | ConvertTo-Json -Compress -Depth 20
        $Client.Writer.WriteLine($json)
        $Client.Writer.Flush()
        $deadline = [DateTime]::UtcNow.AddSeconds([int]$TimeoutSeconds)
        $logs = New-Object System.Collections.Generic.List[object]
        while ([DateTime]::UtcNow -lt $deadline) {
            $line = $Client.Reader.ReadLine()
            if ($null -eq $line) { throw "helper-closed" }
            $reply = $line | ConvertFrom-Json
            if ([string]$reply.id -ne $id) { continue }
            $kind = [string]$reply.type
            if ($kind -eq "log") {
                $logs.Add([pscustomobject]@{ Level = [string]$reply.level; Message = [string]$reply.message })
                continue
            }
            if ($kind -eq "error") {
                return [pscustomobject]@{ Ok = $false; Result = $null; Message = [string]$reply.message; Logs = $logs.ToArray() }
            }
            return [pscustomobject]@{ Ok = $true; Result = $reply.result; Message = ""; Logs = $logs.ToArray() }
        }
        throw "helper-timeout"
    }
}

function Get-WinToolHelperMessageProperty {
    param(
        $Message,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Message) {
        return $null
    }
    if ($Message -is [System.Collections.IDictionary] -and $Message.Contains($Name)) {
        return $Message[$Name]
    }
    $property = $Message.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
    return $null
}

function Test-WinToolHelperConnected {
    $client = $script:WinToolHelperClient
    if ($null -eq $client) {
        return $false
    }
    try {
        return [bool]$client.Pipe.IsConnected
    }
    catch {
        return $false
    }
}

function Close-WinToolHelperClient {
    $client = $script:WinToolHelperClient
    $script:WinToolHelperClient = $null
    if ($null -eq $client) {
        return
    }
    foreach ($name in @("Writer", "Reader", "Pipe")) {
        try {
            if ($null -ne $client.$name) {
                $client.$name.Dispose()
            }
        }
        catch {
            $null = $_.Exception.Message
        }
    }
}

function Stop-WinToolElevatedHelper {
    if (Test-WinToolHelperConnected) {
        try {
            Send-WinToolHelperCommand -Operation "shutdown" -TimeoutSeconds 3 | Out-Null
        }
        catch {
            $null = $_.Exception.Message
        }
    }
    Close-WinToolHelperClient
    $process = $script:WinToolHelperProcess
    $script:WinToolHelperProcess = $null
    $script:WinToolHelperPipeName = $null
    if ($null -ne $process) {
        try {
            if (-not $process.HasExited) {
                $process.Kill()
            }
        }
        catch {
            $null = $_.Exception.Message
        }
        try { $process.Dispose() } catch { $null = $_.Exception.Message }
    }
}

function New-WinToolHelperStub {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName,
        [int]$ParentId = $PID
    )
    $directory = Join-Path $env:TEMP "WinTool"
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Remove-WinToolStaleTempLauncher -Directory $directory
    $encoding = New-Object System.Text.UTF8Encoding $true
    $entry = Resolve-WinToolEntryPath -EntryPath $script:WinToolEntryPath -CommandPath ""
    if (-not [string]::IsNullOrWhiteSpace($entry) -and -not (Test-Path -LiteralPath $entry)) {
        $entry = $null
    }
    if ([string]::IsNullOrWhiteSpace($entry) -and -not [string]::IsNullOrWhiteSpace($script:WinToolSelfText)) {
        $selfPath = Join-Path $directory ("wintool-self-" + [guid]::NewGuid().ToString("N") + ".ps1")
        [System.IO.File]::WriteAllText($selfPath, $script:WinToolSelfText, $encoding)
        $entry = $selfPath
    }
    $working = Get-WinToolWorkingDirectory
    $scriptText = New-WinToolRelaunchScript -WorkingDirectory $working -EntryPath $entry -ApplyProfile "" -Unattended $false -LaunchUrl (Get-WinToolPublishedLaunchUrl) -Hidden $false -HideConsole $true -ShowConsole $false
    $header = New-Object System.Collections.Generic.List[string]
    [void]$header.Add('$env:WINTOOL_HELPER = "1"')
    [void]$header.Add('$env:WINTOOL_HELPER_PIPE = ' + (ConvertTo-WinToolLiteral -Text $PipeName))
    [void]$header.Add('$env:WINTOOL_HELPER_PARENT = ' + (ConvertTo-WinToolLiteral -Text ([string]$ParentId)))
    $scriptText = ($header.ToArray() -join "`r`n") + "`r`n" + $scriptText
    $path = Join-Path $directory ("helper-" + [guid]::NewGuid().ToString("N") + ".ps1")
    [System.IO.File]::WriteAllText($path, $scriptText, $encoding)
    return $path
}

function Start-WinToolHelperProcess {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName
    )
    $executable = Get-WinToolPreferredGuiHostPath
    if ([string]::IsNullOrWhiteSpace($executable)) {
        $executable = Get-WinToolPowerShell7Path
    }
    if ([string]::IsNullOrWhiteSpace($executable)) {
        throw (Get-WinToolText "shell.installPowerShell7Failed")
    }
    $launcherPath = New-WinToolHelperStub -PipeName $PipeName -ParentId $PID
    # Do not pass -WindowStyle Hidden to Start-Process -Verb RunAs: that hid
    # the UAC prompt. The stub hides the console as its first action.
    $line = ConvertTo-WinToolArgumentLine -ArgumentList @(Get-WinToolHostArgument -LauncherPath $launcherPath -Hidden $false)
    Write-WinToolLog -Message (Get-WinToolText "shell.needsAdmin") -Level "info"
    $process = Start-Process -FilePath $executable -ArgumentList $line -Verb RunAs -WindowStyle Normal -PassThru
    $script:WinToolHelperProcess = $process
    return $process
}

function Connect-WinToolHelperClient {
    param(
        [Parameter(Mandatory = $true)][string]$PipeName,
        [int]$TimeoutSeconds = 180
    )
    $pipe = New-WinToolHelperClientPipe -Name $PipeName
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $connected = $false
    $lastError = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $remaining = [int]([Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds))
            if ($remaining -gt 2000) {
                $remaining = 2000
            }
            $pipe.Connect($remaining)
            $connected = $true
            break
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $connected) {
        try { $pipe.Dispose() } catch { $null = $_.Exception.Message }
        $text = Get-WinToolText "error.helperFailed"
        if (-not [string]::IsNullOrWhiteSpace($lastError)) {
            $text += " " + $lastError
        }
        throw $text
    }
    $reader = New-Object System.IO.StreamReader($pipe, [System.Text.Encoding]::UTF8, $false, 4096, $true)
    $writer = New-Object System.IO.StreamWriter($pipe, [System.Text.Encoding]::UTF8, 4096, $true)
    $writer.AutoFlush = $true
    $script:WinToolHelperClient = [pscustomobject]@{
        Pipe   = $pipe
        Reader = $reader
        Writer = $writer
    }
    $script:WinToolHelperPipeName = $PipeName
}

function Send-WinToolHelperCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Operation,
        $Payload,
        [int]$TimeoutSeconds = 600,
        $Client
    )
    if ($null -eq $Client) {
        $Client = $script:WinToolHelperClient
    }
    $connected = $false
    try { $connected = [bool]$Client.Pipe.IsConnected } catch { $connected = $false }
    if (-not $connected) {
        throw (Get-WinToolText "error.helperFailed")
    }
    $id = [guid]::NewGuid().ToString("N")
    $message = @{
        id   = $id
        op   = $Operation
    }
    if ($null -ne $Payload) {
        foreach ($key in @($Payload.Keys)) {
            $message[$key] = $Payload[$key]
        }
    }
    Write-WinToolHelperLine -Writer $Client.Writer -Value $message
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $logs = New-Object System.Collections.Generic.List[object]
    while ([DateTime]::UtcNow -lt $deadline) {
        $reply = Read-WinToolHelperLine -Reader $Client.Reader
        if ($null -eq $reply) {
            throw (Get-WinToolText "error.helperFailed")
        }
        $replyId = [string](Get-WinToolHelperMessageProperty -Message $reply -Name "id")
        if ($replyId -ne $id) {
            continue
        }
        $kind = [string](Get-WinToolHelperMessageProperty -Message $reply -Name "type")
        if ($kind -eq "log") {
            $level = [string](Get-WinToolHelperMessageProperty -Message $reply -Name "level")
            $text = [string](Get-WinToolHelperMessageProperty -Message $reply -Name "message")
            $logs.Add([pscustomobject]@{ Level = $level; Message = $text })
            if ($null -ne $script:WinToolHelperClientLogSink) {
                & $script:WinToolHelperClientLogSink $text $level
            }
            else {
                $useLevel = $level
                if ($useLevel -notin @("info", "ok", "warn", "error")) {
                    $useLevel = "info"
                }
                Write-WinToolLog -Message $text -Level $useLevel
            }
            continue
        }
        if ($kind -eq "error") {
            $errorText = [string](Get-WinToolHelperMessageProperty -Message $reply -Name "message")
            return [pscustomobject]@{
                Ok      = $false
                Result  = $null
                Message = $errorText
                Logs    = $logs.ToArray()
            }
        }
        return [pscustomobject]@{
            Ok      = $true
            Result  = (Get-WinToolHelperMessageProperty -Message $reply -Name "result")
            Message = ""
            Logs    = $logs.ToArray()
        }
    }
    throw (Get-WinToolText "error.helperFailed")
}

function Request-WinToolElevatedHelper {
    if (Test-WinToolAdministrator) {
        return $true
    }
    if (Test-WinToolHelperConnected) {
        return $true
    }
    if (-not (Test-WinToolWindows)) {
        Write-WinToolLog -Message (Get-WinToolText "error.helperFailed") -Level "error"
        return $false
    }
    Close-WinToolHelperClient
    $pipeName = "WinTool.Hinrikao.Helper." + [guid]::NewGuid().ToString("N")
    $script:WinToolHelperPipeName = $pipeName
    try {
        $null = Start-WinToolHelperProcess -PipeName $pipeName
        Connect-WinToolHelperClient -PipeName $pipeName -TimeoutSeconds 180
        $ping = Send-WinToolHelperCommand -Operation "ping" -TimeoutSeconds 30
        if (-not [bool]$ping.Ok) {
            throw (Get-WinToolText "error.helperFailed")
        }
        return $true
    }
    catch {
        $record = $_
        Stop-WinToolElevatedHelper
        $text = Get-WinToolElevationFailureText -ErrorRecord $record
        $code = 0
        $exception = $record.Exception
        while ($null -ne $exception) {
            if ($exception -is [System.ComponentModel.Win32Exception]) {
                $code = [int]$exception.NativeErrorCode
                break
            }
            $exception = $exception.InnerException
        }
        if ($code -eq 1223) {
            $text = Get-WinToolText "error.helperUacCanceled"
        }
        elseif ([string]$record.Exception.Message -notmatch 'helperFailed|could not start the administrator helper') {
            if ([string]$record.Exception.Message -match 'canceled|cancelled|1223') {
                $text = Get-WinToolText "error.helperUacCanceled"
            }
            else {
                $text = Get-WinToolText "error.helperFailed"
                if (-not [string]::IsNullOrWhiteSpace([string]$record.Exception.Message)) {
                    $text += " " + [string]$record.Exception.Message
                }
            }
        }
        else {
            $text = [string]$record.Exception.Message
        }
        Write-WinToolLog -Message $text -Level "warn"
        try {
            Show-WinToolElevationNotice -Text $text
        }
        catch {
            $null = $_.Exception.Message
        }
        return $false
    }
}

function Invoke-WinToolHelperPlan {
    param($Step)
    $payload = @{
        steps = @($Step)
    }
    $result = Send-WinToolHelperCommand -Operation "invoke-plan" -Payload $payload
    if (-not [bool]$result.Ok) {
        $message = [string]$result.Message
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = Get-WinToolText "error.helperFailed"
        }
        Write-WinToolLog -Message $message -Level "error"
    }
    return $result
}

function Invoke-WinToolHelperTweakChange {
    param(
        $TweakId,
        [string]$Direction
    )
    $payload = @{
        tweakId   = [string]$TweakId
        direction = [string]$Direction
    }
    return (Send-WinToolHelperCommand -Operation "invoke-tweak" -Payload $payload)
}

function Start-WinToolHelperScriptJob {
    param(
        [Parameter(Mandatory = $true)][string]$Factory,
        [object[]]$Argument
    )
    return (Start-WinToolHelperScriptJobLocal -Factory $Factory -Argument $Argument)
}

function Start-WinToolHelperScriptJobLocal {
    param(
        [Parameter(Mandatory = $true)][string]$Factory,
        [object[]]$Argument
    )
    $sync = [hashtable]::Synchronized(@{
        Done  = $false
        Ok    = $false
        Error = $null
    })
    $thread = [System.Threading.Thread]::new({
            param($State)
            try {
                $payload = @{ factory = [string]$State.Factory }
                if ($null -ne $State.Argument) {
                    $payload["argument"] = @($State.Argument)
                }
                $result = Send-WinToolHelperCommand -Operation "run-script" -Payload $payload
                if ([bool]$result.Ok) {
                    $State.Sync.Ok = $true
                    $value = $result.Result
                    if ($value -is [System.Collections.IDictionary]) {
                        foreach ($key in @($value.Keys)) {
                            $State.Sync[$key] = $value[$key]
                        }
                    }
                    elseif ($null -ne $value -and $null -ne $value.PSObject) {
                        foreach ($property in $value.PSObject.Properties) {
                            $State.Sync[$property.Name] = $property.Value
                        }
                    }
                }
                else {
                    $State.Sync.Error = [string]$result.Message
                }
            }
            catch {
                $State.Sync.Error = $_.Exception.Message
            }
            finally {
                $State.Sync.Done = $true
            }
        })
    # PowerShell 5.1 scriptblocks used as ThreadStart cannot take param this
    # way reliably. Use a runspace that is created from this session.
    $runspace = [runspacefactory]::CreateRunspace($Host)
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $null = $thread
    $script:WinToolHelperJobState = @{
        Sync     = $sync
        Factory  = $Factory
        Argument = @($Argument)
    }
    [void]$powershell.AddScript({
            param($Send, $Sync, $Factory, $Argument, $Client)
            $ErrorActionPreference = "Stop"
            try {
                $payload = @{ factory = [string]$Factory }
                if ($null -ne $Argument) { $payload["argument"] = @($Argument) }
                $result = & $Send $Client "run-script" $payload 600
                if ([bool]$result.Ok) {
                    $Sync.Ok = $true
                    $value = $result.Result
                    if ($value -is [System.Collections.IDictionary]) {
                        foreach ($key in @($value.Keys)) { $Sync[$key] = $value[$key] }
                    }
                    elseif ($null -ne $value) {
                        foreach ($property in $value.PSObject.Properties) { $Sync[$property.Name] = $property.Value }
                    }
                }
                else {
                    $Sync.Error = [string]$result.Message
                }
            }
            catch {
                $Sync.Error = $_.Exception.Message
            }
            finally {
                $Sync.Done = $true
            }
        })
    [void]$powershell.AddArgument((Get-WinToolHelperIsolatedSendScript))
    [void]$powershell.AddArgument($sync)
    [void]$powershell.AddArgument($Factory)
    [void]$powershell.AddArgument(@($Argument))
    [void]$powershell.AddArgument($script:WinToolHelperClient)
    [void]$powershell.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $powershell
        Handle     = $null
        Sync       = $sync
        Runspace   = $runspace
    }
}

function Start-WinToolPrivilegedScriptJob {
    param(
        [Parameter(Mandatory = $true)][string]$Factory,
        [object[]]$Argument
    )
    $scriptText = & $Factory
    if (Test-WinToolAdministrator) {
        return (Start-WinToolScriptJob -ScriptText $scriptText -Argument $Argument)
    }
    if (-not (Request-WinToolElevatedHelper)) {
        $sync = [hashtable]::Synchronized(@{
            Done  = $true
            Ok    = $false
            Error = (Get-WinToolText "error.helperUacCanceled")
        })
        return [pscustomobject]@{
            PowerShell = $null
            Handle     = $null
            Sync       = $sync
            Runspace   = $null
        }
    }
    return (Start-WinToolHelperScriptJobLocal -Factory $Factory -Argument $Argument)
}

function Start-WinToolHelperRestorePointJob {
    param(
        [string]$Description = (Get-WinToolText "msg.wintool-before-tweaks")
    )
    if (-not (Request-WinToolElevatedHelper)) {
        return [pscustomobject]@{
            PowerShell = $null
            Handle     = $null
            Sync       = [hashtable]::Synchronized(@{
                Done  = $true
                Ok    = $false
                Error = (Get-WinToolText "error.helperUacCanceled")
            })
            Runspace   = $null
        }
    }
    $sync = [hashtable]::Synchronized(@{
        Done  = $false
        Ok    = $false
        Error = $null
    })
    $runspace = [runspacefactory]::CreateRunspace($Host)
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    [void]$powershell.AddScript({
            param($Send, $Sync, $Description, $Client)
            try {
                $result = & $Send $Client "restore-point" @{ description = [string]$Description } 180
                $Sync.Ok = [bool]$result.Ok
                if (-not $Sync.Ok) {
                    $Sync.Error = [string]$result.Message
                }
            }
            catch {
                $Sync.Error = $_.Exception.Message
            }
            finally {
                $Sync.Done = $true
            }
        })
    [void]$powershell.AddArgument((Get-WinToolHelperIsolatedSendScript))
    [void]$powershell.AddArgument($sync)
    [void]$powershell.AddArgument($Description)
    [void]$powershell.AddArgument($script:WinToolHelperClient)
    [void]$powershell.BeginInvoke()
    return [pscustomobject]@{
        PowerShell = $powershell
        Handle     = $null
        Sync       = $sync
        Runspace   = $runspace
    }
}

function Start-WinToolHelperPlanAsync {
    param(
        $Step,
        [Parameter(Mandatory = $true)][string]$DoneMessage,
        [string]$AfterDone,
        [switch]$Update
    )
    $null = $Update
    $queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
    $script:WinToolState.Run = @{
        Steps       = @($Step)
        Index       = -1
        Process     = $null
        Queue       = $queue
        StepLog     = New-Object System.Collections.Generic.List[string]
        ExitHandled = $false
        Cancel      = $false
        DoneMessage = $DoneMessage
        AfterDone   = $AfterDone
        SkipZsh     = $false
        Update      = $false
        Tally       = $null
        Cache       = $null
    }
    Start-WinToolActivity -Title $DoneMessage | Out-Null
    Sync-WinToolBusyState -Busy $true
    Enable-WinToolLogPump
    Sync-WinToolProgress -Value 0 -Text (Get-WinToolText "shell.helperStarting") -Indeterminate $true
    $sync = [hashtable]::Synchronized(@{
        Done    = $false
        Ok      = $false
        Error   = $null
        Message = ""
    })
    $runspace = [runspacefactory]::CreateRunspace($Host)
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    # Keep logging on this session: the send function is invoked from the
    # helper client in the job; log lines are forwarded below via the result.
    [void]$powershell.AddScript({
            param($Send, $Sync, $Steps, $Client)
            try {
                $result = & $Send $Client "invoke-plan" @{ steps = $Steps } 3600
                $Sync.Ok = [bool]$result.Ok
                $Sync.Message = [string]$result.Message
                if ($null -ne $result.Logs) {
                    $Sync.Logs = @($result.Logs)
                }
            }
            catch {
                $Sync.Error = $_.Exception.Message
                $Sync.Ok = $false
            }
            finally {
                $Sync.Done = $true
            }
        })
    [void]$powershell.AddArgument((Get-WinToolHelperIsolatedSendScript))
    [void]$powershell.AddArgument($sync)
    [void]$powershell.AddArgument(@($Step))
    [void]$powershell.AddArgument($script:WinToolHelperClient)
    [void]$powershell.BeginInvoke()
    $script:WinToolState.HelperPlanJob = [pscustomobject]@{
        PowerShell = $powershell
        Handle     = $null
        Sync       = $sync
        Runspace   = $runspace
        AfterDone  = $AfterDone
    }
}

function Complete-WinToolHelperPlanJob {
    $job = $script:WinToolState.HelperPlanJob
    if ($null -eq $job) {
        return
    }
    $ok = [bool]$job.Sync.Ok
    $errorMessage = [string]$job.Sync.Error
    if ([string]::IsNullOrWhiteSpace($errorMessage)) {
        $errorMessage = [string]$job.Sync.Message
    }
    foreach ($entry in @($job.Sync.Logs)) {
        if ($null -eq $entry) { continue }
        $level = [string]$entry.Level
        $text = [string]$entry.Message
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($level -notin @("info", "ok", "warn", "error")) { $level = "info" }
        Write-WinToolLog -Message $text -Level $level
    }
    $after = [string]$job.AfterDone
    try { Stop-WinToolThread -Job $job } catch { $null = $_.Exception.Message }
    $script:WinToolState.HelperPlanJob = $null
    if (-not $ok) {
        if ([string]::IsNullOrWhiteSpace($errorMessage)) {
            $errorMessage = Get-WinToolText "error.helperFailed"
        }
        Complete-WinToolPlan -Message $errorMessage
        return
    }
    $message = [string]$script:WinToolState.Run.DoneMessage
    Complete-WinToolPlan -Message $message
    if (-not [string]::IsNullOrWhiteSpace($after)) {
        try { & $after } catch { Write-WinToolLog -Message $_.Exception.Message -Level "warn" }
    }
}

function Invoke-WinToolHelperHostCommand {
    param($Message, [System.IO.StreamWriter]$Writer)
    $id = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "id")
    $op = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "op")
    try {
        switch ($op) {
            "ping" {
                Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = "pong" }
            }
            "shutdown" {
                Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = "bye" }
                return "shutdown"
            }
            "invoke-plan" {
                $steps = @(Get-WinToolHelperMessageProperty -Message $Message -Name "steps")
                $script:WinToolHelperLogCallback = {
                    param($Text, $Level)
                    Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "log"; level = $Level; message = $Text }
                }
                try {
                    Invoke-WinToolPlan -Step $steps | Out-Null
                    Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = "done" }
                }
                finally {
                    $script:WinToolHelperLogCallback = $null
                }
            }
            "invoke-tweak" {
                $tweakId = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "tweakId")
                $direction = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "direction")
                $catalog = @(Get-WinToolNote -Object (Get-WinToolTweakCatalog) -Name "tweaks" -Default @())
                $tweak = $catalog | Where-Object { [string]$_.id -eq $tweakId } | Select-Object -First 1
                if ($null -eq $tweak) {
                    throw (Get-WinToolText "error.helperUnknownTweak" $tweakId)
                }
                $script:WinToolHelperLogCallback = {
                    param($Text, $Level)
                    Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "log"; level = $Level; message = $Text }
                }
                try {
                    Invoke-WinToolTweakChange -Tweak $tweak -Direction $direction -RestartExplorer $true
                    Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = "done" }
                }
                finally {
                    $script:WinToolHelperLogCallback = $null
                }
            }
            "restore-point" {
                $description = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "description")
                Invoke-WinToolRestorePoint -Description $description
                Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = "done" }
            }
            "run-script" {
                $factory = [string](Get-WinToolHelperMessageProperty -Message $Message -Name "factory")
                if (-not (Test-WinToolHelperFactoryAllowed -Name $factory)) {
                    throw (Get-WinToolText "error.helperUnknownFactory" $factory)
                }
                $command = Get-Command -Name $factory -ErrorAction Stop
                $scriptText = & $command
                $argument = @(Get-WinToolHelperMessageProperty -Message $Message -Name "argument")
                $sync = @{
                    Done  = $false
                    Ok    = $false
                    Error = $null
                }
                $body = [scriptblock]::Create($scriptText)
                $invokeArgs = New-Object System.Collections.Generic.List[object]
                $invokeArgs.Add($sync)
                foreach ($item in @($argument)) {
                    $invokeArgs.Add($item)
                }
                $null = & $body @($invokeArgs.ToArray())
                if (-not [bool]$sync.Ok) {
                    $reason = [string]$sync.Error
                    if ([string]::IsNullOrWhiteSpace($reason)) { $reason = Get-WinToolText "error.helperScriptFailed" }
                    throw $reason
                }
                $result = @{}
                foreach ($key in @($sync.Keys)) {
                    if ($key -in @("Done")) { continue }
                    $result[$key] = $sync[$key]
                }
                Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "ok"; result = $result }
            }
            default {
                throw (Get-WinToolText "error.helperUnknownOperation" $op)
            }
        }
    }
    catch {
        Write-WinToolHelperLine -Writer $Writer -Value @{ id = $id; type = "error"; message = $_.Exception.Message }
    }
    return "ok"
}

function Test-WinToolHelperParentAlive {
    param([int]$ParentId)
    if ($ParentId -le 0) {
        return $true
    }
    $process = Get-Process -Id $ParentId -ErrorAction SilentlyContinue
    return ($null -ne $process)
}

function Invoke-WinToolElevatedHelperHost {
    if (-not (Test-WinToolAdministrator)) {
        throw (Get-WinToolText "error.helperFailed")
    }
    $pipeName = Get-WinToolHelperPipeName
    if ([string]::IsNullOrWhiteSpace($pipeName)) {
        throw (Get-WinToolText "error.helperFailed")
    }
    $parentId = 0
    [void][int]::TryParse([string]$env:WINTOOL_HELPER_PARENT, [ref]$parentId)
    if ((Get-WinToolCurrentConsoleMode) -eq "hide") {
        Hide-WinToolConsole
    }
    $pipe = New-WinToolHelperServerPipe -Name $pipeName
    try {
        $wait = $pipe.BeginWaitForConnection($null, $null)
        while (-not $wait.IsCompleted) {
            if (-not (Test-WinToolHelperParentAlive -ParentId $parentId)) {
                return
            }
            Start-Sleep -Milliseconds 200
        }
        $pipe.EndWaitForConnection($wait)
        $reader = New-Object System.IO.StreamReader($pipe, [System.Text.Encoding]::UTF8, $false, 4096, $true)
        $writer = New-Object System.IO.StreamWriter($pipe, [System.Text.Encoding]::UTF8, 4096, $true)
        $writer.AutoFlush = $true
        try {
            while ($pipe.IsConnected) {
                if (-not (Test-WinToolHelperParentAlive -ParentId $parentId)) {
                    break
                }
                if ($pipe.IsAsync) {
                    if ($reader.Peek() -lt 0 -and $pipe.ReadTimeout) { }
                }
                $message = Read-WinToolHelperLine -Reader $reader
                if ($null -eq $message) {
                    break
                }
                $status = Invoke-WinToolHelperHostCommand -Message $message -Writer $writer
                if ($status -eq "shutdown") {
                    break
                }
            }
        }
        finally {
            try { $writer.Dispose() } catch { $null = $_.Exception.Message }
            try { $reader.Dispose() } catch { $null = $_.Exception.Message }
        }
    }
    finally {
        try { $pipe.Dispose() } catch { $null = $_.Exception.Message }
        Remove-WinToolHiddenConsole
    }
}

# In-process pipe pair for tests (same privilege, no UAC).
function Invoke-WinToolHelperRoundTrip {
    param(
        [int]$TimeoutSeconds = 30
    )
    if (-not (Test-WinToolWindows)) {
        return $null
    }
    $name = "WinTool.Hinrikao.Test." + [guid]::NewGuid().ToString("N")
    $server = New-WinToolHelperServerPipe -Name $name
    $done = [hashtable]::Synchronized(@{ Error = $null; Finished = $false })
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    $hostFn = ${function:Invoke-WinToolHelperHostCommand}
    $readFn = ${function:Read-WinToolHelperLine}
    $writeFn = ${function:Write-WinToolHelperLine}
    [void]$powershell.AddScript({
            param($Pipe, $Done, $HostCommand, $ReadLine, $WriteLine)
            $null = $WriteLine
            try {
                $Pipe.WaitForConnection()
                $reader = New-Object System.IO.StreamReader($Pipe, [System.Text.Encoding]::UTF8, $false, 4096, $true)
                $writer = New-Object System.IO.StreamWriter($Pipe, [System.Text.Encoding]::UTF8, 4096, $true)
                $writer.AutoFlush = $true
                try {
                    while ($Pipe.IsConnected) {
                        $message = & $ReadLine -Reader $reader
                        if ($null -eq $message) { break }
                        $status = & $HostCommand -Message $message -Writer $writer
                        if ($status -eq "shutdown") { break }
                    }
                }
                finally {
                    try { $writer.Dispose() } catch { $null = $_.Exception.Message }
                    try { $reader.Dispose() } catch { $null = $_.Exception.Message }
                }
            }
            catch {
                $Done.Error = $_.Exception.Message
            }
            finally {
                $Done.Finished = $true
            }
        })
    [void]$powershell.AddArgument($server)
    [void]$powershell.AddArgument($done)
    [void]$powershell.AddArgument($hostFn)
    [void]$powershell.AddArgument($readFn)
    [void]$powershell.AddArgument($writeFn)
    [void]$powershell.BeginInvoke()
    try {
        Connect-WinToolHelperClient -PipeName $name -TimeoutSeconds $TimeoutSeconds
        $ping = Send-WinToolHelperCommand -Operation "ping" -TimeoutSeconds $TimeoutSeconds
        $null = Send-WinToolHelperCommand -Operation "shutdown" -TimeoutSeconds 5
        return $ping
    }
    finally {
        Close-WinToolHelperClient
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not [bool]$done.Finished -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        try { $powershell.Stop() } catch { $null = $_.Exception.Message }
        try { $powershell.Dispose() } catch { $null = $_.Exception.Message }
        try { $runspace.Dispose() } catch { $null = $_.Exception.Message }
        try { $server.Dispose() } catch { $null = $_.Exception.Message }
    }
}
