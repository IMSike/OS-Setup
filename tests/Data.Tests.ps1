BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
    $repoRoot = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
}

Describe 'Données du dépôt' {
    It 'le catalogue et les profils sont valides' {
        { Import-OSSetupData -Root $repoRoot } | Should -Not -Throw
    }

    It 'les fichiers de réponses d''exemple sont valides et cohérents' {
        $data = Import-OSSetupData -Root $repoRoot
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
    It 'le schéma des éléments liste exactement les faits détectés par le moteur' {
        $schema = Get-Content -Path (Join-Path -Path $repoRoot -ChildPath 'schemas\item.schema.json') -Raw | ConvertFrom-Json -AsHashtable
        $schemaNames = $schema['properties']['when']['propertyNames']['enum']
        ($schemaNames | Sort-Object) | Should -Be (Get-OSSetupFactName | Sort-Object)
    }

    It 'Get-OSSetupFact retourne tous les faits' {
        $facts = Get-OSSetupFact
        @($facts.Keys) | Should -Be (Get-OSSetupFactName)
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
