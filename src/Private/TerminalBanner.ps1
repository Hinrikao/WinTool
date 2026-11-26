# Copyright (c) 2026 Henrique
# SPDX-License-Identifier: MIT
# Hide or restore the startup banner in Windows Terminal, shortcuts, Git Bash,
# and WSL. settings.json is patched as JSONC so comments stay in the file.

function Skip-WinToolJsoncTrivia {
    param(
        [string]$Text,
        [int]$Index
    )
    $length = $Text.Length
    while ($Index -lt $length) {
        $char = $Text[$Index]
        if ($char -eq " " -or $char -eq "`t" -or $char -eq "`r" -or $char -eq "`n") {
            $Index++
            continue
        }
        if ($char -eq "/" -and ($Index + 1) -lt $length) {
            $next = $Text[$Index + 1]
            if ($next -eq "/") {
                $Index += 2
                while ($Index -lt $length -and $Text[$Index] -ne "`n") {
                    $Index++
                }
                continue
            }
            if ($next -eq "*") {
                $Index += 2
                while (($Index + 1) -lt $length -and -not ($Text[$Index] -eq "*" -and $Text[$Index + 1] -eq "/")) {
                    $Index++
                }
                if (($Index + 1) -lt $length) {
                    $Index += 2
                }
                else {
                    $Index = $length
                }
                continue
            }
        }
        break
    }
    return $Index
}

function Get-WinToolJsoncStringSpan {
    param(
        [string]$Text,
        [int]$Index
    )
    if ($Index -ge $Text.Length -or $Text[$Index] -ne '"') {
        return $null
    }
    $builder = New-Object System.Text.StringBuilder
    $escape = $false
    $cursor = $Index + 1
    $length = $Text.Length
    while ($cursor -lt $length) {
        $char = $Text[$cursor]
        if ($escape) {
            switch ($char) {
                "n" { [void]$builder.Append("`n") }
                "r" { [void]$builder.Append("`r") }
                "t" { [void]$builder.Append("`t") }
                default { [void]$builder.Append($char) }
            }
            $escape = $false
            $cursor++
            continue
        }
        if ($char -eq "\") {
            $escape = $true
            $cursor++
            continue
        }
        if ($char -eq '"') {
            return [pscustomobject]@{ Start = $Index; End = ($cursor + 1); Value = $builder.ToString() }
        }
        [void]$builder.Append($char)
        $cursor++
    }
    return $null
}

function Get-WinToolJsoncMatchEnd {
    param(
        [string]$Text,
        [int]$Index
    )
    if ($Index -ge $Text.Length) {
        return -1
    }
    $open = $Text[$Index]
    if ($open -ne "{" -and $open -ne "[") {
        return -1
    }
    $depth = 1
    $cursor = $Index + 1
    $length = $Text.Length
    while ($cursor -lt $length) {
        $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index $cursor
        if ($cursor -ge $length) {
            break
        }
        $char = $Text[$cursor]
        if ($char -eq '"') {
            $span = Get-WinToolJsoncStringSpan -Text $Text -Index $cursor
            if ($null -eq $span) {
                break
            }
            $cursor = [int]$span.End
            continue
        }
        if ($char -eq "{" -or $char -eq "[") {
            $depth++
            $cursor++
            continue
        }
        if ($char -eq "}" -or $char -eq "]") {
            $depth--
            $cursor++
            if ($depth -eq 0) {
                return $cursor
            }
            continue
        }
        $cursor++
    }
    return -1
}

function Get-WinToolJsoncValueSpan {
    param(
        [string]$Text,
        [int]$Index
    )
    $Index = Skip-WinToolJsoncTrivia -Text $Text -Index $Index
    if ($Index -ge $Text.Length) {
        return $null
    }
    $char = $Text[$Index]
    if ($char -eq '"') {
        $span = Get-WinToolJsoncStringSpan -Text $Text -Index $Index
        if ($null -eq $span) {
            return $null
        }
        return [pscustomobject]@{ Start = $span.Start; End = $span.End; Kind = "string"; Value = $span.Value }
    }
    if ($char -eq "{" -or $char -eq "[") {
        $end = Get-WinToolJsoncMatchEnd -Text $Text -Index $Index
        if ($end -lt 0) {
            return $null
        }
        $kind = "object"
        if ($char -eq "[") {
            $kind = "array"
        }
        return [pscustomobject]@{ Start = $Index; End = $end; Kind = $kind; Value = $null }
    }
    $cursor = $Index
    while ($cursor -lt $Text.Length) {
        $char = $Text[$cursor]
        if ($char -eq "," -or $char -eq "}" -or $char -eq "]" -or $char -eq " " -or $char -eq "`t" -or $char -eq "`r" -or $char -eq "`n" -or $char -eq "/") {
            break
        }
        $cursor++
    }
    return [pscustomobject]@{ Start = $Index; End = $cursor; Kind = "primitive"; Value = $Text.Substring($Index, $cursor - $Index) }
}

function Get-WinToolJsoncObjectMap {
    param(
        [string]$Text,
        [int]$Start
    )
    if ($Start -ge $Text.Length -or $Text[$Start] -ne "{") {
        return $null
    }
    $end = Get-WinToolJsoncMatchEnd -Text $Text -Index $Start
    if ($end -lt 0) {
        return $null
    }
    $properties = New-Object System.Collections.Generic.List[object]
    $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ($Start + 1)
    while ($cursor -lt ($end - 1)) {
        if ($Text[$cursor] -eq "}") {
            break
        }
        if ($Text[$cursor] -ne '"') {
            break
        }
        $name = Get-WinToolJsoncStringSpan -Text $Text -Index $cursor
        if ($null -eq $name) {
            break
        }
        $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ([int]$name.End)
        if ($cursor -ge $Text.Length -or $Text[$cursor] -ne ":") {
            break
        }
        $value = Get-WinToolJsoncValueSpan -Text $Text -Index ($cursor + 1)
        if ($null -eq $value) {
            break
        }
        $properties.Add([pscustomobject]@{
            Name       = [string]$name.Value
            NameStart  = [int]$name.Start
            ValueStart = [int]$value.Start
            ValueEnd   = [int]$value.End
            Kind       = [string]$value.Kind
            Value      = $value.Value
        }) | Out-Null
        $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ([int]$value.End)
        if ($cursor -lt $Text.Length -and $Text[$cursor] -eq ",") {
            $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ($cursor + 1)
        }
    }
    return [pscustomobject]@{ Start = $Start; End = $end; Property = $properties.ToArray() }
}

function Get-WinToolJsoncObjectList {
    param(
        [string]$Text
    )
    $list = New-Object System.Collections.Generic.List[object]
    $cursor = 0
    $length = $Text.Length
    while ($cursor -lt $length) {
        $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index $cursor
        if ($cursor -ge $length) {
            break
        }
        $char = $Text[$cursor]
        if ($char -eq '"') {
            $span = Get-WinToolJsoncStringSpan -Text $Text -Index $cursor
            if ($null -eq $span) {
                break
            }
            $cursor = [int]$span.End
            continue
        }
        if ($char -eq "{") {
            $object = Get-WinToolJsoncObjectMap -Text $Text -Start $cursor
            if ($null -ne $object) {
                $list.Add($object) | Out-Null
            }
            $cursor++
            continue
        }
        $cursor++
    }
    return $list.ToArray()
}

function Get-WinToolJsoncProperty {
    param(
        $Object,
        [string]$Name
    )
    if ($null -eq $Object) {
        return $null
    }
    foreach ($property in @($Object.Property)) {
        if ([string]$property.Name -eq $Name) {
            return $property
        }
    }
    return $null
}

