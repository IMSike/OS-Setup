BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $script:sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\src\store-update'
    $script:pwshAction = @{ family = 'Microsoft.PowerShell_8wekyb3d8bbwe'; productId = '9MZ1SNWT0N5D'; name = 'PowerShell 7'; closeFirst = @('herdr') }
}

Describe 'Scripts des tâches des mises à jour du Store' {
    It '<_> est analysable sans erreur' -ForEach @('StoreUpdate.System.ps1', 'StoreUpdate.User.ps1', 'StoreUpdate.Prompt.ps1') {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath $_), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It '<_> suit les conventions : StrictMode, CmdletBinding, mention de copie déployée' -ForEach @('StoreUpdate.System.ps1', 'StoreUpdate.User.ps1', 'StoreUpdate.Prompt.ps1') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath $_), [ref]$null, [ref]$null)
        $ast.ParamBlock.Attributes.TypeName.Name | Should -Contain 'CmdletBinding'
        $ast.EndBlock.Statements.Extent.Text | Should -Contain 'Set-StrictMode -Version Latest'
        $ast.Extent.Text | Should -Match 'modifier le dépôt, pas cette copie'
    }

    It 'la recherche isole chaque application et écrit check.json après chacune' {
        # Le script n'est testable qu'en analyse (API du Store) : on vérifie la structure de sa boucle.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.User.ps1'), [ref]$null, [ref]$null)
        $loop = $ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.ForEachStatementAst] -and $Node.Variable.VariablePath.UserPath -eq 'app' }, $true)
        $loop | Should -Not -BeNullOrEmpty
        $loop.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.TryStatementAst] } | Should -Not -BeNullOrEmpty
        $loop.Body.Statements | Where-Object { $_.Extent.Text -like '*WriteAllText($checkFile*' } | Should -Not -BeNullOrEmpty
    }

    It 'la tâche SYSTEM attend une recherche démarrée après sa demande' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.System.ps1'), [ref]$null, [ref]$null)
        $search = $ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Invoke-UserSearch' }, $true).Extent.Text
        $search | Should -Not -Match 'Start-Sleep -Seconds 5'
        $search | Should -Match 'LastRunTime -ne \$previous'
        $search | Should -Match 'LASTEXITCODE'
    }

    It 'la tâche SYSTEM n''attend dans le pont WMI que les applications installées' {
        $text = Get-Content -Path (Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.System.ps1') -Raw
        $text | Should -Match '\$present = @\(\$apps \| Where-Object \{ Get-AppVersion -App \$_ \}\)'
        $text | Should -Match '\$installed\.Count -eq \$present\.Count'
        $text | Should -Not -Match '\$installed\.Count -eq \$apps\.Count'
    }

    It 'les tâches lancent Windows PowerShell par son chemin complet' {
        $argument = InModuleScope OSSetup { Get-OSSetupStoreUpdateTaskArgument -Role System }
        $expected = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'WindowsPowerShell\v1.0\powershell.exe'
        $argument | Should -BeLike "--headless `"$expected`" *"
    }

    It '<_> appelle les exécutables système par leur chemin complet' -ForEach @('StoreUpdate.System.ps1', 'StoreUpdate.Prompt.ps1') {
        $text = Get-Content -Path (Join-Path -Path $sourceRoot -ChildPath $_) -Raw
        $text | Should -Not -Match '&\s+(schtasks|icacls)\.exe'
    }

    It '<Script> lance la tâche « <Role> » sous le nom que lui donne le module' -ForEach @(
        @{ Script = 'StoreUpdate.System.ps1'; Variable = 'userTask'; Role = 'User' }
        @{ Script = 'StoreUpdate.Prompt.ps1'; Variable = 'systemTask'; Role = 'System' }
    ) {
        # Les scripts déployés sont autonomes et recopient le nom : un renommage dans le module seul ferait échouer
        # « schtasks /run » sans erreur visible (sortie jetée).
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath $Script), [ref]$null, [ref]$null)
        $assignment = $ast.Find({
                param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $Node.Left.VariablePath.UserPath -eq $Variable
            }, $false)
        $assignment | Should -Not -BeNullOrEmpty
        $expected = InModuleScope OSSetup -Parameters @{ Role = $Role } { param($Role) $script:StoreUpdateTask[$Role] }
        $assignment.Right.Expression.Value | Should -Be $expected
    }

    It 'chaque script déclaré par le module existe dans src/store-update' {
        $names = InModuleScope OSSetup { @($script:StoreUpdateScript.Values) }
        $names.Count | Should -Be 3
        foreach ($name in $names) { Join-Path -Path $sourceRoot -ChildPath $name | Should -Exist }
    }

    It 'la tâche SYSTEM reconnaît la tâche de reprise du setup sous son nom actuel' {
        $resume = InModuleScope OSSetup { $script:ResumeTaskName }
        $resume | Should -Not -BeNullOrEmpty
        Get-Content -Path (Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.System.ps1') -Raw | Should -Match ([regex]::Escape("-TaskName '$resume'"))
    }

    It 'la fenêtre reconnaît la tâche de reprise du setup sous son nom actuel' {
        $resume = InModuleScope OSSetup { $script:ResumeTaskName }
        Get-Content -Path (Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.Prompt.ps1') -Raw | Should -Match ([regex]::Escape("$resumeTask = '$resume'"))
    }
}

Describe 'Fenêtre : attente de la tâche SYSTEM' {
    BeforeAll {
        # Le script exécute son corps au chargement : seule la fonction est extraite. Planificateur, horloge et attente
        # sont simulés ($sim) : aucun effet sur le système.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.Prompt.ps1'), [ref]$null, [ref]$null)
        $function = $ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Invoke-SystemRun' }, $true).Extent.Text
        $stubs = @'
$systemTask = 'OS-Setup - Store (système)'
$log = 'store-update.log'
function Get-Item { [CmdletBinding()] param([string]$Path) }
function Save-State($State) {}
function Write-StoreUpdateLog([string]$Message) { $sim.log.Add($Message) }
function Get-Date { $sim.clock }
function Start-Sleep([int]$Seconds) { $sim.clock = $sim.clock.AddSeconds($Seconds) }
function Get-ScheduledTask { [CmdletBinding()] param([string]$TaskName)
    [pscustomobject]@{ TaskName = $TaskName; State = $(if ($sim.busyUntil -and $sim.clock -lt $sim.busyUntil) { 'Running' } else { 'Ready' }) } }
function Get-ScheduledTaskInfo { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject) process { [pscustomobject]@{ LastRunTime = $sim.lastRunTime } } }
$schtasks = 'Invoke-FakeSchtasks'
function Invoke-FakeSchtasks {
    $sim.runs.Add($sim.clock)
    # Une seule instance (IgnoreNew) : demande ignorée pendant une exécution.
    if ($sim.startOnRun -and -not ($sim.busyUntil -and $sim.clock -lt $sim.busyUntil)) {
        if ($sim.stampRuns) { $sim.lastRunTime = $sim.clock.AddSeconds($sim.skew) }
        $sim.busyUntil = $sim.clock.AddSeconds($sim.duration)
    }
}
'@
        $load = $stubs + "`n" + $function
    }

    BeforeEach {
        $now = [datetime]'2026-11-01T10:00:00'
        $sim = @{ clock = $now; busyUntil = $null; lastRunTime = $now.AddDays(-1); startOnRun = $true; duration = 60; skew = 0; stampRuns = $true
            runs = [System.Collections.Generic.List[datetime]]::new(); log = [System.Collections.Generic.List[string]]::new() }
    }

    It 'attend la fin d''une exécution en cours avant de relancer la tâche' {
        $sim.busyUntil = $now.AddMinutes(5)
        $sim.lastRunTime = $now.AddMinutes(-1)
        . ([scriptblock]::Create($load))
        Invoke-SystemRun ([pscustomobject]@{ lastRun = $null }) | Should -BeTrue
        $sim.runs.Count | Should -Be 1
        $sim.runs[0] | Should -BeGreaterOrEqual $now.AddMinutes(5)
    }

    It 'renvoie faux si la tâche ne démarre jamais' {
        $sim.startOnRun = $false
        . ([scriptblock]::Create($load))
        Invoke-SystemRun ([pscustomobject]@{ lastRun = $null }) | Should -BeFalse
        $sim.log | Should -Contain 'tâche système non terminée'
    }

    It 'renvoie vrai quand l''exécution lancée se termine' {
        . ([scriptblock]::Create($load))
        Invoke-SystemRun ([pscustomobject]@{ lastRun = $null }) | Should -BeTrue
        $sim.runs.Count | Should -Be 1
        $sim.runs[0] | Should -Be $now
        $sim.log | Should -BeNullOrEmpty
    }

    It 'reconnaît l''exécution lancée quand le Planificateur la date quelques secondes trop tôt' {
        # Observé en VM : LastRunTime 10 s avant l'heure réelle de la demande.
        $sim.skew = -10
        . ([scriptblock]::Create($load))
        Invoke-SystemRun ([pscustomobject]@{ lastRun = $null }) | Should -BeTrue
        $sim.log | Should -BeNullOrEmpty
    }

    It 'reconnaît l''exécution lancée vue en cours quand LastRunTime ne change pas' {
        # Observé en VM : deux exécutions à 5 s d'intervalle gardent le même LastRunTime.
        $sim.stampRuns = $false
        . ([scriptblock]::Create($load))
        Invoke-SystemRun ([pscustomobject]@{ lastRun = $null }) | Should -BeTrue
        $sim.log | Should -BeNullOrEmpty
    }
}

