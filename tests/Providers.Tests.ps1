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
            $action = @{ name = 'OS-Setup - test'; script = 'C:\Program Files\OS-Setup\test.ps1'; taskDescription = 'Tâche de test.' }
            & (Get-OSSetupProvider -Name 'logon-task').Invoke $action @{}
        }
        Should -Invoke -ModuleName OSSetup -CommandName Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'OS-Setup - test' -and $Description -eq 'Tâche de test.' -and $PesterBoundParameters['ErrorAction'] -eq 'Stop'
        }
    }

    It 'prend le texte de la tâche dans taskDescription : description reste la phrase du plan' {
        $schema = Join-Path -Path $PSScriptRoot -ChildPath '..\schemas\item.schema.json'
        $item = { param($Action) ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ id = 'x'; name = 'X'; category = 'test'; platforms = @('windows'); actions = @($Action) }) }
        $task = [ordered]@{ provider = 'logon-task'; name = 'T'; script = '{{ProgramFiles}}\OS-Setup\t.ps1' }
        Test-Json -Json (& $item ($task + @{ taskDescription = 'Texte.' })) -SchemaFile $schema | Should -BeTrue
        Test-Json -Json (& $item ($task + @{ description = 'Texte.' })) -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeFalse
        InModuleScope OSSetup {
            & (Get-OSSetupProvider -Name 'logon-task').Describe @{ name = 'T'; script = 'C:\Program Files\OS-Setup\t.ps1'; taskDescription = 'Texte.' } @{} |
                Should -Be 'tâche planifiée « T » à l''ouverture de session : t.ps1'
        }
    }
}

Describe 'Provider logon-task : conformité' {
    BeforeAll {
        $script:logonAction = @{ name = 'OS-Setup - test'; script = 'C:\Program Files\OS-Setup\test.ps1'; taskDescription = 'Tâche de test.' }
    }

    It 'est conforme <Case>' -ForEach @(
        @{ Case = 'pour la tâche attendue, activée'; Execute = $null; State = 'Ready'; RunLevel = 'Highest'; Expected = $true }
        @{ Case = 'non quand elle est désactivée'; Execute = $null; State = 'Disabled'; RunLevel = 'Highest'; Expected = $false }
        @{ Case = 'non quand elle lance un autre programme'; Execute = 'C:\Program Files\PowerShell\7\pwsh.exe'; State = 'Ready'; RunLevel = 'Highest'; Expected = $false }
        @{ Case = 'non sans les droits les plus élevés'; Execute = $null; State = 'Ready'; RunLevel = 'Limited'; Expected = $false }
    ) {
        InModuleScope OSSetup -Parameters @{ Action = $logonAction; Execute = $Execute; State = $State; RunLevel = $RunLevel } {
            param($Action, $Execute, $State, $RunLevel)
            if (-not $Execute) { $Execute = Get-OSSetupWindowsPowerShellPath }
            $task = [pscustomobject]@{
                TaskName  = $Action['name']
                State     = $State
                Actions   = @([pscustomobject]@{ Execute = $Execute; Arguments = (Get-OSSetupLogonTaskArgument -Script $Action['script']) })
                Principal = [pscustomobject]@{ RunLevel = $RunLevel }
            }
            Mock -CommandName Get-OSSetupScheduledTask -MockWith { $task }
            & (Get-OSSetupProvider -Name 'logon-task').Test $Action @{}
        } | Should -Be $Expected
    }

    It 'enregistre la valeur d''origine (état, programme, arguments)' {
        InModuleScope OSSetup -Parameters @{ Action = $logonAction } {
            param($Action)
            Mock -CommandName Get-OSSetupScheduledTask -MockWith {
                [pscustomobject]@{ State = 'Disabled'; Actions = @([pscustomobject]@{ Execute = 'C:\x.exe'; Arguments = '-a' }) }
            }
            $before = & (Get-OSSetupProvider -Name 'logon-task').Read $Action @{}
            $before['state'] | Should -Be 'Disabled'
            $before['execute'] | Should -Be 'C:\x.exe'
            $before['arguments'] | Should -Be '-a'
            Mock -CommandName Get-OSSetupScheduledTask
            (& (Get-OSSetupProvider -Name 'logon-task').Read $Action @{})['exists'] | Should -BeFalse
        }
    }

    It 'n''est pas conforme quand la tâche lance un autre script, ou des arguments modifiés' {
        InModuleScope OSSetup -Parameters @{ Action = $logonAction } {
            param($Action)
            $powershell = Get-OSSetupWindowsPowerShellPath
            foreach ($arguments in @(
                    (Get-OSSetupLogonTaskArgument -Script 'C:\Program Files\OS-Setup\autre.ps1')
                    '-NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\OS-Setup\test.ps1"'
                )) {
                $task = [pscustomobject]@{
                    State     = 'Ready'
                    Actions   = @([pscustomobject]@{ Execute = $powershell; Arguments = $arguments })
                    Principal = [pscustomobject]@{ RunLevel = 'Highest' }
                }
                Mock -CommandName Get-OSSetupScheduledTask -MockWith { $task }
                & (Get-OSSetupProvider -Name 'logon-task').Test $Action @{} | Should -BeFalse
            }
        }
    }
}