function Get-WinToolJsoncObjectIndent {
    param(
        [string]$Text,
        $Object
    )
    $start = [int]$Object.Start
    $lineStart = $start
    while ($lineStart -gt 0 -and $Text[$lineStart - 1] -ne "`n") {
        $lineStart--
    }
    $pad = ""
    $cursor = $lineStart
    while ($cursor -lt $start -and ($Text[$cursor] -eq " " -or $Text[$cursor] -eq "`t")) {
        $pad += $Text[$cursor]
        $cursor++
    }
    $properties = @($Object.Property)
    if ($properties.Count -gt 0) {
        $nameStart = [int]$properties[0].NameStart
        $propLine = $nameStart
        while ($propLine -gt 0 -and $Text[$propLine - 1] -ne "`n") {
            $propLine--
        }
        $sameLine = $true
        $probe = $start + 1
        while ($probe -lt $nameStart) {
            if ($Text[$probe] -eq "`n") {
                $sameLine = $false
                break
            }
            $probe++
        }
        if (-not $sameLine) {
            $inner = ""
            $cursor = $propLine
            while ($cursor -lt $nameStart -and ($Text[$cursor] -eq " " -or $Text[$cursor] -eq "`t")) {
                $inner += $Text[$cursor]
                $cursor++
            }
            if (-not [string]::IsNullOrEmpty($inner)) {
                return $inner
            }
        }
    }
    return $pad + "  "
}

function Test-WinToolJsoncObjectIsCompact {
    param(
        [string]$Text,
        $Object
    )
    $properties = @($Object.Property)
    if ($properties.Count -eq 0) {
        return $true
    }
    $probe = [int]$Object.Start + 1
    $nameStart = [int]$properties[0].NameStart
    while ($probe -lt $nameStart) {
        if ($Text[$probe] -eq "`n") {
            return $false
        }
        $probe++
    }
    return $true
}

function Set-WinToolJsoncObjectString {
    param(
        [string]$Text,
        $Object,
        [string]$Name,
        [string]$Value
    )
    $encoded = ConvertTo-WinToolJsonString -Text $Value
    $property = Get-WinToolJsoncProperty -Object $Object -Name $Name
    if ($null -ne $property) {
        return $Text.Substring(0, [int]$property.ValueStart) + $encoded + $Text.Substring([int]$property.ValueEnd)
    }
    $afterOpen = [int]$Object.Start + 1
    $next = Skip-WinToolJsoncTrivia -Text $Text -Index $afterOpen
    $hasSibling = ($next -lt [int]$Object.End -and $Text[$next] -ne "}")
    if (Test-WinToolJsoncObjectIsCompact -Text $Text -Object $Object) {
        $insert = " " + (ConvertTo-WinToolJsonString -Text $Name) + ": " + $encoded
        if ($hasSibling) {
            $insert += ","
            if ($afterOpen -lt $Text.Length -and $Text[$afterOpen] -ne " " -and $Text[$afterOpen] -ne "`n" -and $Text[$afterOpen] -ne "`r") {
                $insert += " "
            }
        }
        return $Text.Substring(0, $afterOpen) + $insert + $Text.Substring($afterOpen)
    }
    $indent = Get-WinToolJsoncObjectIndent -Text $Text -Object $Object
    $insert = "`n" + $indent + (ConvertTo-WinToolJsonString -Text $Name) + ": " + $encoded
    if ($hasSibling) {
        $insert += ","
    }
    return $Text.Substring(0, $afterOpen) + $insert + $Text.Substring($afterOpen)
}

function Get-WinToolJsoncLiteralText {
    param(
        $Value,
        [string]$Kind = "string"
    )
    if ($Kind -eq "string") {
        return (ConvertTo-WinToolJsonString -Text ([string]$Value))
    }
    if ($Kind -eq "number") {
        if ($null -eq $Value) {
            return "0"
        }
        return ([string]$Value)
    }
    if ($Kind -eq "boolean") {
        if ($Value) { return "true" }
        return "false"
    }
    if ($Kind -eq "object") {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return "{}" }
        return [string]$Value
    }
    if ($Kind -eq "array") {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return "[]" }
        return [string]$Value
    }
    return [string]$Value
}

function Set-WinToolJsoncObjectLiteral {
    param(
        [string]$Text,
        $Object,
        [string]$Name,
        [string]$Literal
    )
    $property = Get-WinToolJsoncProperty -Object $Object -Name $Name
    if ($null -ne $property) {
        return $Text.Substring(0, [int]$property.ValueStart) + $Literal + $Text.Substring([int]$property.ValueEnd)
    }
    $afterOpen = [int]$Object.Start + 1
    $next = Skip-WinToolJsoncTrivia -Text $Text -Index $afterOpen
    $hasSibling = ($next -lt [int]$Object.End -and $Text[$next] -ne "}")
    if (Test-WinToolJsoncObjectIsCompact -Text $Text -Object $Object) {
        $insert = " " + (ConvertTo-WinToolJsonString -Text $Name) + ": " + $Literal
        if ($hasSibling) {
            $insert += ","
            if ($afterOpen -lt $Text.Length -and $Text[$afterOpen] -ne " " -and $Text[$afterOpen] -ne "`n" -and $Text[$afterOpen] -ne "`r") {
                $insert += " "
            }
        }
        return $Text.Substring(0, $afterOpen) + $insert + $Text.Substring($afterOpen)
    }
    $indent = Get-WinToolJsoncObjectIndent -Text $Text -Object $Object
    $insert = "`n" + $indent + (ConvertTo-WinToolJsonString -Text $Name) + ": " + $Literal
    if ($hasSibling) {
        $insert += ","
    }
    return $Text.Substring(0, $afterOpen) + $insert + $Text.Substring($afterOpen)
}

function Get-WinToolJsoncRootStart {
    param(
        [Parameter(Mandatory = $true)][string]$Text
    )
    $span = Get-WinToolJsoncValueSpan -Text $Text -Start 0
    if ($null -eq $span -or [string]$span.Kind -ne "object") {
        return $null
    }
    return [int]$span.Start
}

function Set-WinToolJsoncPath {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$Name,
        $Value,
        [string]$Kind = "string"
    )
    $names = @($Name)
    if ($names.Count -lt 1) {
        throw "A settings path needs at least one name."
    }
    $literal = Get-WinToolJsoncLiteralText -Value $Value -Kind $Kind
    $guard = 0
    while ($guard -lt 20) {
        $guard++
        $root = Get-WinToolJsoncRootStart -Text $Text
        if ($null -eq $root) {
            throw "The settings file has no JSON object at the root."
        }
        $start = [int]$root
        $created = $false
        for ($index = 0; $index -lt ($names.Count - 1); $index++) {
            $map = Get-WinToolJsoncObjectMap -Text $Text -Start $start
            if ($null -eq $map) {
                throw "The settings file is not a valid JSON object."
            }
            $property = Get-WinToolJsoncProperty -Object $map -Name $names[$index]
            if ($null -eq $property) {
                $Text = Set-WinToolJsoncObjectLiteral -Text $Text -Object $map -Name $names[$index] -Literal "{}"
                $created = $true
                break
            }
            if ([string]$property.Kind -ne "object") {
                throw ("The settings property '{0}' is not an object." -f $names[$index])
            }
            $start = [int]$property.ValueStart
        }
        if ($created) {
            continue
        }
        $map = Get-WinToolJsoncObjectMap -Text $Text -Start $start
        $existing = Get-WinToolJsoncProperty -Object $map -Name $names[$names.Count - 1]
        if ($null -ne $existing) {
            $current = $Text.Substring([int]$existing.ValueStart, ([int]$existing.ValueEnd - [int]$existing.ValueStart))
            if ($current.Trim() -eq $literal) {
                return [pscustomobject]@{ Text = $Text; Changed = $false }
            }
        }
        $Text = Set-WinToolJsoncObjectLiteral -Text $Text -Object $map -Name $names[$names.Count - 1] -Literal $literal
        return [pscustomobject]@{ Text = $Text; Changed = $true }
    }
    throw "Could not write the settings path."
}

