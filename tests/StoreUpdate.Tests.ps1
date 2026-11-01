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
