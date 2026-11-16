BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')

    function Get-UnsafeLogonTaskScript {
        # Actions logon-task (toujours lancées avec les droits les plus élevés) dont le script n'est pas sous
        # {{ProgramFiles}}\OS-Setup, seul dossier dont on sait que seuls les administrateurs le modifient : « élément :
        # script ». Liste blanche, pas liste noire : un dossier à la racine (C:\Outils), ProgramData, un autre disque ou le
        # dépôt sont aussi modifiables sans élévation. Deux contrôles : le texte du catalogue (quelle que soit la machine) et
        # le chemin développé et normalisé sur cette machine (pas de « ..\ » pour en sortir).
        param($Data, [System.Collections.IDictionary]$Variables)
        $allowed = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'OS-Setup').TrimEnd('\') + '\'
        foreach ($item in $Data.Items.Values) {
            foreach ($action in @($item['actions'] | Where-Object { $_ -and $_['provider'] -eq 'logon-task' })) {
                $script = $action['script']
                $expanded = try { Expand-OSSetupString -Text $script -Variables $Variables } catch { $script }
                $expanded = try { [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($expanded)) } catch { '' }
                if (-not $script.StartsWith('{{ProgramFiles}}\OS-Setup\', [StringComparison]::OrdinalIgnoreCase) -or
                    -not $expanded.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
                    "$($item['id']) : $script"
                }
            }
        }
    }

    function Get-ElevatedScriptEnvironmentUse {
        # Scripts des actions logon-task (droits les plus élevés) qui lisent une variable d'environnement : « élément :
        # détail ». Elle vient de l'environnement de l'utilisateur (HKCU\Environment), qu'il modifie sans élévation :
        # un chemin écrit ou exécuté qui en dépend (docker.exe sous $env:ProgramFiles, journal sous $env:LOCALAPPDATA)
        # serait détourné. Règle simple : aucune lecture ($env:X, GetEnvironmentVariable, ExpandEnvironmentVariables) ;
        # dossiers connus par [Environment]::GetFolderPath ou SystemDirectory. Le script est retrouvé par l'action file
        # du même élément qui le déploie (source sous dotfiles/).
        param($Data, [string]$DotfilesRoot)
        foreach ($item in $Data.Items.Values) {
            foreach ($task in @($item['actions'] | Where-Object { $_ -and $_['provider'] -eq 'logon-task' })) {
                $deploy = @($item['actions'] | Where-Object { $_ -and $_['provider'] -eq 'file' -and $_['source'] -and $_['target'] -eq $task['script'] })
                if (-not $deploy) { "$($item['id']) : script non déployé par une action file ($($task['script']))"; continue }
                $path = Join-Path -Path $DotfilesRoot -ChildPath $deploy[0]['source']
                $tokens = $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
                $uses = $ast.FindAll({
                        param($node)
                        ($node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.DriveName -eq 'env') -or
                        ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                            "$($node.Member)" -in 'GetEnvironmentVariable', 'GetEnvironmentVariables', 'ExpandEnvironmentVariables')
                    }, $true)
                foreach ($use in $uses) { "$($item['id']) : $($deploy[0]['source']):$($use.Extent.StartLineNumber) $($use.Extent.Text)" }
            }
        }
    }
}

