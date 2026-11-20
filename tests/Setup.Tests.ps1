BeforeAll {
    # setup.ps1 est exécuté pour de vrai (pwsh enfant), mais depuis une copie dans TestDrive dont le module OSSetup est
    # remplacé par des fonctions factices : chacune note son appel, puis retourne ou lève ce que le scénario prévoit.
    # Aucune action sur le système.
    $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $setupPath = Join-Path -Path $repoRoot -ChildPath 'setup.ps1'
    $setupAst = [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$null, [ref]$null)
    $script:moduleCommands = @($setupAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -like '*-OSSetup*' } | Sort-Object -Unique)
    # Fonctions sans effet sur le système reprises telles quelles du module (leur logique fait partie du comportement testé).
    $script:realCommands = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src\OSSetup\Functions') -Filter '*.ps1') {
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
        foreach ($definition in $fileAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            if ($definition.Name -in 'ConvertTo-OSSetupProfileList') { $script:realCommands[$definition.Name] = $definition.Extent.Text }
        }
    }

    function Invoke-TestSetup {
        <#
        Exécute la copie de setup.ps1 et retourne { ExitCode; Calls } (Calls : appels du module, dans l'ordre, chacun
        { name; args }). Returns / Throws : valeurs retournées / messages d'exception par fonction, en plus des valeurs
        par défaut d'une exécution sans incident.
        #>
        param(
            [string[]]$Argument = @(),
            [hashtable]$Returns = @{},
            [hashtable]$Throws = @{},
            # Ligne de commande PowerShell exécutée avant setup.ps1 dans le même processus (ex. code de sortie natif).
            [string]$Before
        )
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path (Join-Path -Path $root -ChildPath 'src\OSSetup') -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $setupPath -Destination $root
        $calls = Join-Path -Path $root -ChildPath 'calls.jsonl'
        $scenario = Join-Path -Path $root -ChildPath 'scenario.json'
        $defaults = @{
            'Test-OSSetupElevated'          = $true
            'Get-OSSetupResumeRoot'         = (Join-Path -Path $root -ChildPath 'resume')
            'Start-OSSetupLog'              = (Join-Path -Path $root -ChildPath 'logs\setup.log')
            'Get-OSSetupMaxPass'            = 5
            'Import-OSSetupData'            = @{ Items = @{}; Profiles = @{} }
            'Get-OSSetupFact'               = @{}
            'New-OSSetupDefaultAnswer'      = @{ profiles = @('base') }
            'Read-OSSetupAnswer'            = @{ profiles = @('base') }
            'Test-OSSetupInteractiveConsole' = $false
            'Get-OSSetupPlan'               = @(@{ Status = 'todo' })
            'Invoke-OSSetupPlan'            = @(@{ Status = 'done'; RebootRequired = $false; RequiresLogoff = $false })
            'Test-OSSetupResumePwsh'        = $true
            'Request-OSSetupRestart'        = $true
            'Request-OSSetupLogoff'         = $false
        }
        foreach ($key in $Returns.Keys) { $defaults[$key] = $Returns[$key] }
        @{ returns = $defaults; throws = $Throws } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scenario -Encoding utf8
        $stubs = foreach ($name in $script:moduleCommands) {
            if ($script:realCommands.ContainsKey($name)) { $script:realCommands[$name] }
            else { "function $name { Invoke-TestStub -Name '$name' -Arguments `$args }" }
        }
        # Chemins insérés entre apostrophes dans le code généré : apostrophes doublées (profil « O'Brien »).
        $scenarioText = $scenario -replace "'", "''"
        $callsText = $calls -replace "'", "''"
        $module = @(
            "`$script:Scenario = Get-Content -LiteralPath '$scenarioText' -Raw | ConvertFrom-Json -AsHashtable"
            'function Invoke-TestStub {'
            '    param([string]$Name, [object[]]$Arguments)'
            '    $values = @($Arguments | ForEach-Object { if ($_ -is [System.Collections.IList]) { @($_ | ForEach-Object { "$_" }) -join ''|'' } else { "$_" } })'
            "    Add-Content -LiteralPath '$callsText' -Value ([ordered]@{ name = `$Name; args = `$values } | ConvertTo-Json -Compress) -Encoding utf8"
            '    if ($script:Scenario.throws.ContainsKey($Name)) { throw $script:Scenario.throws[$Name] }'
            '    if ($script:Scenario.returns.ContainsKey($Name)) { $script:Scenario.returns[$Name] }'
            '}'
            # Garde : une fonction du module masque la cmdlet dans setup.ps1. Aucune relance élevée (invite UAC) ne peut
            # partir de ces tests, quel que soit le scénario.
            'function Start-Process { Invoke-TestStub -Name ''Start-Process'' -Arguments $args; throw ''Start-Process interdit dans les tests.'' }'
        ) + $stubs
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'src\OSSetup\OSSetup.psm1') -Value $module -Encoding utf8
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'src\OSSetup\OSSetup.psd1') -Encoding utf8 `
            -Value "@{ RootModule = 'OSSetup.psm1'; ModuleVersion = '1.0'; GUID = '$([guid]::NewGuid())'; FunctionsToExport = '*' }"

        $setupCopy = Join-Path -Path $root -ChildPath 'setup.ps1'
        $pwsh = (Get-Process -Id $PID).Path
        if ($Before) {
            # Noms de paramètres tels quels, valeurs entre apostrophes.
            $quoted = @($Argument | ForEach-Object { if ($_ -match '^-\w+$') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join ' '
            & $pwsh -NoProfile -NonInteractive -Command "$Before; & '$($setupCopy -replace "'", "''")' $quoted; exit `$LASTEXITCODE" *> $null
        }
        else {
            & $pwsh -NoProfile -NonInteractive -File $setupCopy @Argument *> $null
        }
        $exitCode = $LASTEXITCODE
        $recorded = if (Test-Path -LiteralPath $calls) { @(Get-Content -LiteralPath $calls -Encoding utf8 | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
        [pscustomobject]@{ ExitCode = $exitCode; Calls = $recorded; Names = @($recorded | ForEach-Object { $_.name }) }
    }

    function Get-TestCallArgument {
        # Arguments du premier appel de la fonction, ou $null si elle n'a pas été appelée.
        param($Result, [string]$Name)
        $call = $Result.Calls | Where-Object { $_.name -eq $Name } | Select-Object -First 1
        if ($call) { @($call.args) } else { $null }
    }
}

