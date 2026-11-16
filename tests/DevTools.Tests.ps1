BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    function New-TestData {
        $items = [ordered]@{
            identity = [ordered]@{
                id = 'identity'; name = 'Identité'; category = 'test'; platforms = @('windows'); dependsOn = @()
                actions = @([ordered]@{ provider = 'git-config'; key = 'user.name'; value = '{{UserName}}' })
            }
            after    = [ordered]@{
                id = 'after'; name = 'Après'; category = 'test'; platforms = @('windows'); dependsOn = @('identity')
                actions = @([ordered]@{ provider = 'git-config'; key = 'core.editor'; value = 'code --wait' })
            }
        }
        $profiles = [ordered]@{
            dev = [ordered]@{
                id = 'dev'; name = 'Dev'; items = @('identity', 'after'); choices = @()
                variables = [ordered]@{
                    Root     = [ordered]@{ prompt = 'Racine'; default = 'C:\dev' }
                    UserName = [ordered]@{ prompt = 'Nom pour Git'; personal = $true }
                }
            }
        }
        [pscustomobject]@{ Root = 'C:\repo'; Items = $items; Profiles = $profiles }
    }
}

Describe 'Informations personnelles' {
    It 'sépare emplacements et informations personnelles' {
        $data = New-TestData
        @((Get-OSSetupVariableDefinition -Data $data -ResolvedProfileId 'dev' -Kind location).Keys) | Should -Be @('Root')
        @((Get-OSSetupVariableDefinition -Data $data -ResolvedProfileId 'dev' -Kind personal).Keys) | Should -Be @('UserName')
    }

    It 'liste celles qui ne sont pas renseignées, et les prend en compte une fois renseignées' {
        $data = New-TestData
        (Get-OSSetupMissingVariable -Data $data -Answers @{ profiles = @('dev') })['UserName'] | Should -Be 'Nom pour Git'
        $answers = @{ profiles = @('dev'); variables = @{ UserName = 'Ada' } }
        (Get-OSSetupMissingVariable -Data $data -Answers $answers).Count | Should -Be 0
        (Resolve-OSSetupVariable -Data $data -Answers $answers)['UserName'] | Should -Be 'Ada'
    }

    It 'ajoute l''étape « Informations personnelles » à l''assistant' {
        $steps = @(Get-OSSetupWizardStep -Data (New-TestData) -Facts @{} -Answers @{ profiles = @('dev') } -SkipProfiles)
        $steps.Id | Should -Be @('personal', 'locations')
    }

    It 'ignore les actions qui utilisent une information non renseignée, et leurs dépendants' {
        Mock -ModuleName OSSetup -CommandName git -MockWith { $global:LASTEXITCODE = 1 }
        $data = New-TestData
        $answers = @{ profiles = @('dev') }
        $context = @{
            Variables        = Resolve-OSSetupVariable -Data $data -Answers $answers
            MissingVariables = Get-OSSetupMissingVariable -Data $data -Answers $answers
        }
        $plan = @(Get-OSSetupPlan -Data $data -ItemId 'identity', 'after' -Context $context)
        $plan[0].Status | Should -Be 'skipped'
        $plan[0].Detail | Should -Match 'Nom pour Git'
        $plan[1].Status | Should -Be 'todo'

        $results = @(Invoke-OSSetupPlan -Plan $plan -Context $context -WhatIf)
        $results.Status | Should -Be @('skipped', 'skipped')
        Should -Invoke -ModuleName OSSetup -CommandName git -ParameterFilter { $args -notcontains '--get' } -Times 0 -Exactly
    }

    It 'ignore aussi une action qui ne l''utilise que dans un tableau ou un objet' {
        $data = New-TestData
        $data.Items['identity']['actions'] = @(
            [ordered]@{ provider = 'registry'; path = 'HKCU:\Software\OSSetupTest'; name = 'Names'; type = 'MultiString'; value = @('x', '{{UserName}}') }
            [ordered]@{ provider = 'file'; target = 'C:\x.json'; mode = 'merge-json'; source = 'x.json'; options = [ordered]@{ user = [ordered]@{ name = '{{UserName}}' } } }
        )
        $answers = @{ profiles = @('dev') }
        $context = @{
            Variables        = Resolve-OSSetupVariable -Data $data -Answers $answers
            MissingVariables = Get-OSSetupMissingVariable -Data $data -Answers $answers
        }
        $plan = @(Get-OSSetupPlan -Data $data -ItemId 'identity' -Context $context)
        $plan.Status | Should -Be @('skipped', 'skipped')
        $plan[0].Detail | Should -Match 'Nom pour Git'
        $plan[1].Detail | Should -Match 'Nom pour Git'
    }
}

