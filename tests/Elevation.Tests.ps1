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

Describe 'ConvertTo-OSSetupProfileList' {
    It 'découpe les profils séparés par des virgules et retire espaces et éléments vides' {
        ConvertTo-OSSetupProfileList -Value 'base,dev' | Should -Be @('base', 'dev')
        ConvertTo-OSSetupProfileList -Value 'base', ' dev , ', '' | Should -Be @('base', 'dev')
        ConvertTo-OSSetupProfileList -Value 'base' | Should -Be @('base')
        ConvertTo-OSSetupProfileList -Value @() | Should -BeNullOrEmpty
    }
}

Describe 'Assert-OSSetupInteractiveUser' {
    # Élévation et explorer.exe simulés : le résultat ne dépend pas de la console qui lance les tests.
    BeforeAll {
        $sessionId = (Get-Process -Id $PID).SessionId
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }

    BeforeEach {
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog -MockWith {}
    }

    It 'sans élévation, ne vérifie rien (le nom du propriétaire d''un processus exige les droits administrateur)' {
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $false }
        Mock -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith { throw 'inattendu' }
        { Assert-OSSetupInteractiveUser } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -Times 0 -Exactly
    }

    It 'accepte le compte qui a ouvert la session' {
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $true }
        Mock -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ SessionId = $sessionId; UserName = $currentUser }
        }
        { Assert-OSSetupInteractiveUser } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly
    }

    It 'sans explorer.exe dans la session, avertit et laisse continuer' {
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $true }
        Mock -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ SessionId = $sessionId + 1000; UserName = 'PC\autre-session' }
        }
        { Assert-OSSetupInteractiveUser } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*explorer.exe absent*' } -Times 1 -Exactly
    }

    It 'refuse un setup élevé avec un autre compte que celui de la session' {
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $true }
        Mock -ModuleName OSSetup -CommandName Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith {
            [pscustomobject]@{ SessionId = $sessionId; UserName = 'PC\utilisateur-standard' }
        }
        { Assert-OSSetupInteractiveUser } | Should -Throw '*utilisateur-standard*mauvais profil*'
    }
}