Describe 'Données du dépôt' {
    BeforeAll {
        # Catalogue lu une seule fois (plusieurs secondes : validation par le schéma) ; une erreur est gardée pour le premier test.
        $loadError = $null
        $data = try { Import-OSSetupData -Root $repoRoot } catch { $loadError = $_; $null }
    }

    It 'le catalogue et les profils sont valides' {
        $loadError | Should -BeNullOrEmpty
        $data | Should -Not -BeNullOrEmpty
    }

    It 'chaque tâche logon-task, lancée avec les droits les plus élevés, exécute un script sous {{ProgramFiles}}\OS-Setup' {
        $variables = Resolve-OSSetupVariable -Data $data -Answers @{ profiles = @($data.Profiles.Keys) }
        $found = @(Get-UnsafeLogonTaskScript -Data $data -Variables $variables)
        $found.Count | Should -Be 0 -Because "un script modifiable sans élévation et lancé avec les droits les plus élevés donne les droits administrateur sans invite UAC : le déployer sous {{ProgramFiles}}\OS-Setup ($($found -join ', '))"
    }

    It 'le contrôle des scripts de logon-task refuse tout script hors de {{ProgramFiles}}\OS-Setup' {
        $variables = Get-OSSetupBuiltinVariable
        $fake = [pscustomobject]@{
            Items = [ordered]@{
                local   = @{ id = 'local'; actions = @(@{ provider = 'logon-task'; script = '{{LocalAppData}}\OS-Setup\a.ps1' }) }
                env     = @{ id = 'env'; actions = @(@{ provider = 'logon-task'; script = '%APPDATA%\a.ps1' }) }
                profile = @{ id = 'profile'; actions = @(@{ provider = 'logon-task'; script = (Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath 'a.ps1') }) }
                safe    = @{ id = 'safe'; actions = @(@{ provider = 'logon-task'; script = '{{ProgramFiles}}\OS-Setup\a.ps1' }) }
                root    = @{ id = 'root'; actions = @(@{ provider = 'logon-task'; script = 'C:\Outils\a.ps1' }) }
                data    = @{ id = 'data'; actions = @(@{ provider = 'logon-task'; script = '%ProgramData%\OS-Setup\a.ps1' }) }
                other3p = @{ id = 'other3p'; actions = @(@{ provider = 'logon-task'; script = '{{ProgramFiles}}\Autre\a.ps1' }) }
                escape  = @{ id = 'escape'; actions = @(@{ provider = 'logon-task'; script = '{{ProgramFiles}}\OS-Setup\..\Autre\a.ps1' }) }
                other   = @{ id = 'other'; actions = @(@{ provider = 'file'; target = '{{LocalAppData}}\a.ps1' }) }
            }
        }
        $found = @(Get-UnsafeLogonTaskScript -Data $fake -Variables $variables)
        @($found | ForEach-Object { ($_ -split ' : ')[0] } | Sort-Object) | Should -Be @('data', 'env', 'escape', 'local', 'other3p', 'profile', 'root')
    }

    It 'les scripts des tâches logon-task, lancés avec les droits les plus élevés, ne lisent aucune variable d''environnement' {
        $found = @(Get-ElevatedScriptEnvironmentUse -Data $data -DotfilesRoot (Join-Path -Path $repoRoot -ChildPath 'dotfiles'))
        $found.Count | Should -Be 0 -Because "l'utilisateur modifie son environnement sans élévation : un chemin qui en dépend serait détourné, utiliser [Environment]::GetFolderPath ($($found -join ' ; '))"
    }

    It 'le contrôle des variables d''environnement des scripts élevés repère $env:, GetEnvironmentVariable, ExpandEnvironmentVariables et un script non déployé' {
        $dotfiles = Join-Path -Path $TestDrive -ChildPath 'dotfiles'
        New-Item -Path $dotfiles -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $dotfiles -ChildPath 'bad.ps1') -Value @(
            '$a = Join-Path $env:ProgramFiles ''x'''
            '$b = [Environment]::GetEnvironmentVariable(''TEMP'')'
            '$c = [Environment]::ExpandEnvironmentVariables(''%APPDATA%'')'
        )
        Set-Content -Path (Join-Path -Path $dotfiles -ChildPath 'good.ps1') -Value '$a = [Environment]::GetFolderPath(''ProgramFiles'')'
        $task = { param($Name) @{ provider = 'logon-task'; script = "{{ProgramFiles}}\OS-Setup\$Name.ps1" } }
        $file = { param($Name) @{ provider = 'file'; source = "$Name.ps1"; target = "{{ProgramFiles}}\OS-Setup\$Name.ps1" } }
        $data = [pscustomobject]@{
            Items = [ordered]@{
                bad     = @{ id = 'bad'; actions = @((& $file 'bad'), (& $task 'bad')) }
                good    = @{ id = 'good'; actions = @((& $file 'good'), (& $task 'good')) }
                missing = @{ id = 'missing'; actions = @((& $task 'missing')) }
            }
        }
        $found = @(Get-ElevatedScriptEnvironmentUse -Data $data -DotfilesRoot $dotfiles)
        @($found | ForEach-Object { ($_ -split ' : ')[0] }) | Should -Be @('bad', 'bad', 'bad', 'missing')
        $found[0] | Should -BeLike '*bad.ps1:1 $env:ProgramFiles'
    }

    It 'les fichiers de réponses d''exemple sont valides et cohérents' {
        foreach ($file in Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'answers') -Filter '*.example.json') {
            $answers = Read-OSSetupAnswerFile -Path $file.FullName -Root $repoRoot
            { Test-OSSetupAnswer -Data $data -Answers $answers } | Should -Not -Throw
        }
    }
}

