BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    # Outil externe factice : sortie, code de sortie et encodage de la console lus pendant l'appel.
    function global:Invoke-OSSetupTestTool {
        $global:OSSetupTestToolArgs = $args
        $global:OSSetupTestToolEncoding = [Console]::OutputEncoding.WebName
        if ($global:OSSetupTestToolThrow) { throw 'outil en panne' }
        $global:LASTEXITCODE = $global:OSSetupTestToolExitCode
        'première ligne', '', '   ', '|■■■■      | 40 %', 'dernière ligne'
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-OSSetupTestTool -ErrorAction SilentlyContinue
    Remove-Variable -Name OSSetupTestToolArgs, OSSetupTestToolEncoding, OSSetupTestToolThrow, OSSetupTestToolExitCode -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Invoke-OSSetupNativeCommand' {
    BeforeEach {
        $global:OSSetupTestToolExitCode = 0
        $global:OSSetupTestToolThrow = $false
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
    }

    It 'passe les arguments et journalise les lignes non vides en Detail' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -ArgumentList 'install', 'a b'
        @($global:OSSetupTestToolArgs) | Should -Be @('install', 'a b')
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 3 -Exactly -ParameterFilter { $Level -eq 'Detail' }
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  première ligne' }
    }

    It 'ne journalise pas les lignes qui correspondent au filtre' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -LogFilter '^\|'
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 2 -Exactly
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly -ParameterFilter { $Message -match '\|' }
    }

    It 'lève une exception avec le code de sortie en cas d''échec' {
        $global:OSSetupTestToolExitCode = 3
        { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -ArgumentList 'install' } |
            Should -Throw 'Invoke-OSSetupTestTool install a échoué (code 3).'
        { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Label 'outil factice' } |
            Should -Throw 'outil factice a échoué (code 3).'
    }

    It 'avec -NoThrow, retourne le code de sortie sans exception' {
        $global:OSSetupTestToolExitCode = 5
        $result = Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -NoThrow -PassThru
        $result.ExitCode | Should -Be 5
        $result.Output | Should -Contain 'dernière ligne'
    }

    It 'ne retourne rien sans -PassThru' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool | Should -BeNullOrEmpty
    }

    It 'passe la console en UTF-8 le temps de l''appel avec -Utf8, et restaure l''encodage, même en cas d''exception' {
        $before = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
            Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Utf8
            $global:OSSetupTestToolEncoding | Should -Be 'utf-8'
            [Console]::OutputEncoding.CodePage | Should -Be 850

            $global:OSSetupTestToolThrow = $true
            { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Utf8 } | Should -Throw '*outil en panne*'
            [Console]::OutputEncoding.CodePage | Should -Be 850
        }
        finally {
            [Console]::OutputEncoding = $before
        }
    }

    It 'sans -Utf8, ne change pas l''encodage de la console' {
        $before = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
            Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool
            $global:OSSetupTestToolEncoding | Should -Not -Be 'utf-8'
        }
        finally {
            [Console]::OutputEncoding = $before
        }
    }
}

