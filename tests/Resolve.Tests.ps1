BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    function New-TestItem {
        param([string]$Id, [string[]]$DependsOn = @(), [string[]]$Platforms = @('windows'))
        [ordered]@{ id = $Id; name = $Id.ToUpperInvariant(); category = 'test'; platforms = $Platforms; dependsOn = $DependsOn; actions = @() }
    }

    function New-TestData {
        $items = [ordered]@{}
        foreach ($item in @(
                (New-TestItem -Id 'a'),
                (New-TestItem -Id 'b' -DependsOn 'c'),
                (New-TestItem -Id 'c'),
                (New-TestItem -Id 'x'),
                (New-TestItem -Id 'y'),
                (New-TestItem -Id 'lin' -Platforms 'linux')
            )) {
            $items[$item.id] = $item
        }
        $profiles = [ordered]@{
            base = [ordered]@{
                id = 'base'; name = 'Base'; items = @('a')
                choices = @([ordered]@{ id = 'pick'; prompt = 'Choix'; mode = 'multi'; options = @('x', 'y'); default = @('x'); min = 0 })
            }
            dev  = [ordered]@{
                id = 'dev'; name = 'Dev'; extends = @('base'); items = @('b')
                choices = @([ordered]@{ id = 'one'; prompt = 'Un seul'; mode = 'single'; options = @('x', 'y'); default = @('y') })
                variables = [ordered]@{ Root = [ordered]@{ prompt = 'Racine'; default = '{{Base}}\dev' } }
            }
        }
        [pscustomobject]@{ Root = 'C:\repo'; Items = $items; Profiles = $profiles }
    }

    $windows = @{ Platform = 'windows'; GpuVendor = @('intel', 'nvidia'); Activated = $false }
}

Describe 'Resolve-OSSetupProfileSet' {
    It 'place les profils étendus avant le profil demandé, sans doublon' {
        $data = New-TestData
        Resolve-OSSetupProfileSet -Data $data -ProfileId 'dev', 'base' | Should -Be @('base', 'dev')
    }

    It 'détecte un cycle d''héritage' {
        $data = New-TestData
        $data.Profiles['base']['extends'] = @('dev')
        { Resolve-OSSetupProfileSet -Data $data -ProfileId 'dev' } | Should -Throw '*Cycle*'
    }

    It 'rejette un profil inconnu' {
        { Resolve-OSSetupProfileSet -Data (New-TestData) -ProfileId 'nope' } | Should -Throw '*inconnu*'
    }
}

Describe 'Resolve-OSSetupItemList' {
    It 'combine profils, choix par défaut et dépendances dans l''ordre' {
        $answers = @{ profiles = @('dev') }
        Resolve-OSSetupItemList -Data (New-TestData) -Answers $answers -Facts $windows | Should -Be @('a', 'c', 'b', 'x', 'y')
    }

    It 'utilise les choix explicites du fichier de réponses' {
        $answers = @{ profiles = @('base'); choices = @{ pick = @('y') } }
        Resolve-OSSetupItemList -Data (New-TestData) -Answers $answers -Facts $windows | Should -Be @('a', 'y')
    }

    It 'n''ajoute pas en silence une dépendance proposée dans un menu mais non choisie' {
        # 'c' dépend de 'x', option du choix « pick » : 'c' (et 'b', qui dépend de 'c') sont ignorés si 'x' n'est pas coché.
        $data = New-TestData
        $data.Items['c']['dependsOn'] = @('x')
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        $answers = @{ profiles = @('dev'); choices = @{ pick = @('y'); one = @('y') } }
        Resolve-OSSetupItemList -Data $data -Answers $answers -Facts $windows | Should -Be @('a', 'y')
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -ParameterFilter { $Message -match "'c' ignoré : nécessite 'x', non choisi" }

        $answers = @{ profiles = @('dev'); choices = @{ pick = @('x'); one = @('y') } }
        Resolve-OSSetupItemList -Data $data -Answers $answers -Facts $windows | Should -Be @('a', 'x', 'c', 'b', 'y')
    }

    It 'n''ajoute pas la dépendance technique d''un élément ignoré' {
        # 'x' dépend de 'c' (technique) puis de 'y' (proposé, non coché) : 'x' est ignoré, 'c' n'a plus de raison d'être.
        $data = New-TestData
        $data.Items['x']['dependsOn'] = @('c', 'y')
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Resolve-OSSetupItemList -Data $data -Answers @{ profiles = @('base'); choices = @{ pick = @('x') } } -Facts $windows | Should -Be @('a')
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -ParameterFilter { $Message -match "'x' ignoré : nécessite 'y', non choisi" }

        # Même chose quand l'élément refusé est plus loin dans la chaîne : 'x' → 'b' → 'c' → 'y'.
        $data = New-TestData
        $data.Items['x']['dependsOn'] = @('b')
        $data.Items['c']['dependsOn'] = @('y')
        Resolve-OSSetupItemList -Data $data -Answers @{ profiles = @('base'); choices = @{ pick = @('x') } } -Facts $windows | Should -Be @('a')
    }

    It 'ignore les éléments d''une autre plateforme' {
        $data = New-TestData
        $data.Profiles['base']['items'] = @('a', 'lin')
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Resolve-OSSetupItemList -Data $data -Answers @{ profiles = @('base') } -Facts $windows | Should -Be @('a', 'x')
    }

    It 'détecte un cycle de dépendances' {
        $data = New-TestData
        $data.Items['c']['dependsOn'] = @('b')
        { Resolve-OSSetupItemList -Data $data -Answers @{ profiles = @('dev') } -Facts $windows } | Should -Throw '*Cycle*'
    }
}