Describe 'Documentation' {
    BeforeDiscovery {
        # Catégorie du catalogue → page qui documente chacun de ses éléments, dans chaque langue.
        $pages = @(
            @{ Categories = @('system', 'privacy', 'power'); Page = 'windows\settings.md' }
            @{ Categories = @('desktop'); Page = 'windows\desktop.md' }
            @{ Categories = @('browsers', 'browser-settings'); Page = 'windows\browsers.md' }
            @{ Categories = @('apps'); Page = 'windows\apps.md' }
            @{ Categories = @('dev'); Page = 'windows\development.md' }
            @{ Categories = @('drivers'); Page = 'windows\drivers.md' }
            @{ Categories = @('remove'); Page = 'windows\removable-apps.md' }
        )
        $documentedItems = foreach ($language in 'en', 'fr') {
            foreach ($page in $pages) { @{ Language = $language; Categories = $page.Categories; Page = $page.Page } }
        }
    }

    It 'chaque élément de <Categories> est décrit dans docs/<Language>/<Page>' -ForEach $documentedItems {
        $doc = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath "docs\$Language\$Page") -Raw -ErrorAction Stop
        $ids = foreach ($category in $Categories) {
            Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath "catalog\$category") -Filter '*.json' | ForEach-Object { $_.BaseName }
        }
        @($ids).Count | Should -BeGreaterThan 0
        $missing = @($ids | Where-Object { $doc -notmatch "``$([regex]::Escape($_))``" })
        $missing.Count | Should -Be 0 -Because "chaque élément doit être expliqué : effet, implications, retour arrière (manquants : $($missing -join ', '))"
    }

    It 'la documentation anglaise et la française ont les mêmes pages' {
        $relative = {
            param([string]$Language)
            $root = Join-Path -Path $repoRoot -ChildPath "docs\$Language"
            Get-ChildItem -Path $root -Filter '*.md' -Recurse | ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName) } | Sort-Object
        }
        (& $relative 'en') | Should -Be (& $relative 'fr')
        foreach ($name in 'README', 'CONTRIBUTING') {
            Join-Path -Path $repoRoot -ChildPath "$name.md" | Should -Exist
            Join-Path -Path $repoRoot -ChildPath "$name.fr.md" | Should -Exist
        }
    }

    It 'chaque page cite les mêmes éléments du catalogue dans les deux langues' {
        $ids = Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'catalog') -Filter '*.json' -Recurse | ForEach-Object { $_.BaseName }
        $enRoot = Join-Path -Path $repoRoot -ChildPath 'docs\en'
        $differences = foreach ($enPage in Get-ChildItem -Path $enRoot -Filter '*.md' -Recurse) {
            $relativePath = [IO.Path]::GetRelativePath($enRoot, $enPage.FullName)
            $frPage = Join-Path -Path $repoRoot -ChildPath "docs\fr\$relativePath"
            if (-not (Test-Path -Path $frPage)) { continue }
            $en = Get-Content -Path $enPage.FullName -Raw
            $fr = Get-Content -Path $frPage -Raw
            foreach ($id in $ids) {
                $pattern = "``$([regex]::Escape($id))``"
                if (($en -match $pattern) -ne ($fr -match $pattern)) { "$relativePath : $id" }
            }
        }
        @($differences).Count | Should -Be 0 -Because "une page modifiée l'est dans les deux langues ($($differences -join ', '))"
    }

    It 'les liens relatifs de la documentation mènent à un fichier existant' {
        $files = @(Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'docs') -Filter '*.md' -Recurse) +
            @(Get-ChildItem -Path $repoRoot -Filter '*.md')
        $broken = foreach ($file in $files) {
            $text = Get-Content -Path $file.FullName -Raw
            # Les blocs de code ne contiennent pas de liens.
            $text = [regex]::Replace($text, '(?s)```.*?```', '')
            foreach ($match in [regex]::Matches($text, '\]\(([^)#\s]+)(#[^)]*)?\)')) {
                $target = $match.Groups[1].Value
                if ($target -match '^[a-z]+:') { continue }
                if (-not (Test-Path -Path (Join-Path -Path $file.DirectoryName -ChildPath $target))) { "$($file.Name) → $target" }
            }
        }
        @($broken).Count | Should -Be 0 -Because "liens cassés : $($broken -join ', ')"
    }
}