Describe 'setup.ps1 : garde des tests' {
    It 'ne lance jamais la relance en administrateur, même sans droits administrateur' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' -Returns @{ 'Test-OSSetupElevated' = $false }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Contain 'Start-Process'
        $result.Names | Should -Not -Contain 'Invoke-OSSetupPlan'
    }
}

Describe 'setup.ps1 : reprise abandonnée avant de commencer' {
    It 'sans état à reprendre, retire la tâche et la copie sans journal ni nettoyage de fin' {
        $result = Invoke-TestSetup -Argument '-Resume', '-NoPause' -Returns @{ 'Read-OSSetupRunState' = $null }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Contain 'Unregister-OSSetupResumeTask'
        $result.Names | Should -Contain 'Remove-OSSetupResumeCode'
        foreach ($name in 'Start-OSSetupLog', 'Invoke-OSSetupCleanup', 'Write-OSSetupRunResult', 'Import-OSSetupData') {
            $result.Names | Should -Not -Contain $name
        }
    }

    It 'quand le journal ne peut pas être créé, retire la tâche et la copie au lieu de recommencer à chaque session' {
        $state = @{ runId = 'r1'; pass = 1; yes = $true; failed = $false; answers = @{ profiles = @('base') } }
        $result = Invoke-TestSetup -Argument '-Resume', '-NoPause' -Returns @{ 'Read-OSSetupRunState' = $state } `
            -Throws @{ 'Start-OSSetupLog' = 'Écriture refusée par sécurité : lien.' }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Contain 'Unregister-OSSetupResumeTask'
        $result.Names | Should -Contain 'Remove-OSSetupResumeCode'
        $result.Names | Should -Not -Contain 'Save-OSSetupRunState'
        $result.Names | Should -Not -Contain 'Import-OSSetupData'
    }

    It 'quand le fichier journal ne peut pas être écrit, abandonne la reprise au lieu de fermer la fenêtre sans raison' {
        $state = @{ runId = 'r1'; pass = 1; yes = $true; failed = $false; answers = @{ profiles = @('base') } }
        $result = Invoke-TestSetup -Argument '-Resume', '-NoPause' -Returns @{ 'Read-OSSetupRunState' = $state } `
            -Throws @{ 'Write-OSSetupLog' = 'accès refusé' }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Contain 'Unregister-OSSetupResumeTask'
        $result.Names | Should -Contain 'Remove-OSSetupResumeCode'
        foreach ($name in 'Save-OSSetupRunState', 'Import-OSSetupData', 'Write-OSSetupRunResult', 'Invoke-OSSetupCleanup') {
            $result.Names | Should -Not -Contain $name
        }
    }

    It 'hors reprise, s''arrête aussi proprement quand le journal ne peut pas être créé' {
        $result = Invoke-TestSetup -Argument '-NoPause' -Throws @{ 'Start-OSSetupLog' = 'accès refusé' }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Not -Contain 'Import-OSSetupData'
        $result.Names | Should -Not -Contain 'Unregister-OSSetupResumeTask'
    }
}

