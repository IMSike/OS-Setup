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

    It 'fonctionne dans un dépôt dont le chemin contient des crochets (pas de jokers)' {
        $bracketRoot = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid().ToString('N'))\dépôt [1]\state"
        Save-OSSetupRunState -StateRoot $bracketRoot -State @{ runId = 'r1'; pass = 1; answers = @{ profiles = @('base') } }
        (Read-OSSetupRunState -StateRoot $bracketRoot)['runId'] | Should -Be 'r1'
        Write-OSSetupRunResult -StateRoot $bracketRoot -RunId 'r1' -ExitCode 0
        Test-Path -LiteralPath (Join-Path -Path $bracketRoot -ChildPath 'last-result.json') | Should -BeTrue
        Remove-OSSetupRunState -StateRoot $bracketRoot
        Read-OSSetupRunState -StateRoot $bracketRoot | Should -BeNullOrEmpty
    }

    It 'écrit le journal dans un dépôt dont le chemin contient des crochets' {
        Mock -ModuleName OSSetup Write-Host {}
        $logs = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid().ToString('N'))\dépôt [1]\logs"
        try {
            $logPath = Start-OSSetupLog -Directory $logs -RunId 'r1'
            Write-OSSetupLog -Message 'ligne'
        }
        finally {
            InModuleScope OSSetup { $script:LogPath = $null }
        }
        Get-Content -LiteralPath $logPath -Raw | Should -BeLike '*ligne*'
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
        Mock -ModuleName OSSetup Wait-OSSetupCountdown { $true }
        Request-OSSetupLogoff -Seconds 7 | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Wait-OSSetupCountdown -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }

    It 'ne demande pas la fermeture quand une touche interrompt le compte à rebours' {
        Mock -ModuleName OSSetup Wait-OSSetupCountdown { $false }
        Request-OSSetupLogoff | Should -BeFalse
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
        Mock -ModuleName OSSetup Wait-OSSetupCountdown { $true }
        Request-OSSetupRestart -Seconds 7 | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Wait-OSSetupCountdown -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 1 -Exactly
    }

    It 'ne redémarre pas en simulation' {
        Request-OSSetupRestart -Immediate -WhatIf | Should -BeFalse
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 0 -Exactly
    }

    It 'reporté sans reprise automatique prévue, demande de relancer le setup à la main' {
        Mock -ModuleName OSSetup Wait-OSSetupCountdown { $false }
        Request-OSSetupRestart -Manual | Should -BeFalse
        Should -Invoke -ModuleName OSSetup Restart-Computer -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like '*Relancez le setup à la main*' }
    }
}

Describe 'Wait-OSSetupCountdown' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-Host {}
        Mock -ModuleName OSSetup Test-OSSetupInteractiveConsole { $false }
        # Horloge simulée : chaque attente avance d'une seconde, sans attente réelle.
        $global:OSSetupTestClock = [datetime]'2026-01-01'
        Mock -ModuleName OSSetup Get-Date { $global:OSSetupTestClock }
        Mock -ModuleName OSSetup Start-Sleep { $global:OSSetupTestClock = $global:OSSetupTestClock.AddSeconds(1) }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestClock -Scope Global -ErrorAction SilentlyContinue
    }

    It 'décompte chaque seconde puis arrive à son terme' {
        Wait-OSSetupCountdown -Label 'Redémarrage' -Hint ' — touche' -Seconds 3 | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Start-Sleep -Times 3 -Exactly
        foreach ($remaining in 3, 2, 1) {
            Should -Invoke -ModuleName OSSetup Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like "*Redémarrage dans $remaining s *" }
        }
    }

    It 'n''affiche pas l''invite à appuyer sur une touche hors console interactive' {
        Wait-OSSetupCountdown -Label 'Redémarrage' -Hint ' — touche' -Seconds 1 | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Write-Host -Times 0 -Exactly -ParameterFilter { $Object -like '*touche*' }
    }
}

