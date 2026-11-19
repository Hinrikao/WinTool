@{
    IncludeDefaultRules = $true
    Severity = @('Error', 'Warning')
    # WinTool confirms real changes in the window. It is not a pipeline cmdlet.
    # Write-Host is used only for the admin prompt, before a window exists.
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingWriteHost'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
    }
}
