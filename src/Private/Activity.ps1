# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

$script:WinToolHasActivity = $true

function Initialize-WinToolActivityState {
    if ($null -eq $script:WinToolState) {
        $script:WinToolState = @{}
    }
    if ($null -eq $script:WinToolState.ActivityRuns) {
        $script:WinToolState.ActivityRuns = New-Object System.Collections.Generic.List[object]
    }
    if ($null -eq $script:WinToolState["ActivityCurrent"]) {
        $script:WinToolState.ActivityCurrent = $null
    }
    if ($null -eq $script:WinToolState["ActivityFilter"]) {
        $script:WinToolState.ActivityFilter = "all"
    }
    if ($null -eq $script:WinToolState["ActivityExpanded"]) {
        $script:WinToolState.ActivityExpanded = $false
    }
    if ($null -eq $script:WinToolState["ActivityPinned"]) {
        $script:WinToolState.ActivityPinned = $false
    }
    if ($null -eq $script:WinToolState["ActivityBadge"]) {
        $script:WinToolState.ActivityBadge = 0
    }
}

function New-WinToolActivityRun {
    param(
        [Parameter(Mandatory = $true)][string]$Title
    )
    $started = [datetime]::Now
    return [pscustomobject]@{
        Id        = [guid]::NewGuid().ToString("N")
        Title     = $Title
        Started   = $started
        Ended     = $null
        Status    = "running"
        Summary   = ""
        Steps     = New-Object System.Collections.Generic.List[object]
        Completed = 0
        Warnings  = 0
        Errors    = 0
        Skipped   = 0
    }
}

function Start-WinToolActivity {
    param(
        [Parameter(Mandatory = $true)][string]$Title
    )
    Initialize-WinToolActivityState
    if ($null -ne $script:WinToolState.ActivityCurrent) {
        Complete-WinToolActivity
    }
    $run = New-WinToolActivityRun -Title $Title
    $script:WinToolState.ActivityRuns.Insert(0, $run)
    $script:WinToolState.ActivityCurrent = $run
    return $run
}

function Add-WinToolActivityStep {
    param(
        [string]$Status = "ok",
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message,
        [string]$Detail = ""
    )
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $null
    }
    Initialize-WinToolActivityState
    $run = $script:WinToolState.ActivityCurrent
    if ($null -eq $run) {
        return $null
    }
    $level = [string]$Status
    if ($level -eq "info") { $level = "ok" }
    if ($level -eq "fail") { $level = "error" }
    if (@("ok", "warn", "error", "skipped", "running") -notcontains $level) {
        $level = "ok"
    }
    $step = [pscustomobject]@{
        Status  = $level
        Message = $Message
        Detail  = $Detail
        Time    = [datetime]::Now
    }
    $run.Steps.Add($step) | Out-Null
    $script:WinToolState.ActivityDirty = $true
    switch ($level) {
        "ok" { $run.Completed = [int]$run.Completed + 1 }
        "warn" { $run.Warnings = [int]$run.Warnings + 1 }
        "error" { $run.Errors = [int]$run.Errors + 1 }
        "skipped" { $run.Skipped = [int]$run.Skipped + 1 }
    }
    return $step
}

function Complete-WinToolActivity {
    param(
        [string]$Summary = "",
        [string]$Status = ""
    )
    Initialize-WinToolActivityState
    $run = $script:WinToolState.ActivityCurrent
    if ($null -eq $run) {
        return $null
    }
    $run.Ended = [datetime]::Now
    if (-not [string]::IsNullOrWhiteSpace($Summary)) {
        $run.Summary = $Summary
    }
    $final = [string]$Status
    if ([string]::IsNullOrWhiteSpace($final)) {
        if ([int]$run.Errors -gt 0) { $final = "error" }
        elseif ([int]$run.Warnings -gt 0) { $final = "warn" }
        else { $final = "ok" }
    }
    if ($final -eq "fail") { $final = "error" }
    $run.Status = $final
    $script:WinToolState.ActivityCurrent = $null
    $script:WinToolState.ActivityBadge = [int]$script:WinToolState.ActivityRuns.Count
    return $run
}

function Get-WinToolActivityRun {
    Initialize-WinToolActivityState
    return @($script:WinToolState.ActivityRuns.ToArray())
}