function Get-WinToolJsoncArrayItem {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Start
    )
    $items = New-Object System.Collections.Generic.List[object]
    if ($Start -ge $Text.Length -or $Text[$Start] -ne "[") {
        return $items.ToArray()
    }
    $end = Get-WinToolJsoncMatchEnd -Text $Text -Index $Start
    if ($end -lt 0) {
        return $items.ToArray()
    }
    $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ($Start + 1)
    while ($cursor -lt ($end - 1)) {
        if ($Text[$cursor] -eq "]") {
            break
        }
        $value = Get-WinToolJsoncValueSpan -Text $Text -Index $cursor
        if ($null -eq $value) {
            break
        }
        $items.Add($value) | Out-Null
        $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ([int]$value.End)
        if ($cursor -lt $Text.Length -and $Text[$cursor] -eq ",") {
            $cursor = Skip-WinToolJsoncTrivia -Text $Text -Index ($cursor + 1)
        }
    }
    return $items.ToArray()
}

function Add-WinToolJsoncArrayItem {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Start,
        [Parameter(Mandatory = $true)][string]$Item
    )
    if ($Start -ge $Text.Length -or $Text[$Start] -ne "[") {
        throw "The settings path is not a JSON array."
    }
    $end = Get-WinToolJsoncMatchEnd -Text $Text -Index $Start
    if ($end -lt 0) {
        throw "The JSON array is not closed."
    }
    $close = $end - 1
    $items = @(Get-WinToolJsoncArrayItem -Text $Text -Start $Start)
    $closeLine = $Text.LastIndexOf("`n", $close)
    $closeIndent = ""
    if ($closeLine -ge 0) {
        $pad = $closeLine + 1
        while ($pad -lt $close -and ($Text[$pad] -eq " " -or $Text[$pad] -eq "`t")) {
            $closeIndent += $Text[$pad]
            $pad++
        }
    }
    $itemIndent = $closeIndent + "    "
    if ($items.Count -gt 0) {
        $first = $items[0]
        $line = $Text.LastIndexOf("`n", [int]$first.Start)
        if ($line -ge 0 -and $line -lt [int]$first.Start) {
            $itemIndent = $Text.Substring($line + 1, ([int]$first.Start - ($line + 1)))
        }
        $last = $items[$items.Count - 1]
        $insert = "," + "`n" + $itemIndent + $Item
        return $Text.Substring(0, [int]$last.End) + $insert + $Text.Substring([int]$last.End)
    }
    $trim = $close
    while ($trim -gt $Start -and ($Text[$trim - 1] -eq " " -or $Text[$trim - 1] -eq "`t")) {
        $trim--
    }
    $insert = $itemIndent + $Item + "`n" + $closeIndent
    if ($trim -eq $Start + 1) {
        $insert = "`n" + $insert
    }
    return $Text.Substring(0, $trim) + $insert + $Text.Substring($close)
}

function ConvertTo-WinToolJsoncCompactObject {
    param(
        [Parameter(Mandatory = $true)]$Field
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Field.Keys) {
        $parts.Add((ConvertTo-WinToolJsonString -Text ([string]$key)) + ": " + (ConvertTo-WinToolJsonString -Text ([string]$Field[$key]))) | Out-Null
    }
    return ("{ " + ($parts.ToArray() -join ", ") + " }")
}

function Get-WinToolJsoncSchemeEntry {

    param(
        [Parameter(Mandatory = $true)]$Scheme
    )
    $fields = [ordered]@{
        name = [string]$Scheme.name
        background = [string]$Scheme.background
        foreground = [string]$Scheme.foreground
        cursorColor = [string](Get-WinToolNote -Object $Scheme -Name "cursor" -Default (Get-WinToolNote -Object $Scheme -Name "cursorColor" -Default ""))
        selectionBackground = [string](Get-WinToolNote -Object $Scheme -Name "selection" -Default (Get-WinToolNote -Object $Scheme -Name "selectionBackground" -Default ""))
    }
    $palette = Get-WinToolNote -Object $Scheme -Name "palette"
    foreach ($key in $script:WinToolSchemeColorKeys) {
        $fromScheme = [string](Get-WinToolNote -Object $Scheme -Name $key -Default "")
        $value = $fromScheme
        if ([string]::IsNullOrWhiteSpace($value) -and $null -ne $palette) {
            $value = [string](Get-WinToolNote -Object $palette -Name $key -Default "")
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw ("The color scheme " + [string]$Scheme.name + " has no " + $key + " color.")
        }
        $fields[$key] = $value
    }
    return $fields
}

function Set-WinToolJsoncColorScheme {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)]$Scheme
    )
    $fields = Get-WinToolJsoncSchemeEntry -Scheme $Scheme
    $changed = $false
    $original = $Text
    $root = Get-WinToolJsoncRootStart -Text $Text
    if ($null -eq $root) {
        throw "The settings file has no JSON object at the root."
    }
    $map = Get-WinToolJsoncObjectMap -Text $Text -Start ([int]$root)
    $schemes = Get-WinToolJsoncProperty -Object $map -Name "schemes"
    $itemText = ConvertTo-WinToolJsoncCompactObject -Field $fields
    if ($null -eq $schemes) {
        $Text = Set-WinToolJsoncObjectLiteral -Text $Text -Object $map -Name "schemes" -Literal ("[ " + $itemText + " ]")
        $changed = $true
    }
    else {
        if ([string]$schemes.Kind -ne "array") {
            throw "The settings property 'schemes' is not an array."
        }
        $items = @(Get-WinToolJsoncArrayItem -Text $Text -Start ([int]$schemes.ValueStart))
        $found = $null
        foreach ($item in $items) {
            if ([string]$item.Kind -ne "object") { continue }
            $object = Get-WinToolJsoncObjectMap -Text $Text -Start ([int]$item.Start)
            $nameProperty = Get-WinToolJsoncProperty -Object $object -Name "name"
            if ($null -eq $nameProperty) { continue }
            $nameText = $Text.Substring([int]$nameProperty.ValueStart, ([int]$nameProperty.ValueEnd - [int]$nameProperty.ValueStart)).Trim()
            if ($nameText -eq (ConvertTo-WinToolJsonString -Text ([string]$fields.name))) {
                $found = $object
                break
            }
        }
        if ($null -eq $found) {
            $Text = Add-WinToolJsoncArrayItem -Text $Text -Start ([int]$schemes.ValueStart) -Item $itemText
            $changed = $true
        }
        else {
            foreach ($key in $fields.Keys) {
                $wanted = Get-WinToolJsoncLiteralText -Value $fields[$key] -Kind "string"
                $property = Get-WinToolJsoncProperty -Object $found -Name $key
                if ($null -ne $property) {
                    $current = $Text.Substring([int]$property.ValueStart, ([int]$property.ValueEnd - [int]$property.ValueStart))
                    if ($current.Trim() -eq $wanted) {
                        continue
                    }
                }
                $Text = Set-WinToolJsoncObjectLiteral -Text $Text -Object $found -Name $key -Literal $wanted
                $changed = $true
                $root = Get-WinToolJsoncRootStart -Text $Text
                $map = Get-WinToolJsoncObjectMap -Text $Text -Start ([int]$root)
                $schemes = Get-WinToolJsoncProperty -Object $map -Name "schemes"
                $items = @(Get-WinToolJsoncArrayItem -Text $Text -Start ([int]$schemes.ValueStart))
                $found = $null
                foreach ($item in $items) {
                    if ([string]$item.Kind -ne "object") { continue }
                    $object = Get-WinToolJsoncObjectMap -Text $Text -Start ([int]$item.Start)
                    $nameProperty = Get-WinToolJsoncProperty -Object $object -Name "name"
                    if ($null -eq $nameProperty) { continue }
                    $nameText = $Text.Substring([int]$nameProperty.ValueStart, ([int]$nameProperty.ValueEnd - [int]$nameProperty.ValueStart)).Trim()
                    if ($nameText -eq (ConvertTo-WinToolJsonString -Text ([string]$fields.name))) {
                        $found = $object
                        break
                    }
                }
                if ($null -eq $found) {
                    throw "The color scheme disappeared while it was being updated."
                }
            }
        }
    }
    $result = Set-WinToolJsoncPath -Text $Text -Name @("profiles", "defaults", "colorScheme") -Value ([string]$fields.name) -Kind "string"
    if ([bool]$result.Changed) {
        $changed = $true
    }
    $next = [string]$result.Text
    if ($next -eq $original) {
        $changed = $false
    }
    return [pscustomobject]@{ Text = $next; Changed = $changed }
}