Describe 'Faits' {
    BeforeAll {
        # Requêtes WMI simulées : la vraie détection prend plusieurs secondes et dépend de la machine.
        if ($IsWindows) {
            Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } { [pscustomobject]@{ BuildNumber = '19045' } }
            Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                [pscustomobject]@{ Name = 'Windows(R), Professional edition'; LicenseStatus = 1 }
            }
            Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
                [pscustomobject]@{ Manufacturer = 'Dell Inc.'; Model = 'Modèle'; HypervisorPresent = $false }
            }
            Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [pscustomobject]@{ Manufacturer = 'GenuineIntel'; VirtualizationFirmwareEnabled = $true }
            }
            Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_VideoController' } {
                [pscustomobject]@{ Name = 'Intel(R) UHD Graphics' }
                [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3070' }
            }
            Mock -ModuleName OSSetup Get-ItemProperty -ParameterFilter { $LiteralPath -eq 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' } {
                [pscustomobject]@{ EditionID = 'Professional' }
            }
        }
    }

    It 'le schéma des éléments liste exactement les faits détectés par le moteur' {
        $schema = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'schemas\item.schema.json') -Raw | ConvertFrom-Json -AsHashtable
        $schemaNames = $schema['properties']['when']['propertyNames']['enum']
        ($schemaNames | Sort-Object) | Should -Be (Get-OSSetupFactName | Sort-Object)
    }

    It 'Get-OSSetupFact retourne tous les faits' {
        $facts = Get-OSSetupFact
        @($facts.Keys) | Should -Be (Get-OSSetupFactName)
    }

    It 'Get-OSSetupFact traduit les réponses WMI en faits' -Skip:(-not $IsWindows) {
        $facts = Get-OSSetupFact
        $facts['OSName'] | Should -Be 'windows-10'
        $facts['OSBuild'] | Should -Be 19045
        $facts['Edition'] | Should -Be 'Professional'
        $facts['Activated'] | Should -BeTrue
        $facts['Manufacturer'] | Should -Be 'dell'
        $facts['CpuVendor'] | Should -Be 'intel'
        $facts['VirtualizationEnabled'] | Should -BeTrue
        $facts['GpuVendor'] | Should -Be @('intel', 'nvidia')
    }

    It 'Get-OSSetupFact détecte l''activation sans LIKE dans le filtre WMI (lent)' -Skip:(-not $IsWindows) {
        Mock -ModuleName OSSetup Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
            [pscustomobject]@{ Name = 'Office 16, OfficeProPlus edition'; LicenseStatus = 5 }
            [pscustomobject]@{ Name = 'Windows(R), Professional edition'; LicenseStatus = 1 }
        }
        (Get-OSSetupFact)['Activated'] | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'SoftwareLicensingProduct' -and $Filter -notmatch 'LIKE'
        }
    }
}

