BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    function New-TestOption {
        param([string[]]$Value)
        foreach ($v in $Value) { [pscustomobject]@{ Value = $v; Label = $v.ToUpperInvariant() } }
    }

    function Send-TestKey {
        # Applique une suite de touches ; retourne le premier résultat de fin de menu.
        param([hashtable]$State, [ConsoleKey[]]$Key)
        foreach ($k in $Key) {
            $result = Invoke-OSSetupMenuKey -State $State -Key $k
            if ($result) { return $result }
        }
    }

    function New-TestData {
        $items = [ordered]@{}
        foreach ($id in 'a', 'x', 'y') {
            $items[$id] = [ordered]@{ id = $id; name = $id.ToUpperInvariant(); category = 'test'; platforms = @('windows'); actions = @() }
        }
        $profiles = [ordered]@{
            base = [ordered]@{
                id = 'base'; name = 'Base'; items = @('a')
                choices = @([ordered]@{ id = 'pick'; prompt = 'Choix'; mode = 'multi'; options = @('x', 'y'); default = @('x'); min = 0 })
            }
            dev  = [ordered]@{
                id = 'dev'; name = 'Dev'; extends = @('base'); items = @()
                choices = @([ordered]@{ id = 'one'; prompt = 'Un seul'; mode = 'single'; options = @('x', 'y'); default = @('y') })
                variables = [ordered]@{ Root = [ordered]@{ prompt = 'Racine'; default = '{{UserProfile}}\dev' } }
            }
        }
        [pscustomobject]@{ Root = 'C:\repo'; Items = $items; Profiles = $profiles }
    }

    $windows = @{ Platform = 'windows' }
}

Describe 'Invoke-OSSetupMenuKey' {
    It 'Espace et Entrée cochent et décochent en mode multiple' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi
        Send-TestKey -State $state -Key Spacebar, DownArrow, Enter | Should -BeNullOrEmpty
        $state.Selected | Should -Be @('a', 'b')
        Send-TestKey -State $state -Key Enter | Should -BeNullOrEmpty
        $state.Selected | Should -Be @('a')
    }

    It 'valide uniquement sur la ligne « Valider »' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Selected 'b' -Mode multi
        $result = Send-TestKey -State $state -Key DownArrow, DownArrow, Enter
        $result.Action | Should -Be 'next'
        $result.Values | Should -Be @('b')
    }

    It 'refuse de valider hors des bornes et l''explique' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Min 1
        Send-TestKey -State $state -Key End, Enter | Should -BeNullOrEmpty
        $state.Message | Should -Match 'au moins 1'
    }

    It 'bloque une sélection au-delà du maximum' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Max 1
        Send-TestKey -State $state -Key Enter, DownArrow, Enter | Should -BeNullOrEmpty
        $state.Selected | Should -Be @('a')
        $state.Message | Should -Not -BeNullOrEmpty
    }

    It 'remplace la sélection en choix unique, sans pouvoir la vider si un choix est requis' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Selected 'a' -Mode single -Min 1 -Max 1
        Send-TestKey -State $state -Key DownArrow, Enter | Should -BeNullOrEmpty
        $state.Selected | Should -Be @('b')
        Send-TestKey -State $state -Key Enter | Should -BeNullOrEmpty
        $state.Selected | Should -Be @('b')
    }

    It 'permet de vider un choix unique facultatif' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a') -Selected 'a' -Mode single -Min 0 -Max 1
        Send-TestKey -State $state -Key Spacebar | Should -BeNullOrEmpty
        $state.Selected.Count | Should -Be 0
    }

    It 'termine immédiatement en mode action' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode action
        $result = Send-TestKey -State $state -Key DownArrow, Enter
        $result.Values | Should -Be @('b')
    }

    It 'revient en arrière avec Échap ou la ligne « Retour », seulement si autorisé' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a') -Mode multi
        Send-TestKey -State $state -Key Escape | Should -BeNullOrEmpty

        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a') -Mode multi -AllowBack
        (Send-TestKey -State $state -Key Escape).Action | Should -Be 'back'

        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a') -Mode multi -AllowBack
        (Send-TestKey -State $state -Key End, Enter).Action | Should -Be 'back'
    }

    It 'place le curseur sur « Valider » pour une étape déjà renseignée' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Selected 'a' -Mode multi -CursorOnValidate
        (Send-TestKey -State $state -Key Enter).Values | Should -Be @('a')
    }

    It 'fait boucler le curseur' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi
        Send-TestKey -State $state -Key UpArrow | Out-Null
        $state.Cursor | Should -Be 2
    }
}

