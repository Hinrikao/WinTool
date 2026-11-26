# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
#requires -Version 5.1

<#
.SYNOPSIS
    Incrementally translate data/i18n/en.json into the shipped locale files.
.DESCRIPTION
    Uses the free CTranslate2 + NLLB-200 provider by default (no account or
    API key). Set WINTOOL_I18N_PROVIDER=azure and the AZURE_TRANSLATOR_KEY and
    AZURE_TRANSLATOR_REGION secrets to use Azure Translator instead.
#>
param(
    [string]$Locales = "pt-BR,es,fr,de,it,ja,ko,zh-Hans,zh-Hant,pl,nl,ru,tr",
    [string]$Provider = $env:WINTOOL_I18N_PROVIDER,
    [switch]$Force,
    [switch]$EnsureModelOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot "i18n/translate.py"
if (-not (Test-Path -LiteralPath $script)) {
    throw "build/i18n/translate.py is missing."
}

function Get-WinToolPython {
    $venv = $env:WINTOOL_I18N_PYTHON
    if (-not [string]::IsNullOrWhiteSpace($venv) -and (Test-Path -LiteralPath $venv)) {
        return $venv
    }
    foreach ($name in @("python3", "python")) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return [string]$cmd.Source
        }
    }
    throw "Python 3 is required to translate locales."
}

$python = Get-WinToolPython
$args = @($script)
if ($EnsureModelOnly) {
    $args += "--ensure-model"
}
else {
    $args += @("--locales", $Locales)
    if (-not [string]::IsNullOrWhiteSpace($Provider)) {
        $args += @("--provider", $Provider)
    }
    if ($Force) {
        $args += "--force"
    }
}
& $python @args
if ($LASTEXITCODE -ne 0) {
    throw "Locale translation failed with exit code $LASTEXITCODE."
}