Describe 'setup.ps1 : redémarrage nécessaire' {
    It 'prépare la reprise (copie, état, tâche) puis redémarre, sans terminer l''exécution' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' `
            -Returns @{ 'Invoke-OSSetupPlan' = @(@{ Status = 'reboot'; RebootRequired = $true }) }
        $result.ExitCode | Should -Be 0
        $order = @($result.Names | Where-Object { $_ -in 'Copy-OSSetupResumeCode', 'Save-OSSetupRunState', 'Register-OSSetupResumeTask', 'Request-OSSetupRestart' })
        $order | Should -Be @('Copy-OSSetupResumeCode', 'Save-OSSetupRunState', 'Register-OSSetupResumeTask', 'Request-OSSetupRestart')
        $result.Names | Should -Not -Contain 'Write-OSSetupRunResult'
        $result.Names | Should -Not -Contain 'Invoke-OSSetupCleanup'
    }

    It 'sans PowerShell 7 du Store ni du MSI, ne crée pas de tâche vouée à l''échec et demande de relancer à la main' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' -Returns @{
            'Invoke-OSSetupPlan'     = @(@{ Status = 'reboot'; RebootRequired = $true })
            'Test-OSSetupResumePwsh' = $false
        }
        $result.ExitCode | Should -Be 0
        foreach ($name in 'Copy-OSSetupResumeCode', 'Save-OSSetupRunState', 'Register-OSSetupResumeTask', 'Write-OSSetupRunResult', 'Invoke-OSSetupCleanup') {
            $result.Names | Should -Not -Contain $name
        }
        Get-TestCallArgument -Result $result -Name 'Request-OSSetupRestart' | Should -Contain '-Manual'
        $warning = $result.Calls | Where-Object { $_.name -eq 'Write-OSSetupLog' -and "$($_.args)" -like '*reprise automatique est impossible*' }
        "$($warning.args)" | Should -BeLike '*relancez le setup à la main*-AnswerFile*answers-last.json*'
    }

    It 'si la tâche de reprise ne peut pas être créée, termine l''exécution en échec et retire ce qui a été préparé' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' `
            -Returns @{ 'Invoke-OSSetupPlan' = @(@{ Status = 'reboot'; RebootRequired = $true }) } `
            -Throws @{ 'Register-OSSetupResumeTask' = 'accès refusé' }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Not -Contain 'Request-OSSetupRestart'
        Get-TestCallArgument -Result $result -Name 'Write-OSSetupRunResult' | Should -Contain '1'
        foreach ($name in 'Unregister-OSSetupResumeTask', 'Remove-OSSetupRunState', 'Remove-OSSetupResumeCode', 'Invoke-OSSetupCleanup') {
            $result.Names | Should -Contain $name
        }
    }
}

Describe 'setup.ps1 : arguments transmis par pwsh -File' {
    It 'découpe « -Profiles base,dev » (un seul texte) en deux profils' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base,dev', '-AcceptDefaults', '-Yes', '-NoPause'
        $result.ExitCode | Should -Be 0
        Get-TestCallArgument -Result $result -Name 'New-OSSetupDefaultAnswer' | Should -Contain 'base|dev'
    }

    It 'refuse « -Profiles base dev » au lieu de prendre « dev » pour le fichier de réponses' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', 'dev', '-Yes', '-NoPause'
        $result.ExitCode | Should -Not -Be 0
        $result.Names | Should -Not -Contain 'Read-OSSetupAnswerFile'
        $result.Names | Should -Not -Contain 'Invoke-OSSetupPlan'
    }
}

Describe 'setup.ps1 : restes des exécutions précédentes' {
    It 'supprime au début les restes des commandes sans droits administrateur, hors simulation seulement' {
        (Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause').Names |
            Should -Contain 'Clear-OSSetupUnelevatedLeftover'
        (Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-WhatIf').Names |
            Should -Not -Contain 'Clear-OSSetupUnelevatedLeftover'
    }

    It 'continue si leur suppression échoue' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' -Throws @{ 'Clear-OSSetupUnelevatedLeftover' = 'accès refusé' }
        $result.ExitCode | Should -Be 0
        $result.Names | Should -Contain 'Invoke-OSSetupPlan'
    }
}

Describe 'setup.ps1 : outils du bootstrap gardés au nettoyage de fin' {
    It 'calcule les paquets des éléments retenus une fois ces éléments connus' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause'
        $result.Names | Should -Contain 'Get-OSSetupSelectedWingetId'
        $result.Names | Should -Contain 'Invoke-OSSetupCleanup'
    }

    It 'sur un échec avant la résolution des éléments, ne calcule rien (aucun outil désinstallé)' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' -Throws @{ 'Get-OSSetupFact' = 'panne' }
        $result.ExitCode | Should -Be 1
        $result.Names | Should -Not -Contain 'Get-OSSetupSelectedWingetId'
        $result.Names | Should -Contain 'Invoke-OSSetupCleanup'
    }
}

Describe 'setup.ps1 : actions reportées à la fermeture du setup' {
    It 'confie au nettoyage de fin les commandes des actions « atclose », sans échec' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' -Returns @{
            'Invoke-OSSetupPlan' = @(
                @{ Status = 'done'; RebootRequired = $false; RequiresLogoff = $false }
                @{ Status = 'atclose'; RebootRequired = $false; RequiresLogoff = $false; RunAtClose = @('commande-reportée') }
            )
        }
        $result.ExitCode | Should -Be 0
        $arguments = Get-TestCallArgument -Result $result -Name 'Invoke-OSSetupCleanup'
        $index = [array]::IndexOf($arguments, '-RunAtClose')
        $index | Should -BeGreaterOrEqual 0
        $arguments[$index + 1] | Should -Be 'commande-reportée'
    }

    It 'ne transmet aucune commande quand aucune action n''est reportée' {
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause'
        $arguments = Get-TestCallArgument -Result $result -Name 'Invoke-OSSetupCleanup'
        $index = [array]::IndexOf($arguments, '-RunAtClose')
        $arguments[$index + 1] | Should -BeNullOrEmpty
    }
}

Describe 'setup.ps1 : code de sortie' {
    It 'sort avec son propre code quand il n''y a rien à faire, pas avec celui d''une commande native antérieure' {
        # Comme la relance en administrateur : « & setup.ps1 …; exit $LASTEXITCODE ».
        $result = Invoke-TestSetup -Argument '-Profiles', 'base', '-AcceptDefaults', '-Yes', '-NoPause' `
            -Returns @{ 'Get-OSSetupPlan' = @(@{ Status = 'ok' }) } -Before 'cmd.exe /c exit 7'
        $result.ExitCode | Should -Be 0
        $result.Names | Should -Not -Contain 'Invoke-OSSetupPlan'
        $result.Names | Should -Contain 'Write-OSSetupRunResult'
    }

    It 'sort avec son propre code après une annulation' {
        $result = Invoke-TestSetup -Argument '-NoPause' -Returns @{ 'Read-OSSetupConfirmation' = 'cancel' } -Before 'cmd.exe /c exit 7'
        $result.ExitCode | Should -Be 0
        $result.Names | Should -Not -Contain 'Invoke-OSSetupPlan'
    }

    It 'sur une reprise sans rien à faire, garde l''échec d''une passe précédente' {
        $state = @{ runId = 'r1'; pass = 1; yes = $true; failed = $true; answers = @{ profiles = @('base') } }
        $result = Invoke-TestSetup -Argument '-Resume', '-NoPause' -Returns @{
            'Read-OSSetupRunState' = $state
            'Get-OSSetupPlan'      = @(@{ Status = 'ok' })
        }
        $result.ExitCode | Should -Be 1
        Get-TestCallArgument -Result $result -Name 'Write-OSSetupRunResult' | Should -Contain '1'
    }
}
