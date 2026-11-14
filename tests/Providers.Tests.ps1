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

Describe 'Provider logon-task : conformité' {
    BeforeAll {
        $script:logonAction = @{ name = 'OS-Setup - test'; script = 'C:\Program Files\OS-Setup\test.ps1'; description = 'Tâche de test.' }
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
