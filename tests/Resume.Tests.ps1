[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Provider factice : interface commune des providers ($Action, $Context).')]
param()

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    # Provider factice : une action est « appliquée » quand Invoke est passé ; reboot = $true la fait signaler un redémarrage.
    InModuleScope OSSetup {
        $script:Providers['fake'] = @{
            Name     = 'fake'
            Describe = { param($Action, $Context) "fake $($Action['key'])" }
            Test     = { param($Action, $Context) [bool]$global:OSSetupTestApplied[$Action['key']] }
            Invoke   = {
                param($Action, $Context)
                $global:OSSetupTestApplied[$Action['key']] = $true
                if ($Action['reboot']) { @{ RebootRequired = $true } }
            }
        }
    }

    function New-TestStep {
        param([string]$ItemId, [string]$Key, [switch]$Reboot, [string[]]$DependsOn = @(), [switch]$RequiresReboot)
        [pscustomobject]@{
            ItemId         = $ItemId
            ItemName       = $ItemId
            RequiresAdmin  = $false
            RequiresReboot = [bool]$RequiresReboot
            RequiresLogoff = $false
            DependsOn      = $DependsOn
            Index          = 1
            Provider       = 'fake'
            Action         = @{ provider = 'fake'; key = $Key; reboot = [bool]$Reboot }
            Description    = "fake $Key"
            Status         = 'todo'
            Detail         = $null
        }
    }
}

Describe 'Invoke-OSSetupPlan : redémarrages' {
    BeforeEach {
        $global:OSSetupTestApplied = @{}
        Mock -ModuleName OSSetup Write-OSSetupLog {}
    }

    AfterAll {
        Remove-Variable -Name OSSetupTestApplied -Scope Global -ErrorAction SilentlyContinue
    }

    It 'termine l''élément qui signale un redémarrage et reporte ses dépendants, y compris indirects' {
        $plan = @(
            New-TestStep -ItemId 'feature' -Key 'f1' -Reboot
            New-TestStep -ItemId 'feature' -Key 'f2'
            New-TestStep -ItemId 'independent' -Key 'i'
            New-TestStep -ItemId 'app' -Key 'a' -DependsOn 'feature'
            New-TestStep -ItemId 'config' -Key 'c' -DependsOn 'app'
        )
        $results = @(Invoke-OSSetupPlan -Plan $plan -Context @{})
        $results.Status | Should -Be @('reboot', 'done', 'done', 'deferred', 'deferred')
        $global:OSSetupTestApplied.Keys | Sort-Object | Should -Be @('f1', 'f2', 'i')
        @($results | Where-Object { $_.RebootRequired }).Count | Should -Be 3
    }

    It 'tient compte d''un élément déclaré requiresReboot' {
        $plan = @(
            New-TestStep -ItemId 'driver' -Key 'd' -RequiresReboot
            New-TestStep -ItemId 'tool' -Key 't' -DependsOn 'driver'
        )
        $results = @(Invoke-OSSetupPlan -Plan $plan -Context @{})
        $results.Status | Should -Be @('done', 'deferred')
        $results[0].RebootRequired | Should -BeTrue
    }

    It 'ne demande aucun redémarrage quand rien ne le signale' {
        $results = @(Invoke-OSSetupPlan -Plan @(New-TestStep -ItemId 'x' -Key 'x') -Context @{})
        $results[0].Status | Should -Be 'done'
        $results[0].RebootRequired | Should -BeFalse
    }

    It 'revérifie une action jugée conforme au moment du plan quand une action précédente du même élément a été appliquée' {
        # Ex. installation (a1) qui crée un raccourci que l'action suivante (a2) doit supprimer.
        $first = New-TestStep -ItemId 'app' -Key 'a1'
        $second = New-TestStep -ItemId 'app' -Key 'a2'
        $second.Status = 'ok'
        $unchanged = New-TestStep -ItemId 'other' -Key 'o1'
        $unchanged.Status = 'ok'
        $results = @(Invoke-OSSetupPlan -Plan @($first, $second, $unchanged) -Context @{})
        $results.Status | Should -Be @('done', 'done', 'ok')
        $global:OSSetupTestApplied.Keys | Sort-Object | Should -Be @('a1', 'a2')
    }

    It 'revérifie aussi un élément qui dépend d''un élément modifié pendant l''exécution' {
        # Ex. Brave installé (b1), puis désactivation de son entrée de démarrage (élément séparé qui en dépend).
        $install = New-TestStep -ItemId 'brave' -Key 'b1'
        $startup = New-TestStep -ItemId 'brave-no-autostart' -Key 's1' -DependsOn 'brave'
        $startup.Status = 'ok'
        $results = @(Invoke-OSSetupPlan -Plan @($install, $startup) -Context @{})
        $results.Status | Should -Be @('done', 'done')
    }

    It 'ne demande pas de redémarrage pour un élément déjà conforme marqué requiresReboot' {
        $step = New-TestStep -ItemId 'driver' -Key 'd' -RequiresReboot
        $step.Status = 'ok'
        $results = @(Invoke-OSSetupPlan -Plan @($step, (New-TestStep -ItemId 'tool' -Key 't' -DependsOn 'driver')) -Context @{})
        $results.Status | Should -Be @('ok', 'done')
    }
}