Describe 'Provider git-config' {
    It 'est conforme quand la clé a déjà la valeur, et l''écrit sinon' {
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'git-config'
            $action = @{ key = 'pull.rebase'; value = 'true' }
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'git.exe' } } -ParameterFilter { $Name -eq 'git' }
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 0; 'true' }
            & $provider.Test $action @{} | Should -BeTrue
            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 1 }
            & $provider.Test $action @{} | Should -BeFalse

            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 0 }
            & $provider.Invoke $action @{}
            Should -Invoke -CommandName git -ParameterFilter { ($args -join ' ') -eq 'config --global pull.rebase true' } -Times 1 -Exactly

            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 255 }
            { & $provider.Invoke $action @{} } | Should -Throw '*git config*255*'
        }
    }

    It 'lit une valeur accentuée en UTF-8 (sortie de git), sans la journaliser' {
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'git-config'
            $action = @{ key = 'user.name'; value = 'Prénom Nom' }
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'git.exe' } } -ParameterFilter { $Name -eq 'git' }
            Mock -CommandName Write-OSSetupLog
            # Git écrit en UTF-8 : décodée avec une autre page de code, la valeur serait corrompue.
            Mock -CommandName git -MockWith {
                $global:LASTEXITCODE = 0
                if ([Console]::OutputEncoding.CodePage -eq 65001) { 'Prénom Nom' } else { 'PrÃ©nom Nom' }
            }
            $before = [Console]::OutputEncoding
            try {
                [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
                & $provider.Test $action @{} | Should -BeTrue
                (& $provider.Read $action @{})['value'] | Should -Be 'Prénom Nom'
                [Console]::OutputEncoding.CodePage | Should -Be 850
            }
            finally {
                [Console]::OutputEncoding = $before
            }
            Should -Invoke -CommandName Write-OSSetupLog -Times 0 -Exactly
        }
    }

    It 'est non conforme, sans erreur, quand git est absent' {
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'git-config'
            Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'git' }
            Mock -CommandName git
            & $provider.Test @{ key = 'pull.rebase'; value = 'true' } @{} | Should -BeFalse
            (& $provider.Read @{ key = 'pull.rebase'; value = 'true' } @{})['exists'] | Should -BeFalse
            Should -Invoke -CommandName git -Times 0 -Exactly
        }
    }
}

