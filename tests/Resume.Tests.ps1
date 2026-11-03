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

    It 'écrit l''état sans laisser de fichier temporaire, en remplaçant le précédent' {
        Save-OSSetupRunState -StateRoot $stateRoot -State @{ runId = 'r1'; pass = 1; answers = @{ profiles = @('base') } }
        Save-OSSetupRunState -StateRoot $stateRoot -State @{ runId = 'r1'; pass = 2; answers = @{ profiles = @('base') } }
        (Read-OSSetupRunState -StateRoot $stateRoot)['pass'] | Should -Be 2
        (Get-ChildItem -LiteralPath $stateRoot).Name | Should -Be @('run.json')
    }

    It 'écrit le résultat final' {
        Write-OSSetupRunResult -StateRoot $stateRoot -RunId 'r1' -ExitCode 1
        (Get-Content -Path (Join-Path -Path $stateRoot -ChildPath 'last-result.json') -Raw | ConvertFrom-Json).exitCode | Should -Be 1
    }
}

Describe 'Request-OSSetupLogoff' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Mock -ModuleName OSSetup Write-Host {}
        Mock -ModuleName OSSetup Test-OSSetupInteractiveConsole { $false }
    }

    It 'demande la fermeture aussitôt avec -Immediate' {
        Request-OSSetupLogoff -Immediate | Should -BeTrue
    }

    It 'demande la fermeture après le compte à rebours' {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        Request-OSSetupLogoff -Seconds 1 | Should -BeTrue
        $watch.Elapsed.TotalMilliseconds | Should -BeGreaterOrEqual 900
    }

    It 'ne demande pas la fermeture en simulation' {
        Request-OSSetupLogoff -Immediate -WhatIf | Should -BeFalse
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

Describe 'Get-OSSetupPwshPath' {
    BeforeAll {
        $script:storeAlias = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'
    }

    It 'remplace le dossier versionné du PowerShell du Store par l''alias d''exécution' {
        Mock -ModuleName OSSetup Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\WindowsApps\pwsh.exe' }
        Mock -ModuleName OSSetup Get-Process {
            [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.4.0_x64__8wekyb3d8bbwe\pwsh.exe' }
        }
        Get-OSSetupPwshPath | Should -Be $script:storeAlias
    }

    It 'choisit l''alias du Store dès qu''il existe, même sous le MSI de PowerShell 7' {
        Mock -ModuleName OSSetup Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\WindowsApps\pwsh.exe' }
        Mock -ModuleName OSSetup Get-Process { [pscustomobject]@{ Path = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
        Get-OSSetupPwshPath | Should -Be $script:storeAlias
    }

    It 'garde le chemin d''un PowerShell hors Store quand celui du Store est absent' {
        Mock -ModuleName OSSetup Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\WindowsApps\pwsh.exe' }
        Mock -ModuleName OSSetup Get-Process { [pscustomobject]@{ Path = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
        Get-OSSetupPwshPath | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
    }
}

Describe 'Register-OSSetupResumeTask' {
    BeforeEach {
        Mock -ModuleName OSSetup New-ScheduledTaskAction { 'action' }
        Mock -ModuleName OSSetup New-ScheduledTaskTrigger { 'trigger' }
        Mock -ModuleName OSSetup New-ScheduledTaskPrincipal { 'principal' }
        Mock -ModuleName OSSetup New-ScheduledTaskSettingsSet { 'settings' }
        Mock -ModuleName OSSetup Register-ScheduledTask {} -RemoveParameterType Action, Trigger, Principal, Settings
    }

    It 'lance le lanceur de la copie figée par le Windows PowerShell du système, jamais l''alias du profil' {
        # Simulation en plus du remplacement : aucune tâche réelle ne peut être créée.
        Register-OSSetupResumeTask -ResumeRoot 'C:\Program Files\OS-Setup\resume' -WhatIf
        $powershell = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\powershell.exe')
        Should -Invoke -ModuleName OSSetup New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter {
            $Execute -eq $powershell -and $Argument -like '*-File "C:\Program Files\OS-Setup\resume\resume.ps1"' -and
            $Argument -notlike '*WindowsApps*'
        }
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 0 -Exactly
    }

    It 'reste reconnue par la règle des tâches orphelines du Store (-File, state\run.json à côté)' {
        Register-OSSetupResumeTask -ResumeRoot 'C:\Program Files\OS-Setup\resume' -WhatIf
        Should -Invoke -ModuleName OSSetup New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter {
            $Argument -match '-File\s+"([^"]+)"' -and
            (Join-Path -Path (Split-Path -Path $Matches[1] -Parent) -ChildPath 'state\run.json') -eq 'C:\Program Files\OS-Setup\resume\state\run.json'
        }
    }
}

Describe 'Copie figée de la reprise' {
    BeforeEach {
        $source = Join-Path -Path $TestDrive -ChildPath "src-$([guid]::NewGuid().ToString('N'))"
        $target = Join-Path -Path $TestDrive -ChildPath "resume-$([guid]::NewGuid().ToString('N'))"
        foreach ($dir in 'src\OSSetup', 'catalog', 'docs', 'tests', 'logs', 'state', '.git') {
            New-Item -Path (Join-Path -Path $source -ChildPath $dir) -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path "$source\setup.ps1" -Value '# setup'
        Set-Content -Path "$source\src\resume.ps1" -Value '# lanceur'
        Set-Content -Path "$source\src\OSSetup\OSSetup.psm1" -Value '# module'
        Set-Content -Path "$source\catalog\item.json" -Value '{}'
        Set-Content -Path "$source\logs\setup.log" -Value 'journal'
        Set-Content -Path "$source\state\answers-last.json" -Value '{}'
    }

    It 'copie le code et le catalogue, le lanceur à la racine, sans journaux, état, documentation, tests ni .git' {
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        (Get-ChildItem -LiteralPath $target -Force).Name | Sort-Object | Should -Be @('catalog', 'resume.ps1', 'setup.ps1', 'src')
        Get-Content -Path "$target\resume.ps1" | Should -Be '# lanceur'
        Test-Path -Path "$target\src\OSSetup\OSSetup.psm1" | Should -BeTrue
    }

    It 'garde run.json de la copie et remplace le reste' {
        New-Item -Path "$target\state" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$target\state\run.json" -Value '{}'
        Set-Content -Path "$target\ancien.ps1" -Value '# ancien'
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        Test-Path -Path "$target\state\run.json" | Should -BeTrue
        Test-Path -Path "$target\ancien.ps1" | Should -BeFalse
    }

    It 'fige la trace du bootstrap dans la copie, et retire celle d''une copie précédente' {
        Set-Content -Path "$source\state\bootstrap.json" -Value '{"ownsClone":true}'
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        Get-Content -Path "$target\state\bootstrap.json" | Should -Be '{"ownsClone":true}'
        Remove-Item -Path "$source\state\bootstrap.json"
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        Test-Path -Path "$target\state\bootstrap.json" | Should -BeFalse
    }

    It 'ignore les jonctions de la racine du dépôt' {
        $outside = Join-Path -Path $TestDrive -ChildPath "outside-$([guid]::NewGuid().ToString('N'))"
        New-Item -Path $outside -ItemType Directory -Force | Out-Null
        New-Item -Path "$source\lien" -ItemType Junction -Value $outside | Out-Null
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        Test-Path -Path "$target\lien" | Should -BeFalse
    }

    It 'ne fait rien quand le setup s''exécute déjà depuis la copie' {
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $source
        Test-Path -Path "$source\resume.ps1" | Should -BeFalse
        Test-Path -Path "$source\logs\setup.log" | Should -BeTrue
    }

    It 'supprime la copie, et ne signale rien quand elle n''existe pas' {
        Copy-OSSetupResumeCode -SourceRoot $source -Destination $target
        Remove-OSSetupResumeCode -Path $target
        Test-Path -Path $target | Should -BeFalse
        { Remove-OSSetupResumeCode -Path $target } | Should -Not -Throw
    }
}

Describe 'setup.ps1 : relance élevée' {
    It 'relance par Get-OSSetupPwshPath (alias du Store dès qu''il existe)' {
        $setup = Join-Path -Path $PSScriptRoot -ChildPath '..\setup.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($setup, [ref]$null, [ref]$null)
        $elevation = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Start-Process' -and
                $node.Extent.Text -match '-Verb RunAs'
            }, $true)
        @($elevation).Count | Should -Be 1
        $elevation[0].Extent.Text | Should -Match '-FilePath \$pwsh\b'
        $ast.Extent.Text | Should -Match '\$pwsh = Get-OSSetupPwshPath'
    }
}

Describe 'Écritures de la reprise élevée dans le dépôt' {
    BeforeEach {
        $work = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $outside = Join-Path -Path $work -ChildPath 'outside'
        New-Item -Path (Join-Path -Path $work -ChildPath 'repo'), $outside -ItemType Directory -Force | Out-Null
        $junction = Join-Path -Path $work -ChildPath 'repo\logs'
        New-Item -Path $junction -ItemType Junction -Value $outside | Out-Null
    }
    AfterEach {
        InModuleScope OSSetup { $script:DataGuardRoot = $null; $script:LogPath = $null }
    }

    It 'laisse tout passer hors reprise' {
        { Assert-OSSetupDataPath -Path (Join-Path -Path $junction -ChildPath 'setup.log') } | Should -Not -Throw
    }

    It 'pendant la reprise, refuse un chemin dont un dossier est une jonction, même si le fichier n''existe pas' {
        Enable-OSSetupDataGuard -Root (Join-Path -Path $work -ChildPath 'repo')
        { Assert-OSSetupDataPath -Path (Join-Path -Path $junction -ChildPath 'setup.log') } | Should -Throw '*Junction*'
    }

    It 'pendant la reprise, refuse un fichier qui est un lien physique' {
        Enable-OSSetupDataGuard -Root (Join-Path -Path $work -ChildPath 'repo')
        Set-Content -Path "$outside\target.txt" -Value 'x'
        $hardLink = Join-Path -Path $work -ChildPath 'repo\answers-last.json'
        New-Item -Path $hardLink -ItemType HardLink -Value "$outside\target.txt" | Out-Null
        { Assert-OSSetupDataPath -Path $hardLink } | Should -Throw '*HardLink*'
    }

    It 'pendant la reprise, accepte un chemin sans lien' {
        Enable-OSSetupDataGuard -Root (Join-Path -Path $work -ChildPath 'repo')
        Set-Content -Path "$work\repo\existing.txt" -Value 'x'
        { Assert-OSSetupDataPath -Path "$work\repo\existing.txt" } | Should -Not -Throw
        { Assert-OSSetupDataPath -Path "$work\repo\state\backups\run\original-values.json" } | Should -Not -Throw
    }

    It 'pendant la reprise, arrête le journal devenu une jonction sans écrire dans sa cible' {
        Enable-OSSetupDataGuard -Root (Join-Path -Path $work -ChildPath 'repo')
        InModuleScope OSSetup -Parameters @{ Path = (Join-Path -Path $junction -ChildPath 'setup.log') } {
            param($Path)
            $script:LogPath = $Path
        }
        Mock -ModuleName OSSetup Write-Host {}

        { Write-OSSetupLog -Message 'ligne' } | Should -Throw '*Junction*'

        InModuleScope OSSetup { $script:LogPath } | Should -BeNullOrEmpty
        Test-Path -LiteralPath "$outside\setup.log" | Should -BeFalse
    }

    It 'pendant la reprise, ne copie pas dans l''historique une sauvegarde qui contient une jonction' {
        Enable-OSSetupDataGuard -Root (Join-Path -Path $work -ChildPath 'repo')
        Set-Content -Path "$outside\secret.txt" -Value 'protégé'
        $backups = Join-Path -Path $work -ChildPath 'repo\state\backups\run1'
        New-Item -Path $backups -ItemType Directory -Force | Out-Null
        New-Item -Path "$backups\lien" -ItemType Junction -Value $outside | Out-Null
        $history = Join-Path -Path $work -ChildPath 'history'

        { Save-OSSetupHistory -Root (Join-Path -Path $work -ChildPath 'repo') -RunId 'run1' -HistoryRoot $history -Confirm:$false } |
            Should -Throw '*Junction*'

        @(Get-ChildItem -LiteralPath $history -Recurse -Filter 'secret.txt' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }
}
