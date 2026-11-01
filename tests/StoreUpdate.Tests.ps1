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

    It '<_> est analysable par Windows PowerShell 5.1, qui les exécute' -ForEach @('StoreUpdate.System.ps1', 'StoreUpdate.User.ps1', 'StoreUpdate.Prompt.ps1') {
        $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -Path $powershell)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 absent'; return }
        $path = (Resolve-Path -Path (Join-Path -Path $sourceRoot -ChildPath $_)).Path
        $command = "`$e = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$path', [ref]`$null, [ref]`$e); `$e | ForEach-Object { `$_.Message }"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        @(& $powershell -NoProfile -NonInteractive -EncodedCommand $encoded) | Should -BeNullOrEmpty
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
        $search | Should -Match 'LastRunTime -ge \$started'
        $search | Should -Match 'LASTEXITCODE'
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
function Save-State($State) {}
function Write-StoreUpdateLog([string]$Message) { $sim.log.Add($Message) }
function Get-Date { $sim.clock }
function Start-Sleep([int]$Seconds) { $sim.clock = $sim.clock.AddSeconds($Seconds) }
function Get-ScheduledTask { [CmdletBinding()] param([string]$TaskName)
    [pscustomobject]@{ TaskName = $TaskName; State = $(if ($sim.busyUntil -and $sim.clock -lt $sim.busyUntil) { 'Running' } else { 'Ready' }) } }
function Get-ScheduledTaskInfo { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject) process { [pscustomobject]@{ LastRunTime = $sim.lastRunTime } } }
function schtasks.exe {
    $sim.runs.Add($sim.clock)
    # Une seule instance (IgnoreNew) : demande ignorée pendant une exécution.
    if ($sim.startOnRun -and -not ($sim.busyUntil -and $sim.clock -lt $sim.busyUntil)) {
        $sim.lastRunTime = $sim.clock
        $sim.busyUntil = $sim.clock.AddSeconds($sim.duration)
    }
}
'@
        $load = $stubs + "`n" + $function
    }

    BeforeEach {
        $now = [datetime]'2026-11-01T10:00:00'
        $sim = @{ clock = $now; busyUntil = $null; lastRunTime = $now.AddDays(-1); startOnRun = $true; duration = 60
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
            Mock -ModuleName OSSetup Get-ScheduledTask {
                $role = @{ 'OS-Setup - Store (système)' = 'System'; 'OS-Setup - Store (recherche)' = 'User'; 'OS-Setup - Store (fenêtre)' = 'Prompt' }[[string]$TaskName]
                [pscustomobject]@{ TaskName = $TaskName; Actions = @([pscustomobject]@{ Arguments = (Get-OSSetupStoreUpdateTaskArgument -Role $role) }) }
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