Describe 'Étapes manuelles' {
    It 'ne lance rien sans surveillance et signale l''étape à faire plus tard' {
        Mock -ModuleName OSSetup -CommandName Start-OSSetupManualAssist
        $action = [ordered]@{ provider = 'manual'; check = 'default-browser'; value = 'VivaldiHTM*'; instructions = 'choisir Vivaldi.' }
        { Invoke-OSSetupManualStep -Action $action -Context @{ Interactive = $false } } | Should -Throw '*plus tard*choisir Vivaldi*'
        Should -Invoke -ModuleName OSSetup -CommandName Start-OSSetupManualAssist -Times 0 -Exactly
    }

    It 'vérifie le navigateur par défaut d''après le choix de l''utilisateur' {
        Mock -ModuleName OSSetup -CommandName Get-ItemProperty -MockWith { [pscustomobject]@{ ProgId = 'VivaldiHTM.ABC123' } }
        Test-OSSetupManualStep -Check 'default-browser' -Value 'VivaldiHTM*' | Should -BeTrue
        Test-OSSetupManualStep -Check 'default-browser' -Value 'FirefoxURL-*' | Should -BeFalse
    }

    It 'vérifie qu''une distribution WSL a un compte autre que root' {
        Mock -ModuleName OSSetup -CommandName Get-OSSetupWslDistribution -MockWith {
            [pscustomobject]@{ Name = 'Ubuntu'; DefaultUid = 0 }
            [pscustomobject]@{ Name = 'Debian'; DefaultUid = 1000 }
        }
        Test-OSSetupManualStep -Check 'wsl-user' -Value 'Ubuntu' | Should -BeFalse
        Test-OSSetupManualStep -Check 'wsl-user' -Value 'Debian' | Should -BeTrue
    }

    It 'termine quand la vérification réussit après l''aide' {
        Mock -ModuleName OSSetup -CommandName Start-OSSetupManualAssist
        Mock -ModuleName OSSetup -CommandName Write-Host
        Mock -ModuleName OSSetup -CommandName Read-OSSetupMenu -MockWith { @{ Action = 'next'; Values = @('check') } }
        Mock -ModuleName OSSetup -CommandName Test-OSSetupManualStep -MockWith { $true }
        $action = [ordered]@{ provider = 'manual'; check = 'gh-auth'; instructions = 'se connecter.' }
        { Invoke-OSSetupManualStep -Action $action -Context @{ Interactive = $true } } | Should -Not -Throw
        Should -Invoke -ModuleName OSSetup -CommandName Start-OSSetupManualAssist -Times 1 -Exactly
    }

    It 'n''écrit pas au journal la consigne déjà portée par la ligne de l''étape, mais l''affiche' {
        # Sans description, la ligne de l'étape est « étape manuelle : <consigne> » (provider manual).
        Mock -ModuleName OSSetup -CommandName Start-OSSetupManualAssist
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName Write-Host
        Mock -ModuleName OSSetup -CommandName Read-OSSetupMenu -MockWith { @{ Action = 'next'; Values = @('check') } }
        Mock -ModuleName OSSetup -CommandName Test-OSSetupManualStep -MockWith { $true }
        $action = [ordered]@{ provider = 'manual'; check = 'gh-auth'; instructions = 'se connecter.' }
        InModuleScope OSSetup { & (Get-OSSetupProvider -Name 'manual').Describe @{ instructions = 'se connecter.' } @{} } |
            Should -Be 'étape manuelle : se connecter.'
        Invoke-OSSetupManualStep -Action $action -Context @{ Interactive = $true }
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup -CommandName Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'Étape manuelle : se connecter.' }
    }

    It 'écrit la consigne et chaque vérification manquée au journal quand l''action a sa propre description' {
        Mock -ModuleName OSSetup -CommandName Start-OSSetupManualAssist
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName Write-Host
        $global:OSSetupTestMenuQueue = [System.Collections.Generic.Queue[string]]::new([string[]]@('check', 'skip'))
        try {
            Mock -ModuleName OSSetup -CommandName Read-OSSetupMenu -MockWith { @{ Action = 'next'; Values = @($global:OSSetupTestMenuQueue.Dequeue()) } }
            Mock -ModuleName OSSetup -CommandName Test-OSSetupManualStep -MockWith { $false }
            $action = [ordered]@{ provider = 'manual'; description = 'connexion à GitHub'; check = 'gh-auth'; instructions = 'se connecter.' }
            { Invoke-OSSetupManualStep -Action $action -Context @{ Interactive = $true } } | Should -Throw '*passée*'
            Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq 'Étape manuelle : se connecter.' }
            Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like 'Pas encore fait*' }
        }
        finally {
            Remove-Variable -Name OSSetupTestMenuQueue -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Mémoire de WSL' {
    It 'calcule le pourcentage de la RAM' {
        (Get-OSSetupWslMemoryLimit -PhysicalGB 63.8 -Percent 40).GB | Should -Be 25
        (Get-OSSetupWslMemoryLimit -PhysicalGB 16 -Percent 40).Clamped | Should -BeFalse
    }

    It 'laisse au moins 4 Go à Windows' {
        $limit = Get-OSSetupWslMemoryLimit -PhysicalGB 8 -Percent 90
        $limit.GB | Should -Be 4
        $limit.Clamped | Should -BeTrue
    }

    It 'donne au moins 2 Go à WSL' {
        (Get-OSSetupWslMemoryLimit -PhysicalGB 7.9 -Percent 10).GB | Should -Be 2
    }

    It 'n''écrit rien sur une machine trop petite' {
        Get-OSSetupWslMemoryLimit -PhysicalGB 5.9 -Percent 40 | Should -BeNullOrEmpty
    }
}