function Remove-WinToolJsoncObjectProperty {
    param(
        [string]$Text,
        $Object,
        [string]$Name
    )
    $property = Get-WinToolJsoncProperty -Object $Object -Name $Name
    if ($null -eq $property) {
        return $Text
    }
    $start = [int]$property.NameStart
    $end = [int]$property.ValueEnd
    $before = $start
    while ($before -gt [int]$Object.Start -and ($Text[$before - 1] -eq " " -or $Text[$before - 1] -eq "`t")) {
        $before--
    }
    if ($before -gt [int]$Object.Start -and ($Text[$before - 1] -eq "`n" -or $Text[$before - 1] -eq "`r")) {
        if ($Text[$before - 1] -eq "`n" -and $before -gt ([int]$Object.Start + 1) -and $Text[$before - 2] -eq "`r") {
            $before -= 2
        }
        else {
            $before--
        }
    }
    $after = Skip-WinToolJsoncTrivia -Text $Text -Index $end
    if ($after -lt [int]$Object.End -and $Text[$after] -eq ",") {
        $end = $after + 1
        $start = [int]$property.NameStart
        $before = $start
        while ($before -gt [int]$Object.Start -and ($Text[$before - 1] -eq " " -or $Text[$before - 1] -eq "`t")) {
            $before--
        }
        if ($before -gt [int]$Object.Start -and ($Text[$before - 1] -eq "`n" -or $Text[$before - 1] -eq "`r")) {
            if ($Text[$before - 1] -eq "`n" -and $before -gt ([int]$Object.Start + 1) -and $Text[$before - 2] -eq "`r") {
                $before -= 2
            }
            else {
                $before--
            }
        }
        return $Text.Substring(0, $before) + $Text.Substring($end)
    }
    $comma = $start
    while ($comma -gt [int]$Object.Start -and $Text[$comma - 1] -ne ",") {
        $comma--
    }
    if ($comma -gt [int]$Object.Start -and $Text[$comma - 1] -eq ",") {
        $before = $comma - 1
        while ($before -gt [int]$Object.Start -and ($Text[$before - 1] -eq " " -or $Text[$before - 1] -eq "`t")) {
            $before--
        }
        return $Text.Substring(0, $before) + $Text.Substring($end)
    }
    return $Text.Substring(0, $before) + $Text.Substring($end)
}

function Add-WinToolJsoncListItem {
    param(
        [string]$Text,
        [string]$Source,
        [string]$Commandline
    )
    $objects = @(Get-WinToolJsoncObjectList -Text $Text)
    $arrayStart = -1
    $arrayEnd = -1
    foreach ($object in $objects) {
        $list = Get-WinToolJsoncProperty -Object $object -Name "list"
        if ($null -ne $list -and [string]$list.Kind -eq "array") {
            $arrayStart = [int]$list.ValueStart
            $arrayEnd = [int]$list.ValueEnd
            break
        }
        $profiles = Get-WinToolJsoncProperty -Object $object -Name "profiles"
        if ($null -ne $profiles -and [string]$profiles.Kind -eq "array") {
            $arrayStart = [int]$profiles.ValueStart
            $arrayEnd = [int]$profiles.ValueEnd
            break
        }
    }
    if ($arrayStart -lt 0) {
        return $Text
    }
    $close = $arrayEnd - 1
    $innerStart = Skip-WinToolJsoncTrivia -Text $Text -Index ($arrayStart + 1)
    $empty = ($innerStart -ge $close)
    $indent = "      "
    $item = "{ " + (ConvertTo-WinToolJsonString -Text "source") + ": " + (ConvertTo-WinToolJsonString -Text $Source) + ", " + (ConvertTo-WinToolJsonString -Text "commandline") + ": " + (ConvertTo-WinToolJsonString -Text $Commandline) + " }"
    if ($empty) {
        return $Text.Substring(0, $arrayStart + 1) + "`n" + $indent + $item + "`n    " + $Text.Substring($close)
    }
    $probe = $close
    while ($probe -gt $arrayStart -and ($Text[$probe - 1] -eq " " -or $Text[$probe - 1] -eq "`t" -or $Text[$probe - 1] -eq "`r" -or $Text[$probe - 1] -eq "`n")) {
        $probe--
    }
    $comma = ""
    if ($probe -gt $arrayStart -and $Text[$probe - 1] -ne ",") {
        $comma = ","
    }
    $insert = $comma + "`n" + $indent + $item
    return $Text.Substring(0, $probe) + $insert + $Text.Substring($probe)
}

function Test-WinToolCommandToken {
    param(
        [string]$Commandline,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Commandline) -or [string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }
    $pattern = '(?i)(?<=^|\s|")' + [regex]::Escape($Token) + '(?=\s|"|$)'
    return [regex]::IsMatch($Commandline, $pattern)
}

function Add-WinToolCommandToken {
    param(
        [string]$Commandline,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $Commandline
    }
    if (Test-WinToolCommandToken -Commandline $Commandline -Token $Token) {
        return $Commandline
    }
    $trimmed = ""
    if (-not [string]::IsNullOrWhiteSpace($Commandline)) {
        $trimmed = $Commandline.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $Token
    }
    if ($trimmed.StartsWith("-") -or $trimmed.StartsWith("/")) {
        return $Token + " " + $trimmed
    }
    if ($trimmed.StartsWith('"')) {
        $close = $trimmed.IndexOf('"', 1)
        if ($close -gt 0) {
            return ($trimmed.Substring(0, $close + 1) + " " + $Token + $trimmed.Substring($close + 1))
        }
    }
    $space = $trimmed.IndexOf(" ")
    if ($space -lt 0) {
        return $trimmed + " " + $Token
    }
    return $trimmed.Substring(0, $space) + " " + $Token + $trimmed.Substring($space)
}

function Remove-WinToolCommandToken {
    param(
        [string]$Commandline,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Commandline) -or -not (Test-WinToolCommandToken -Commandline $Commandline -Token $Token)) {
        return $Commandline
    }
    $updated = [regex]::Replace($Commandline, '(?i)(?<=^|\s|")' + [regex]::Escape($Token) + '(?=\s|"|$)', "")
    return [regex]::Replace($updated.Trim(), " {2,}", " ")
}

function Add-WinToolCmdClearCommand {
    param(
        [string]$Commandline
    )
    $line = $Commandline
    if ([string]::IsNullOrWhiteSpace($line)) {
        $line = "cmd.exe"
    }
    if ($line -match '(?i)/k(\s+"|\s+)cls(\s|&|"|$)') {
        return $line
    }
    if ($line -match '(?i)/(c)(\s|$)') {
        return $line
    }
    if ($line -match '(?i)/k\s*$') {
        return $line.TrimEnd() + " cls"
    }
    if ($line -match '(?i)/k\s+') {
        return [regex]::Replace($line, '(?i)/k\s+', "/k cls & ", 1)
    }
    return $line.TrimEnd() + " /k cls"
}