Describe 'Get-OSSetupLogonTaskArgument' {
    It 'lance le script sans profil, sans fenêtre ni question, chemin à espaces entre guillemets en dernier' {
        $arguments = InModuleScope OSSetup { Get-OSSetupLogonTaskArgument -Script 'C:\Program Files\OS-Setup\docker\entretien.ps1' }
        $arguments | Should -BeLike '*-File "C:\Program Files\OS-Setup\docker\entretien.ps1"'
        foreach ($switch in '-NoProfile', '-NonInteractive', '-WindowStyle Hidden', '-ExecutionPolicy Bypass') {
            $arguments | Should -BeLike "*$switch *"
        }
    }
}

Describe 'Provider logon-task : enregistrement' {
    It 'crée une tâche à l''ouverture de session du compte, droits les plus élevés, qui lance le script par Windows PowerShell' {
        # Seul l'enregistrement est simulé : les objets de la tâche (en mémoire, sans effet) sont les vrais.
        Mock -ModuleName OSSetup Register-ScheduledTask {}
        InModuleScope OSSetup {
            & (Get-OSSetupProvider -Name 'logon-task').Invoke @{ name = 'OS-Setup - test'; script = 'C:\Program Files\OS-Setup\test.ps1'; taskDescription = 'T.' } @{}
        }
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $powershell = InModuleScope OSSetup { Get-OSSetupWindowsPowerShellPath }
        $arguments = InModuleScope OSSetup { Get-OSSetupLogonTaskArgument -Script 'C:\Program Files\OS-Setup\test.ps1' }
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'OS-Setup - test' -and $Force -and
            @($Action).Count -eq 1 -and $Action.Execute -eq $powershell -and $Action.Arguments -eq $arguments -and
            $Trigger.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and $Trigger.UserId -eq $user -and
            $Principal.UserId -eq $user -and "$($Principal.RunLevel)" -eq 'Highest' -and "$($Principal.LogonType)" -eq 'Interactive'
        }
    }
}

Describe 'Schéma : aucune propriété que le provider ne lit pas' {
    It 'décrit <Provider> sans <Removed> (comportement fixe du provider)' -ForEach @(
        @{ Provider = 'fnm-node'; Action = [ordered]@{ provider = 'fnm-node' }; Removed = 'version'; Value = 'lts' }
        @{ Provider = 'startup-entry'; Action = [ordered]@{ provider = 'startup-entry'; name = 'Discord' }; Removed = 'enabled'; Value = $false }
    ) {
        $schema = Join-Path -Path $PSScriptRoot -ChildPath '..\schemas\item.schema.json'
        $item = { param($Action) ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ id = 'x'; name = 'X'; category = 'test'; platforms = @('windows'); actions = @($Action) }) }
        Test-Json -Json (& $item $Action) -SchemaFile $schema | Should -BeTrue
        $Action[$Removed] = $Value
        Test-Json -Json (& $item $Action) -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Providers d''outils : outil absent' {
    It '<Provider> : non conforme sans erreur, valeur d''origine lisible' -ForEach @(
        @{ Provider = 'fnm-node'; Tool = 'fnm'; Action = @{} }
        @{ Provider = 'npm-global'; Tool = 'npm'; Action = @{ package = 'typescript' } }
        @{ Provider = 'rtk-init'; Tool = 'rtk'; Action = @{} }
    ) {
        InModuleScope OSSetup -Parameters @{ Provider = $Provider; Tool = $Tool; Action = $Action } {
            param($Provider, $Tool, $Action)
            # Une fonction du même nom (ex. simulation) ne compte pas : seule une application installée fait foi.
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq $Tool -and $CommandType -eq 'Application' }
            $provider = Get-OSSetupProvider -Name $Provider
            & $provider.Test $Action @{} | Should -BeFalse
            if ($provider.ContainsKey('Read')) { { & $provider.Read $Action @{} } | Should -Not -Throw }
        }
    }
}