Describe 'Fichier INI (.wslconfig)' {
    It 'remplace une clé existante et garde les commentaires' {
        $text = "# note`r`n[wsl2]`r`nMemory=24GB`r`n`r`n[experimental]`r`nautoMemoryReclaim=dropCache`r`n"
        $result = Set-OSSetupIniValue -Text $text -Section 'wsl2' -Key 'memory' -Value '12GB'
        $result | Should -BeLike '# note*memory=12GB*autoMemoryReclaim=dropCache*'
        $result | Should -Not -BeLike '*24GB*'
        Get-OSSetupIniValue -Text $result -Section 'wsl2' -Key 'memory' | Should -Be '12GB'
    }

    It 'ajoute la clé à la fin de sa section' {
        $text = "[wsl2]`r`nswap=0`r`n`r`n[experimental]`r`nsparseVhd=true`r`n"
        $result = Set-OSSetupIniValue -Text $text -Section 'wsl2' -Key 'memory' -Value '6GB'
        $result | Should -Be "[wsl2]`r`nswap=0`r`nmemory=6GB`r`n`r`n[experimental]`r`nsparseVhd=true`r`n"
    }

    It 'crée la section (et le fichier) au besoin' {
        Set-OSSetupIniValue -Text '' -Section 'wsl2' -Key 'memory' -Value '6GB' | Should -Be "[wsl2]`r`nmemory=6GB`r`n"
        Get-OSSetupIniValue -Text "[experimental]`r`nmemory=1GB" -Section 'wsl2' -Key 'memory' | Should -BeNullOrEmpty
    }
}

Describe 'Plafonds selon le disque' {
    It 'garde le plafond sur un grand disque' {
        $limit = Get-OSSetupDiskBoundedSize -DiskGB 476 -MaxGB 30 -Percent 10
        $limit.GB | Should -Be 30
        $limit.Clamped | Should -BeFalse
    }

    It 'ramène le plafond à un pourcentage d''un petit disque' {
        $limit = Get-OSSetupDiskBoundedSize -DiskGB 119 -MaxGB 30 -Percent 10
        $limit.GB | Should -Be 11
        $limit.Clamped | Should -BeTrue
    }

    It 'avertit seulement sous le seuil d''espace libre' {
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
        Mock -ModuleName OSSetup -CommandName Get-OSSetupSystemDisk -MockWith { [pscustomobject]@{ Drive = 'C:'; SizeGB = 119; FreeGB = 32.4 } }
        Write-OSSetupDiskSpaceWarning
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' }
        # Affiché quel que soit le profil : il ne cite pas d'outils qui n'ont peut-être pas été choisis.
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly -ParameterFilter { $Message -match 'Docker|WSL|Playwright' }
        Mock -ModuleName OSSetup -CommandName Get-OSSetupSystemDisk -MockWith { [pscustomobject]@{ Drive = 'C:'; SizeGB = 476; FreeGB = 210 } }
        Write-OSSetupDiskSpaceWarning
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' }
    }
}