Describe 'Invoke-OSSetupUnelevatedCommand' -Skip:(-not $IsWindows) {
    # Aucune tâche planifiée réelle : enregistrement, lancement, état et suppression sont simulés. Le lancement simulé
    # écrit ce qu'écrirait l'enveloppe (journal, code de sortie), ou l'exécute réellement avec Windows PowerShell 5.1.
    BeforeEach {
        $workRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $workRoot -ItemType Directory | Out-Null
        $child = @{ Mode = 'fake'; Lines = @('première ligne', '', 'installé ✓'); ExitCode = '0' }
        $taskState = 'Running'
        $global:OSSetupTestWrapper = $null
        $global:OSSetupTestCommandBytes = $null
        Mock -ModuleName OSSetup Write-OSSetupLog
        Mock -ModuleName OSSetup Register-ScheduledTask
        Mock -ModuleName OSSetup Unregister-ScheduledTask
        Mock -ModuleName OSSetup Stop-ScheduledTask
        Mock -ModuleName OSSetup Start-Sleep
        # Recherche des restes d'une exécution précédente (nom générique) : aucun.
        Mock -ModuleName OSSetup Get-ScheduledTask { if ("$TaskName".EndsWith('*')) { return }; [pscustomobject]@{ TaskName = $TaskName; State = $taskState } }
        Mock -ModuleName OSSetup Start-ScheduledTask {
            $work = @(Get-ChildItem -Path $workRoot -Directory)
            $wrapper = Join-Path -Path $work[0].FullName -ChildPath 'run.ps1'
            $global:OSSetupTestWrapper = Get-Content -Path $wrapper -Raw
            $global:OSSetupTestCommandBytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $work[0].FullName -ChildPath 'command.ps1'))
            switch ($child.Mode) {
                'fake' {
                    Set-Content -Path (Join-Path -Path $work[0].FullName -ChildPath 'output.log') -Value $child.Lines -Encoding utf8
                    Set-Content -Path (Join-Path -Path $work[0].FullName -ChildPath 'exitcode.txt') -Value $child.ExitCode
                }
                'real' {
                    $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
                    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper | Out-Null
                }
            }
        }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestWrapper, OSSetupTestCommandBytes -Scope Global -ErrorAction SilentlyContinue
    }

    It 'enregistre une tâche ponctuelle à jeton limité au nom de l''utilisateur, recopie la sortie et nettoie' {
        Invoke-OSSetupUnelevatedCommand -Command "Write-Output 'ok'" -Label 'le script' -WorkRoot $workRoot

        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $Principal.RunLevel -eq 'Limited' -and $Principal.LogonType -eq 'Interactive' -and $Principal.UserId -eq $user -and
            -not $Trigger -and $Action[0].Execute -like '*\WindowsPowerShell\v1.0\powershell.exe' -and $Action[0].Arguments -match 'run\.ps1' -and
            $Action[0].WorkingDirectory -eq [Environment]::GetFolderPath('UserProfile')
        }
        Should -Invoke -ModuleName OSSetup Start-ScheduledTask -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 2 -Exactly -ParameterFilter { $Level -eq 'Detail' }
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  installé ✓' }
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -match '^OS-Setup - sans droits administrateur \([0-9a-f]{8}\)$' }
        @(Get-ChildItem -Path $workRoot -Force) | Should -BeNullOrEmpty
    }

    It 'passe la commande telle quelle à l''enfant (script lancé par -File, UTF-8 avec BOM), sortie en UTF-8' {
        $command = "Invoke-RestMethod -Uri 'https://example.test/it''s.ps1' | Invoke-Expression"
        Invoke-OSSetupUnelevatedCommand -Command $command -Label 'le script' -WorkRoot $workRoot
        $global:OSSetupTestWrapper | Should -Match '-File ''[^'']+\\command\.ps1'' 2>&1'
        $global:OSSetupTestCommandBytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [System.Text.Encoding]::UTF8.GetString($global:OSSetupTestCommandBytes, 3, $global:OSSetupTestCommandBytes.Length - 3) |
            Should -Be "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`r`n$command`r`n"
    }

    It 'lève une exception avec le code de sortie, après avoir recopié la sortie et nettoyé' {
        $child.ExitCode = '3'
        { Invoke-OSSetupUnelevatedCommand -Command 'exit 3' -Label 'le script' -WorkRoot $workRoot } | Should -Throw 'le script a échoué (code 3).'
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  première ligne' }
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly
        @(Get-ChildItem -Path $workRoot -Force) | Should -BeNullOrEmpty
    }

    It 'passé le délai, laisse la commande finir en arrière-plan (ni arrêt ni suppression) et échoue comme non terminée' {
        $child.Mode = 'none'
        { Invoke-OSSetupUnelevatedCommand -Command 'Start-Sleep 60' -Label 'le script' -TimeoutSeconds 0 -WorkRoot $workRoot } |
            Should -Throw "le script non terminé après 0 s : il continue en arrière-plan (tâche « OS-Setup - sans droits administrateur (*) ») ; relancer le setup une fois qu'il a fini pour vérifier."
        Should -Invoke -ModuleName OSSetup Stop-ScheduledTask -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 0 -Exactly
        @(Get-ChildItem -Path $workRoot -Directory).Name | Should -Match '^os-setup-[0-9a-f]{32}$'
    }

    It 'laisse la tâche s''arrêter d''elle-même au bout de 4 h au moins, au-delà du délai d''attente' {
        Invoke-OSSetupUnelevatedCommand -Command 'x' -Label 'le script' -WorkRoot $workRoot
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            [System.Xml.XmlConvert]::ToTimeSpan($Settings.ExecutionTimeLimit) -eq [TimeSpan]::FromHours(4)
        }
    }

    It 'signale une commande toujours en cours à chaque intervalle' {
        $child.Mode = 'none'
        Mock -ModuleName OSSetup Start-Sleep {
            $work = @(Get-ChildItem -Path $workRoot -Directory)[0].FullName
            if ($global:OSSetupTestSleeps++ -ge 1) { Set-Content -Path (Join-Path -Path $work -ChildPath 'exitcode.txt') -Value '0' }
        }
        $global:OSSetupTestSleeps = 0
        Invoke-OSSetupUnelevatedCommand -Command 'x' -Label 'le script' -ProgressSeconds 0 -WorkRoot $workRoot
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  le script : toujours en cours (0 min)' }
        Remove-Variable -Name OSSetupTestSleeps -Scope Global
    }

    It 'échoue sans attendre la fin du délai quand la tâche s''arrête sans code de sortie' {
        $child.Mode = 'none'
        $taskState = 'Ready'
        { Invoke-OSSetupUnelevatedCommand -Command 'x' -Label 'le script' -StartGraceSeconds 0 -WorkRoot $workRoot } |
            Should -Throw '*sans code de sortie*'
        Should -Invoke -ModuleName OSSetup Stop-ScheduledTask -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly
    }

    It 'nettoie même quand l''enregistrement de la tâche échoue' {
        Mock -ModuleName OSSetup Register-ScheduledTask { throw 'accès refusé' }
        { Invoke-OSSetupUnelevatedCommand -Command 'x' -Label 'le script' -WorkRoot $workRoot } | Should -Throw '*accès refusé*'
        Should -Invoke -ModuleName OSSetup Start-ScheduledTask -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly
        @(Get-ChildItem -Path $workRoot -Force) | Should -BeNullOrEmpty
    }

    It 'avec -WhatIf, n''enregistre ni ne lance rien' {
        Invoke-OSSetupUnelevatedCommand -Command 'x' -Label 'le script' -WorkRoot $workRoot -WhatIf
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Start-ScheduledTask -Times 0 -Exactly
        @(Get-ChildItem -Path $workRoot -Force) | Should -BeNullOrEmpty
    }

    It 'l''enveloppe, exécutée par Windows PowerShell 5.1, écrit la sortie (accents compris) et le code de sortie de l''enfant' {
        $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -Path $powershell)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 absent'; return }
        $child.Mode = 'real'
        { Invoke-OSSetupUnelevatedCommand -Command "Write-Output 'déjà installé'; [Console]::Error.WriteLine('avertissement'); exit 4" -Label 'le script' -WorkRoot $workRoot } |
            Should -Throw 'le script a échoué (code 4).'
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  déjà installé' }
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -match 'avertissement' }

        $child.Mode = 'real'
        Invoke-OSSetupUnelevatedCommand -Command "Write-Output 'fini'" -Label 'le script' -WorkRoot $workRoot
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  fini' }
        @(Get-ChildItem -Path $workRoot -Force) | Should -BeNullOrEmpty
    }
}

