BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    # Dossier temporaire du profil, où le nettoyage accepte de supprimer le script du bootstrap.
    $profileTemp = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'AppData\Local\Temp'

    function New-TestClone {
        # Faux dépôt laissé par le bootstrap : journal, réponses, sauvegardes, bootstrap.json, src/cleanup.ps1. Des
        # crochets dans son nom vérifient qu'aucun chemin n'est lu comme un motif à jokers. Il est rangé sous un
        # dossier sans crochets : Pester vide TestDrive avec -Path et échouerait sur un nom à crochets à sa racine.
        param([bool]$OwnsClone, [string[]]$InstalledTool = @(), [string]$RunId = 'r1',
            [string]$BootstrapScript = (Join-Path -Path $profileTemp -ChildPath 'bootstrap.ps1'))
        $root = Join-Path -Path $TestDrive -ChildPath "$([guid]::NewGuid().ToString('N'))\dépôt [1]"
        New-Item -Path "$root\logs", "$root\state\backups\$RunId", "$root\src" -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath "$root\logs\setup-$RunId.log" -Value 'journal'
        Set-Content -LiteralPath "$root\state\answers-last.json" -Value '{}'
        Set-Content -LiteralPath "$root\state\backups\$RunId\config.txt" -Value 'ancienne config'
        Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
        @{ ownsClone = $OwnsClone; bootstrapScript = $BootstrapScript; installedTools = $InstalledTool } |
            ConvertTo-Json | Set-Content -LiteralPath "$root\state\bootstrap.json"
        $root
    }

    $windowsPowerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    function Invoke-TestCleanupScript {
        # Exécute une copie de src/cleanup.ps1 comme le setup : Windows PowerShell 5.1, processus séparé (le script
        # remplace PSModulePath pour tout son processus, ce qui perturberait celui des tests).
        param([string]$Script, [string]$ConfigPath)
        & $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script -ConfigPath $ConfigPath | Out-Null
    }

    function Get-LaunchedConfig {
        # Configuration passée au processus de nettoyage (dernier lancement capturé).
        $path = $global:OSSetupTestCleanupArgs[-1].Trim('"')
        Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
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

Describe 'Test-OSSetupRemovableBootstrapScript' {
    It 'accepte un .ps1 posé dans <Case>' -ForEach @(
        @{ Case = 'le dossier temporaire du profil'; Path = 'C:\Users\test\AppData\Local\Temp\bootstrap.ps1' }
        @{ Case = 'Téléchargements'; Path = 'C:\Users\test\Downloads\bootstrap.ps1' }
    ) {
        Test-OSSetupRemovableBootstrapScript -Path $Path -UserProfile 'C:\Users\test' | Should -BeTrue
    }

    It 'refuse <Case>' -ForEach @(
        @{ Case = 'un autre dossier'; Path = 'C:\Windows\System32\bootstrap.ps1' }
        @{ Case = 'un sous-dossier de %TEMP%'; Path = 'C:\Users\test\AppData\Local\Temp\x\bootstrap.ps1' }
        @{ Case = 'un fichier autre que .ps1'; Path = 'C:\Users\test\AppData\Local\Temp\bootstrap.exe' }
        @{ Case = 'une remontée hors de %TEMP%'; Path = 'C:\Users\test\AppData\Local\Temp\..\bootstrap.ps1' }
        @{ Case = 'un chemin relatif'; Path = 'bootstrap.ps1' }
        @{ Case = 'un chemin vide'; Path = '' }
    ) {
        Test-OSSetupRemovableBootstrapScript -Path $Path -UserProfile 'C:\Users\test' | Should -BeFalse
    }

    It 'ne suit ni la variable TMP ni les dossiers de l''Explorateur, modifiables sans élévation' {
        # Dossier protégé désigné par une variable TMP et un dossier Téléchargements redirigés.
        $previous = $env:TMP
        try {
            $env:TMP = 'C:\Windows\System32'
            Mock -ModuleName OSSetup Get-ItemPropertyValue { 'C:\Windows\System32' }
            Test-OSSetupRemovableBootstrapScript -Path 'C:\Windows\System32\bootstrap.ps1' -UserProfile 'C:\Users\test' | Should -BeFalse
        }
        finally {
            $env:TMP = $previous
        }
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
            Remove-Item -LiteralPath $global:OSSetupTestCleanupArgs[-1].Trim('"'), $global:OSSetupTestCleanupArgs[-3].Trim('"') -Force -ErrorAction SilentlyContinue
            # Seul un historique créé par le test (dossier de l'exécution sous %LOCALAPPDATA%\OS-Setup) est supprimé.
            if ($config.logPath -and $config.logPath.StartsWith($historyRoot)) {
                Remove-Item -LiteralPath (Split-Path -Path $config.logPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
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
        Set-Content -LiteralPath "$code\src\cleanup.ps1" -Value '# copie de la reprise'
        Copy-Item -LiteralPath "$root\state\bootstrap.json" -Destination "$code\state\bootstrap.json"
        # Trace du dépôt modifiée après la copie : elle ne doit pas être suivie.
        $frozenScript = (Get-Content -LiteralPath "$code\state\bootstrap.json" -Raw | ConvertFrom-Json).bootstrapScript
        @{ ownsClone = $true; bootstrapScript = (Join-Path -Path $profileTemp -ChildPath 'autre.ps1'); installedTools = @('Autre.Outil') } |
            ConvertTo-Json | Set-Content -LiteralPath "$root\state\bootstrap.json"
        Invoke-OSSetupCleanup -Root $root -CodeRoot $code -RunId $runId -SelectedWingetId @() -Yes
        Get-Content -LiteralPath $global:OSSetupTestCleanupArgs[-3].Trim('"') -Raw | Should -Match 'copie de la reprise'
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
        Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination "$root\src\cleanup.ps1"
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
        $config.remove | Should -Be @($root, (Join-Path -Path $profileTemp -ChildPath 'bootstrap.ps1'))
        $config.uninstall | Should -BeNullOrEmpty
        $config.waitPid | Should -Be $PID
        Test-Path -LiteralPath (Join-Path -Path $historyRoot -ChildPath "$runId\setup-$runId.log") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $historyRoot -ChildPath "$runId\backups\config.txt") | Should -BeTrue
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
}

Describe 'src/cleanup.ps1' {
    BeforeAll {
        function Get-TestRealPath {
            # Chemin sans jonction ni lien symbolique : TestDrive est sous %TEMP%, qui peut passer par une jonction
            # (dossier temporaire déplacé) ; le script refuserait alors tout chemin du test.
            param([string]$Path)
            $full = [IO.Path]::GetFullPath($Path)
            $current = [IO.Path]::GetPathRoot($full)
            foreach ($part in $full.Substring($current.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries)) {
                $current = Join-Path -Path $current -ChildPath $part
                $info = [IO.DirectoryInfo]::new($current)
                if ($info.Exists -and $info.LinkTarget) { $current = $info.ResolveLinkTarget($true).FullName }
            }
            $current
        }

        function New-TestCleanupWork {
            # Dossier de travail et copie du script, avec sa configuration.
            param([hashtable]$Config)
            $work = Get-TestRealPath -Path (Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N')))
            New-Item -Path $work -ItemType Directory -Force | Out-Null
            $script = Join-Path -Path $work -ChildPath 'cleanup.ps1'
            Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src\cleanup.ps1') -Destination $script
            @{ Work = $work; Script = $script; Config = (Join-Path -Path $work -ChildPath 'cleanup.json') }
        }

        function Save-TestCleanupConfig {
            # Rien à attendre : le processus noté n'existe pas.
            param([string]$Path, [string[]]$Remove = @(), [string]$LogPath)
            [ordered]@{ waitPid = [int]::MaxValue; uninstall = @(); remove = @($Remove); logPath = $LogPath; logoff = $false } |
                ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
        }
    }

    BeforeEach {
        if (-not (Test-Path -LiteralPath $windowsPowerShell)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 absent' }
    }

    It 'supprime le dossier, ses fichiers en lecture seule et la jonction, sans toucher la cible de la jonction' {
        $test = New-TestCleanupWork
        $clone = Join-Path -Path $test.Work -ChildPath 'clone'
        $outside = Join-Path -Path $test.Work -ChildPath 'outside'
        New-Item -Path "$clone\sub", $outside -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath "$clone\sub\file.txt" -Value 'x'
        Set-Content -LiteralPath "$clone\readonly.txt" -Value 'x'
        (Get-Item -LiteralPath "$clone\readonly.txt").IsReadOnly = $true
        Set-Content -LiteralPath "$outside\keep.txt" -Value 'à garder'
        New-Item -Path "$clone\link" -ItemType Junction -Value $outside | Out-Null
        Save-TestCleanupConfig -Path $test.Config -Remove $clone -LogPath "$($test.Work)\setup.log"

        Invoke-TestCleanupScript -Script $test.Script -ConfigPath $test.Config

        Test-Path -LiteralPath $clone | Should -BeFalse
        Get-Content -LiteralPath "$outside\keep.txt" | Should -Be 'à garder'
        Get-Content -LiteralPath "$($test.Work)\setup.log" -Raw -Encoding utf8 | Should -BeLike "*Suppression de $clone : faite*"
        # Configuration et script supprimés à la fin.
        Test-Path -LiteralPath $test.Config | Should -BeFalse
        Test-Path -LiteralPath $test.Script | Should -BeFalse
    }

    It 'ne supprime rien et n''écrit pas le journal au travers d''une jonction parente' {
        $test = New-TestCleanupWork
        $outside = Join-Path -Path $test.Work -ChildPath 'outside'
        New-Item -Path "$outside\clone", (Join-Path -Path $test.Work -ChildPath 'repo') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath "$outside\clone\keep.txt" -Value 'à garder'
        $junction = Join-Path -Path $test.Work -ChildPath 'repo\parent'
        New-Item -Path $junction -ItemType Junction -Value $outside | Out-Null
        Save-TestCleanupConfig -Path $test.Config -Remove "$junction\clone" -LogPath "$junction\setup.log"

        Invoke-TestCleanupScript -Script $test.Script -ConfigPath $test.Config

        Get-Content -LiteralPath "$outside\clone\keep.txt" | Should -Be 'à garder'
        Test-Path -LiteralPath "$outside\setup.log" | Should -BeFalse
    }

    It 'supprime un dossier dont le chemin contient des crochets, et y écrit son journal' {
        $test = New-TestCleanupWork
        $repo = Join-Path -Path $test.Work -ChildPath 'dépôt [1]'
        New-Item -Path "$repo\clone" -ItemType Directory -Force | Out-Null
        Save-TestCleanupConfig -Path $test.Config -Remove "$repo\clone" -LogPath "$repo\setup.log"

        Invoke-TestCleanupScript -Script $test.Script -ConfigPath $test.Config

        Test-Path -LiteralPath "$repo\clone" | Should -BeFalse
        Get-Content -LiteralPath "$repo\setup.log" -Raw -Encoding utf8 | Should -BeLike '*Suppression de * : faite*'
    }

    It 'ne charge pas un module placé en tête de PSModulePath à la place d''une cmdlet de Windows' {
        # Module piège dans un dossier modifiable par l'utilisateur (comme Documents\WindowsPowerShell\Modules) : il
        # exporte Get-Content, première cmdlet du script, et laisse une trace s'il est exécuté.
        $test = New-TestCleanupWork
        $modules = Join-Path -Path $test.Work -ChildPath 'modules'
        $trap = Join-Path -Path $modules -ChildPath 'Trap'
        $marker = Join-Path -Path $test.Work -ChildPath 'trap-ran.txt'
        New-Item -Path $trap -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath "$trap\Trap.psm1" -Value @(
            "function Get-Content { [IO.File]::WriteAllText('$marker', 'x') }"
            'Export-ModuleMember -Function Get-Content'
        )
        Set-Content -LiteralPath "$trap\Trap.psd1" -Value "@{ RootModule = 'Trap.psm1'; ModuleVersion = '1.0'; GUID = '$([guid]::NewGuid())'; FunctionsToExport = @('Get-Content') }"
        Save-TestCleanupConfig -Path $test.Config

        $previous = $env:PSModulePath
        try {
            $env:PSModulePath = "$modules;$previous"
            Invoke-TestCleanupScript -Script $test.Script -ConfigPath $test.Config
        }
        finally {
            $env:PSModulePath = $previous
        }

        Test-Path -LiteralPath $marker | Should -BeFalse
        # Le script a bien tourné jusqu'au bout : il a supprimé sa configuration et lui-même.
        Test-Path -LiteralPath $test.Config | Should -BeFalse
        Test-Path -LiteralPath $test.Script | Should -BeFalse
    }
}