function Remove-WinToolCmdClearCommand {
    param(
        [string]$Commandline,
        [string]$Previous
    )
    if ($null -ne $Previous) {
        return $Previous
    }
    $line = $Commandline
    if ($line -match '(?i)^(.+?)\s+/k\s+cls$') {
        return $Matches[1]
    }
    if ($line -match '(?i)/k\s+cls\s*&\s*') {
        return [regex]::Replace($line, '(?i)/k\s+cls\s*&\s*', "/k ", 1)
    }
    return $line
}

function Add-WinToolVsDevNoLogo {
    param(
        [string]$Commandline
    )
    if (Test-WinToolCommandToken -Commandline $Commandline -Token "-no_logo") {
        return $Commandline
    }
    if ([string]::IsNullOrWhiteSpace($Commandline)) {
        return $Commandline
    }
    if ($Commandline -match '(?i)VsDevCmd\.bat') {
        return [regex]::Replace($Commandline, '(?i)(VsDevCmd\.bat)', { param($match) $match.Groups[1].Value + " -no_logo" }, 1)
    }
    return $Commandline.TrimEnd() + " -no_logo"
}

function Remove-WinToolVsDevNoLogo {
    param(
        [string]$Commandline,
        [string]$Previous
    )
    if ($null -ne $Previous) {
        return $Previous
    }
    return [regex]::Replace($Commandline, '(?i)\s+-no_logo(?=\s|"|$)', "", 1).Trim()
}

function Test-WinToolHideStartupBanner {
    param(
        $Selection
    )
    $flag = Get-WinToolNote -Object $Selection -Name "hideStartupBanner"
    if ($null -eq $flag) {
        return $true
    }
    return [bool]$flag
}

function Get-WinToolTerminalBannerKind {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Commandline
    )
    $sourceText = [string]$Source
    $line = [string]$Commandline
    $label = [string]$Name
    if ($sourceText -match '(?i)Azure' -or $label -match '(?i)Azure Cloud Shell' -or $line -match '(?i)Azure') {
        return "azure"
    }
    if ($line -match '(?i)powershell_ise\.exe') {
        return "other"
    }
    $vsDev = ($line -match '(?i)VsDevCmd\.bat' -or $line -match '(?i)Enter-VsDevShell' -or $line -match '(?i)Launch-VsDevShell' -or $label -match '(?i)Developer (PowerShell|Command Prompt)')
    $isPwsh = ($line -match '(?i)(^|[\\/ "])pwsh(\.exe)?(\s|"|$)' -or $sourceText -match '(?i)PowershellCore')
    $isPowershell = ($line -match '(?i)(^|[\\/ "])powershell(\.exe)?(\s|"|$)' -or $sourceText -match '(?i)WindowsPowerShell' -or $label -match '(?i)^Windows PowerShell$')
    if ($vsDev -and ($isPwsh -or $isPowershell -or $label -match '(?i)Developer PowerShell')) {
        return "vsdev-ps"
    }
    if ($vsDev) {
        return "vsdev-cmd"
    }
    if ($isPwsh) {
        return "pwsh"
    }
    if ($isPowershell) {
        return "powershell"
    }
    if ($line -match '(?i)(^|[\\/ "])cmd(\.exe)?(\s|"|$)' -or $label -match '(?i)^Command Prompt$') {
        return "cmd"
    }
    if ($line -match '(?i)(git-bash|bash)\.exe' -or $label -match '(?i)Git Bash' -or $sourceText -match '(?i)GitBash') {
        return "gitbash"
    }
    if ($sourceText -match '(?i)\.Wsl$' -or $sourceText -match '(?i)Windows\.Terminal\.Wsl' -or $line -match '(?i)(^|[\\/ "])wsl(\.exe)?(\s|"|$)') {
        return "wsl"
    }
    return "other"
}

function Get-WinToolDefaultBannerCommandline {
    param(
        [string]$Kind,
        [string]$Commandline,
        [string]$Source
    )
    if (-not [string]::IsNullOrWhiteSpace($Commandline)) {
        return $Commandline
    }
    if ($Kind -eq "pwsh" -or $Source -match '(?i)PowershellCore') {
        return "pwsh.exe"
    }
    if ($Kind -eq "powershell" -or $Source -match '(?i)WindowsPowerShell') {
        return "powershell.exe"
    }
    if ($Kind -eq "cmd") {
        return "cmd.exe"
    }
    return $Commandline
}

function Get-WinToolBannerCommandline {
    param(
        [string]$Kind,
        [string]$Commandline,
        [string]$Source
    )
    $line = Get-WinToolDefaultBannerCommandline -Kind $Kind -Commandline $Commandline -Source $Source
    switch ($Kind) {
        "powershell" { return (Add-WinToolCommandToken -Commandline $line -Token "-NoLogo") }
        "pwsh" { return (Add-WinToolCommandToken -Commandline $line -Token "-NoLogo") }
        "vsdev-ps" {
            $updated = Add-WinToolCommandToken -Commandline $line -Token "-NoLogo"
            if ($updated -match '(?i)VsDevCmd\.bat') {
                $updated = Add-WinToolVsDevNoLogo -Commandline $updated
            }
            return $updated
        }
        "cmd" { return (Add-WinToolCmdClearCommand -Commandline $line) }
        "vsdev-cmd" { return (Add-WinToolVsDevNoLogo -Commandline $line) }
        default { return $Commandline }
    }
}

function Restore-WinToolBannerCommandline {
    param(
        [string]$Kind,
        [string]$Commandline,
        [string]$Previous
    )
    if ($null -ne $Previous) {
        return $Previous
    }
    switch ($Kind) {
        "powershell" { return (Remove-WinToolCommandToken -Commandline $Commandline -Token "-NoLogo") }
        "pwsh" { return (Remove-WinToolCommandToken -Commandline $Commandline -Token "-NoLogo") }
        "vsdev-ps" {
            $updated = Remove-WinToolCommandToken -Commandline $Commandline -Token "-NoLogo"
            return (Remove-WinToolVsDevNoLogo -Commandline $updated -Previous $null)
        }
        "cmd" { return (Remove-WinToolCmdClearCommand -Commandline $Commandline -Previous $null) }
        "vsdev-cmd" { return (Remove-WinToolVsDevNoLogo -Commandline $Commandline -Previous $null) }
        default { return $Commandline }
    }
}

function Get-WinToolJsoncProfileMatch {
    param(
        $Object,
        [string]$Guid,
        [string]$Source,
        [string]$Name,
        [string]$Commandline
    )
    $guidValue = Get-WinToolJsoncProperty -Object $Object -Name "guid"
    $sourceValue = Get-WinToolJsoncProperty -Object $Object -Name "source"
    $nameValue = Get-WinToolJsoncProperty -Object $Object -Name "name"
    $commandValue = Get-WinToolJsoncProperty -Object $Object -Name "commandline"
    if ($null -eq $guidValue -and $null -eq $sourceValue -and $null -eq $nameValue -and $null -eq $commandValue) {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($Guid) -and $null -ne $guidValue -and [string]$guidValue.Value -eq $Guid) {
        return $true
    }
    $sourceOk = $true
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $sourceOk = ($null -ne $sourceValue -and [string]$sourceValue.Value -eq $Source)
    }
    $nameOk = $true
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $nameOk = ($null -ne $nameValue -and [string]$nameValue.Value -eq $Name)
    }
    if ($sourceOk -and $nameOk -and (-not [string]::IsNullOrWhiteSpace($Source) -or -not [string]::IsNullOrWhiteSpace($Name))) {
        if (-not [string]::IsNullOrWhiteSpace($Commandline) -and $null -ne $commandValue -and [string]$commandValue.Value -ne $Commandline) {
            if ([string]::IsNullOrWhiteSpace($Guid) -and [string]::IsNullOrWhiteSpace($Source)) {
                return $false
            }
        }
        return $true
    }
    return $false
}