Describe 'Provider claude-plugin' {
    BeforeAll {
        $script:action = @{ plugin = 'dx'; marketplace = 'cc-plugins'; source = 'IMSike/CC-Plugins' }
        # Pester ne simule qu'une commande existante : une fonction vide remplace claude là où il manque (ex. runner CI).
        $script:claudeStub = -not (Get-Command -Name claude -ErrorAction SilentlyContinue)
        if ($script:claudeStub) {
            function global:claude { }
        }
    }

    AfterAll {
        if ($script:claudeStub) { Remove-Item -Path Function:\claude -ErrorAction SilentlyContinue }
    }

    It 'est conforme seulement quand le plugin est installé et activé' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Scope = 'user'; Enabled = $true } }
            & $provider.Test $Action @{} | Should -BeTrue
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Scope = 'user'; Enabled = $false } }
            & $provider.Test $Action @{} | Should -BeFalse
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'other@cc-plugins'; Scope = 'user'; Enabled = $true } }
            & $provider.Test $Action @{} | Should -BeFalse
            # Installé pour un projet seulement : pas pour le compte.
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Scope = 'project'; Enabled = $true } }
            & $provider.Test $Action @{} | Should -BeFalse
        }
    }

    It 'installe pour le compte un plugin installé seulement pour un projet, sans toucher à ce dernier' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0 }
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Scope = 'project'; Enabled = $false } }
            & $provider.Invoke $Action @{}
            Should -Invoke -CommandName claude -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'plugin install dx --marketplace IMSike/CC-Plugins --scope user' }
            Should -Invoke -CommandName claude -Times 0 -Exactly -ParameterFilter { $args -contains 'enable' }
        }
    }

    It 'installe depuis la marketplace, et réactive un plugin désactivé' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0 }
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Scope = 'user'; Enabled = $false } }
            & $provider.Invoke $Action @{}
            Should -Invoke -CommandName claude -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'plugin install dx --marketplace IMSike/CC-Plugins --scope user' }
            Should -Invoke -CommandName claude -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'plugin enable dx@cc-plugins' }

            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 1 }
            { & $provider.Invoke $Action @{} } | Should -Throw '*claude plugin install*'
        }
    }

    It 'lit la liste des plugins de claude plugin list --json' {
        InModuleScope OSSetup {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'claude.exe' } } -ParameterFilter { $Name -eq 'claude' }
            Mock -CommandName claude -MockWith {
                $global:LASTEXITCODE = 0
                '[{ "id": "dx@cc-plugins", "scope": "user", "enabled": true }, { "id": "x@y", "enabled": false }]'
            }
            $plugins = @(Get-OSSetupClaudePlugin)
            $plugins.Count | Should -Be 2
            $plugins[0].Id | Should -Be 'dx@cc-plugins'
            $plugins[0].Enabled | Should -BeTrue
            $plugins[0].Scope | Should -Be 'user'
            $plugins[1].Enabled | Should -BeFalse
            $plugins[1].Scope | Should -BeNullOrEmpty
        }
    }

    It 'n''est pas conforme, en disant pourquoi, quand scope ou enabled manque à la sortie de Claude Code' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $script:LoggedOnce.Clear()
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'claude.exe' } } -ParameterFilter { $Name -eq 'claude' }
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0; '[{ "id": "dx@cc-plugins", "enabled": true }]' }
            foreach ($i in 1..2) { & $provider.Test $Action @{} | Should -BeFalse }
            Should -Invoke -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Detail' -and $Message -like '*dx@cc-plugins*« scope » absent*non conforme*' }
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0; '[{ "id": "dx@cc-plugins", "scope": "user" }]' }
            & $provider.Test $Action @{} | Should -BeFalse
            Should -Invoke -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -like '*dx@cc-plugins*« enabled » absent*' }
            $script:LoggedOnce.Clear()
        }
    }

    It 'n''est pas conforme, en disant pourquoi, quand scope ou enabled est nul dans la sortie de Claude Code' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $script:LoggedOnce.Clear()
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'claude.exe' } } -ParameterFilter { $Name -eq 'claude' }
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0; '[{ "id": "dx@cc-plugins", "scope": null, "enabled": null }]' }
            & $provider.Test $Action @{} | Should -BeFalse
            Should -Invoke -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Detail' -and $Message -like '*dx@cc-plugins*« scope » absent ou nul*non conforme*' }
            Should -Invoke -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Detail' -and $Message -like '*dx@cc-plugins*« enabled » absent ou nul*non conforme*' }
            $script:LoggedOnce.Clear()
        }
    }
}

Describe 'Réglages de herdr' {
    It 'config-explorer.toml reprend config.toml à l''identique, plus les raccourcis du plugin' {
        # Les deux fichiers sont copiés tels quels (l'un ou l'autre selon le plugin) : un réglage changé dans l'un
        # doit l'être dans l'autre. Commentaires d'en-tête exclus de la comparaison.
        $herdr = Join-Path -Path $PSScriptRoot -ChildPath '..\dotfiles\herdr'
        $read = {
            param([string]$Name)
            @(Get-Content -LiteralPath (Join-Path -Path $herdr -ChildPath $Name) -Encoding utf8 | Where-Object { $_ -notmatch '^\s*#' })
        }
        $base = & $read 'config.toml'
        $explorer = & $read 'config-explorer.toml'
        $keys = [Array]::IndexOf($explorer, '[[keys.command]]')
        $keys | Should -BeGreaterThan 0
        ($explorer[0..($keys - 1)] -join "`n").Trim() | Should -Be (($base -join "`n").Trim())
    }
}

