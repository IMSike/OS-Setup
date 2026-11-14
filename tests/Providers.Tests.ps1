[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fonctions factices : mêmes signatures que les vraies.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
}

Describe 'Provider scheduled-task : erreurs des cmdlets du Planificateur' {
    It 'demande l''arrêt sur erreur à <Cmdlet> (cmdlet CDXML, hors de la préférence du module)' -ForEach @(
        @{ Cmdlet = 'Enable-ScheduledTask'; Enabled = $true }
        @{ Cmdlet = 'Disable-ScheduledTask'; Enabled = $false }
    ) {
        Mock -ModuleName OSSetup -CommandName $Cmdlet
        InModuleScope OSSetup -Parameters @{ Enabled = $Enabled } {
            param($Enabled)
            & (Get-OSSetupProvider -Name 'scheduled-task').Invoke @{ task = '\Dossier\Tâche'; enabled = $Enabled } @{}
        }
        Should -Invoke -ModuleName OSSetup -CommandName $Cmdlet -Times 1 -Exactly -ParameterFilter {
            $TaskPath -eq '\Dossier\' -and $TaskName -eq 'Tâche' -and $PesterBoundParameters['ErrorAction'] -eq 'Stop'
        }
    }
}

Describe 'Provider logon-task : erreurs des cmdlets du Planificateur' {
    It 'demande l''arrêt sur erreur à Register-ScheduledTask' {
        Mock -ModuleName OSSetup -CommandName Register-ScheduledTask
        InModuleScope OSSetup {
            $action = @{ name = 'OS-Setup - test'; script = 'C:\Program Files\OS-Setup\test.ps1'; description = 'Tâche de test.' }
            & (Get-OSSetupProvider -Name 'logon-task').Invoke $action @{}
        }
        Should -Invoke -ModuleName OSSetup -CommandName Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'OS-Setup - test' -and $PesterBoundParameters['ErrorAction'] -eq 'Stop'
        }
    }
}