function Update-WinToolTerminalBannerText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [switch]$Undo,
        $Change
    )
    $log = New-Object System.Collections.Generic.List[string]
    $changes = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Change) {
        foreach ($item in @($Change)) {
            $changes.Add($item) | Out-Null
        }
    }
    $objects = @(Get-WinToolJsoncObjectList -Text $Text)
    $updated = $Text
    $kindsSeen = @{}
    if ($Undo) {
        $working = $updated
        foreach ($item in $changes) {
            if ([string]$item.Action -eq "add-source") {
                $objects = @(Get-WinToolJsoncObjectList -Text $working)
                foreach ($object in $objects) {
                    $sourceValue = Get-WinToolJsoncProperty -Object $object -Name "source"
                    $commandValue = Get-WinToolJsoncProperty -Object $object -Name "commandline"
                    if ($null -ne $sourceValue -and [string]$sourceValue.Value -eq [string]$item.Source -and $null -ne $commandValue -and [string]$commandValue.Value -eq [string]$item.Current) {
                        $start = [int]$object.Start
                        $end = [int]$object.End
                        $before = $start
                        while ($before -gt 0 -and ($working[$before - 1] -eq " " -or $working[$before - 1] -eq "`t")) {
                            $before--
                        }
                        if ($before -gt 0 -and $working[$before - 1] -eq ",") {
                            $before--
                        }
                        elseif ($end -lt $working.Length) {
                            $after = Skip-WinToolJsoncTrivia -Text $working -Index $end
                            if ($after -lt $working.Length -and $working[$after] -eq ",") {
                                $end = $after + 1
                            }
                        }
                        $working = $working.Substring(0, $before) + $working.Substring($end)
                        $log.Add("Removed the added " + [string]$item.Source + " profile override.")
                        break
                    }
                }
                continue
            }
            $objects = @(Get-WinToolJsoncObjectList -Text $working)
            foreach ($object in $objects) {
                if (Get-WinToolJsoncProfileMatch -Object $object -Guid ([string]$item.Guid) -Source ([string]$item.Source) -Name ([string]$item.Name) -Commandline ([string]$item.Current)) {
                    if ([bool]$item.AddedCommandline) {
                        $working = Remove-WinToolJsoncObjectProperty -Text $working -Object $object -Name "commandline"
                    }
                    else {
                        $working = Set-WinToolJsoncObjectString -Text $working -Object $object -Name "commandline" -Value ([string]$item.Previous)
                    }
                    $log.Add("Restored the command line for " + $(if ([string]$item.Name) { [string]$item.Name } else { [string]$item.Source }) + ".")
                    break
                }
            }
        }
        return [pscustomobject]@{ Text = $working; Log = $log.ToArray(); Change = @(); Changed = ($working -ne $Text) }
    }

    $pending = New-Object System.Collections.Generic.List[object]
    foreach ($object in $objects) {
        $guidValue = Get-WinToolJsoncProperty -Object $object -Name "guid"
        $sourceValue = Get-WinToolJsoncProperty -Object $object -Name "source"
        $nameValue = Get-WinToolJsoncProperty -Object $object -Name "name"
        $commandValue = Get-WinToolJsoncProperty -Object $object -Name "commandline"
        if ($null -eq $guidValue -and $null -eq $sourceValue -and $null -eq $nameValue -and $null -eq $commandValue) {
            continue
        }
        $guid = ""
        $source = ""
        $name = ""
        $commandline = ""
        if ($null -ne $guidValue) { $guid = [string]$guidValue.Value }
        if ($null -ne $sourceValue) { $source = [string]$sourceValue.Value }
        if ($null -ne $nameValue) { $name = [string]$nameValue.Value }
        if ($null -ne $commandValue) { $commandline = [string]$commandValue.Value }
        $kind = Get-WinToolTerminalBannerKind -Name $name -Source $source -Commandline $commandline
        $kindsSeen[$kind] = $true
        if ($kind -eq "azure") {
            $log.Add("Left Azure Cloud Shell unchanged (it is a remote session).")
            continue
        }
        if ($kind -eq "wsl") {
            $log.Add("Left the " + $(if ($name) { $name } else { "WSL" }) + " profile command line unchanged; the MOTD is hidden with ~/.hushlogin.")
            continue
        }
        if ($kind -eq "gitbash") {
            $log.Add("Left the Git Bash profile command line unchanged; login messages are hidden with a .hushlogin file.")
            continue
        }
        if ($kind -eq "other") {
            $label = $name
            if ([string]::IsNullOrWhiteSpace($label)) { $label = $source }
            if ([string]::IsNullOrWhiteSpace($label)) { $label = $commandline }
            if ([string]::IsNullOrWhiteSpace($label)) { $label = "unnamed profile" }
            $log.Add("Left an unknown Windows Terminal profile unchanged: " + $label + ".")
            continue
        }
        $next = Get-WinToolBannerCommandline -Kind $kind -Commandline $commandline -Source $source
        if ([string]::IsNullOrWhiteSpace($next) -or $next -eq $commandline) {
            continue
        }
        $pending.Add([pscustomobject]@{
            Object           = $object
            Action           = "set-commandline"
            Guid             = $guid
            Source           = $source
            Name             = $name
            Kind             = $kind
            Previous         = $commandline
            Current          = $next
            AddedCommandline = ($null -eq $commandValue)
        }) | Out-Null
    }
    $working = $updated
    $ordered = @($pending | Sort-Object { [int]$_.Object.Start } -Descending)
    foreach ($item in $ordered) {
        $working = Set-WinToolJsoncObjectString -Text $working -Object $item.Object -Name "commandline" -Value ([string]$item.Current)
        $changes.Add([pscustomobject]@{
            Action           = $item.Action
            Guid             = $item.Guid
            Source           = $item.Source
            Name             = $item.Name
            Kind             = $item.Kind
            Previous         = $item.Previous
            Current          = $item.Current
            AddedCommandline = $item.AddedCommandline
        }) | Out-Null
        $log.Add("Hid the startup banner for " + $(if ([string]$item.Name) { [string]$item.Name } else { [string]$item.Kind }) + ".")
    }

    $needPwsh = -not $kindsSeen.ContainsKey("pwsh")
    $needWindows = -not $kindsSeen.ContainsKey("powershell")
    if ($needPwsh) {
        $command = Get-WinToolBannerCommandline -Kind "pwsh" -Commandline "" -Source "Windows.Terminal.PowershellCore"
        $working = Add-WinToolJsoncListItem -Text $working -Source "Windows.Terminal.PowershellCore" -Commandline $command
        $changes.Add([pscustomobject]@{ Action = "add-source"; Source = "Windows.Terminal.PowershellCore"; Current = $command; Kind = "pwsh" }) | Out-Null
        $log.Add("Added a PowerShell 7 profile override with -NoLogo.")
    }
    if ($needWindows) {
        $command = Get-WinToolBannerCommandline -Kind "powershell" -Commandline "" -Source "Windows.Terminal.WindowsPowerShell"
        $working = Add-WinToolJsoncListItem -Text $working -Source "Windows.Terminal.WindowsPowerShell" -Commandline $command
        $changes.Add([pscustomobject]@{ Action = "add-source"; Source = "Windows.Terminal.WindowsPowerShell"; Current = $command; Kind = "powershell" }) | Out-Null
        $log.Add("Added a Windows PowerShell profile override with -NoLogo.")
    }
    return [pscustomobject]@{ Text = $working; Log = $log.ToArray(); Change = $changes.ToArray(); Changed = ($working -ne $Text) }
}