Describe 'Fenêtre : décisions sous Windows PowerShell 5.1' {
    BeforeAll {
        # Le script est chargé avec un point dans un Windows PowerShell 5.1 enfant, qui l'exécute en vrai. Fichiers dans
        # $TestDrive ; Store, processus, tâche SYSTEM et fenêtre remplacés : aucun effet sur le système.
        $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $promptScript = (Resolve-Path -Path (Join-Path -Path $sourceRoot -ChildPath 'StoreUpdate.Prompt.ps1')).Path
        $app = [ordered]@{ family = 'Microsoft.PowerShell_8wekyb3d8bbwe'; productId = '9MZ1SNWT0N5D'; name = 'PowerShell 7'; closeFirst = @() }

        function Invoke-PromptScenario {
            # Lance la fenêtre (ou $Call) avec la version installée, l'état ouvert et le choix indiqués ; renvoie les appels
            # remplacés et le fichier d'état écrit.
            param([string]$Root, [string]$Version = '1.0', [bool]$Open = $true, [string]$Choice = '1h', [string]$Call = 'Invoke-StoreUpdatePrompt', [bool]$Resume = $false)
            $command = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
. '$promptScript'
`$root = '$Root'
`$log = Join-Path -Path `$root -ChildPath 'store-update.log'
`$stateFile = Join-Path -Path `$root -ChildPath 'state.json'
`$global:calls = [ordered]@{ systemRuns = 0; prompts = 0; output = `$null }
function Get-AppVersion { param(`$App) '$Version' }
function Get-AppProcess { param(`$App) if (`$$Open) { @(1) } else { @() } }
function Invoke-SystemRun { param(`$State) `$global:calls.systemRuns++; `$State.lastRun = (Get-Date).ToString('o'); Save-State -State `$State; `$true }
function Show-UpdatePrompt { param(`$App) `$global:calls.prompts++; '$Choice' }
function Show-Message { param(`$Text) }
function Test-ResumePending { `$$Resume }
`$global:calls.output = @($Call | ForEach-Object { "`$_" })
`$global:calls.state = if (Test-Path -Path `$stateFile) { [IO.File]::ReadAllText(`$stateFile) }
ConvertTo-Json -InputObject `$global:calls -Compress
"@
            $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            $output = & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded
            ($output -join "`n") | ConvertFrom-Json
        }

        function Set-CheckFile {
            param([string]$Root, [object]$Entry)
            $check = if ($null -ne $Entry) { @{ $app.productId = $Entry } } else { @{} }
            Set-Content -Path (Join-Path -Path $Root -ChildPath 'check.json') -Value (ConvertTo-Json -InputObject $check -Depth 4) -Encoding utf8
        }
    }

    BeforeEach {
        if (-not (Test-Path -Path $powershell)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 absent'; return }
        $root = Join-Path -Path $TestDrive -ChildPath "prompt-$([guid]::NewGuid())"
        New-Item -Path $root -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Value (ConvertTo-Json -InputObject @($app) -Depth 4) -Encoding utf8
        $fresh = (Get-Date).ToString('o')
    }

    It 'écrit un report absent comme null, pas comme {}' {
        # Régression corrigée par aa6794e : sous 5.1, un report vide s'écrivait {}, puis faisait échouer la lecture suivante.
        Set-Content -Path (Join-Path -Path $root -ChildPath 'state.json') -Value '{ "snoozeUntil": null, "lastRun": null }'
        $result = Invoke-PromptScenario -Root $root
        $result.systemRuns | Should -Be 1
        $result.state | Should -Match '"snoozeUntil":\s*null'
        $result.state | Should -Not -Match '\{\s*\}'
    }

    It 'ne fait rien pendant un report' {
        $snooze = (Get-Date).AddHours(1).ToString('o')
        Set-Content -Path (Join-Path -Path $root -ChildPath 'state.json') -Value (ConvertTo-Json -InputObject @{ snoozeUntil = $snooze; lastRun = $null })
        $result = Invoke-PromptScenario -Root $root
        $result.systemRuns | Should -Be 0
        $result.prompts | Should -Be 0
        ($result.state | ConvertFrom-Json).snoozeUntil | Should -Be ([datetime]$snooze)
    }

    It 'fait vérifier par la tâche SYSTEM sans check.json' {
        (Invoke-PromptScenario -Root $root).systemRuns | Should -Be 1
    }

    It 'fait vérifier par la tâche SYSTEM quand la vérification a plus de 4 h' {
        Set-CheckFile -Root $root -Entry @{ available = $false; version = '1.0'; checked = (Get-Date).AddHours(-5).ToString('o') }
        (Invoke-PromptScenario -Root $root).systemRuns | Should -Be 1
    }

    It 'fait vérifier par la tâche SYSTEM quand l''entrée de check.json est incomplète' {
        Set-CheckFile -Root $root -Entry @{ available = $true }
        $result = Invoke-PromptScenario -Root $root
        $result.systemRuns | Should -Be 1
        $result.prompts | Should -Be 0
    }

    It 'ne relance pas la tâche SYSTEM après une vérification récente sans mise à jour' {
        Set-CheckFile -Root $root -Entry @{ available = $false; version = '1.0'; checked = $fresh }
        $result = Invoke-PromptScenario -Root $root
        $result.systemRuns | Should -Be 0
        $result.prompts | Should -Be 0
    }

    It 'reporte d''une heure une mise à jour proposée pour une application ouverte' {
        Set-CheckFile -Root $root -Entry @{ available = $true; version = '1.0'; checked = $fresh; state = 'proposée' }
        $before = Get-Date
        $result = Invoke-PromptScenario -Root $root -Open $true -Choice '1h'
        $result.prompts | Should -Be 1
        $result.systemRuns | Should -Be 0
        $snooze = [datetime]($result.state | ConvertFrom-Json).snoozeUntil
        $snooze | Should -BeGreaterOrEqual $before.AddHours(1)
        $snooze | Should -BeLessOrEqual (Get-Date).AddHours(1)
    }

    It 'laisse la tâche SYSTEM installer une mise à jour proposée pour une application fermée' {
        Set-CheckFile -Root $root -Entry @{ available = $true; version = '1.0'; checked = $fresh; state = 'proposée' }
        $result = Invoke-PromptScenario -Root $root -Open $false
        $result.systemRuns | Should -Be 1
        $result.prompts | Should -Be 0
    }

    It 'ne propose rien et ne lance rien pendant une reprise du setup' {
        Set-CheckFile -Root $root -Entry @{ available = $true; version = '1.0'; checked = $fresh; state = 'proposée' }
        $result = Invoke-PromptScenario -Root $root -Resume $true -Choice 'Now'
        $result.prompts | Should -Be 0
        $result.systemRuns | Should -Be 0
    }

    It 'lit la version d''un paquet absent comme une chaîne vide, sans erreur sous StrictMode' {
        # Vraie fonction Get-AppVersion (extraite du script), sous Windows PowerShell 5.1 et StrictMode.
        $command = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$ast = [System.Management.Automation.Language.Parser]::ParseFile('$promptScript', [ref]`$null, [ref]`$null)
. ([scriptblock]::Create(`$ast.Find({ param(`$Node) `$Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and `$Node.Name -eq 'Get-AppVersion' }, `$true).Extent.Text))
'[' + (Get-AppVersion -App ([pscustomobject]@{ family = 'OSSetup.PaquetInexistant_0000000000000' })) + ']'
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded | Should -Be '[]'
    }

    It 'ignore une mise à jour déjà installée depuis la vérification' {
        Set-CheckFile -Root $root -Entry @{ available = $true; version = '1.0'; checked = $fresh; state = 'proposée' }
        $result = Invoke-PromptScenario -Root $root -Version '2.0' -Call "Get-PendingApp -App @(Read-JsonFile -Path (Join-Path -Path `$root -ChildPath 'apps.json'))"
        $result.output | Should -BeNullOrEmpty
        (Invoke-PromptScenario -Root $root -Version '1.0' -Call "Get-PendingApp -App @(Read-JsonFile -Path (Join-Path -Path `$root -ChildPath 'apps.json')) | ForEach-Object { `$_.productId }").output |
            Should -Be @('9MZ1SNWT0N5D')
    }
}