Describe 'Providers d''outils : outil présent' {
    BeforeAll {
        # Pester ne simule qu'une commande existante, et pas un script npm.ps1 appelé « npm » : des fonctions vides
        # masquent les outils, présents ou non (ex. runner CI).
        $script:toolStubs = @('gh', 'npm', 'fnm' | Where-Object { -not (Test-Path -Path "Function:\$_") })
        foreach ($stub in $script:toolStubs) { New-Item -Path "Function:\global:$stub" -Value {} | Out-Null }
    }

    AfterAll {
        foreach ($stub in $script:toolStubs) { Remove-Item -Path "Function:\$stub" -ErrorAction SilentlyContinue }
    }

    BeforeEach {
        Mock -ModuleName OSSetup Get-Command { [pscustomobject]@{ Name = "$Name.exe" } } -ParameterFilter { $Name -in 'gh', 'npm', 'fnm' -and $CommandType -eq 'Application' }
    }

    It 'gh-extension reconnaît le dépôt exact dans gh extension list, pas un dépôt au nom plus long' {
        Mock -ModuleName OSSetup gh {
            $global:LASTEXITCODE = 0
            "gh dash`tdlvhdr/gh-dash`tv4.7.0"
            "gh copilot-x`tgithub/gh-copilot-x`tv1.0.0"
        }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'gh-extension' }
        & $provider.Test @{ repo = 'dlvhdr/gh-dash' } @{} | Should -BeTrue
        & $provider.Test @{ repo = 'github/gh-copilot' } @{} | Should -BeFalse
        & $provider.Test @{ repo = 'gh-dash' } @{} | Should -BeFalse
    }

    It 'npm-global est conforme selon le code de sortie de npm ls pour ce paquet' {
        Mock -ModuleName OSSetup npm { $global:LASTEXITCODE = if ($args -contains 'typescript') { 0 } else { 1 } }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'npm-global' }
        & $provider.Test @{ package = 'typescript' } @{} | Should -BeTrue
        & $provider.Test @{ package = 'absent' } @{} | Should -BeFalse
        Should -Invoke -ModuleName OSSetup npm -Times 1 -Exactly -ParameterFilter { ($args -join ' ') -eq 'ls --global typescript --depth=0' }
    }

    It 'fnm-node est conforme seulement avec une version par défaut, et installe la LTS avant d''en faire la version par défaut' {
        Mock -ModuleName OSSetup fnm { $global:LASTEXITCODE = 1 }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'fnm-node' }
        & $provider.Test @{} @{} | Should -BeFalse
        Mock -ModuleName OSSetup fnm { $global:LASTEXITCODE = 0 }
        & $provider.Test @{} @{} | Should -BeTrue

        $global:OSSetupTestCalls = [System.Collections.Generic.List[string]]::new()
        try {
            Mock -ModuleName OSSetup Invoke-OSSetupNativeCommand { $global:OSSetupTestCalls.Add("$FilePath $($ArgumentList -join ' ')") }
            & $provider.Invoke @{} @{}
            $global:OSSetupTestCalls | Should -Be @('fnm install --lts', 'fnm default lts-latest')
        }
        finally {
            Remove-Variable -Name OSSetupTestCalls -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Provider playwright-cli' {
    BeforeEach {
        $saved = @{ USERPROFILE = $env:USERPROFILE; LOCALAPPDATA = $env:LOCALAPPDATA; PLAYWRIGHT_BROWSERS_PATH = $env:PLAYWRIGHT_BROWSERS_PATH }
        $root = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        $env:USERPROFILE = Join-Path -Path $root -ChildPath 'profil'
        $env:LOCALAPPDATA = Join-Path -Path $root -ChildPath 'local'
        $env:PLAYWRIGHT_BROWSERS_PATH = $null
        New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'playwright-cli' }
    }

    AfterEach {
        foreach ($name in $saved.Keys) { Set-Item -Path "Env:\$name" -Value $saved[$name] }
    }

    It 'reconnaît le dossier du navigateur, pas celui d''une variante headless ni sans révision' {
        $browsers = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ms-playwright'
        & $provider.Test @{ browser = 'chromium' } @{} | Should -BeFalse
        New-Item -Path (Join-Path -Path $browsers -ChildPath 'chromium_headless_shell-1247') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $browsers -ChildPath 'chromium-tip') -ItemType Directory -Force | Out-Null
        & $provider.Test @{ browser = 'chromium' } @{} | Should -BeFalse
        New-Item -Path (Join-Path -Path $browsers -ChildPath 'chromium-1247') -ItemType Directory -Force | Out-Null
        & $provider.Test @{ browser = 'chromium' } @{} | Should -BeTrue
    }

    It 'cherche les navigateurs dans PLAYWRIGHT_BROWSERS_PATH quand elle est définie' {
        $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ms-playwright\chromium-1247') -ItemType Directory -Force | Out-Null
        & $provider.Test @{ browser = 'chromium' } @{} | Should -BeFalse
        New-Item -Path (Join-Path -Path $env:PLAYWRIGHT_BROWSERS_PATH -ChildPath 'chromium-1247') -ItemType Directory -Force | Out-Null
        & $provider.Test @{ browser = 'chromium' } @{} | Should -BeTrue
    }

    It 'vérifie les skills dans le dossier de l''agent demandé' {
        & $provider.Test @{ skills = 'claude' } @{} | Should -BeFalse
        $skill = Join-Path -Path $env:USERPROFILE -ChildPath '.agents\skills\playwright-cli\SKILL.md'
        New-Item -Path (Split-Path -Path $skill -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $skill -Value ''
        & $provider.Test @{ skills = 'claude' } @{} | Should -BeFalse
        & $provider.Test @{ skills = 'agents' } @{} | Should -BeTrue
    }

    It 'installe depuis le profil de l''utilisateur, puis revient au dossier courant, même en cas d''échec' {
        $here = (Get-Location).Path
        Mock -ModuleName OSSetup Invoke-OSSetupNativeCommand { $global:OSSetupTestLocation = (Get-Location).Path; throw 'échec simulé' }
        try {
            { & $provider.Invoke @{ skills = 'claude' } @{} } | Should -Throw '*échec simulé*'
            $global:OSSetupTestLocation | Should -Be $env:USERPROFILE
            (Get-Location).Path | Should -Be $here
            Should -Invoke -ModuleName OSSetup Invoke-OSSetupNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'playwright-cli' -and ($ArgumentList -join ' ') -eq 'install --skills=claude --global'
            }
        }
        finally {
            Remove-Variable -Name OSSetupTestLocation -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Fichiers de configuration du profil : .wslconfig et daemon.json de Docker' {
    BeforeEach {
        $savedProfile = $env:USERPROFILE
        $env:USERPROFILE = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path $env:USERPROFILE -ItemType Directory -Force | Out-Null
        $context = @{ BackupRoot = Join-Path -Path $TestDrive -ChildPath "backups-$([guid]::NewGuid())" }
        Mock -ModuleName OSSetup Write-OSSetupLog
    }

    AfterEach {
        $env:USERPROFILE = $savedProfile
    }

    It 'wsl-config écrit la clé dans .wslconfig, en gardant le reste, après sauvegarde' {
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'
        $original = "# perso`r`n[wsl2]`r`nswap=0`r`n"
        [IO.File]::WriteAllText($path, $original)
        $action = @{ section = 'wsl2'; key = 'memory'; value = '8GB' }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'wsl-config' }
        & $provider.Test $action $context | Should -BeFalse
        (& $provider.Read $action $context)['exists'] | Should -BeFalse
        & $provider.Invoke $action $context
        & $provider.Test $action $context | Should -BeTrue
        [IO.File]::ReadAllText($path) | Should -BeLike '# perso*swap=0*memory=8GB*'
        $backup = @(Get-ChildItem -Path $context.BackupRoot -Recurse -File)
        $backup.Count | Should -Be 1
        [IO.File]::ReadAllText($backup[0].FullName) | Should -Be $original
    }

    It 'wsl-config crée .wslconfig sans BOM quand il n''existe pas' {
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'wsl-config' }
        & $provider.Invoke @{ section = 'wsl2'; key = 'memory'; value = '8GB' } $context
        $bytes = [IO.File]::ReadAllBytes((Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'))
        $bytes[0] | Should -Be ([byte][char]'[')
    }

    It 'wsl-config n''écrit rien quand la machine est trop petite pour un plafond' {
        Mock -ModuleName OSSetup Get-OSSetupPhysicalMemoryGB { 4 }
        $action = @{ section = 'wsl2'; key = 'memory'; memoryPercent = 40 }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'wsl-config' }
        & $provider.Test $action $context | Should -BeTrue
        & $provider.Invoke $action $context
        Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig' | Should -Not -Exist
    }

    It 'docker-build-cache fusionne le plafond dans daemon.json en gardant les autres réglages, après sauvegarde' {
        Mock -ModuleName OSSetup Get-OSSetupSystemDisk { [pscustomobject]@{ Drive = 'C:'; SizeGB = 119; FreeGB = 50 } }
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.docker\daemon.json'
        New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force | Out-Null
        $original = '{ "experimental": true, "builder": { "gc": { "enabled": false, "policy": [] } } }'
        Set-Content -LiteralPath $path -Value $original -NoNewline
        $action = @{ maxGB = 30; diskPercent = 10 }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'docker-build-cache' }
        & $provider.Test $action $context | Should -BeFalse
        & $provider.Invoke $action $context
        & $provider.Test $action $context | Should -BeTrue
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        $json['experimental'] | Should -BeTrue
        $json['builder']['gc']['enabled'] | Should -BeTrue
        $json['builder']['gc']['defaultKeepStorage'] | Should -Be '11GB'
        $json['builder']['gc'].ContainsKey('policy') | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*11 Go*' }
        $backup = @(Get-ChildItem -Path $context.BackupRoot -Recurse -File)
        Get-Content -LiteralPath $backup[0].FullName -Raw | Should -Be $original
    }

    It 'docker-build-cache crée daemon.json et son dossier au besoin' {
        Mock -ModuleName OSSetup Get-OSSetupSystemDisk { [pscustomobject]@{ Drive = 'C:'; SizeGB = 476; FreeGB = 200 } }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'docker-build-cache' }
        (& $provider.Read @{ maxGB = 30; diskPercent = 10 } $context)['exists'] | Should -BeFalse
        & $provider.Invoke @{ maxGB = 30; diskPercent = 10 } $context
        $json = Get-Content -LiteralPath (Join-Path -Path $env:USERPROFILE -ChildPath '.docker\daemon.json') -Raw | ConvertFrom-Json -AsHashtable
        $json['builder']['gc']['defaultKeepStorage'] | Should -Be '30GB'
    }
}

