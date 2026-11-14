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

Describe 'Provider winget : installation' {
    BeforeAll {
        # Pester ne simule qu'une commande existante : une fonction vide remplace winget là où il manque (ex. runner CI).
        $script:wingetStub = -not (Get-Command -Name winget -ErrorAction SilentlyContinue)
        if ($script:wingetStub) {
            function global:winget { }
        }
    }

    AfterAll {
        if ($script:wingetStub) { Remove-Item -Path Function:\winget -ErrorAction SilentlyContinue }
    }

    BeforeEach {
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName Update-OSSetupSessionPath
        Mock -ModuleName OSSetup -CommandName Start-Sleep
        Mock -ModuleName OSSetup -CommandName Start-Process
        Mock -ModuleName OSSetup -CommandName Test-OSSetupElevated -MockWith { $false }
        Mock -ModuleName OSSetup -CommandName Test-OSSetupWingetInstalled -MockWith { $true }
    }

    It 'échoue sur 0x8A150019 (droits requis) sans relancer winget ni demander d''autre élévation' {
        Mock -ModuleName OSSetup -CommandName winget -MockWith { $global:LASTEXITCODE = -1978335207 }
        { InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'winget').Invoke @{ id = 'Some.App' } @{} } } | Should -Throw '*0x8A150019*'
        Should -Invoke -ModuleName OSSetup -CommandName Start-Process -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup -CommandName winget -Times 1 -Exactly
    }

    It 'journalise la sortie de winget, lue en UTF-8, sans les barres de progression' {
        Mock -ModuleName OSSetup -CommandName winget -MockWith {
            $global:LASTEXITCODE = 0
            if ([Console]::OutputEncoding.CodePage -eq 65001) { 'Trouvé Some App [Some.App]' } else { 'Trouv├® Some App [Some.App]' }
            '  ██████▒▒▒▒  '
            '  1.50 MB / 3.00 MB'
            'Installé correctement'
        }
        $before = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
            InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'winget').Invoke @{ id = 'Some.App'; scope = 'user' } @{} } | Should -BeNullOrEmpty
            [Console]::OutputEncoding.CodePage | Should -Be 850
        }
        finally {
            [Console]::OutputEncoding = $before
        }
        Should -Invoke -ModuleName OSSetup -CommandName winget -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -like 'install --id Some.App --exact *--scope user' }
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 2 -Exactly
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  Trouvé Some App [Some.App]' }
    }

    It 'traite 0x8A15002B (déjà installé) comme un succès et signale le redémarrage demandé (0x8A150109)' {
        Mock -ModuleName OSSetup -CommandName winget -MockWith { $global:LASTEXITCODE = -1978335189 }
        InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'winget').Invoke @{ id = 'Some.App' } @{} } | Should -BeNullOrEmpty
        Mock -ModuleName OSSetup -CommandName winget -MockWith { $global:LASTEXITCODE = -1978334967 }
        (InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'winget').Invoke @{ id = 'Some.App' } @{} }).RebootRequired | Should -BeTrue
    }
}