Describe 'Lanceur de la reprise (src/resume.ps1)' {
    BeforeAll {
        $script:launcherPath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\resume.ps1'
        $script:windowsPowerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'cherche le paquet du Store par l''API des paquets, puis le MSI, jamais l''alias d''exécution' {
        $launcher = Get-Content -LiteralPath $script:launcherPath -Raw -Encoding utf8
        $launcher | Should -BeLike "*FindPackagesForUser('', 'Microsoft.PowerShell_8wekyb3d8bbwe')*"
        $launcher | Should -BeLike "*IsDevelopmentMode*"
        $launcher | Should -BeLike "*GetFolderPath('ProgramFiles'), 'PowerShell', '7', 'pwsh.exe')*"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:launcherPath, [ref]$null, [ref]$null)
        $code = ($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)).Value -join "`n"
        $code | Should -Not -Match 'LOCALAPPDATA|LocalApplicationData|Microsoft\\WindowsApps'
        # Aucun module chargé : rien que du .NET et l'API WinRT.
        $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -notin 'Set-StrictMode', 'Get-ResumePwshPath' } | Should -BeNullOrEmpty
    }

    It 'Get-ResumePwshPath, sous Windows PowerShell 5.1, rend un pwsh.exe existant hors du profil, ou rien' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:launcherPath, [ref]$null, [ref]$null)
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ResumePwshPath' }, $true)
        $script = Join-Path -Path $TestDrive -ChildPath 'get-resume-pwsh.ps1'
        Set-Content -LiteralPath $script -Value ($function.Extent.Text + "`r`nGet-ResumePwshPath") -Encoding utf8BOM
        $found = & $script:windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script
        $LASTEXITCODE | Should -Be 0
        if ($found) {
            "$found" | Should -BeLike '*\pwsh.exe'
            [IO.File]::Exists("$found") | Should -BeTrue
            "$found" | Should -Not -BeLike "$([Environment]::GetFolderPath('UserProfile'))\*"
        }
    }

    It 'transmet le code de sortie du setup quand PowerShell 7 est là, sinon s''arrête sur un message lisible' {
        $launcher = Get-Content -LiteralPath $script:launcherPath -Raw -Encoding utf8
        $pwshLine = '$pwsh = Get-ResumePwshPath'
        $launcher.Contains($pwshLine) | Should -BeTrue
        # Les deux cas, quelle que soit la machine : la recherche est remplacée par un pwsh existant (celui des
        # tests), puis par aucun.
        $cases = @(
            @{ Pwsh = "'$((Get-Process -Id $PID).Path -replace "'", "''")'"; ExitCode = 3 }
            @{ Pwsh = '$null'; ExitCode = 1 }
        )
        foreach ($case in $cases) {
            # Copie factice : son setup.ps1 sort seulement avec le code 3 (reprise demandée par -Resume).
            $copy = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            New-Item -Path $copy -ItemType Directory | Out-Null
            $text = $launcher.Replace($pwshLine, "`$pwsh = $($case.Pwsh)")
            Set-Content -LiteralPath "$copy\resume.ps1" -Value $text -Encoding utf8BOM -NoNewline
            Set-Content -LiteralPath "$copy\setup.ps1" -Value 'param([switch]$Resume) if ($Resume) { exit 3 } exit 9'
            # Entrée standard vide : la pause sur erreur se termine aussitôt.
            $output = $null | & $script:windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$copy\resume.ps1" 2>&1
            $LASTEXITCODE | Should -Be $case.ExitCode -Because $case.Pwsh
            if ($case.ExitCode -eq 1) { "$output" | Should -BeLike '*PowerShell 7 introuvable*Appuyez sur Entrée*' }
        }
    }
}