function Get-WinToolTerminalSettingsCandidate {
    $local = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) {
        return @()
    }
    $packages = Join-Path $local "Packages"
    return @(
        (Join-Path $packages "Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $packages "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $packages "Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe\LocalState\settings.json"),
        (Join-Path $local "Microsoft\Windows Terminal\settings.json")
    )
}

function Get-WinToolTerminalSettingsPathList {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @(Get-WinToolTerminalSettingsCandidate)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            $paths.Add($path) | Out-Null
        }
    }
    return $paths.ToArray()
}

function Get-WinToolBannerStatePath {
    param(
        [string]$Path
    )
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }
    $root = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = [string]$env:TEMP
    }
    return (Join-Path $root "WinTool\banner-state.json")
}

function Read-WinToolBannerState {
    param(
        [string]$Path
    )
    $file = Get-WinToolBannerStatePath -Path $Path
    if ([string]::IsNullOrWhiteSpace($file) -or -not (Test-Path -LiteralPath $file)) {
        return [pscustomobject]@{ files = @(); shortcuts = @(); hushlogin = $null }
    }
    try {
        $raw = [System.IO.File]::ReadAllText($file)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{ files = @(); shortcuts = @(); hushlogin = $null }
        }
        return (ConvertFrom-WinToolJsonText -Text $raw)
    }
    catch {
        return [pscustomobject]@{ files = @(); shortcuts = @(); hushlogin = $null }
    }
}

function Write-WinToolBannerState {
    param(
        $State,
        [string]$Path
    )
    $file = Get-WinToolBannerStatePath -Path $Path
    $directory = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Write-WinToolUtf8File -Path $file -Text ((ConvertTo-WinToolJsonText -Value $State) + "`n")
}

function Get-WinToolShortcutBannerKind {
    param(
        [string]$TargetPath,
        [string]$Arguments
    )
    $file = ""
    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        $file = [System.IO.Path]::GetFileName($TargetPath)
    }
    $argsText = [string]$Arguments
    if ($file -match '(?i)^powershell_ise\.exe$') {
        return "other"
    }
    if ($argsText -match '(?i)VsDevCmd\.bat' -or $argsText -match '(?i)Enter-VsDevShell') {
        if ($file -match '(?i)^(powershell|pwsh)\.exe$') {
            return "vsdev-ps"
        }
        return "vsdev-cmd"
    }
    if ($file -match '(?i)^pwsh\.exe$') {
        return "pwsh"
    }
    if ($file -match '(?i)^powershell\.exe$') {
        return "powershell"
    }
    if ($file -match '(?i)^cmd\.exe$') {
        return "cmd"
    }
    if ($file -match '(?i)^(bash|git-bash)\.exe$') {
        return "gitbash"
    }
    return "other"
}

function Get-WinToolShortcutBannerArgument {
    param(
        [string]$Kind,
        [string]$Arguments
    )
    switch ($Kind) {
        "powershell" { return (Add-WinToolCommandToken -Commandline $Arguments -Token "-NoLogo") }
        "pwsh" { return (Add-WinToolCommandToken -Commandline $Arguments -Token "-NoLogo") }
        "vsdev-ps" { return (Add-WinToolCommandToken -Commandline $Arguments -Token "-NoLogo") }
        "cmd" {
            $line = "cmd.exe"
            if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
                $line = "cmd.exe " + $Arguments
            }
            $updated = Add-WinToolCmdClearCommand -Commandline $line
            if ($updated.StartsWith("cmd.exe ", [System.StringComparison]::OrdinalIgnoreCase)) {
                return $updated.Substring(8)
            }
            if ($updated -eq "cmd.exe") {
                return ""
            }
            return $updated
        }
        "vsdev-cmd" { return (Add-WinToolVsDevNoLogo -Commandline $Arguments) }
        default { return $null }
    }
}

function Set-WinToolUserHushlogin {
    param(
        [string]$HomePath,
        [switch]$Undo,
        [bool]$Created
    )
    $result = [pscustomobject]@{ Changed = $false; Created = $false; Existed = $false; Path = $null }
    if ([string]::IsNullOrWhiteSpace($HomePath) -or -not (Test-Path -LiteralPath $HomePath)) {
        return $result
    }
    $file = Join-Path $HomePath ".hushlogin"
    $result.Path = $file
    if ($Undo) {
        if ($Created -and (Test-Path -LiteralPath $file)) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            $result.Changed = $true
        }
        return $result
    }
    if (Test-Path -LiteralPath $file) {
        $result.Existed = $true
        return $result
    }
    New-Item -ItemType File -Path $file -Force | Out-Null
    $result.Changed = $true
    $result.Created = $true
    return $result
}

function Get-WinToolWslDistroNameList {
    $names = New-Object System.Collections.Generic.List[string]
    $wsl = $null
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
    }
    if ([string]::IsNullOrWhiteSpace($wsl) -or -not (Test-Path -LiteralPath $wsl)) {
        return @()
    }
    try {
        $env:WSL_UTF8 = "1"
        $output = & $wsl -l -q 2>$null
        foreach ($line in @($output)) {
            $name = ([string]$line).Replace([string][char]0, "").Trim()
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -notmatch '(?i)docker') {
                $names.Add($name) | Out-Null
            }
        }
    }
    catch {
        return @()
    }
    return $names.ToArray()
}

function Set-WinToolWslHushlogin {
    param(
        [string]$Distro,
        [switch]$Undo
    )
    $wsl = $null
    if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        $wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
    }
    if ([string]::IsNullOrWhiteSpace($wsl) -or -not (Test-Path -LiteralPath $wsl)) {
        return $false
    }
    if ($Undo) {
        $script = 'if [ -f "$HOME/.config/wintool/created-hushlogin" ]; then rm -f "$HOME/.hushlogin" "$HOME/.config/wintool/created-hushlogin"; fi'
        & $wsl -d $Distro -- bash -lc $script 2>$null | Out-Null
        return $true
    }
    $script = 'if [ ! -e "$HOME/.hushlogin" ]; then mkdir -p "$HOME/.config/wintool" && touch "$HOME/.hushlogin" && printf "created\n" > "$HOME/.config/wintool/created-hushlogin"; fi'
    & $wsl -d $Distro -- bash -lc $script 2>$null | Out-Null
    return $true
}