Describe 'Profil PowerShell 7' {
    It 'garde intact un dossier des projets contenant apostrophe, $, backtick et guillemets' {
        # Gabarit développé comme par le provider file (mode template), puis seulement analysé : le profil n'est pas
        # exécuté.
        $devRoot = 'C:\Users\O''Brien\dev $env:TEMP $(Get-Date) `n "x" ''@'
        $bytes = InModuleScope OSSetup -Parameters @{ DevRoot = $devRoot; Dotfiles = (Join-Path -Path $PSScriptRoot -ChildPath '..\dotfiles') } {
            $action = @{ source = 'powershell\Microsoft.PowerShell_profile.ps1'; target = 'C:\inutilise.ps1'; mode = 'template' }
            , (Get-OSSetupFileContent -Action $action -Context @{ DotfilesRoot = $Dotfiles; Variables = @{ DevRoot = $DevRoot } })
        }
        $profilePath = Join-Path -Path $TestDrive -ChildPath 'Microsoft.PowerShell_profile.ps1'
        [System.IO.File]::WriteAllBytes($profilePath, $bytes)
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
        $assignment = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$env:DEV_ROOT'
            }, $true)
        $assignment | Should -Not -BeNullOrEmpty
        $assignment.Right.Expression | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
        $assignment.Right.Expression.Value | Should -BeExactly $devRoot
    }
}