Describe 'Provider rtk-init : refus des statistiques' {
    BeforeAll {
        $script:rtkStub = -not (Get-Command -Name rtk -ErrorAction SilentlyContinue)
        if ($script:rtkStub) {
            function global:rtk { }
        }
    }

    AfterAll {
        if ($script:rtkStub) { Remove-Item -Path Function:\rtk -ErrorAction SilentlyContinue }
    }

    It 'échoue avec la cause quand rtk telemetry disable échoue, sans lancer rtk init' {
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName rtk -MockWith {
            if ($args -contains 'status') { $global:LASTEXITCODE = 0; return 'consent: never asked' }
            $global:LASTEXITCODE = 2
        }
        { InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'rtk-init').Invoke @{} @{} } } | Should -Throw '*rtk telemetry disable*2*'
        Should -Invoke -ModuleName OSSetup -CommandName rtk -Times 0 -Exactly -ParameterFilter { $args -contains 'init' }
    }
}

Describe 'Provider windows-update : description' {
    It 'nomme la catégorie de l''action' {
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'windows-update'
            Mock -CommandName Find-OSSetupWindowsUpdate
            & $provider.Describe @{ category = 'drivers' } @{} | Should -Be 'Windows Update (pilotes) : rien à installer'
            Mock -CommandName Find-OSSetupWindowsUpdate -MockWith { [pscustomobject]@{ Title = 'Pilote A' }; [pscustomobject]@{ Title = 'Pilote B' } }
            & $provider.Describe @{ category = 'drivers' } @{} | Should -Be 'Windows Update (pilotes) : installer 2 mise(s) à jour : Pilote A ; Pilote B'
        }
    }
}

Describe 'Provider vscode-extension : liste des extensions' {
    BeforeAll {
        # Pester ne simule qu'une commande existante : des fonctions vides remplacent les éditeurs absents.
        $script:editorStubs = @('code', 'cursor' | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
        foreach ($stub in $script:editorStubs) { New-Item -Path "Function:\global:$stub" -Value {} | Out-Null }
    }

    AfterAll {
        foreach ($stub in $script:editorStubs) { Remove-Item -Path "Function:\$stub" -ErrorAction SilentlyContinue }
    }

    It 'lit la liste une fois par passe et par éditeur, puis la relit après Clear-OSSetupStateCache' {
        InModuleScope OSSetup {
            Clear-OSSetupStateCache
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = "$Name.cmd" } } -ParameterFilter { $Name -in 'code', 'cursor' }
            Mock -CommandName code -MockWith { 'dbaeumer.vscode-eslint'; 'esbenp.prettier-vscode' }
            Mock -CommandName cursor -MockWith { 'dbaeumer.vscode-eslint' }
            $provider = Get-OSSetupProvider -Name 'vscode-extension'
            & $provider.Test @{ id = 'dbaeumer.vscode-eslint' } @{} | Should -BeTrue
            & $provider.Test @{ id = 'esbenp.prettier-vscode' } @{} | Should -BeTrue
            & $provider.Test @{ id = 'ms-python.python' } @{} | Should -BeFalse
            & $provider.Test @{ id = 'esbenp.prettier-vscode'; editor = 'cursor' } @{} | Should -BeFalse
            & $provider.Test @{ id = 'dbaeumer.vscode-eslint'; editor = 'cursor' } @{} | Should -BeTrue
            Should -Invoke -CommandName code -Times 1 -Exactly
            Should -Invoke -CommandName cursor -Times 1 -Exactly

            Clear-OSSetupStateCache
            & $provider.Test @{ id = 'dbaeumer.vscode-eslint' } @{} | Should -BeTrue
            Should -Invoke -CommandName code -Times 2 -Exactly
            Clear-OSSetupStateCache
        }
    }
}