Describe 'Get-OSSetupMenuLine' {
    It 'garde un nombre de lignes constant (redessin sur place)' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Min 1 -AllowBack
        $before = @(Get-OSSetupMenuLine -State $state).Count
        Send-TestKey -State $state -Key End, UpArrow, Enter | Out-Null
        $state.Message | Should -Not -BeNullOrEmpty
        @(Get-OSSetupMenuLine -State $state).Count | Should -Be $before
    }

    It 'affiche la ligne « Valider » et l''état des cases' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Selected 'b' -Mode multi
        $text = (Get-OSSetupMenuLine -State $state).Text
        $text | Should -Contain '  > [ ] A'
        $text | Should -Contain '    [x] B'
        $text | Should -Contain '    [ Valider ]'
        $text | Should -Contain 't (plusieurs choix possibles)'
    }

    It 'colore l''état d''un libellé « Sujet : état »' {
        $option = [pscustomobject]@{ Value = 'loc'; Label = 'Localisation : désactivée' }
        $state = New-OSSetupMenuState -Title 't' -Option $option -Mode multi
        $line = Get-OSSetupMenuLine -State $state | Where-Object { $_.Text -eq '  > [ ] Localisation : désactivée' }
        $line.Segments.Text | Should -Be @('  > [ ] Localisation', ' : désactivée')
        $line.Segments[1].Color | Should -Be 'Cyan'
    }

    It 'utilise les mêmes cases en choix unique, signalé dans le titre' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Selected 'b' -Mode single -Max 1
        $text = (Get-OSSetupMenuLine -State $state).Text
        $text | Should -Contain 't (un seul choix)'
        $text | Should -Contain '    [x] B'
    }
}

Describe 'Read-OSSetupMenuText' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-Host {}
        # Saisies successives ; file vide : $null, comme Read-Host quand l'entrée standard est épuisée.
        $global:OSSetupTestInput = [System.Collections.Generic.Queue[object]]::new()
        Mock -ModuleName OSSetup Read-Host { if ($global:OSSetupTestInput.Count) { $global:OSSetupTestInput.Dequeue() } else { $null } }
        function Set-TestInput([string[]]$Line) {
            foreach ($l in $Line) { $global:OSSetupTestInput.Enqueue($l) }
        }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestInput -Scope Global -ErrorAction SilentlyContinue
    }

    It 'redemande toute la saisie quand un numéro est invalide, au lieu de valider une sélection vide' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Selected 'a'
        Set-TestInput 'x', '2'
        (Read-OSSetupMenuText -State $state).Values | Should -Be @('b')
        Should -Invoke -ModuleName OSSetup Read-Host -Times 2 -Exactly
    }

    It 'refuse un numéro hors de la liste au lieu de l''ignorer' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi
        Set-TestInput '1 9', '1 2'
        (Read-OSSetupMenuText -State $state).Values | Should -Be @('a', 'b')
        Should -Invoke -ModuleName OSSetup Write-Host -Times 1 -Exactly -ParameterFilter { $Object -like '*non reconnue*''9''*' }
    }

    It 'accepte 0 pour « aucun » quand aucun choix n''est requis, et l''annonce' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Selected 'a'
        Set-TestInput '0'
        $result = Read-OSSetupMenuText -State $state
        $result.Action | Should -Be 'next'
        @($result.Values).Count | Should -Be 0
        Should -Invoke -ModuleName OSSetup Read-Host -ParameterFilter { $Prompt -like '*0 pour aucun*' }
    }

    It 'n''accepte pas 0 quand un choix est requis' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Min 1
        Set-TestInput '0', '1'
        (Read-OSSetupMenuText -State $state).Values | Should -Be @('a')
        Should -Invoke -ModuleName OSSetup Read-Host -Times 2 -Exactly -ParameterFilter { $Prompt -notlike '*0 pour aucun*' }
    }

    It 'explique les bornes d''un menu sans maximum comme le menu au clavier' {
        $state = New-OSSetupMenuState -Title 't' -Option (New-TestOption 'a', 'b') -Mode multi -Min 1
        Set-TestInput '', '1'
        (Read-OSSetupMenuText -State $state).Values | Should -Be @('a')
        Should -Invoke -ModuleName OSSetup Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Sélectionnez au moins 1 élément(s).' }
        Should -Invoke -ModuleName OSSetup Write-Host -Times 0 -Exactly -ParameterFilter { $Object -like '*2147483647*' }
    }

    It 'lève une erreur explicite quand l''entrée standard est épuisée' {
        $state = New-OSSetupMenuState -Title 'Profils' -Option (New-TestOption 'a') -Mode multi
        { Read-OSSetupMenuText -State $state } | Should -Throw '*Profils*-AnswerFile*-Yes*'
    }
}