Describe 'État de reprise' {
    BeforeEach {
        # TestDrive est partagé par les tests d'un même Describe : un dossier distinct par test.
        $stateRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
    }

    It 'restitue des réponses utilisables (tableaux) après enregistrement' {
        $answers = @{ profiles = @('dev'); choices = [ordered]@{ browsers = @('vivaldi'); editor = @() }; variables = @{ DevRoot = 'C:\Dev' } }
        Save-OSSetupRunState -StateRoot $stateRoot -State @{ runId = 'r1'; pass = 1; yes = $true; failed = $false; answers = $answers }
        $state = Read-OSSetupRunState -StateRoot $stateRoot
        $state['runId'] | Should -Be 'r1'
        $state['pass'] | Should -Be 1
        $state['answers']['profiles'] | Should -Be @('dev')
        , $state['answers']['choices']['browsers'] | Should -BeOfType [array]
        $state['answers']['choices']['editor'].Count | Should -Be 0
        $state['answers']['variables']['DevRoot'] | Should -Be 'C:\Dev'
    }

    It 'retourne $null sans exécution en attente, et supprime l''état' {
        Read-OSSetupRunState -StateRoot $stateRoot | Should -BeNullOrEmpty
        Save-OSSetupRunState -StateRoot $stateRoot -State @{ runId = 'r1'; pass = 1; answers = @{ profiles = @('base') } }
        Remove-OSSetupRunState -StateRoot $stateRoot
        Read-OSSetupRunState -StateRoot $stateRoot | Should -BeNullOrEmpty
    }

    It 'écrit le résultat final' {
        Write-OSSetupRunResult -StateRoot $stateRoot -RunId 'r1' -ExitCode 1
        (Get-Content -Path (Join-Path -Path $stateRoot -ChildPath 'last-result.json') -Raw | ConvertFrom-Json).exitCode | Should -Be 1
    }
}

Describe 'Request-OSSetupRestart' {
    BeforeEach {
        Mock -ModuleName OSSetup Restart-Computer {}
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Mock -ModuleName OSSetup Write-Host {}
        Mock -ModuleName OSSetup Test-OSSetupInteractiveConsole { $false }
    }

    It 'redémarre aussitôt avec -Immediate' {
        Request-OSSetupRestart -Immediate | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 1 -Exactly
    }

    It 'redémarre après le compte à rebours' {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        Request-OSSetupRestart -Seconds 1 | Should -BeTrue
        $watch.Elapsed.TotalMilliseconds | Should -BeGreaterOrEqual 900
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 1 -Exactly
    }

    It 'ne redémarre pas en simulation' {
        Request-OSSetupRestart -Immediate -WhatIf | Should -BeFalse
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 0 -Exactly
    }
}