Describe 'Provider windows-feature : fonctionnalité inexistante' {
    It 'ne journalise son absence qu''une fois, quel que soit le nombre de tests' {
        InModuleScope OSSetup {
            $script:LoggedOnce.Clear()
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName Test-OSSetupElevated -MockWith { $false }
            Mock -CommandName Get-CimInstance
            $provider = Get-OSSetupProvider -Name 'windows-feature'
            foreach ($i in 1..3) { & $provider.Test @{ name = 'MicrosoftWindowsPowerShellV2Root'; enabled = $false } @{} | Should -BeTrue }
            Should -Invoke -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like '*MicrosoftWindowsPowerShellV2Root inexistante*' }
            $script:LoggedOnce.Clear()
        }
    }
}

Describe 'Providers path et startup-entry : portée' {
    It 'path transmet la portée du catalogue, compte par défaut' {
        InModuleScope OSSetup {
            Mock -CommandName Get-OSSetupPathEntry -MockWith { 'C:\Outils\' }
            $provider = Get-OSSetupProvider -Name 'path'
            & $provider.Test @{ path = 'C:\Outils' } @{} | Should -BeTrue
            Should -Invoke -CommandName Get-OSSetupPathEntry -Times 1 -Exactly -ParameterFilter { $Scope -eq 'User' }
            & $provider.Test @{ path = 'C:\Outils'; scope = 'machine' } @{} | Should -BeTrue
            Should -Invoke -CommandName Get-OSSetupPathEntry -Times 1 -Exactly -ParameterFilter { $Scope -eq 'Machine' }
        }
    }

    It 'startup-entry transmet la portée du catalogue, compte par défaut' {
        InModuleScope OSSetup {
            Mock -CommandName Get-OSSetupStartupEntry
            $provider = Get-OSSetupProvider -Name 'startup-entry'
            & $provider.Test @{ name = 'Discord' } @{} | Should -BeTrue
            & $provider.Test @{ name = 'Discord'; scope = 'machine' } @{} | Should -BeTrue
            Should -Invoke -CommandName Get-OSSetupStartupEntry -Times 1 -Exactly -ParameterFilter { $Scope -eq 'user' }
            Should -Invoke -CommandName Get-OSSetupStartupEntry -Times 1 -Exactly -ParameterFilter { $Scope -eq 'machine' }
        }
    }
}

Describe 'Provider herdr-plugin' {
    BeforeAll {
        # Pester ne simule qu'une commande existante : une fonction vide remplace herdr là où il manque (ex. runner CI).
        $script:herdrStub = -not (Get-Command -Name herdr -ErrorAction SilentlyContinue)
        if ($script:herdrStub) {
            function global:herdr { }
        }
        $script:savedAppData = $env:APPDATA
    }

    AfterAll {
        if ($script:herdrStub) { Remove-Item -Path Function:\herdr -ErrorAction SilentlyContinue }
        $env:APPDATA = $script:savedAppData
    }

    BeforeEach {
        $env:APPDATA = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path (Join-Path -Path $env:APPDATA -ChildPath 'herdr') -ItemType Directory -Force | Out-Null
        $pluginsPath = Join-Path -Path $env:APPDATA -ChildPath 'herdr\plugins.json'
        $action = @{ repo = 'gcaudan/herdr-explorer'; id = 'gcaudan.explorer' }
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName herdr -MockWith { $global:LASTEXITCODE = 0 }
    }

    It 'est conforme seulement quand le plugin est enregistré et activé' {
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'herdr-plugin' }
        & $provider.Test $action @{} | Should -BeFalse
        Set-Content -Path $pluginsPath -Value '[{ "plugin_id": "gcaudan.explorer", "enabled": false }]'
        & $provider.Test $action @{} | Should -BeFalse
        Set-Content -Path $pluginsPath -Value '[{ "plugin_id": "gcaudan.explorer", "enabled": true }]'
        & $provider.Test $action @{} | Should -BeTrue
    }

    It 'installe un plugin absent, et réactive un plugin désactivé sans le réinstaller' {
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'herdr-plugin' }
        & $provider.Invoke $action @{}
        Should -Invoke -ModuleName OSSetup -CommandName herdr -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'plugin install gcaudan/herdr-explorer --yes' }

        Set-Content -Path $pluginsPath -Value '[{ "plugin_id": "gcaudan.explorer", "enabled": false }]'
        & $provider.Invoke $action @{}
        Should -Invoke -ModuleName OSSetup -CommandName herdr -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'plugin enable gcaudan.explorer' }
        Should -Invoke -ModuleName OSSetup -CommandName herdr -Times 2 -Exactly
    }
}