function Invoke-WinToolTerminalBanner {
    param(
        [switch]$Undo,
        [string[]]$SettingsPath,
        [string]$StatePath,
        [string]$HomePath,
        [string]$StartMenuPath,
        [switch]$SkipShortcuts,
        [switch]$SkipWsl
    )
    $stateFile = Get-WinToolBannerStatePath -Path $StatePath
    $state = Read-WinToolBannerState -Path $stateFile
    if ($null -eq (Get-WinToolNote -Object $state -Name "files")) {
        $state | Add-Member -NotePropertyName "files" -NotePropertyValue @() -Force
    }
    $paths = @($SettingsPath)
    if ($paths.Count -eq 0 -or ([string]::IsNullOrWhiteSpace($paths[0]) -and $paths.Count -eq 1)) {
        $paths = @(Get-WinToolTerminalSettingsPathList)
    }
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                Write-WinToolLog -Message "Windows Terminal settings were not found at $path." -Level "info"
            }
            continue
        }
        Backup-WinToolTerminalSetting -Path $path
        $raw = [System.IO.File]::ReadAllText($path)
        $change = @()
        $kept = New-Object System.Collections.Generic.List[object]
        foreach ($item in @(Get-WinToolNote -Object $state -Name "files" -Default @())) {
            if ([string](Get-WinToolNote -Object $item -Name "path") -eq $path) {
                $change = @(Get-WinToolNote -Object $item -Name "change" -Default @())
            }
            else {
                $kept.Add($item) | Out-Null
            }
        }
        $result = Update-WinToolTerminalBannerText -Text $raw -Undo:$Undo -Change $change
        foreach ($line in @($result.Log)) {
            Write-WinToolLog -Message $line -Level "info"
        }
        if ([bool]$result.Changed) {
            Write-WinToolUtf8File -Path $path -Text ([string]$result.Text)
        }
        if ($Undo) {
            $state | Add-Member -NotePropertyName "files" -NotePropertyValue $kept.ToArray() -Force
        }
        elseif ([bool]$result.Changed) {
            $kept.Add([pscustomobject]@{ path = $path; change = @($result.Change) }) | Out-Null
            $state | Add-Member -NotePropertyName "files" -NotePropertyValue $kept.ToArray() -Force
        }
    }

    $profileHome = $HomePath
    if ([string]::IsNullOrWhiteSpace($profileHome)) {
        $profileHome = [string]$env:USERPROFILE
        if ([string]::IsNullOrWhiteSpace($profileHome)) {
            $profileHome = [string]$env:HOME
        }
    }
    $hushState = Get-WinToolNote -Object $state -Name "hushlogin"
    $createdWindows = $false
    if ($null -ne $hushState) {
        $createdWindows = [bool](Get-WinToolNote -Object $hushState -Name "windowsCreated" -Default $false)
    }
    $hush = Set-WinToolUserHushlogin -HomePath $profileHome -Undo:$Undo -Created $createdWindows
    if ($hush.Created) {
        Write-WinToolLog -Message "Created $profileHome\.hushlogin to hide Git Bash login messages." -Level "ok"
        $createdWindows = $true
    }
    elseif ($Undo -and $hush.Changed) {
        Write-WinToolLog -Message "Removed the .hushlogin file WinTool created in $profileHome." -Level "ok"
        $createdWindows = $false
    }
    elseif ($hush.Existed -and -not $Undo) {
        Write-WinToolLog -Message "Left an existing $profileHome\.hushlogin in place." -Level "info"
    }

    $wslCreated = New-Object System.Collections.Generic.List[string]
    if ($null -ne $hushState) {
        foreach ($name in @(Get-WinToolNote -Object $hushState -Name "wsl" -Default @())) {
            if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                $wslCreated.Add([string]$name) | Out-Null
            }
        }
    }
    if (-not $SkipWsl) {
        if ($Undo) {
            foreach ($distro in @($wslCreated)) {
                if (Set-WinToolWslHushlogin -Distro $distro -Undo) {
                    Write-WinToolLog -Message "Removed the ~/.hushlogin file WinTool created in $distro." -Level "ok"
                }
            }
            $wslCreated = New-Object System.Collections.Generic.List[string]
        }
        else {
            foreach ($distro in @(Get-WinToolWslDistroNameList)) {
                if (Set-WinToolWslHushlogin -Distro $distro) {
                    Write-WinToolLog -Message "Hid the login message in $distro with ~/.hushlogin." -Level "ok"
                    if (-not ($wslCreated -contains $distro)) {
                        $wslCreated.Add($distro) | Out-Null
                    }
                }
            }
        }
    }

    $shortcutEntries = New-Object System.Collections.Generic.List[object]
    if (-not $SkipShortcuts) {
        $menu = $StartMenuPath
        if ([string]::IsNullOrWhiteSpace($menu)) {
            $appData = [string]$env:APPDATA
            if (-not [string]::IsNullOrWhiteSpace($appData)) {
                $menu = Join-Path $appData "Microsoft\Windows\Start Menu\Programs"
            }
        }
        if ($Undo) {
            foreach ($item in @(Get-WinToolNote -Object $state -Name "shortcuts" -Default @())) {
                $shortcutEntries.Add($item) | Out-Null
            }
            if ($env:OS -eq "Windows_NT" -and $shortcutEntries.Count -gt 0) {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    foreach ($item in $shortcutEntries) {
                        $linkPath = [string](Get-WinToolNote -Object $item -Name "path")
                        if ([string]::IsNullOrWhiteSpace($linkPath) -or -not (Test-Path -LiteralPath $linkPath)) {
                            continue
                        }
                        $link = $shell.CreateShortcut($linkPath)
                        $link.Arguments = [string](Get-WinToolNote -Object $item -Name "previous" -Default "")
                        $link.Save()
                        Write-WinToolLog -Message ("Restored Start menu shortcut arguments for " + [System.IO.Path]::GetFileName($linkPath) + ".") -Level "ok"
                    }
                }
                catch {
                    Write-WinToolLog -Message "Start menu shortcuts could not be restored: $($_.Exception.Message)" -Level "warn"
                }
            }
            $shortcutEntries = New-Object System.Collections.Generic.List[object]
        }
        elseif ($env:OS -eq "Windows_NT" -and -not [string]::IsNullOrWhiteSpace($menu) -and (Test-Path -LiteralPath $menu)) {
            try {
                $shell = New-Object -ComObject WScript.Shell
                foreach ($file in @(Get-ChildItem -LiteralPath $menu -Filter "*.lnk" -Recurse -File -ErrorAction SilentlyContinue)) {
                    $link = $shell.CreateShortcut($file.FullName)
                    $kind = Get-WinToolShortcutBannerKind -TargetPath ([string]$link.TargetPath) -Arguments ([string]$link.Arguments)
                    if ($kind -eq "other" -or $kind -eq "gitbash" -or $kind -eq "wsl" -or $kind -eq "azure") {
                        if ($kind -eq "other") {
                            Write-WinToolLog -Message ("Left Start menu shortcut unchanged: " + $file.Name + ".") -Level "info"
                        }
                        continue
                    }
                    $previous = [string]$link.Arguments
                    $next = Get-WinToolShortcutBannerArgument -Kind $kind -Arguments $previous
                    if ($null -eq $next -or $next -eq $previous) {
                        continue
                    }
                    $link.Arguments = $next
                    $link.Save()
                    $shortcutEntries.Add([pscustomobject]@{ path = $file.FullName; previous = $previous; current = $next; kind = $kind }) | Out-Null
                    Write-WinToolLog -Message ("Hid the startup banner in Start menu shortcut " + $file.Name + ".") -Level "ok"
                }
            }
            catch {
                Write-WinToolLog -Message "Start menu shortcuts were left unchanged: $($_.Exception.Message)" -Level "warn"
            }
        }
        elseif ($env:OS -ne "Windows_NT") {
            Write-WinToolLog -Message "Start menu shortcuts are only updated on Windows." -Level "info"
        }
    }

    $state | Add-Member -NotePropertyName "hushlogin" -NotePropertyValue ([pscustomobject]@{ windowsCreated = $createdWindows; wsl = $wslCreated.ToArray() }) -Force
    $state | Add-Member -NotePropertyName "shortcuts" -NotePropertyValue $shortcutEntries.ToArray() -Force
    Write-WinToolBannerState -State $state -Path $stateFile
}

function Get-WinToolTerminalBannerStep {
    param(
        [switch]$Undo
    )
    if ($Undo) {
        return [pscustomobject]@{ Type = "banner"; Label = "Show the startup banner in terminals again"; Undo = $true }
    }
    return [pscustomobject]@{ Type = "banner"; Label = "Hide the startup banner in terminals"; Undo = $false }
}

function Invoke-WinToolTerminalBannerStep {
    param(
        $Step
    )
    $undo = [bool](Get-WinToolNote -Object $Step -Name "Undo" -Default $false)
    Invoke-WinToolTerminalBanner -Undo:$undo
}