Describe 'Get-OSSetupChoiceWarning' {
    BeforeAll {
        $data = New-TestData
        $data.Items['y']['uncheckedWarning'] = 'Attention à y.'
    }

    It 'avertit pour un élément proposé mais non coché (valeurs par défaut comprises)' {
        # Choix « pick » : défaut x, donc y non coché.
        $warnings = @(Get-OSSetupChoiceWarning -Data $data -Answers @{ profiles = @('base') })
        $warnings.Count | Should -Be 1
        $warnings[0].ItemId | Should -Be 'y'
        $warnings[0].Message | Should -Be 'Attention à y.'
    }

    It 'n''avertit pas quand l''élément est coché' {
        @(Get-OSSetupChoiceWarning -Data $data -Answers @{ profiles = @('base'); choices = @{ pick = @('x', 'y') } }).Count | Should -Be 0
    }

    It 'se limite au groupe demandé' {
        # Profil dev : « pick » (y non coché) et « one » (défaut y, coché).
        $answers = @{ profiles = @('dev'); choices = @{ pick = @('x') } }
        @(Get-OSSetupChoiceWarning -Data $data -Answers $answers -ChoiceId 'one').Count | Should -Be 0
        @(Get-OSSetupChoiceWarning -Data $data -Answers $answers -ChoiceId 'pick').Count | Should -Be 1
    }

    It 'avertit pour un élément coché qui le déclare (checkedWarning)' {
        $local = New-TestData
        $local.Items['x']['checkedWarning'] = 'Supprimer x efface des données.'
        $warnings = @(Get-OSSetupChoiceWarning -Data $local -Answers @{ profiles = @('base') })
        $warnings.Count | Should -Be 1
        $warnings[0].ItemId | Should -Be 'x'
        $warnings[0].Checked | Should -BeTrue
        @(Get-OSSetupChoiceWarning -Data $local -Answers @{ profiles = @('base'); choices = @{ pick = @('y') } }).Count | Should -Be 0
    }
}

Describe 'Get-OSSetupAvailableOption' {
    It 'masque une option dont la dépendance est proposée mais non choisie' {
        # 'y' dépend de 'x', option du choix « pick » (défaut : x).
        $data = New-TestData
        $data.Items['y']['dependsOn'] = @('x')
        $choice = $data.Profiles['dev']['choices'][0]
        @(Get-OSSetupAvailableOption -Data $data -Answers @{ profiles = @('dev') } -Choice $choice) | Should -Be @('x', 'y')
        @(Get-OSSetupAvailableOption -Data $data -Answers @{ profiles = @('dev'); choices = @{ pick = @('y') } } -Choice $choice) | Should -Be @('x')
    }

    It 'garde une option dont la dépendance n''est proposée dans aucun menu (dépendance technique)' {
        $data = New-TestData
        $data.Items['y']['dependsOn'] = @('c')
        $choice = $data.Profiles['base']['choices'][0]
        @(Get-OSSetupAvailableOption -Data $data -Answers @{ profiles = @('base') } -Choice $choice) | Should -Be @('x', 'y')
    }
}

Describe 'Resolve-OSSetupItemList : runLast' {
    It 'place les éléments « runLast » en fin de liste' {
        $data = New-TestData
        $data.Items['a']['runLast'] = $true
        Resolve-OSSetupItemList -Data $data -Answers @{ profiles = @('base') } -Facts $windows | Should -Be @('x', 'a')
    }
}

