BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    function New-TestClone {
        # Faux dépôt laissé par le bootstrap : journal, réponses, sauvegardes, bootstrap.json, src/cleanup.ps1.
        param([bool]$OwnsClone, [string[]]$InstalledTool = @(), [string]$RunId = 'r1',
            [string]$BootstrapScript = (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'bootstrap.ps1'))
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path "$root\logs", "$root\state\backups\$RunId", "$root\src" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$root\logs\setup-$RunId.log" -Value 'journal'
        Set-Content -Path "$root\state\answers-last.json" -Value '{}'
        Set-Content -Path "$root\state\backups\$RunId\config.txt" -Value 'ancienne config'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
        @{ ownsClone = $OwnsClone; bootstrapScript = $BootstrapScript; installedTools = $InstalledTool } |
            ConvertTo-Json | Set-Content -Path "$root\state\bootstrap.json"
        $root
    }

    function Get-LaunchedConfig {
        # Configuration passée au processus de nettoyage (dernier lancement capturé).
        $path = $global:OSSetupTestCleanupArgs[-1].Trim('"')
        Get-Content -Path $path -Raw | ConvertFrom-Json
    }
}

Describe 'Get-OSSetupToolToRemove' {
    It 'retire les outils du bootstrap qu''aucun élément retenu n''installe' {
        Get-OSSetupToolToRemove -InstalledTool 'Git.Git', 'Microsoft.PowerShell' -SelectedWingetId 'Microsoft.PowerShell', 'Vivaldi.Vivaldi' |
            Should -Be @('Git.Git')
    }

    It 'garde le PowerShell noté par un ancien bootstrap quand celui du Store est retenu' {
        Get-OSSetupToolToRemove -InstalledTool 'Git.Git', 'Microsoft.PowerShell' -SelectedWingetId '9MZ1SNWT0N5D' |
            Should -Be @('Git.Git')
    }

    It 'ne retire rien si le bootstrap n''a rien installé' {
        Get-OSSetupToolToRemove -InstalledTool @() -SelectedWingetId @() | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSSetupSelectedWingetId' {
    It 'liste les paquets winget des éléments retenus' {
        $data = [pscustomobject]@{
            Items = @{
                git  = @{ actions = @(@{ provider = 'winget'; id = 'Git.Git' }) }
                dark = @{ actions = @(@{ provider = 'registry'; path = 'HKCU:\x' }) }
            }
        }
        Get-OSSetupSelectedWingetId -Data $data -ItemId 'git', 'dark' | Should -Be @('Git.Git')
    }
}

Describe 'Test-OSSetupRemovableBootstrapScript' {
    It 'accepte un .ps1 posé dans %TEMP%' {
        Test-OSSetupRemovableBootstrapScript -Path (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'bootstrap.ps1') | Should -BeTrue
    }

    It 'accepte un .ps1 posé dans Téléchargements' {
        Mock -ModuleName OSSetup Get-ItemPropertyValue { 'C:\Users\test\Downloads' }
        Test-OSSetupRemovableBootstrapScript -Path 'C:\Users\test\Downloads\bootstrap.ps1' | Should -BeTrue
    }

    It 'refuse <Case>' -ForEach @(
        @{ Case = 'un autre dossier'; Path = 'C:\Windows\System32\bootstrap.ps1' }
        @{ Case = 'un sous-dossier de %TEMP%'; Path = (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'x\bootstrap.ps1') }
        @{ Case = 'un fichier autre que .ps1'; Path = (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'bootstrap.exe') }
        @{ Case = 'une remontée hors de %TEMP%'; Path = (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath '..\bootstrap.ps1') }
        @{ Case = 'un chemin relatif'; Path = 'bootstrap.ps1' }
        @{ Case = 'un chemin vide'; Path = '' }
    ) {
        Test-OSSetupRemovableBootstrapScript -Path $Path | Should -BeFalse
    }
}

Describe 'Invoke-OSSetupCleanup' {
    BeforeEach {
        $global:OSSetupTestCleanupArgs = $null
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Mock -ModuleName OSSetup Start-Process { $global:OSSetupTestCleanupArgs = $ArgumentList }
        $historyRoot = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'OS-Setup'
        # Jamais Program Files pendant les tests : le script et sa configuration vont dans TestDrive.
        $PSDefaultParameterValues['Invoke-OSSetupCleanup:WorkRoot'] = Join-Path -Path $TestDrive -ChildPath 'cleanup-work'
    }

    AfterEach {
        if ($global:OSSetupTestCleanupArgs) {
            $config = Get-LaunchedConfig
            Remove-Item -Path $global:OSSetupTestCleanupArgs[-1].Trim('"'), $global:OSSetupTestCleanupArgs[-3].Trim('"') -Force -ErrorAction SilentlyContinue
            # Seul un historique créé par le test (dossier de l'exécution sous %LOCALAPPDATA%\OS-Setup) est supprimé.
            if ($config.logPath -and $config.logPath.StartsWith($historyRoot)) {
                Remove-Item -Path (Split-Path -Path $config.logPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-Variable -Name OSSetupTestCleanupArgs -Scope Global -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove('Invoke-OSSetupCleanup:WorkRoot')
    }

    It 'prépare le script et sa configuration dans le dossier réservé aux administrateurs, pas dans %TEMP%' {
        $PSDefaultParameterValues.Remove('Invoke-OSSetupCleanup:WorkRoot')
        $command = Get-Command -Name Invoke-OSSetupCleanup
        $default = $command.ScriptBlock.Ast.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'WorkRoot' }
        $default.DefaultValue.Extent.Text | Should -Match "GetFolderPath\('ProgramFiles'\), 'OS-Setup', 'cleanup'"
    }

    It 'lit le script et la trace du bootstrap dans CodeRoot (copie de la reprise), pas dans le dépôt' {
        $runId = "test-$([guid]::NewGuid().ToString('N'))"
        $root = New-TestClone -OwnsClone $true -InstalledTool 'Git.Git' -RunId $runId
        $code = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path "$code\src", "$code\state" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$code\src\cleanup.ps1" -Value '# copie de la reprise'
        Copy-Item -Path "$root\state\bootstrap.json" -Destination "$code\state\bootstrap.json"
        # Trace du dépôt modifiée après la copie : elle ne doit pas être suivie.
        $frozenScript = (Get-Content -Path "$code\state\bootstrap.json" -Raw | ConvertFrom-Json).bootstrapScript
        @{ ownsClone = $true; bootstrapScript = (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'autre.ps1'); installedTools = @('Autre.Outil') } |
            ConvertTo-Json | Set-Content -Path "$root\state\bootstrap.json"
        Invoke-OSSetupCleanup -Root $root -CodeRoot $code -RunId $runId -SelectedWingetId @() -Yes
        Get-Content -Path $global:OSSetupTestCleanupArgs[-3].Trim('"') -Raw | Should -Match 'copie de la reprise'
        $config = Get-LaunchedConfig
        $config.uninstall | Should -Be @('Git.Git')
        $config.remove | Should -Be @($root, $frozenScript)
    }

    It 'ne fait rien sans trace du bootstrap (clone de développement)' {
        $root = Join-Path -Path $TestDrive -ChildPath 'dev-clone'
        New-Item -Path $root -ItemType Directory -Force | Out-Null
        Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId @() -Yes
        Should -Invoke -ModuleName OSSetup Start-Process -Times 0 -Exactly
    }

    It 'sur un clone de développement, lance seulement la fermeture de session demandée' {
        $root = Join-Path -Path $TestDrive -ChildPath 'dev-clone-logoff'
        New-Item -Path "$root\src" -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
        Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId @() -Yes -Logoff
        $config = Get-LaunchedConfig
        $config.logoff | Should -BeTrue
        $config.uninstall | Should -BeNullOrEmpty
        $config.remove | Should -BeNullOrEmpty
    }

    It 'avec -Yes, garde l''historique puis supprime la copie du dépôt et le bootstrap' {
        $runId = "test-$([guid]::NewGuid().ToString('N'))"
        $root = New-TestClone -OwnsClone $true -InstalledTool 'Git.Git' -RunId $runId
        Invoke-OSSetupCleanup -Root $root -RunId $runId -SelectedWingetId 'Git.Git' -Yes
        $config = Get-LaunchedConfig
        $config.remove | Should -Be @($root, (Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'bootstrap.ps1'))
        $config.uninstall | Should -BeNullOrEmpty
        $config.waitPid | Should -Be $PID
        Test-Path -Path (Join-Path -Path $historyRoot -ChildPath "$runId\setup-$runId.log") | Should -BeTrue
        Test-Path -Path (Join-Path -Path $historyRoot -ChildPath "$runId\backups\config.txt") | Should -BeTrue
    }

    It 'ne supprime pas un script du bootstrap noté hors de %TEMP% et de Téléchargements' {
        $runId = "test-$([guid]::NewGuid().ToString('N'))"
        $root = New-TestClone -OwnsClone $true -RunId $runId -BootstrapScript 'C:\Windows\System32\drivers\etc\hosts.ps1'
        Invoke-OSSetupCleanup -Root $root -RunId $runId -SelectedWingetId @() -Yes
        (Get-LaunchedConfig).remove | Should -Be @($root)
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*Script du bootstrap conservé*' }
    }

    It 'sur une copie qui n''appartient pas au bootstrap, désinstalle seulement les outils non choisis' {
        $root = New-TestClone -OwnsClone $false -InstalledTool 'Git.Git', 'Microsoft.PowerShell'
        $setupLog = Join-Path -Path $TestDrive -ChildPath 'setup-r1.log'
        InModuleScope OSSetup -Parameters @{ Path = $setupLog } { param($Path) $script:LogPath = $Path }
        try {
            Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId 'Microsoft.PowerShell' -Yes
        }
        finally {
            InModuleScope OSSetup { $script:LogPath = $null }
        }
        $config = Get-LaunchedConfig
        $config.uninstall | Should -Be @('Git.Git')
        $config.remove | Should -BeNullOrEmpty
        # Le dépôt reste en place : le résultat du nettoyage va dans son journal.
        $config.logPath | Should -Be $setupLog
    }

    It 'ne désinstalle rien si la liste des éléments retenus est inconnue' {
        $root = New-TestClone -OwnsClone $false -InstalledTool 'Git.Git'
        Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId $null -Yes
        Should -Invoke -ModuleName OSSetup Start-Process -Times 0 -Exactly
    }

    It 'garde tout si l''utilisateur le choisit' {
        Mock -ModuleName OSSetup Read-OSSetupMenu { @{ Action = 'next'; Values = @('keep') } }
        $root = New-TestClone -OwnsClone $true
        Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId @()
        Should -Invoke -ModuleName OSSetup Start-Process -Times 0 -Exactly
    }

    It 'transmet les désinstallations reportées à la fermeture du setup, même sur un clone de développement' {
        $root = Join-Path -Path $TestDrive -ChildPath 'dev-clone-atclose'
        New-Item -Path "$root\src" -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
        $command = [ordered]@{ displayName = 'PowerShell 7-x64'; registryKey = 'HKLM:\x\{GUID}'; filePath = 'msiexec.exe'; arguments = '/x {GUID} /qn /norestart' }
        Invoke-OSSetupCleanup -Root $root -RunId 'r1' -SelectedWingetId @() -RunAtClose @($command) -Yes
        $config = Get-LaunchedConfig
        @($config.run).Count | Should -Be 1
        $config.run[0].filePath | Should -Be 'msiexec.exe'
        $config.run[0].arguments | Should -Be '/x {GUID} /qn /norestart'
        $config.run[0].registryKey | Should -Be 'HKLM:\x\{GUID}'
    }
}

Describe 'src/cleanup.ps1 : désinstallations reportées' {
    BeforeEach {
        # Script et configuration copiés comme par Invoke-OSSetupCleanup ; aucune commande réelle n'est lancée.
        $script:work = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $script:work -ItemType Directory -Force | Out-Null
        $script:cleanupScript = Join-Path -Path $script:work -ChildPath 'cleanup.ps1'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination $script:cleanupScript
        $script:cleanupLog = Join-Path -Path $script:work -ChildPath 'setup.log'
        $script:cleanupConfig = Join-Path -Path $script:work -ChildPath 'cleanup.json'
        [ordered]@{
            # Valeurs inoffensives même si un remplacement manquait : processus et exécutable inexistants.
            waitPid   = [int]::MaxValue
            run       = @([ordered]@{ displayName = 'PowerShell 7-x64'; registryKey = 'HKLM:\OSSetupTest\{GUID}'; filePath = 'OSSetupTest-absent.exe'; arguments = '/x {GUID} /qn /norestart' })
            uninstall = @()
            remove    = @()
            logPath   = $script:cleanupLog
            logoff    = $false
        } | ConvertTo-Json -Depth 4 | Set-Content -Path $script:cleanupConfig -Encoding utf8
        Mock Wait-Process {}
        Mock Start-Process { $global:OSSetupTestMsiPresent = $false; [pscustomobject]@{ ExitCode = 0 } }
        Mock Test-Path { $global:OSSetupTestMsiPresent } -ParameterFilter { $LiteralPath -like 'HKLM:\OSSetupTest\*' }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestMsiPresent -Scope Global -ErrorAction SilentlyContinue
    }

    It 'lance la commande reportée après la fermeture du setup et consigne le résultat' {
        $global:OSSetupTestMsiPresent = $true
        & $script:cleanupScript -ConfigPath $script:cleanupConfig
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'OSSetupTest-absent.exe' -and $ArgumentList -eq '/x {GUID} /qn /norestart'
        }
        Get-Content -Path $script:cleanupLog -Raw -Encoding utf8 | Should -BeLike '*Désinstallation de PowerShell 7-x64 : faite (code 0)*'
        # Configuration et script supprimés à la fin.
        Test-Path -Path $script:cleanupConfig | Should -BeFalse
        Test-Path -Path $script:cleanupScript | Should -BeFalse
    }

    It 'ne relance rien si le logiciel est déjà désinstallé' {
        $global:OSSetupTestMsiPresent = $false
        & $script:cleanupScript -ConfigPath $script:cleanupConfig
        Should -Invoke Start-Process -Times 0 -Exactly
        Get-Content -Path $script:cleanupLog -Raw -Encoding utf8 | Should -BeLike '*Désinstallation de PowerShell 7-x64 : déjà faite*'
    }
}

Describe 'src/cleanup.ps1 : suppression sans suivre les liens' {
    It 'supprime le dossier, ses fichiers en lecture seule et la jonction, sans toucher la cible de la jonction' {
        $work = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $clone = Join-Path -Path $work -ChildPath 'clone'
        $outside = Join-Path -Path $work -ChildPath 'outside'
        New-Item -Path "$clone\sub", $outside -ItemType Directory -Force | Out-Null
        Set-Content -Path "$clone\sub\file.txt" -Value 'x'
        Set-Content -Path "$clone\readonly.txt" -Value 'x'
        (Get-Item -LiteralPath "$clone\readonly.txt").IsReadOnly = $true
        Set-Content -Path "$outside\keep.txt" -Value 'à garder'
        New-Item -Path "$clone\link" -ItemType Junction -Value $outside | Out-Null
        $cleanupScript = Join-Path -Path $work -ChildPath 'cleanup.ps1'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination $cleanupScript
        $cleanupConfig = Join-Path -Path $work -ChildPath 'cleanup.json'
        [ordered]@{ waitPid = [int]::MaxValue; run = @(); uninstall = @(); remove = @($clone); logPath = "$work\setup.log"; logoff = $false } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $cleanupConfig -Encoding utf8
        Mock Wait-Process {}

        & $cleanupScript -ConfigPath $cleanupConfig

        Test-Path -LiteralPath $clone | Should -BeFalse
        Get-Content -LiteralPath "$outside\keep.txt" | Should -Be 'à garder'
        Get-Content -Path "$work\setup.log" -Raw -Encoding utf8 | Should -BeLike "*Suppression de $clone : faite*"
    }
}
