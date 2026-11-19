# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT

function ConvertTo-WinToolJsonString {
    param(
        [AllowNull()][string]$Text
    )
    if ($null -eq $Text) {
        return "null"
    }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($char in $Text.ToCharArray()) {
        $code = [int]$char
        if ($code -eq 34) {
            [void]$builder.Append('\"')
        }
        elseif ($code -eq 92) {
            [void]$builder.Append('\\')
        }
        elseif ($code -eq 8) {
            [void]$builder.Append('\b')
        }
        elseif ($code -eq 12) {
            [void]$builder.Append('\f')
        }
        elseif ($code -eq 10) {
            [void]$builder.Append('\n')
        }
        elseif ($code -eq 13) {
            [void]$builder.Append('\r')
        }
        elseif ($code -eq 9) {
            [void]$builder.Append('\t')
        }
        elseif ($code -lt 32) {
            [void]$builder.Append('\u')
            [void]$builder.Append($code.ToString("x4"))
        }
        else {
            [void]$builder.Append($char)
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-WinToolJsonText {
    param(
        $Value,
        [int]$Indent = 0
    )
    $pad = " " * ($Indent * 2)
    $next = $Indent + 1
    $inner = " " * ($next * 2)

    if ($null -eq $Value) {
        return "null"
    }
    if ($Value -is [string]) {
        return (ConvertTo-WinToolJsonString -Text $Value)
    }
    if ($Value -is [bool]) {
        if ($Value) { return "true" }
        return "false"
    }
    if ($Value -is [ValueType]) {
        return [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $isCustom = $Value -is [System.Management.Automation.PSCustomObject]
    if (-not $isCustom -and $Value -is [System.Collections.IDictionary]) {
        $names = @($Value.Keys)
        if ($names.Count -eq 0) {
            return "{}"
        }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($name in $names) {
            $encoded = ConvertTo-WinToolJsonString -Text ([string]$name)
            $child = ConvertTo-WinToolJsonText -Value $Value[$name] -Indent $next
            $lines.Add($inner + $encoded + ": " + $child)
        }
        return "{`n" + ($lines -join ",`n") + "`n" + $pad + "}"
    }

    if (-not $isCustom -and $Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            return "[]"
        }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($item in $items) {
            $lines.Add($inner + (ConvertTo-WinToolJsonText -Value $item -Indent $next))
        }
        return "[`n" + ($lines -join ",`n") + "`n" + $pad + "]"
    }

    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -eq 0) {
        return "{}"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($property in $properties) {
        $encoded = ConvertTo-WinToolJsonString -Text ([string]$property.Name)
        $child = ConvertTo-WinToolJsonText -Value $property.Value -Indent $next
        $lines.Add($inner + $encoded + ": " + $child)
    }
    return "{`n" + ($lines -join ",`n") + "`n" + $pad + "}"
}

function ConvertTo-WinToolPlainJson {
    param(
        [AllowEmptyString()][string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    $builder = New-Object System.Text.StringBuilder
    $chars = $Text.ToCharArray()
    $inString = $false
    $escape = $false
    $index = 0
    while ($index -lt $chars.Length) {
        $char = $chars[$index]
        if ($inString) {
            [void]$builder.Append($char)
            if ($escape) {
                $escape = $false
            }
            elseif ($char -eq '\') {
                $escape = $true
            }
            elseif ($char -eq '"') {
                $inString = $false
            }
            $index++
            continue
        }
        if ($char -eq '"') {
            $inString = $true
            [void]$builder.Append($char)
            $index++
            continue
        }
        if ($char -eq '/' -and ($index + 1) -lt $chars.Length) {
            $next = $chars[$index + 1]
            if ($next -eq '/') {
                $index += 2
                while ($index -lt $chars.Length -and $chars[$index] -ne "`n") {
                    $index++
                }
                continue
            }
            if ($next -eq '*') {
                $index += 2
                while (($index + 1) -lt $chars.Length -and -not ($chars[$index] -eq '*' -and $chars[$index + 1] -eq '/')) {
                    $index++
                }
                if (($index + 1) -lt $chars.Length) {
                    $index += 2
                }
                else {
                    $index = $chars.Length
                }
                continue
            }
        }
        [void]$builder.Append($char)
        $index++
    }
    return [regex]::Replace($builder.ToString(), ',(?=\s*[}\]])', '')
}

function ConvertFrom-WinToolJsonText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $plain = ConvertTo-WinToolPlainJson -Text $Text
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw "The JSON text was empty."
    }
    return ($plain | ConvertFrom-Json)
}

function Read-WinToolJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    $text = [System.IO.File]::ReadAllText($Path)
    return (ConvertFrom-WinToolJsonText -Text $text)
}

function Write-WinToolJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )
    $json = ConvertTo-WinToolJsonText -Value $Value
    Write-WinToolUtf8File -Path $Path -Text ($json + "`n")
}
