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
                variables = [ordered]@{ Root = [ordered]@{ prompt = 'Racine'; default = '{{Temp}}\dev' } }
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
