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
}

Describe 'Provider git-config' {
    It 'est conforme quand la clé a déjà la valeur, et l''écrit sinon' {
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'git-config'
            $action = @{ key = 'pull.rebase'; value = 'true' }
            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 0; 'true' }
            & $provider.Test $action @{} | Should -BeTrue
            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 1 }
            & $provider.Test $action @{} | Should -BeFalse

            Mock -CommandName git -MockWith { $global:LASTEXITCODE = 0 }
            & $provider.Invoke $action @{}
            Should -Invoke -CommandName git -ParameterFilter { ($args -join ' ') -eq 'config --global pull.rebase true' } -Times 1 -Exactly
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
        Mock -ModuleName OSSetup -CommandName Get-OSSetupSystemDisk -MockWith { [pscustomobject]@{ Drive = 'C:'; SizeGB = 476; FreeGB = 210 } }
        Write-OSSetupDiskSpaceWarning
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warning' }
    }
}

Describe 'Provider claude-plugin' {
    BeforeAll {
        $script:action = @{ plugin = 'dx'; marketplace = 'cc-plugins'; source = 'IMSike/CC-Plugins' }
    }

    It 'est conforme seulement quand le plugin est installé et activé' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Enabled = $true } }
            & $provider.Test $Action @{} | Should -BeTrue
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Enabled = $false } }
            & $provider.Test $Action @{} | Should -BeFalse
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'other@cc-plugins'; Enabled = $true } }
            & $provider.Test $Action @{} | Should -BeFalse
        }
    }

    It 'installe depuis la marketplace, et réactive un plugin désactivé' {
        InModuleScope OSSetup -Parameters @{ Action = $action } {
            param($Action)
            $provider = Get-OSSetupProvider -Name 'claude-plugin'
            Mock -CommandName Write-OSSetupLog
            Mock -CommandName claude -MockWith { $global:LASTEXITCODE = 0 }
            Mock -CommandName Get-OSSetupClaudePlugin -MockWith { [pscustomobject]@{ Id = 'dx@cc-plugins'; Enabled = $false } }
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
            $plugins[1].Enabled | Should -BeFalse
        }
    }
}