Describe 'Clear-OSSetupUnelevatedLeftover' -Skip:(-not $IsWindows) {
    # Restes d'une commande qui avait dépassé le délai : tâches et dossiers simulés.
    BeforeEach {
        $workRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $running = Join-Path -Path $workRoot -ChildPath "os-setup-$('a' * 32)"
        $finished = Join-Path -Path $workRoot -ChildPath "os-setup-$('b' * 32)"
        $other = Join-Path -Path $workRoot -ChildPath 'os-setup-winget'
        foreach ($folder in $running, $finished, $other) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
        Mock -ModuleName OSSetup Unregister-ScheduledTask
        Mock -ModuleName OSSetup Get-ScheduledTask {
            [pscustomobject]@{ TaskName = 'OS-Setup - sans droits administrateur (aaaaaaaa)'; State = 'Running'
                Actions = @([pscustomobject]@{ Arguments = "-NoProfile -File `"$running\run.ps1`"" }) }
            [pscustomobject]@{ TaskName = 'OS-Setup - sans droits administrateur (bbbbbbbb)'; State = 'Ready'
                Actions = @([pscustomobject]@{ Arguments = "-NoProfile -File `"$finished\run.ps1`"" }) }
        }
    }

    It 'supprime les tâches terminées et les dossiers inutilisés, garde une commande encore en cours et son dossier' {
        Clear-OSSetupUnelevatedLeftover -WorkRoot $workRoot -Confirm:$false
        Should -Invoke -ModuleName OSSetup Get-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'OS-Setup - sans droits administrateur*' }
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'OS-Setup - sans droits administrateur (bbbbbbbb)' }
        $running | Should -Exist
        $finished | Should -Not -Exist
        $other | Should -Exist
    }

    It 'avec -WhatIf, ne supprime rien' {
        Clear-OSSetupUnelevatedLeftover -WorkRoot $workRoot -WhatIf
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 0 -Exactly
        $finished | Should -Exist
    }
}

Describe 'Provider install-script' {
    BeforeEach {
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'install-script' }
        Mock -ModuleName OSSetup Invoke-OSSetupUnelevatedCommand
        Mock -ModuleName OSSetup Invoke-OSSetupNativeCommand
        Mock -ModuleName OSSetup Update-OSSetupSessionPath
    }

    It 'exécute le script de l''éditeur sans droits administrateur, puis relit le PATH' {
        & $provider.Invoke ([ordered]@{ provider = 'install-script'; url = "https://example.test/it's.ps1"; command = 'tool' }) @{}
        Should -Invoke -ModuleName OSSetup Invoke-OSSetupUnelevatedCommand -Times 1 -Exactly -ParameterFilter {
            $Command -eq "`$ProgressPreference = 'SilentlyContinue'; Invoke-RestMethod -Uri 'https://example.test/it''s.ps1' | Invoke-Expression" -and
            $Label -eq "le script d'installation"
        }
        Should -Invoke -ModuleName OSSetup Invoke-OSSetupNativeCommand -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Update-OSSetupSessionPath -Times 1 -Exactly
    }

    It 'propage l''échec du script' {
        Mock -ModuleName OSSetup Invoke-OSSetupUnelevatedCommand { throw "le script d'installation a échoué (code 1)." }
        { & $provider.Invoke ([ordered]@{ provider = 'install-script'; url = 'https://example.test/i.ps1'; command = 'tool' }) @{} } |
            Should -Throw '*code 1*'
    }
}
