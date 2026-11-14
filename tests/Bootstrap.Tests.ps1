BeforeAll {
    # Fonctions du bootstrap extraites du script (le script lui-même n'est pas exécuté).
    $path = Join-Path -Path $PSScriptRoot -ChildPath '..\bootstrap.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-Step' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    $script:bootstrapText = $ast.Extent.Text
}

Describe 'bootstrap.ps1 : copie du dépôt et trace pour le nettoyage de fin' {
    BeforeAll {
        foreach ($name in 'Initialize-BootstrapRepository', 'Save-BootstrapInfo') {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        function Read-TestBootstrapInfo([string]$Root) {
            Get-Content -LiteralPath (Join-Path -Path $Root -ChildPath 'state\bootstrap.json') -Raw | ConvertFrom-Json
        }
    }

    BeforeEach {
        $work = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        $destination = Join-Path -Path $work -ChildPath 'OS-Setup'
        $global:OSSetupTestGit = [System.Collections.Generic.List[string]]::new()
        # Aucun git réel : clone simulé (dossier .git créé), autres commandes notées.
        Mock git {
            $global:OSSetupTestGit.Add("$args")
            if ($args[0] -eq 'clone') { New-Item -Path (Join-Path -Path $args[-1] -ChildPath '.git') -ItemType Directory -Force | Out-Null }
            $global:LASTEXITCODE = 0
        }
        Mock Write-Host {}
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestGit -Scope Global -ErrorAction SilentlyContinue
    }

    It 'note comme lui appartenant la copie qu''il vient de cloner' {
        $repository = Initialize-BootstrapRepository -RepoUrl 'https://example.invalid/r.git' -Branch 'main' -Destination $destination -ScriptRoot ''
        $repository.Cloned | Should -BeTrue
        $global:OSSetupTestGit[0] | Should -BeLike 'clone --branch main *'
        Save-BootstrapInfo -RepoRoot $repository.Root -OwnsClone $repository.Cloned -ScriptPath ''
        (Read-TestBootstrapInfo -Root $destination).ownsClone | Should -BeTrue
    }

    It 'ne s''approprie pas un clone de développement placé dans la destination' {
        # Clone de développement dans %USERPROFILE%\OS-Setup, bootstrap lancé depuis ce clone ou téléchargé.
        New-Item -Path "$destination\.git" -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath "$destination\setup.ps1" -Value '# setup'
        foreach ($scriptRoot in $destination, '') {
            $repository = Initialize-BootstrapRepository -RepoUrl 'https://example.invalid/r.git' -Branch 'main' -Destination $destination -ScriptRoot $scriptRoot
            $repository.Root | Should -Be $destination
            $repository.Cloned | Should -BeFalse
            Save-BootstrapInfo -RepoRoot $repository.Root -OwnsClone $repository.Cloned -ScriptPath ''
            (Read-TestBootstrapInfo -Root $destination).ownsClone | Should -BeFalse
        }
    }

    Context 'copie existante sur une autre branche que -Branch' {
        BeforeEach {
            New-Item -Path "$destination\.git" -ItemType Directory -Force | Out-Null
            $global:OSSetupTestGitStatus = @()
            Mock git {
                $global:OSSetupTestGit.Add("$args")
                $global:LASTEXITCODE = 0
                if ($args -contains 'rev-parse') { return 'dev' }
                if ($args -contains 'status') { return $global:OSSetupTestGitStatus }
            }
        }

        AfterEach {
            Remove-Variable -Name OSSetupTestGitStatus -Scope Global -ErrorAction SilentlyContinue
        }

        It 'reste sur la branche courante quand -Branch n''est pas donné' {
            Initialize-BootstrapRepository -RepoUrl 'u' -Branch 'main' -Destination $destination -ScriptRoot '' | Out-Null
            $global:OSSetupTestGit | Should -Be @("-C $destination pull --ff-only")
        }

        It 'bascule sur la branche demandée une copie sans modification locale, puis la met à jour' {
            Initialize-BootstrapRepository -RepoUrl 'u' -Branch 'main' -Destination $destination -ScriptRoot '' -BranchRequested | Out-Null
            $global:OSSetupTestGit | Should -Be @(
                "-C $destination rev-parse --abbrev-ref HEAD"
                "-C $destination status --porcelain"
                "-C $destination fetch origin"
                "-C $destination checkout main"
                "-C $destination pull --ff-only"
            )
        }

        It 'ne bascule pas une copie qui a des modifications locales et explique quoi faire' {
            $global:OSSetupTestGitStatus = @(' M setup.ps1')
            { Initialize-BootstrapRepository -RepoUrl 'u' -Branch 'main' -Destination $destination -ScriptRoot '' -BranchRequested } |
                Should -Throw '*branche « dev »*modifications locales*pas basculée sur « main »*'
            $global:OSSetupTestGit | Where-Object { $_ -match 'checkout|pull|fetch|reset|stash' } | Should -BeNullOrEmpty
        }

        It 'ne fait que mettre à jour une copie déjà sur la branche demandée' {
            Initialize-BootstrapRepository -RepoUrl 'u' -Branch 'dev' -Destination $destination -ScriptRoot '' -BranchRequested | Out-Null
            $global:OSSetupTestGit | Should -Be @("-C $destination rev-parse --abbrev-ref HEAD", "-C $destination pull --ff-only")
        }
    }

    It 'garde la copie clonée par un bootstrap précédent, et ses outils installés' {
        New-Item -Path "$destination\state" -ItemType Directory -Force | Out-Null
        @{ ownsClone = $true; bootstrapScript = $null; installedTools = @('Git.Git') } | ConvertTo-Json |
            Set-Content -LiteralPath "$destination\state\bootstrap.json"
        Save-BootstrapInfo -RepoRoot $destination -OwnsClone $false -InstalledTool 'Microsoft.PowerShell' -ScriptPath ''
        $info = Read-TestBootstrapInfo -Root $destination
        $info.ownsClone | Should -BeTrue
        @($info.installedTools) | Sort-Object | Should -Be @('Git.Git', 'Microsoft.PowerShell')
    }

    It 'note le script du bootstrap seulement s''il est hors du dépôt, y compris dans un dossier voisin au nom proche' {
        $repoRoot = Join-Path -Path $work -ChildPath 'OS-Setup'
        Save-BootstrapInfo -RepoRoot $repoRoot -OwnsClone $true -ScriptPath "$repoRoot\bootstrap.ps1"
        (Read-TestBootstrapInfo -Root $repoRoot).bootstrapScript | Should -BeNullOrEmpty
        Save-BootstrapInfo -RepoRoot $repoRoot -OwnsClone $true -ScriptPath "$work\OS-Setup-outils\bootstrap.ps1"
        (Read-TestBootstrapInfo -Root $repoRoot).bootstrapScript | Should -Be "$work\OS-Setup-outils\bootstrap.ps1"
    }

    It 'écrit la trace dans un dépôt dont le chemin contient des crochets' {
        $repoRoot = Join-Path -Path $work -ChildPath 'dépôt [1]'
        Save-BootstrapInfo -RepoRoot $repoRoot -OwnsClone $true -ScriptPath ''
        Save-BootstrapInfo -RepoRoot $repoRoot -OwnsClone $false -InstalledTool 'Git.Git' -ScriptPath ''
        $info = Read-TestBootstrapInfo -Root $repoRoot
        $info.ownsClone | Should -BeTrue
        @($info.installedTools) | Should -Be @('Git.Git')
    }
}

Describe 'bootstrap.ps1 -WhatIf : simulation' {
    BeforeAll {
        foreach ($name in 'Test-WhatIfArgument', 'Show-BootstrapSimulation', 'Test-Elevated') {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:simulationAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-BootstrapSimulation' }, $true)
        $script:simulationParameters = @{ RepoUrl = 'https://example.invalid/repo.git'; Branch = 'main'; Destination = 'C:\OSSetupTest\OS-Setup' }
    }

    BeforeEach {
        $global:OSSetupTestHost = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $global:OSSetupTestHost.Add([string]$Object) }
        Mock Test-Elevated { $false }
        Mock Get-Command { $null }
        Mock Test-Path { $false }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestHost -Scope Global -ErrorAction SilentlyContinue
    }

    It 'reconnaît -WhatIf parmi les arguments du setup' {
        Test-WhatIfArgument -Argument '-AnswerFile', 'x.json', '-WhatIf' | Should -BeTrue
        Test-WhatIfArgument -Argument '-WhatIf:$true' | Should -BeTrue
        Test-WhatIfArgument -Argument '-WhatIf:$false' | Should -BeFalse
        Test-WhatIfArgument -Argument 'WhatIf' | Should -BeFalse
        Test-WhatIfArgument -Argument $null | Should -BeFalse
    }

    It 'reconnaît aussi <_>, que setup.ps1 accepte comme -WhatIf' -ForEach @('-What', '-wh', '-WHATI', '-wi', '-wi:$true') {
        Test-WhatIfArgument -Argument '-Profiles', 'base', $_ | Should -BeTrue
    }

    It 'ne prend pas pour -WhatIf <_>' -ForEach @('-W', '-wa', '-WarningAction', '-What:$false', '-WhatIfX') {
        Test-WhatIfArgument -Argument $_ | Should -BeFalse
    }

    It 'reconnaît exactement les formes que PowerShell lie au paramètre WhatIf d''un script' {
        # Script témoin avec SupportsShouldProcess, comme setup.ps1 (paramètres communs WarningAction… compris).
        $probe = Join-Path -Path $TestDrive -ChildPath 'probe.ps1'
        Set-Content -LiteralPath $probe -Value '[CmdletBinding(SupportsShouldProcess)] param() [bool]$WhatIfPreference'
        foreach ($form in '-What', '-wh', '-wi', '-WhatIf') {
            & ([scriptblock]::Create("& '$probe' $form")) | Should -BeTrue -Because $form
            Test-WhatIfArgument -Argument $form | Should -BeTrue -Because $form
        }
        { & ([scriptblock]::Create("& '$probe' -W")) } | Should -Throw '*ambigu*'
    }

    It 'sur une machine vierge, annonce les installations et le clonage puis s''arrête en expliquant pourquoi' {
        Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' | Should -BeNullOrEmpty
        $text = $global:OSSetupTestHost -join "`n"
        $text | Should -BeLike '*winget : serait installé*'
        $text | Should -BeLike '*Git.Git : serait installé*'
        $text | Should -BeLike '*Microsoft.PowerShell : serait installé*'
        $text | Should -BeLike '*serait cloné dans C:\OSSetupTest\OS-Setup*'
        $text | Should -BeLike '*Simulation du setup impossible (PowerShell 7 absent, pas encore de copie du dépôt)*'
    }

    It 'lance la simulation du setup depuis un clone quand PowerShell 7 est présent' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'C:\OSSetupTest\clone\setup.ps1' }
        $result = Show-BootstrapSimulation @script:simulationParameters -ScriptRoot 'C:\OSSetupTest\clone'
        $result.Pwsh | Should -Be 'C:\OSSetupTest\pwsh.exe'
        $result.SetupScript | Should -Be 'C:\OSSetupTest\clone\setup.ps1'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*copie utilisée telle quelle (C:\OSSetupTest\clone)*'
    }

    It 'utilise la copie existante dans la destination sans la mettre à jour' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'C:\OSSetupTest\OS-Setup\*' }
        (Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '').SetupScript | Should -Be 'C:\OSSetupTest\OS-Setup\setup.ps1'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*serait mis à jour (git pull --ff-only)*'
    }

    It 'n''appelle aucune commande qui modifie la machine' {
        $commands = $script:simulationAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
        $allowed = 'Get-Command', 'Join-Path', 'Select-Object', 'Test-Elevated', 'Test-Path', 'Write-Host', 'Write-Step'
        $commands | Where-Object { $_ -notin $allowed } | Should -BeNullOrEmpty
    }

    It 'simule avant la relance en administrateur et avant toute installation' {
        $simulation = $script:bootstrapText.IndexOf('if (Test-WhatIfArgument -Argument $SetupArguments)')
        $simulation | Should -BeGreaterThan 0
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Relance en administrateur (validez')
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Initialize-Winget' + [Environment]::NewLine)
    }
}