Describe 'Test-OSSetupItemApplicable' {
    It 'accepte un élément sans condition sur la bonne plateforme' {
        Test-OSSetupItemApplicable -Item (New-TestItem -Id 'a') -Facts $windows | Should -BeTrue
    }

    It 'accepte si une des valeurs d''un fait liste correspond' {
        $item = New-TestItem -Id 'a'
        $item['when'] = @{ GpuVendor = 'nvidia' }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeTrue
    }

    It 'refuse si une condition n''est pas remplie' {
        $item = New-TestItem -Id 'a'
        $item['when'] = @{ GpuVendor = 'nvidia'; Activated = $true }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeFalse
    }

    It 'accepte un fait attendu à false' {
        $item = New-TestItem -Id 'a'
        $item['when'] = @{ Activated = $false }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeTrue
        $item['when'] = @{ Activated = @($false) }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeTrue
        $item['when'] = @{ Activated = $true }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeFalse
    }

    It 'accepte une liste de valeurs attendues' {
        $item = New-TestItem -Id 'a'
        $item['when'] = @{ GpuVendor = @('amd', 'intel') }
        Test-OSSetupItemApplicable -Item $item -Facts $windows | Should -BeTrue
    }
}

Describe 'ConvertTo-OSSetupVendor' {
    It 'normalise <Name> en <Expected>' -ForEach @(
        @{ Name = 'NVIDIA GeForce RTX 3070'; Expected = 'nvidia' }
        @{ Name = 'AuthenticAMD'; Expected = 'amd' }
        @{ Name = 'GenuineIntel'; Expected = 'intel' }
        @{ Name = 'Gigabyte Technology Co., Ltd.'; Expected = 'gigabyte' }
        @{ Name = 'Microsoft Basic Display Adapter'; Expected = 'microsoft' }
        @{ Name = 'Inconnu SA'; Expected = 'other' }
    ) {
        ConvertTo-OSSetupVendor -Name $Name | Should -Be $Expected
    }
}