Describe 'Save-OSSetupAnswerFile' {
    It 'écrit à un chemin qui contient des crochets (chemin littéral)' {
        $path = Join-Path -Path $TestDrive -ChildPath 'Réponses [poste]\dev.json'
        Save-OSSetupAnswerFile -Answers @{ profiles = @('dev'); choices = @{}; variables = @{} } -Path $path
        (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).profiles | Should -Be @('dev')
    }

    It 'écrit un fichier relisible quand les réponses lues n''ont ni choix ni variables' {
        $source = Join-Path -Path $TestDrive -ChildPath 'sans-choix.json'
        $path = Join-Path -Path $TestDrive -ChildPath 'answers-last.json'
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        Set-Content -LiteralPath $source -Value '{ "profiles": ["base"] }'
        Save-OSSetupAnswerFile -Answers (Read-OSSetupAnswerFile -Path $source -Root $root) -Path $path
        $answers = Read-OSSetupAnswerFile -Path $path -Root $root
        $answers['profiles'] | Should -Be @('base')
        $answers['choices'].Count | Should -Be 0
        $answers['variables'].Count | Should -Be 0
    }

    It 'restitue profils, choix et informations personnelles (accents compris) à la relecture' {
        $path = Join-Path -Path $TestDrive -ChildPath 'complet.json'
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
        $saved = @{
            profiles  = @('base', 'dev')
            choices   = [ordered]@{ browsers = @('firefox'); 'claude-options' = @() }
            variables = [ordered]@{ GitUserName = 'Hélène Dupré'; DevRoot = 'D:\dev' }
        }
        Save-OSSetupAnswerFile -Answers $saved -Path $path
        $answers = Read-OSSetupAnswerFile -Path $path -Root $root
        $answers['profiles'] | Should -Be @('base', 'dev')
        , $answers['choices']['browsers'] | Should -Be @('firefox')
        $answers['choices']['claude-options'].Count | Should -Be 0
        $answers['variables']['GitUserName'] | Should -BeExactly 'Hélène Dupré'
        $answers['variables']['DevRoot'] | Should -Be 'D:\dev'
    }

    It 'refuse un fichier non conforme au schéma, en citant l''écart' {
        $path = Join-Path -Path $TestDrive -ChildPath 'invalide.json'
        Set-Content -LiteralPath $path -Value '{ "profiles": ["base"], "variables": { "GitUserName": 42 } }'
        { Read-OSSetupAnswerFile -Path $path -Root (Join-Path -Path $PSScriptRoot -ChildPath '..') } | Should -Throw '*Fichier de réponses invalide*variables*'
    }
}

Describe 'Read-OSSetupAnswer' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        Mock -ModuleName OSSetup Read-OSSetupMenu { $global:OSSetupTestMenuQueue.Dequeue() }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestMenuQueue -Scope Global -ErrorAction SilentlyContinue
    }

    It 'enchaîne les étapes et tient compte d''un retour arrière' {
        $global:OSSetupTestMenuQueue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($result in @(
                @{ Action = 'next'; Values = @('dev') }        # Profils
                @{ Action = 'next'; Values = @('x', 'y') }     # Choix (base)
                @{ Action = 'back'; Values = @() }             # Un seul (dev) : retour
                @{ Action = 'next'; Values = @('y') }          # Choix, modifié
                @{ Action = 'next'; Values = @('x') }          # Un seul
                @{ Action = 'next'; Values = @('keep') }       # Emplacements
            )) { $global:OSSetupTestMenuQueue.Enqueue($result) }

        $answers = Read-OSSetupAnswer -Data (New-TestData) -Facts $windows
        $answers.profiles | Should -Be @('dev')
        $answers.choices['pick'] | Should -Be @('y')
        $answers.choices['one'] | Should -Be @('x')
        $answers.variables.Count | Should -Be 0
        $global:OSSetupTestMenuQueue.Count | Should -Be 0
    }

    It 'retire les choix des profils abandonnés en revenant en arrière' {
        $global:OSSetupTestMenuQueue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($result in @(
                @{ Action = 'next'; Values = @('dev') }
                @{ Action = 'next'; Values = @('x') }
                @{ Action = 'next'; Values = @('y') }          # choix « one » de dev
                @{ Action = 'back'; Values = @() }             # Emplacements : retour
                @{ Action = 'back'; Values = @() }             # Un seul : retour
                @{ Action = 'back'; Values = @() }             # Choix : retour
                @{ Action = 'next'; Values = @('base') }       # Profils : base seul
                @{ Action = 'next'; Values = @('x') }
            )) { $global:OSSetupTestMenuQueue.Enqueue($result) }

        $answers = Read-OSSetupAnswer -Data (New-TestData) -Facts $windows
        $answers.profiles | Should -Be @('base')
        @($answers.choices.Keys) | Should -Be @('pick')
    }

    It 'reprend des réponses existantes à l''étape demandée' {
        $global:OSSetupTestMenuQueue = [System.Collections.Generic.Queue[object]]::new()
        $global:OSSetupTestMenuQueue.Enqueue(@{ Action = 'next'; Values = @('x') })      # Un seul
        $global:OSSetupTestMenuQueue.Enqueue(@{ Action = 'next'; Values = @('keep') })   # Emplacements

        $existing = @{ profiles = @('dev'); choices = @{ pick = @('y'); one = @('y') }; variables = @{} }
        $answers = Read-OSSetupAnswer -Data (New-TestData) -Facts $windows -Answers $existing -StartStep 'choice:one'
        $answers.choices['pick'] | Should -Be @('y')
        $answers.choices['one'] | Should -Be @('x')
    }
}