function Format-WinToolActivityDuration {
    param($Started, $Ended)
    if ($null -eq $Started) { return "" }
    $end = $Ended
    if ($null -eq $end) { $end = [datetime]::Now }
    $span = ([datetime]$end) - ([datetime]$Started)
    if ($span.TotalSeconds -lt 0) { $span = [TimeSpan]::Zero }
    if ($span.TotalHours -ge 1) {
        return (Get-WinToolText "activity.duration.hours" ([int][math]::Floor($span.TotalHours)) $span.Minutes)
    }
    if ($span.TotalMinutes -ge 1) {
        return (Get-WinToolText "activity.duration.minutes" $span.Minutes $span.Seconds)
    }
    return (Get-WinToolText "activity.duration.seconds" ([int][math]::Round($span.TotalSeconds)))
}

function Format-WinToolActivityWhen {
    param($Started)
    if ($null -eq $Started) { return "" }
    $stamp = [datetime]$Started
    $time = $stamp.ToString("h:mm tt", [System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
    if ($stamp.Date -eq [datetime]::Now.Date) {
        return (Get-WinToolText "activity.today" $time)
    }
    $date = $stamp.ToString("d MMM yyyy", [System.Globalization.CultureInfo]::GetCultureInfo("en-US"))
    return (Get-WinToolText "activity.meta" $date $time)
}

function Format-WinToolActivityCount {
    param($Run)
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add((Get-WinToolCountText "activity.count.completed" ([int]$Run.Completed))) | Out-Null
    $parts.Add((Get-WinToolCountText "activity.count.warning" ([int]$Run.Warnings))) | Out-Null
    $parts.Add((Get-WinToolCountText "activity.count.error" ([int]$Run.Errors))) | Out-Null
    if ([int]$Run.Skipped -gt 0) {
        $parts.Add((Get-WinToolCountText "activity.count.skipped" ([int]$Run.Skipped))) | Out-Null
    }
    return ($parts.ToArray() -join ", ")
}

function Test-WinToolActivityRunVisible {
    param(
        $Run,
        [string]$Filter = "all"
    )
    if ($null -eq $Run) { return $false }
    switch ([string]$Filter) {
        "warnings" { return ([int]$Run.Warnings -gt 0 -or [int]$Run.Errors -gt 0) }
        "errors" { return ([int]$Run.Errors -gt 0) }
        default { return $true }
    }
}

function Test-WinToolActivityStepVisible {
    param(
        $Step,
        [string]$Filter = "all"
    )
    $status = [string](Get-WinToolNote -Object $Step -Name "Status" -Default "ok")
    switch ([string]$Filter) {
        "warnings" { return ($status -eq "warn" -or $status -eq "error") }
        "errors" { return ($status -eq "error") }
        default { return $true }
    }
}

function Format-WinToolActivityReport {
    param(
        $Run = @(),
        [string]$Filter = "all"
    )
    $items = @($Run)
    if ($items.Count -eq 0) {
        $items = @(Get-WinToolActivityRun)
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if (-not (Test-WinToolActivityRunVisible -Run $item -Filter $Filter)) {
            continue
        }
        if ($lines.Count -gt 0) {
            $lines.Add("") | Out-Null
        }
        $lines.Add([string]$item.Title) | Out-Null
        $when = Format-WinToolActivityWhen -Started $item.Started
        $duration = Format-WinToolActivityDuration -Started $item.Started -Ended $item.Ended
        if (-not [string]::IsNullOrWhiteSpace($when) -and -not [string]::IsNullOrWhiteSpace($duration)) {
            $lines.Add((Get-WinToolText "activity.meta" $when $duration)) | Out-Null
        }
        elseif (-not [string]::IsNullOrWhiteSpace($when)) {
            $lines.Add($when) | Out-Null
        }
        $lines.Add((Format-WinToolActivityCount -Run $item)) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace([string]$item.Summary)) {
            $lines.Add([string]$item.Summary) | Out-Null
        }
        foreach ($step in $item.Steps) {
            if (-not (Test-WinToolActivityStepVisible -Step $step -Filter $Filter)) {
                continue
            }
            $tag = "OK  "
            $status = [string]$step.Status
            if ($status -eq "warn") { $tag = "WARN" }
            elseif ($status -eq "error") { $tag = "FAIL" }
            elseif ($status -eq "skipped") { $tag = "SKIP" }
            elseif ($status -eq "running") { $tag = "RUN " }
            $line = "  " + $tag + "  " + [string]$step.Message
            if (-not [string]::IsNullOrWhiteSpace([string]$step.Detail)) {
                $line = $line + "  " + [string]$step.Detail
            }
            $lines.Add($line) | Out-Null
        }
    }
    if ($lines.Count -eq 0) {
        if ($Filter -eq "all") {
            return (Get-WinToolText "activity.empty")
        }
        return (Get-WinToolText "activity.emptyFilter")
    }
    return ($lines.ToArray() -join [Environment]::NewLine)
}
