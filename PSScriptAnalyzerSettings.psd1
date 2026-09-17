@{
    ExcludeRules = @(
        # This is a controller script run by hand: its console output is the
        # product, not a side effect. Write-Host has gone to the information
        # stream since PowerShell 5, so it is capturable like any other.
        'PSAvoidUsingWriteHost'

        # The script requires PowerShell 7, so cross-version compatibility is
        # not in scope. Every finding this rule produces here is a Pester
        # operator such as "Should -Be", which it cannot resolve because Pester
        # adds them at run time.
        'PSUseCompatibleCommands'
    )

    Rules        = @{
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSAvoidLongLines           = @{
            Enable            = $true
            MaximumLineLength = 120
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NoEmptyLineBefore  = $true
            IgnoreOneLineBlock = $true
            NewLineAfter       = $true
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $true
            CheckSeparator                          = $true
            CheckParameter                          = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSUseCorrectCasing         = @{
            Enable        = $true
            CheckCommands = $true
            CheckKeyword  = $true
            CheckOperator = $true
        }
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}