Describe 'Import-OSSetupData' {
    It 'rejette un élément non conforme au schéma' {
        $root = Join-Path -Path $TestDrive -ChildPath 'repo'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'schemas') -Destination (Join-Path -Path $root -ChildPath 'schemas') -Recurse
        New-Item -Path (Join-Path -Path $root -ChildPath 'catalog\test') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $root -ChildPath 'profiles') -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $root -ChildPath 'catalog\test\bad.json') -Value '{ "id": "bad", "name": "Bad", "category": "test", "platforms": ["windows"], "actions": [ { "provider": "unknown" } ] }'
        # Seul le texte du moteur est vérifié : les détails de Test-Json dépendent de la version de PowerShell et de sa langue.
        { Import-OSSetupData -Root $root } | Should -Throw '*bad.json : non conforme au schéma item.schema.json*'
    }

    It 'signale un fichier vide par son nom' {
        $root = Join-Path -Path $TestDrive -ChildPath 'empty'
        Copy-Item -Path (Join-Path -Path $repoRoot -ChildPath 'schemas') -Destination (Join-Path -Path $root -ChildPath 'schemas') -Recurse
        New-Item -Path (Join-Path -Path $root -ChildPath 'catalog\test') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $root -ChildPath 'profiles') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $root -ChildPath 'catalog\test\vide.json') -ItemType File | Out-Null
        Set-Content -Path (Join-Path -Path $root -ChildPath 'profiles\blanc.json') -Value '  '
        $message = try { Import-OSSetupData -Root $root; $null } catch { $_.Exception.Message }
        $message | Should -BeLike '*vide.json : fichier vide.*'
        $message | Should -BeLike '*blanc.json : fichier vide.*'
    }

    It 'charge un dépôt dont le chemin contient des crochets' {
        # Dans un sous-dossier : Pester ne vide pas un dossier à crochets à la racine de TestDrive.
        $root = Join-Path -Path $TestDrive -ChildPath 'brackets\dépôt [1]'
        Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'schemas') -Destination (Join-Path -Path $root -ChildPath 'schemas') -Recurse
        New-Item -Path (Join-Path -Path $root -ChildPath 'catalog\test') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $root -ChildPath 'profiles') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'catalog\test\a.json') `
            -Value '{ "id": "a", "name": "A", "category": "test", "platforms": ["windows"], "actions": [ { "provider": "directory", "path": "C:\\x" } ] }'
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'profiles\base.json') -Value '{ "id": "base", "name": "Base", "items": ["a"] }'
        $data = Import-OSSetupData -Root $root
        @($data.Items.Keys) | Should -Be @('a')
        @($data.Profiles.Keys) | Should -Be @('base')
    }

    It 'refuse un catalogue vide au lieu de produire un plan vide' {
        $root = Join-Path -Path $TestDrive -ChildPath 'no-items'
        Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'schemas') -Destination (Join-Path -Path $root -ChildPath 'schemas') -Recurse
        New-Item -Path (Join-Path -Path $root -ChildPath 'catalog'), (Join-Path -Path $root -ChildPath 'profiles') -ItemType Directory -Force | Out-Null
        { Import-OSSetupData -Root $root } | Should -Throw '*catalog : aucun élément dans le catalogue.*'
    }
}

Describe 'Save-OSSetupOriginalValue : chemin à crochets' {
    It 'ajoute les valeurs d''origine dans une sauvegarde dont le chemin contient des crochets' {
        $backupRoot = Join-Path -Path $TestDrive -ChildPath 'brackets\sauvegardes [1]\run'
        $provider = @{ Read = { param($Action, $Context) [ordered]@{ value = $Action['v'] } } }
        foreach ($value in 1, 2) {
            $step = [pscustomobject]@{ ItemId = 'x'; Description = "pas $value"; Action = @{ v = $value } }
            InModuleScope OSSetup -Parameters @{ BackupRoot = $backupRoot; Step = $step; Provider = $provider } {
                param($BackupRoot, $Step, $Provider)
                Save-OSSetupOriginalValue -BackupRoot $BackupRoot -Step $Step -Provider $Provider -Context @{}
            }
        }
        $entries = @(Get-Content -LiteralPath (Join-Path -Path $backupRoot -ChildPath 'original-values.json') -Raw | ConvertFrom-Json)
        @($entries | ForEach-Object { $_.before.value }) | Should -Be @(1, 2)
    }
}

Describe 'Schéma des éléments' {
    BeforeAll {
        $schema = Join-Path -Path $repoRoot -ChildPath 'schemas\item.schema.json'
        $test = {
            param($Action)
            $json = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{ id = 'x'; name = 'X'; category = 'test'; platforms = @('windows'); actions = @($Action) })
            Test-Json -Json $json -SchemaFile $schema -ErrorAction SilentlyContinue
        }
    }

    It 'shortcut : from obligatoire pour créer, interdit pour supprimer' {
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; from = 'C:\b.lnk' } | Should -BeTrue
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; from = 'C:\b.lnk'; present = $true } | Should -BeTrue
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; present = $false } | Should -BeTrue
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk' } | Should -BeFalse
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; present = $true } | Should -BeFalse
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; present = $false; from = 'C:\b.lnk' } | Should -BeFalse
        & $test @{ provider = 'shortcut'; path = 'C:\a.lnk'; target = 'C:\app.exe' } | Should -BeFalse
    }

    It 'appx : nom accepté par Stop-OSSetupStoreUpdate' {
        & $test @{ provider = 'appx'; name = 'Microsoft.Xbox.TCUI' } | Should -BeTrue
        & $test @{ provider = 'appx'; name = 'Microsoft.*' } | Should -BeFalse
        & $test @{ provider = 'appx'; name = "a'; b" } | Should -BeFalse
    }
}

Describe 'Read-OSSetupJsonFileSet' {
    BeforeAll {
        $schema = Join-Path -Path $repoRoot -ChildPath 'schemas\item.schema.json'
        $newFile = {
            param([string]$Name, [string]$Text)
            $path = Join-Path -Path $TestDrive -ChildPath $Name
            Set-Content -Path $path -Value $Text
            Get-Item -Path $path
        }
        $itemText = { param([string]$Id) "{ ""id"": ""$Id"", ""name"": ""X"", ""category"": ""test"", ""platforms"": [""windows""], ""actions"": [ { ""provider"": ""directory"", ""path"": ""C:\\x"" } ] }" }
    }

    It 'retourne les fichiers valides dans l''ordre, validés en un seul appel' {
        $files = @((& $newFile 'a.json' (& $itemText 'a')), (& $newFile 'b.json' (& $itemText 'b')))
        $errors = [System.Collections.Generic.List[string]]::new()
        $result = @(Read-OSSetupJsonFileSet -File $files -SchemaPath $schema -Errors $errors)
        $errors.Count | Should -Be 0
        @($result | ForEach-Object { $_.Data['id'] }) | Should -Be @('a', 'b')
        $result[0].File.Name | Should -Be 'a.json'
    }

    It 'nomme le fichier fautif et garde les autres' {
        $files = @(
            (& $newFile 'ok.json' (& $itemText 'ok'))
            (& $newFile 'bad.json' '{ "id": "bad" }')
            (& $newFile 'two.json' ((& $itemText 'two') + ', ' + (& $itemText 'three')))
            (& $newFile 'empty.json' '')
        )
        $errors = [System.Collections.Generic.List[string]]::new()
        $result = @(Read-OSSetupJsonFileSet -File $files -SchemaPath $schema -Errors $errors)
        @($result | ForEach-Object { $_.Data['id'] }) | Should -Be @('ok')
        $errors.Count | Should -Be 3
        $errors[0] | Should -BeLike '*bad.json : non conforme au schéma item.schema.json*'
        $errors[1] | Should -BeLike '*two.json : *'
        $errors[2] | Should -BeLike '*empty.json : fichier vide.'
    }

    It 'ne valide pas en un seul appel un ensemble qui contient un fichier de 0 octet' {
        # Get-Content -Raw donne $null pour un fichier de 0 octet : il doit compter comme vide.
        $zero = Join-Path -Path $TestDrive -ChildPath 'zero.json'
        New-Item -Path $zero -ItemType File -Force | Out-Null
        $files = @((& $newFile 'z-ok.json' (& $itemText 'z-ok')), (Get-Item -LiteralPath $zero))
        Mock -ModuleName OSSetup Test-Json { $false } -ParameterFilter { $Json.StartsWith('[') }
        $errors = [System.Collections.Generic.List[string]]::new()
        $result = @(Read-OSSetupJsonFileSet -File $files -SchemaPath $schema -Errors $errors)
        Should -Invoke -ModuleName OSSetup Test-Json -Times 0 -Exactly -ParameterFilter { $Json.StartsWith('[') }
        @($result | ForEach-Object { $_.Data['id'] }) | Should -Be @('z-ok')
        @($errors) | Should -Be @("${zero} : fichier vide.")
    }

    It 'refuse un fichier qui ne serait valide qu''au sein du tableau' {
        $files = @((& $newFile 'seul.json' (& $itemText 'seul')), (& $newFile 'deux.json' ((& $itemText 'un') + ', ' + (& $itemText 'deux'))))
        $errors = [System.Collections.Generic.List[string]]::new()
        $result = @(Read-OSSetupJsonFileSet -File $files -SchemaPath $schema -Errors $errors)
        @($result | ForEach-Object { $_.Data['id'] }) | Should -Be @('seul')
        $errors.Count | Should -Be 1
        $errors[0] | Should -BeLike '*deux.json : *'
    }
}

Describe 'Format-OSSetupSchemaError' {
    BeforeAll {
        $newError = { param([string]$Message) [System.Management.Automation.ErrorRecord]::new([Exception]::new($Message), 'x', 'InvalidData', $null) }
    }

    It 'commence par la ligne du moteur, même sans détail de Test-Json' {
        Format-OSSetupSchemaError -Path 'C:\a.json' -SchemaPath 'C:\s\item.schema.json' -SchemaError @() |
            Should -BeLike 'C:\a.json : non conforme au schéma item.schema.json (vérifier*'
    }

    It 'dédoublonne et plafonne les détails' {
        $errors = @('un', 'deux', 'un', 'trois', 'quatre', 'cinq', 'six', 'sept') | ForEach-Object { & $newError $_ }
        $lines = (Format-OSSetupSchemaError -Path 'C:\a.json' -SchemaPath 'item.schema.json' -SchemaError $errors) -split "`n"
        $lines[0] | Should -Be 'C:\a.json : non conforme au schéma item.schema.json :'
        @($lines | Select-Object -Skip 1 | ForEach-Object { $_.Trim() }) | Should -Be @('un', 'deux', 'trois', 'quatre', 'cinq', '… 2 autre(s) détail(s)')
    }
}