Describe 'Provider registry' {
    # TestRegistry: clé jetable de Pester (sous HKCU:\Software\Pester), supprimée à la fin du bloc.
    BeforeEach {
        $key = "TestRegistry:\$([guid]::NewGuid())"
        New-Item -Path $key | Out-Null
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'registry' }
    }

    It 'n''est pas conforme quand la valeur a la bonne donnée mais un autre type, et la remplace' {
        New-ItemProperty -Path $key -Name 'Flag' -PropertyType String -Value '0' | Out-Null
        $action = @{ path = $key; name = 'Flag'; type = 'DWord'; value = 0 }
        & $provider.Test $action @{} | Should -BeFalse
        & $provider.Invoke $action @{}
        (Get-Item -Path $key).GetValueKind('Flag') | Should -Be 'DWord'
        & $provider.Test $action @{} | Should -BeTrue
    }

    It 'écrit et reconnaît un DWord au-delà de 0x7FFFFFFF, sous forme signée ou non' {
        $action = @{ path = $key; name = 'Big'; type = 'DWord'; value = 4294967295 }
        & $provider.Test $action @{} | Should -BeFalse
        & $provider.Invoke $action @{}
        (Get-Item -Path $key).GetValue('Big') | Should -Be -1
        & $provider.Test $action @{} | Should -BeTrue
        & $provider.Test @{ path = $key; name = 'Big'; type = 'DWord'; value = -1 } @{} | Should -BeTrue
        & $provider.Test @{ path = $key; name = 'Big'; type = 'DWord'; value = 4294967294 } @{} | Should -BeFalse
    }

    It 'compare les QWord non signés' {
        $action = @{ path = $key; name = 'Q'; type = 'QWord'; value = [decimal]::Parse('18446744073709551615') }
        & $provider.Invoke $action @{}
        (Get-Item -Path $key).GetValue('Q') | Should -Be ([long]-1)
        & $provider.Test $action @{} | Should -BeTrue
    }

    It 'compare toujours les chaînes à la casse près' {
        New-ItemProperty -Path $key -Name 'Text' -PropertyType String -Value 'Abc' | Out-Null
        & $provider.Test @{ path = $key; name = 'Text'; type = 'String'; value = 'Abc' } @{} | Should -BeTrue
        & $provider.Test @{ path = $key; name = 'Text'; type = 'String'; value = 'abc' } @{} | Should -BeFalse
        & $provider.Test @{ path = $key; name = 'Text'; type = 'ExpandString'; value = 'Abc' } @{} | Should -BeFalse
    }
}