Describe 'Test-OSSetupAnswer' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-OSSetupLog {}
    }

    It 'accepte des réponses valides' {
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); choices = @{ pick = @('x', 'y'); one = @('x') } } } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 0 -Exactly
    }

    It 'ignore une option inconnue du groupe avec un avertissement, et garde le reste des réponses' {
        $answers = @{ profiles = @('dev'); choices = @{ pick = @('x', 'retiree'); one = @('x') } }
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        $answers['choices']['pick'] | Should -Be @('x')
        $answers['choices']['one'] | Should -Be @('x')
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -eq "Choix 'pick' : option 'retiree' inconnue, ignorée."
        }
        Resolve-OSSetupItemList -Data (New-TestData) -Answers $answers -Facts $windows | Should -Be @('a', 'c', 'b', 'x')
    }

    It 'ignore aussi un élément connu qui n''est pas une option du groupe' {
        $answers = @{ profiles = @('base'); choices = @{ pick = @('a') } }
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        , $answers['choices']['pick'] | Should -BeOfType [array]
        $answers['choices']['pick'].Count | Should -Be 0
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like "*option 'a' inconnue*" }
    }

    It 'rejette plusieurs sélections pour un choix unique' {
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); choices = @{ one = @('x', 'y') } } } | Should -Throw '*entre 0 et 1*'
    }

    It 'compte les sélections sans les options ignorées' {
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); choices = @{ one = @('x', 'retiree') } } } | Should -Not -Throw
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); choices = @{ one = @('x', 'y', 'retiree') } } } | Should -Throw '*entre 0 et 1*'
    }

    It 'ignore un groupe de choix retiré du catalogue avec un avertissement, et garde le reste des réponses' {
        $answers = @{ profiles = @('dev'); choices = @{ retire = @('x'); one = @('x') } }
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        $answers['choices'].Contains('retire') | Should -BeFalse
        $answers['choices']['one'] | Should -Be @('x')
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'Warning' -and $Message -eq "Groupe de choix 'retire' inconnu, ignoré."
        }
    }

    It 'rejette un groupe de choix hors des profils sélectionnés' {
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('base'); choices = @{ one = @('x') } } } | Should -Throw '*aucun profil*'
    }

    It 'compare groupes et options en tenant compte de la casse, comme les clés JSON' {
        # Table sensible à la casse, comme celle que produit ConvertFrom-Json -AsHashtable.
        $answers = '{ "profiles": ["base"], "choices": { "Pick": ["y"] } }' | ConvertFrom-Json -AsHashtable
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        $answers['choices'].Count | Should -Be 0
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq "Groupe de choix 'Pick' inconnu, ignoré." }

        $answers = '{ "profiles": ["base"], "choices": { "pick": ["Y"] } }' | ConvertFrom-Json -AsHashtable
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        $answers['choices']['pick'].Count | Should -Be 0
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like "*option 'Y' inconnue*" }
    }

    It 'ignore avec un avertissement une variable qu''aucun profil choisi ne déclare' {
        $answers = '{ "profiles": ["dev"], "variables": { "Root": "D:\\Dev", "RootDir": "x", "root": "y" } }' | ConvertFrom-Json -AsHashtable
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        @($answers['variables'].Keys) | Should -Be @('Root')
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 2 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Variable*ignorée.' }

        # Variable d'un profil non choisi.
        $answers = @{ profiles = @('base'); variables = @{ Root = 'D:\Dev' } }
        { Test-OSSetupAnswer -Data (New-TestData) -Answers $answers } | Should -Not -Throw
        $answers['variables'].Count | Should -Be 0
    }

    It 'refuse une variable qui porte le nom d''une variable intégrée' {
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); variables = @{ ProgramFiles = 'C:\x' } } } |
            Should -Throw "*'ProgramFiles' est une variable intégrée*"
        { Test-OSSetupAnswer -Data (New-TestData) -Answers @{ profiles = @('dev'); variables = @{ userprofile = 'C:\x' } } } |
            Should -Throw '*variable intégrée*'
    }

    It 'le schéma refuse un groupe, une option ou un nom de variable mal formés' {
        $schema = Join-Path -Path $PSScriptRoot -ChildPath '..\schemas\answers.schema.json'
        Test-Json -Json '{ "profiles": ["base"], "choices": { "pick": ["x"] }, "variables": { "DevRoot": "x" } }' -SchemaFile $schema | Should -BeTrue
        Test-Json -Json '{ "profiles": ["base"], "choices": { "Pick": ["x"] } }' -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeFalse
        Test-Json -Json '{ "profiles": ["base"], "choices": { "pick": ["X"] } }' -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeFalse
        Test-Json -Json '{ "profiles": ["base"], "variables": { "Dev Root": "x" } }' -SchemaFile $schema -ErrorAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Variables' {
    It 'remplace les variables connues' {
        Expand-OSSetupString -Text '{{A}}\{{B}}' -Variables @{ A = 'x'; B = 'y' } | Should -Be 'x\y'
    }

    It 'lève une erreur sur une variable inconnue' {
        { Expand-OSSetupString -Text '{{Nope}}' -Variables @{} } | Should -Throw '*Nope*'
    }

    It 'expanse et repère les variables dans les tableaux et objets d''une action' {
        $action = '{ "provider": "registry", "value": ["{{A}}\\x", "y", ["{{B}}"], []], "options": { "Path": "{{A}}", "path": ["{{B}}"], "n": 3 }, "one": ["{{A}}"], "type": "MultiString" }' |
            ConvertFrom-Json -AsHashtable
        @(Get-OSSetupActionVariableName -Action $action | Sort-Object -Unique) | Should -Be @('A', 'B')

        $expanded = Expand-OSSetupAction -Action $action -Variables @{ A = 'C:\a'; B = 'b' }
        $expanded['value'].Count | Should -Be 4
        $expanded['value'][0] | Should -Be 'C:\a\x'
        $expanded['value'][1] | Should -Be 'y'
        , $expanded['value'][2] | Should -Be @('b')
        $expanded['value'][3].Count | Should -Be 0
        $expanded['options']['Path'] | Should -Be 'C:\a'
        , $expanded['options']['path'] | Should -Be @('b')
        $expanded['options']['n'] | Should -Be 3
        , $expanded['one'] | Should -BeOfType [array]
        $expanded['one'] | Should -Be @('C:\a')
        # L'action d'origine n'est pas modifiée.
        $action['value'][0] | Should -Be '{{A}}\x'
    }

    It 'résout défauts de profil, surcharges et références imbriquées' {
        Mock -ModuleName OSSetup -CommandName Get-OSSetupBuiltinVariable -MockWith { [ordered]@{ Base = 'C:\Users\test' } }
        $values = Resolve-OSSetupVariable -Data (New-TestData) -Answers @{ profiles = @('dev') }
        $values['Root'] | Should -Be 'C:\Users\test\dev'

        $values = Resolve-OSSetupVariable -Data (New-TestData) -Answers @{ profiles = @('dev'); variables = @{ Root = 'D:\{{Base}}' } }
        $values['Root'] | Should -Be 'D:\C:\Users\test'
    }
}