Describe 'Mises à jour encadrées du Store' {
    BeforeEach {
        $root = Join-Path -Path $TestDrive -ChildPath "store-update-$([guid]::NewGuid())"
        New-Item -Path $root -ItemType Directory | Out-Null
        Mock -ModuleName OSSetup Get-OSSetupStoreUpdateRoot { $root }
        Mock -ModuleName OSSetup Get-ScheduledTask {
            [pscustomobject]@{ TaskName = $TaskName; Actions = @([pscustomobject]@{ Arguments = 'faux' }) }
        }
        Mock -ModuleName OSSetup icacls.exe {}
    }

    Context 'conformité' {
        BeforeEach {
            foreach ($file in Get-ChildItem -Path $sourceRoot -Filter '*.ps1') { Copy-Item -Path $file.FullName -Destination $root }
            $entry = InModuleScope OSSetup -Parameters @{ Action = $pwshAction } { param($Action) ConvertTo-OSSetupStoreUpdateApp -Action $Action }
            Set-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Value (ConvertTo-Json -InputObject @($entry) -Depth 4) -Encoding utf8
            foreach ($name in 'check.json', 'store-update.log') { Set-Content -Path (Join-Path -Path $root -ChildPath $name) -Value '' }
            $taskState = 'Ready'
            $marker = InModuleScope OSSetup { $script:StoreUpdateTaskMarker }
            # Compte des tâches de l'utilisateur : le compte courant, par son SID (le Planificateur peut aussi rendre un nom).
            $taskUser = @{ User = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value; Prompt = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
            Mock -ModuleName OSSetup Get-ScheduledTask {
                $role = @{ 'OS-Setup - Store (système)' = 'System'; 'OS-Setup - Store (recherche)' = 'User'; 'OS-Setup - Store (fenêtre)' = 'Prompt' }[[string]$TaskName]
                $userId = if ($role -eq 'System') { 'SYSTEM' } else { $taskUser[$role] }
                [pscustomobject]@{ TaskName = $TaskName; State = $taskState; Description = "OS-Setup : tâche. $marker"
                    Principal = [pscustomobject]@{ UserId = $userId }
                    Actions = @([pscustomobject]@{ Arguments = (Get-OSSetupStoreUpdateTaskArgument -Role $role) }) }
            }
            Mock -ModuleName OSSetup Get-OSSetupDoNotUpdate { 1 }
        }

        It 'est conforme quand scripts, liste, tâches et blocage sont en place' {
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeTrue
        }

        It 'n''est pas conforme sans le blocage' {
            Mock -ModuleName OSSetup Get-OSSetupDoNotUpdate { 0 }
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand un script déployé diffère de celui du dépôt' {
            Add-Content -Path (Join-Path -Path $root -ChildPath 'StoreUpdate.System.ps1') -Value '# modifié'
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand l''application n''est pas listée' {
            $terminal = @{ family = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'; productId = '9N0DX20HK701'; name = 'Windows Terminal' }
            InModuleScope OSSetup -Parameters @{ Action = $terminal; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand une tâche est désactivée' {
            $taskState = 'Disabled'
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand une tâche a une ancienne définition' {
            $marker = '[définition v0]'
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme sans check.json' {
            Remove-Item -Path (Join-Path -Path $root -ChildPath 'check.json')
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'est conforme quand le Planificateur donne le compte courant par son nom' {
            $name = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $taskUser = @{ User = $name; Prompt = $name.Split('\')[-1] }
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeTrue
        }

        It 'n''est pas conforme quand la tâche « <_> » est celle d''un autre compte' -ForEach @('User', 'Prompt') {
            $taskUser[$_] = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand le compte d''une tâche ne se résout plus' {
            $taskUser.User = 'CompteSupprimeOSSetup-0000'
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }

        It 'n''est pas conforme quand une tâche lance autre chose' {
            Mock -ModuleName OSSetup Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName; Actions = @([pscustomobject]@{ Arguments = 'autre' }) } }
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source
            } | Should -BeFalse
        }
    }

    Context 'mise en place' {
        BeforeEach {
            Mock -ModuleName OSSetup Register-OSSetupStoreUpdateTask {}
            Mock -ModuleName OSSetup Set-OSSetupDoNotUpdate {}
        }

        It 'déploie les scripts, liste l''application sans toucher aux autres, enregistre les tâches et pose le blocage' {
            $other = [ordered]@{ family = 'Microsoft.WindowsTerminal_8wekyb3d8bbwe'; productId = '9N0DX20HK701'; name = 'Windows Terminal'; closeFirst = @() }
            $old = [ordered]@{ family = $pwshAction.family; productId = $pwshAction.productId; name = 'ancien nom'; closeFirst = @() }
            Set-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Value (ConvertTo-Json -InputObject @($other, $old) -Depth 4) -Encoding utf8
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Install-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source -Confirm:$false
            }
            foreach ($name in 'StoreUpdate.System.ps1', 'StoreUpdate.User.ps1', 'StoreUpdate.Prompt.ps1') {
                (Get-FileHash -Path (Join-Path -Path $root -ChildPath $name)).Hash | Should -Be (Get-FileHash -Path (Join-Path -Path $sourceRoot -ChildPath $name)).Hash
            }
            $apps = @(Get-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Raw | ConvertFrom-Json)
            $apps.family | Should -Be @('Microsoft.WindowsTerminal_8wekyb3d8bbwe', 'Microsoft.PowerShell_8wekyb3d8bbwe')
            $apps[1].name | Should -Be 'PowerShell 7'
            $apps[1].closeFirst | Should -Be @('herdr')
            Get-Content -Path (Join-Path -Path $root -ChildPath 'check.json') -Raw | Should -Be '{}'
            Should -Invoke -ModuleName OSSetup icacls.exe -Times 2 -Exactly
            Should -Invoke -ModuleName OSSetup Register-OSSetupStoreUpdateTask -Times 1 -Exactly
            Should -Invoke -ModuleName OSSetup Set-OSSetupDoNotUpdate -ParameterFilter { $Family -eq 'Microsoft.PowerShell_8wekyb3d8bbwe' } -Times 1 -Exactly
        }

        It 'ne fait rien en simulation' {
            InModuleScope OSSetup -Parameters @{ Action = $pwshAction; Source = $sourceRoot } {
                param($Action, $Source) Install-OSSetupStoreUpdateGuard -Action $Action -SourceRoot $Source -WhatIf
            }
            Get-ChildItem -Path $root | Should -BeNullOrEmpty
            Should -Invoke -ModuleName OSSetup Register-OSSetupStoreUpdateTask -Times 0 -Exactly
        }
    }

    It 'échoue à poser le blocage d''une application que le Store ne connaît pas' {
        Mock -ModuleName OSSetup Get-CimInstance {}
        Mock -ModuleName OSSetup Set-CimInstance {}
        { InModuleScope OSSetup { Set-OSSetupDoNotUpdate -Family 'Microsoft.PowerShell_8wekyb3d8bbwe' -TimeoutSeconds 0 -Confirm:$false } } |
            Should -Throw '*ne connaît pas*'
        Should -Invoke -ModuleName OSSetup Set-CimInstance -Times 0 -Exactly
    }

    It 'sans droits administrateur, le provider laisse l''action à faire' {
        Mock -ModuleName OSSetup Test-OSSetupElevated { $false }
        InModuleScope OSSetup -Parameters @{ Action = $pwshAction } {
            param($Action) & (Get-OSSetupProvider -Name 'store-update-guard').Test $Action @{ Root = 'C:\inexistant' }
        } | Should -BeFalse
    }
}