Describe 'Provider registry : écriture puis vérification de chaque type' {
    # TestRegistry: clé jetable de Pester (sous HKCU:\Software\Pester), supprimée à la fin du bloc.
    BeforeEach {
        $key = "TestRegistry:\$([guid]::NewGuid())"
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'registry' }
    }

    It '<Type> : conforme après écriture, avec le type et la donnée attendus' -ForEach @(
        @{ Type = 'DWord'; Value = 1; Other = 2 }
        @{ Type = 'QWord'; Value = 5000000000; Other = 5000000001 }
        @{ Type = 'String'; Value = 'Valeur à accents'; Other = 'valeur à accents' }
        # Variable non développée : la donnée écrite et relue est le texte brut.
        @{ Type = 'ExpandString'; Value = '%LOCALAPPDATA%\CrashDumps'; Other = '%LOCALAPPDATA%\crashdumps' }
        # Tableau lu dans le JSON du catalogue ; l'ordre et la casse comptent.
        @{ Type = 'MultiString'; Value = [object[]]@('Premier', 'Second élément', '%TEMP%'); Other = [object[]]@('Second élément', 'Premier', '%TEMP%') }
        @{ Type = 'MultiString'; Value = [object[]]@('Seul'); Other = [object[]]@('seul') }
    ) {
        $action = @{ path = $key; name = 'V'; type = $Type; value = $Value }
        & $provider.Test $action @{} | Should -BeFalse
        & $provider.Invoke $action @{}
        & $provider.Test $action @{} | Should -BeTrue
        $read = & $provider.Read $action @{}
        $read['type'] | Should -Be $Type
        @($read['value']) | Should -Be @($Value)
        & $provider.Test @{ path = $key; name = 'V'; type = $Type; value = $Other } @{} | Should -BeFalse
    }
}

Describe 'ConvertTo-OSSetupRegistryNumber' {
    It 'convertit <Value> (<Type>) en <Signed> signé et <Unsigned> non signé' -ForEach @(
        @{ Value = 0; Type = 'DWord'; Signed = 0; Unsigned = 0 }
        @{ Value = 4294967295; Type = 'DWord'; Signed = -1; Unsigned = 4294967295 }
        @{ Value = -1; Type = 'DWord'; Signed = -1; Unsigned = 4294967295 }
        @{ Value = 2147483648; Type = 'DWord'; Signed = -2147483648; Unsigned = 2147483648 }
        @{ Value = -1; Type = 'QWord'; Signed = -1; Unsigned = [uint64]::MaxValue }
    ) {
        InModuleScope OSSetup -Parameters $_ {
            param($Value, $Type, $Signed, $Unsigned)
            ConvertTo-OSSetupRegistryNumber -Value $Value -Type $Type | Should -Be $Signed
            ConvertTo-OSSetupRegistryNumber -Value $Value -Type $Type -Unsigned | Should -Be $Unsigned
        }
    }

    It 'refuse une valeur hors limites ou non entière' {
        InModuleScope OSSetup {
            { ConvertTo-OSSetupRegistryNumber -Value 4294967296 -Type DWord } | Should -Throw '*hors limites*'
            { ConvertTo-OSSetupRegistryNumber -Value 1.5 -Type DWord } | Should -Throw '*hors limites*'
        }
    }
}

Describe 'Provider shortcut : suppression' {
    It 'sauvegarde le raccourci avant de le supprimer' {
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        $path = Join-Path -Path $root -ChildPath 'Bureau\App.lnk'
        New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $path -Value 'lnk' -NoNewline
        $context = @{ BackupRoot = Join-Path -Path $root -ChildPath 'backups' }
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        InModuleScope OSSetup -Parameters @{ Path = $path; Context = $context } {
            param($Path, $Context)
            & (Get-OSSetupProvider -Name 'shortcut').Invoke @{ path = $Path; present = $false } $Context
        }
        $path | Should -Not -Exist
        $backups = @(Get-ChildItem -Path $context.BackupRoot -Recurse -File)
        $backups.Count | Should -Be 1
        $backups[0].Name | Should -Be 'App.lnk'
        Get-Content -Path $backups[0].FullName -Raw | Should -Be 'lnk'
    }
}

