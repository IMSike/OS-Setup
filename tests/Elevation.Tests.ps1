[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Le test vérifie justement que la ligne de commande produite est exécutable.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
}

Describe 'ConvertTo-OSSetupCommandArgument' {
    It 'convertit chaînes, tableaux et switches' {
        $parameters = [ordered]@{
            AnswerFile = "C:\mes réponses\l'exemple.json"
            Profiles   = @('base', 'dev')
            Yes        = [switch]$true
            NoPause    = [switch]$false
        }
        ConvertTo-OSSetupCommandArgument -Parameter $parameters |
            Should -Be "-AnswerFile 'C:\mes réponses\l''exemple.json' -Profiles 'base','dev' -Yes"
    }

    It 'produit une commande exécutable qui retrouve les mêmes valeurs' {
        $script = Join-Path -Path $TestDrive -ChildPath 'echo.ps1'
        Set-Content -Path $script -Value 'param([string]$AnswerFile, [string[]]$Profiles, [switch]$Yes) "$AnswerFile|$($Profiles -join "+")|$Yes"'
        $arguments = ConvertTo-OSSetupCommandArgument -Parameter ([ordered]@{ AnswerFile = "a b'c"; Profiles = @('x', 'y'); Yes = [switch]$true })
        Invoke-Expression "& '$script' $arguments" | Should -Be "a b'c|x+y|True"
    }
}

Describe 'Assert-OSSetupInteractiveUser' {
    It 'ne lève pas d''erreur pour l''utilisateur de la session courante' {
        { Assert-OSSetupInteractiveUser } | Should -Not -Throw
    }

    It 'refuse un setup élevé avec un autre compte que celui de la session' {
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $true }
        Mock -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ SessionId = (Microsoft.PowerShell.Management\Get-Process -Id $PID).SessionId; UserName = 'PC\utilisateur-standard' }
        }
        { Assert-OSSetupInteractiveUser } | Should -Throw '*utilisateur-standard*mauvais profil*'
    }
}
