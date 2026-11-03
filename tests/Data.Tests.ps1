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

    It 'chaque action winget de source msstore donne le nom de son paquet appx (packageName)' {
        $missing = foreach ($item in $data.Items.Values) {
            foreach ($action in $item['actions']) {
                if ($action['provider'] -eq 'winget' -and $action['source'] -eq 'msstore' -and -not $action['packageName']) { $item['id'] }
            }
        }
        @($missing).Count | Should -Be 0 -Because "winget list rattache aussi un MSI au produit du Store (sans packageName : $($missing -join ', '))"
    }

    It 'chaque tâche logon-task, lancée avec les droits les plus élevés, exécute un script sous {{ProgramFiles}}\OS-Setup' {
        $variables = Resolve-OSSetupVariable -Data $data -Answers @{ profiles = @($data.Profiles.Keys) }
        $found = @(Get-UnsafeLogonTaskScript -Data $data -Variables $variables)
        $found.Count | Should -Be 0 -Because "un script modifiable sans élévation et lancé avec les droits les plus élevés donne les droits administrateur sans invite UAC : le déployer sous {{ProgramFiles}}\OS-Setup ($($found -join ', '))"
    }

    It 'le contrôle des scripts de logon-task refuse tout script hors de {{ProgramFiles}}\OS-Setup' {
        $variables = Get-OSSetupBuiltinVariable -Root $repoRoot
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
            @{ Categories = @('browser-settings'); Page = 'windows\browsers.md' }
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
            Mock -ModuleName OSSetup Get-ItemProperty -ParameterFilter { $Path -eq 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' } {
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
        { Import-OSSetupData -Root $root } | Should -Throw '*bad.json*non conforme*'
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
}