Describe 'Provider shortcut : copie' {
    BeforeEach {
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        $from = Join-Path -Path $root -ChildPath 'Menu\App.lnk'
        $path = Join-Path -Path $root -ChildPath 'Bureau\App.lnk'
        foreach ($file in $from, $path) {
            New-Item -Path (Split-Path -Path $file -Parent) -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path $from -Value 'nouveau' -NoNewline
        Set-Content -Path $path -Value 'ancien' -NoNewline
        $action = @{ path = $path; from = $from }
        $context = @{ BackupRoot = Join-Path -Path $root -ChildPath 'backups' }
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        # Les fichiers de test ne sont pas de vrais raccourcis : la cible est déduite du contenu.
        Mock -ModuleName OSSetup -CommandName Get-OSSetupShortcutTarget -MockWith {
            if ((Get-Content -LiteralPath $Path -Raw) -eq 'nouveau') { 'C:\Program Files\App\app.exe' } else { 'C:\Ailleurs\autre.exe' }
        }
    }

    It 'n''est pas conforme quand un raccourci du même nom pointe ailleurs, et le remplace après sauvegarde' {
        InModuleScope OSSetup -Parameters @{ Action = $action; Context = $context } {
            param($Action, $Context)
            $provider = Get-OSSetupProvider -Name 'shortcut'
            & $provider.Test $Action $Context | Should -BeFalse
            (& $provider.Read $Action $Context)['target'] | Should -Be 'C:\Ailleurs\autre.exe'
            & $provider.Invoke $Action $Context
            & $provider.Test $Action $Context | Should -BeTrue
        }
        Get-Content -Path $path -Raw | Should -Be 'nouveau'
        $backups = @(Get-ChildItem -Path $context.BackupRoot -Recurse -File)
        $backups.Count | Should -Be 1
        Get-Content -Path $backups[0].FullName -Raw | Should -Be 'ancien'
    }
}

Describe 'Get-OSSetupShortcutTarget' {
    It 'lit la cible d''un vrai raccourci sans le modifier' {
        $path = Join-Path -Path $TestDrive -ChildPath 'Cible.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = Join-Path -Path $env:SystemRoot -ChildPath 'notepad.exe'
        $shortcut.Save()
        $before = [System.IO.File]::ReadAllBytes($path)
        InModuleScope OSSetup -Parameters @{ Path = $path } { param($Path) Get-OSSetupShortcutTarget -Path $Path } |
            Should -Be (Join-Path -Path $env:SystemRoot -ChildPath 'notepad.exe')
        [System.IO.File]::ReadAllBytes($path) | Should -Be $before
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
            # Formes relevées dans le journal d'une VM : barre et taille sur la même ligne, fin de ligne comprise.
            "  ███▒▒▒▒▒▒▒  1024 KB / 6.48 MB`r"
            '  ██████████   112 MB /  112 MB'
            '  ████▒▒▒▒▒▒  40%'
            '  \'
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

Describe 'Provider git-config : valeur lue' {
    BeforeAll {
        # Pester ne simule qu'une commande existante : une fonction vide remplace git là où il manque (ex. runner CI).
        $script:gitStub = -not (Get-Command -Name git -ErrorAction SilentlyContinue)
        if ($script:gitStub) {
            function global:git { }
        }
    }

    AfterAll {
        if ($script:gitStub) { Remove-Item -Path Function:\git -ErrorAction SilentlyContinue }
    }

    BeforeEach {
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName Get-Command -ParameterFilter { $Name -eq 'git' -and $CommandType -eq 'Application' } -MockWith { 'git.exe' }
        # Avertissement de Git sur la sortie d'erreur (mêlée à la sortie par Invoke-OSSetupNativeCommand), puis la valeur.
        Mock -ModuleName OSSetup -CommandName git -MockWith {
            $global:LASTEXITCODE = 0
            [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('warning: unable to access ''C:/x/.config/git/attributes'''), 'NativeCommandError', 'NotSpecified', $null)
            'Prénom Nom'
        }
    }

    It 'compare et relève la valeur sans les lignes de la sortie d''erreur, sans rien journaliser' {
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'git-config' }
        $action = @{ key = 'user.name'; value = 'Prénom Nom' }
        & $provider.Test $action @{} | Should -BeTrue
        (& $provider.Read $action @{}).value | Should -BeExactly 'Prénom Nom'
        Should -Invoke -ModuleName OSSetup -CommandName git -Times 2 -Exactly -ParameterFilter { ($args -join ' ') -eq 'config --global --get user.name' }
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly
    }
}
