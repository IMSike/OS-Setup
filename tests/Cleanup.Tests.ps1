BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    function New-TestClone {
        # Faux dépôt laissé par le bootstrap : journal, réponses, sauvegardes, bootstrap.json, src/cleanup.ps1.
        param([bool]$OwnsClone, [string[]]$InstalledTool = @(), [string]$RunId = 'r1')
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path "$root\logs", "$root\state\backups\$RunId", "$root\src" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$root\logs\setup-$RunId.log" -Value 'journal'
        Set-Content -Path "$root\state\answers-last.json" -Value '{}'
        Set-Content -Path "$root\state\backups\$RunId\config.txt" -Value 'ancienne config'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
        @{ ownsClone = $OwnsClone; bootstrapScript = 'C:\Temp\bootstrap.ps1'; installedTools = $InstalledTool } |
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
        @{ ownsClone = $true; bootstrapScript = 'C:\Windows\System32\drivers'; installedTools = @('Autre.Outil') } |
            ConvertTo-Json | Set-Content -Path "$root\state\bootstrap.json"
        Invoke-OSSetupCleanup -Root $root -CodeRoot $code -RunId $runId -SelectedWingetId @() -Yes
        Get-Content -Path $global:OSSetupTestCleanupArgs[-3].Trim('"') -Raw | Should -Match 'copie de la reprise'
        $config = Get-LaunchedConfig
        $config.uninstall | Should -Be @('Git.Git')
        $config.remove | Should -Be @($root, 'C:\Temp\bootstrap.ps1')
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
        $config.remove | Should -Be @($root, 'C:\Temp\bootstrap.ps1')
        $config.uninstall | Should -BeNullOrEmpty
        $config.waitPid | Should -Be $PID
        Test-Path -Path (Join-Path -Path $historyRoot -ChildPath "$runId\setup-$runId.log") | Should -BeTrue
        Test-Path -Path (Join-Path -Path $historyRoot -ChildPath "$runId\backups\config.txt") | Should -BeTrue
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
}