Describe 'Test-OSSetupDataReference' {
    It 'refuse qu''un profil installe un logiciel hors d''un groupe de choix' {
        $data = [pscustomobject]@{
            Items    = @{
                app     = @{ id = 'app'; actions = @(@{ provider = 'winget'; id = 'Some.App' }) }
                feature = @{ id = 'feature'; actions = @(@{ provider = 'windows-feature'; name = 'X' }) }
                setting = @{ id = 'setting'; actions = @(@{ provider = 'registry'; path = 'HKCU:\x' }) }
            }
            Profiles = @{
                p = @{ id = 'p'; items = @('app', 'feature', 'setting'); choices = @(@{ id = 'c'; options = @('app'); default = @() }) }
            }
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems.Count | Should -Be 2
        $problems -join "`n" | Should -Match "'app' installe"
        $problems -join "`n" | Should -Match "'feature' installe"
    }

    It 'refuse qu''un élément dépende d''un élément « runLast » sans l''être lui-même' {
        $data = [pscustomobject]@{
            Items    = @{
                layout = @{ id = 'layout'; runLast = $true }
                early  = @{ id = 'early'; dependsOn = @('layout') }
                late   = @{ id = 'late'; runLast = $true; dependsOn = @('layout') }
            }
            Profiles = @{}
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems.Count | Should -Be 1
        $problems[0] | Should -BeLike "élément 'early' : la dépendance 'layout' est traitée en dernier*"
    }

    It 'refuse qu''un profil déclare une variable du nom d''une variable intégrée' {
        $data = [pscustomobject]@{
            Items    = @{}
            Profiles = @{ p = @{ id = 'p'; variables = @{ DevRoot = @{ prompt = 'x'; default = 'y' }; programFiles = @{ prompt = 'x'; default = 'y' } } } }
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems.Count | Should -Be 1
        $problems[0] | Should -BeLike "*'programFiles' porte le nom d'une variable intégrée*"
    }

    It 'refuse un unlessSelected qui désigne un élément inconnu' {
        $data = [pscustomobject]@{
            Items    = @{
                known = @{ id = 'known' }
                a     = @{ id = 'a'; actions = @(@{ provider = 'shortcut'; unlessSelected = 'known' }, @{ provider = 'shortcut'; unlessSelected = 'nope' }) }
            }
            Profiles = @{}
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems | Should -Be @("élément 'a' : unlessSelected désigne un élément inconnu 'nope'.")
    }

    It 'détecte un cycle de dépendances au chargement' {
        $data = [pscustomobject]@{
            Items    = [ordered]@{
                a = @{ id = 'a'; dependsOn = @('b') }
                b = @{ id = 'b'; dependsOn = @('c') }
                c = @{ id = 'c'; dependsOn = @('a') }
                d = @{ id = 'd'; dependsOn = @('a', 'd') }
            }
            Profiles = @{}
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems | Should -Be @("élément 'a' : cycle de dépendances (a → b → c → a).", "élément 'd' : cycle de dépendances (d → d).")
    }

    It 'refuse des valeurs par défaut hors des bornes du groupe' {
        $items = @{ x = @{ id = 'x' }; y = @{ id = 'y' } }
        $data = [pscustomobject]@{
            Items    = $items
            Profiles = @{
                p = @{
                    id      = 'p'
                    choices = @(
                        @{ id = 'single'; mode = 'single'; options = @('x', 'y'); default = @('x', 'y') }
                        @{ id = 'min'; mode = 'multi'; options = @('x', 'y'); min = 1 }
                        @{ id = 'max'; mode = 'multi'; options = @('x', 'y'); max = 1; default = @('x', 'y') }
                        @{ id = 'ok'; mode = 'multi'; options = @('x', 'y'); min = 1; default = @('y') }
                    )
                }
            }
        }
        $problems = @(Test-OSSetupDataReference -Data $data)
        $problems | Should -Be @(
            "profil 'p' : choix 'single', 2 valeur(s) par défaut, attendu entre 0 et 1."
            "profil 'p' : choix 'min', 0 valeur(s) par défaut, attendu entre 1 et 2."
            "profil 'p' : choix 'max', 2 valeur(s) par défaut, attendu entre 0 et 1."
        )
    }

    It 'accepte dans ''items'' un élément sans action (épingle seule)' {
        $data = [pscustomobject]@{
            Items    = @{ pin = @{ id = 'pin'; taskbarPin = @{ link = 'x.lnk' } } }
            Profiles = @{ p = @{ id = 'p'; items = @('pin') } }
        }
        @(Test-OSSetupDataReference -Data $data).Count | Should -Be 0
    }
}