Describe 'Get-OSSetupPwshPath' {
    BeforeAll {
        $script:storeAlias = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft', 'WindowsApps', 'pwsh.exe')
    }

    It 'remplace le dossier versionné du PowerShell du Store par l''alias d''exécution' {
        Mock -ModuleName OSSetup Test-Path { $false } -ParameterFilter { $LiteralPath -like '*\WindowsApps\pwsh.exe' }
        Mock -ModuleName OSSetup Get-Process {
            [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.1.0_x64__8wekyb3d8bbwe\pwsh.exe' }
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
}

Describe 'Register-OSSetupResumeTask : tâche enregistrée' {
    It 'relance le compte courant à l''ouverture de session, droits les plus élevés, sans limite de durée' {
        # Seul l'enregistrement est simulé : les objets de la tâche (en mémoire, sans effet) sont les vrais.
        Mock -ModuleName OSSetup Register-ScheduledTask {}
        Register-OSSetupResumeTask -ResumeRoot 'C:\Program Files\OS-Setup\resume'
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'OS-Setup - reprise' -and $Force -and
            $Action.WorkingDirectory -eq 'C:\Program Files\OS-Setup' -and
            $Trigger.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $Trigger.UserId -eq $user -and
            $Principal.UserId -eq $user -and "$($Principal.RunLevel)" -eq 'Highest' -and "$($Principal.LogonType)" -eq 'Interactive' -and
            $Settings.ExecutionTimeLimit -eq 'PT0S'
        }
    }
}

Describe 'Unregister-OSSetupResumeTask' {
    BeforeEach {
        Mock -ModuleName OSSetup Unregister-ScheduledTask {}
    }

    It 'supprime la tâche de reprise quand elle existe, sans confirmation' {
        Mock -ModuleName OSSetup Get-ScheduledTask { [pscustomobject]@{ TaskName = 'OS-Setup - reprise' } } -ParameterFilter { $TaskName -eq 'OS-Setup - reprise' }
        Unregister-OSSetupResumeTask
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'OS-Setup - reprise' -and $PesterBoundParameters['Confirm'] -eq $false
        }
    }

    It 'ne fait rien sans tâche' {
        Mock -ModuleName OSSetup Get-ScheduledTask {}
        Unregister-OSSetupResumeTask
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 0 -Exactly
    }

    It 'signale sans interrompre la suite une tâche de reprise impossible à supprimer' {
        Mock -ModuleName OSSetup Get-ScheduledTask { [pscustomobject]@{ TaskName = 'OS-Setup - reprise' } }
        Mock -ModuleName OSSetup Unregister-ScheduledTask { throw 'accès refusé' }
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        { Unregister-OSSetupResumeTask -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*non supprimée*accès refusé*' }
    }
}

Describe 'Get-OSSetupResumePwshPath' {
    BeforeAll {
        # Pester ne simule qu'une commande existante : le module Appx n'est pas chargé dans une session de test.
        $script:resumeAppxStub = -not (Get-Command -Name Get-AppxPackage -ErrorAction SilentlyContinue)
        if ($script:resumeAppxStub) {
            function global:Get-AppxPackage { [CmdletBinding()] param([string]$Name, [switch]$AllUsers) }
        }
        $script:msiPwsh = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'PowerShell', '7', 'pwsh.exe')
        function New-TestStorePackage {
            param([string]$Version, [bool]$DevelopmentMode = $false)
            $location = Join-Path -Path $TestDrive -ChildPath "Microsoft.PowerShell_$($Version)_x64__8wekyb3d8bbwe"
            New-Item -Path $location -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $location -ChildPath 'pwsh.exe') -Value ''
            [pscustomobject]@{ Name = 'Microsoft.PowerShell'; Version = $Version; InstallLocation = $location; IsDevelopmentMode = $DevelopmentMode }
        }
    }

    AfterAll {
        if ($script:resumeAppxStub) { Remove-Item -Path Function:\Get-AppxPackage -ErrorAction SilentlyContinue }
    }

    BeforeEach {
        Mock -ModuleName OSSetup Import-OSSetupAppxModule { }
        Mock -ModuleName OSSetup Write-OSSetupLog { }
    }

    It 'rend le pwsh.exe du paquet du Store le plus récent du compte, pas un paquet en mode développeur' {
        $packages = @(
            (New-TestStorePackage -Version '7.6.1.0')
            (New-TestStorePackage -Version '7.6.10.0')
            (New-TestStorePackage -Version '7.9.0.0' -DevelopmentMode $true)
        )
        Mock -ModuleName OSSetup Get-AppxPackage { $packages }
        Get-OSSetupResumePwshPath | Should -Be (Join-Path -Path $packages[1].InstallLocation -ChildPath 'pwsh.exe')
        Should -Invoke -ModuleName OSSetup Get-AppxPackage -Times 1 -Exactly -ParameterFilter { $Name -eq 'Microsoft.PowerShell' -and -not $AllUsers }
        Test-OSSetupResumePwsh | Should -BeTrue
    }

    It 'sans paquet du Store, se replie sur le MSI s''il existe, sinon ne rend rien' {
        Mock -ModuleName OSSetup Get-AppxPackage { }
        $expected = if ([IO.File]::Exists($script:msiPwsh)) { $script:msiPwsh } else { $null }
        Get-OSSetupResumePwshPath | Should -Be $expected
        Test-OSSetupResumePwsh | Should -Be ([bool]$expected)
    }

    It 'se replie de la même façon quand les paquets sont illisibles' {
        Mock -ModuleName OSSetup Get-AppxPackage { throw 'service indisponible' }
        $expected = if ([IO.File]::Exists($script:msiPwsh)) { $script:msiPwsh } else { $null }
        Get-OSSetupResumePwshPath | Should -Be $expected
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like '*illisibles*' }
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

Describe 'Écritures de la reprise élevée dans le dépôt' {
    BeforeEach {
        $work = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $outside = Join-Path -Path $work -ChildPath 'outside'
        New-Item -Path (Join-Path -Path $work -ChildPath 'repo'), $outside -ItemType Directory -Force | Out-Null
        $junction = Join-Path -Path $work -ChildPath 'repo\logs'
        New-Item -Path $junction -ItemType Junction -Value $outside | Out-Null
    }
    AfterEach {
        InModuleScope OSSetup { $script:DataGuardEnabled = $false; $script:LogPath = $null }
    }

    It 'laisse tout passer hors reprise' {
        { Assert-OSSetupDataPath -Path (Join-Path -Path $junction -ChildPath 'setup.log') } | Should -Not -Throw
    }

    It 'pendant la reprise, refuse un chemin dont un dossier est une jonction, même si le fichier n''existe pas' {
        Enable-OSSetupDataGuard
        { Assert-OSSetupDataPath -Path (Join-Path -Path $junction -ChildPath 'setup.log') } | Should -Throw '*Junction*'
    }

    It 'pendant la reprise, refuse un fichier qui est un lien physique' {
        Enable-OSSetupDataGuard
        Set-Content -Path "$outside\target.txt" -Value 'x'
        $hardLink = Join-Path -Path $work -ChildPath 'repo\answers-last.json'
        New-Item -Path $hardLink -ItemType HardLink -Value "$outside\target.txt" | Out-Null
        { Assert-OSSetupDataPath -Path $hardLink } | Should -Throw '*HardLink*'
    }

    It 'pendant la reprise, contrôle aussi un chemin hors du dépôt (historique)' {
        Enable-OSSetupDataGuard
        $historyJunction = Join-Path -Path $work -ChildPath 'history'
        New-Item -Path $historyJunction -ItemType Junction -Value $outside | Out-Null
        { Assert-OSSetupDataPath -Path (Join-Path -Path $historyJunction -ChildPath 'run1\setup.log') } | Should -Throw '*Junction*'
    }

    It 'pendant la reprise, accepte un chemin sans lien' {
        Enable-OSSetupDataGuard
        Set-Content -Path "$work\repo\existing.txt" -Value 'x'
        { Assert-OSSetupDataPath -Path "$work\repo\existing.txt" } | Should -Not -Throw
        { Assert-OSSetupDataPath -Path "$work\repo\state\backups\run\original-values.json" } | Should -Not -Throw
    }

    It 'pendant la reprise, arrête le journal devenu une jonction sans écrire dans sa cible' {
        Enable-OSSetupDataGuard
        InModuleScope OSSetup -Parameters @{ Path = (Join-Path -Path $junction -ChildPath 'setup.log') } {
            param($Path)
            $script:LogPath = $Path
        }
        Mock -ModuleName OSSetup Write-Host {}

        { Write-OSSetupLog -Message 'ligne' } | Should -Throw '*Junction*'

        InModuleScope OSSetup { $script:LogPath } | Should -BeNullOrEmpty
        Test-Path -LiteralPath "$outside\setup.log" | Should -BeFalse
    }

    It 'arrête le journal impossible à écrire : l''écriture suivante (message d''erreur) ne lève plus' {
        # Un dossier à la place du fichier journal : Add-Content échoue.
        $unwritable = Join-Path -Path $work -ChildPath 'repo\setup.log'
        New-Item -Path $unwritable -ItemType Directory -Force | Out-Null
        InModuleScope OSSetup -Parameters @{ Path = $unwritable } { param($Path) $script:LogPath = $Path }
        Mock -ModuleName OSSetup Write-Host {}

        { Write-OSSetupLog -Message 'ligne' } | Should -Throw
        InModuleScope OSSetup { $script:LogPath } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName OSSetup Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like 'Journal arrêté : *' }
        { Write-OSSetupLog -Level Error -Message 'échec' } | Should -Not -Throw
    }

    It 'pendant la reprise, ne copie pas dans l''historique une sauvegarde qui contient une jonction' {
        Enable-OSSetupDataGuard
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
