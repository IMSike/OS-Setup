BeforeAll {
    # Fonctions du bootstrap extraites du script (le script lui-même n'est pas exécuté).
    $path = Join-Path -Path $PSScriptRoot -ChildPath '..\bootstrap.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    foreach ($name in 'Install-WingetPackage', 'Write-Step', 'Update-SessionPath') {
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $script:WingetAlreadyInstalled = -1978335189
    $script:InstalledTools = @()
    $script:bootstrapText = $ast.Extent.Text
}

Describe 'bootstrap.ps1 : échec de l''installation de PowerShell 7' {
    BeforeEach {
        # winget remplacé : aucune installation réelle.
        function winget { $global:LASTEXITCODE = -1978335212 }
        Mock Write-Host {}
        Mock Update-SessionPath {}
    }

    It 'ajoute l''explication au code d''erreur' {
        { Install-WingetPackage -Id '9MZ1SNWT0N5D' -Command 'pwsh' -Source 'msstore' -Scope '' -Present { $false } -FailureHelp 'Causes probables : Store absent.' } |
            Should -Throw -ExpectedMessage "*9MZ1SNWT0N5D (code 0x8A150014).*Causes probables : Store absent.*"
    }

    It 'garde le message court sans explication' {
        { Install-WingetPackage -Id 'Git.Git' -Command 'git' -Present { $false } } |
            Should -Throw -ExpectedMessage "Échec de l'installation de Git.Git (code 0x8A150014)."
    }

    It 'donne les causes probables pour PowerShell 7 du Store' {
        foreach ($text in 'LTSC', 'debloat', 'winget source list', 'winget source reset --force', 'pare-feu') {
            $script:bootstrapText | Should -BeLike "*$text*"
        }
        $script:bootstrapText | Should -Match "Install-WingetPackage -Id '9MZ1SNWT0N5D'[^\r\n]*``\r?\n\s*-FailureHelp \`$storeHelp"
    }
}

Describe 'bootstrap.ps1 -WhatIf : simulation' {
    BeforeAll {
        foreach ($name in 'Test-WhatIfArgument', 'Show-BootstrapSimulation', 'Test-Elevated') {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:simulationAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-BootstrapSimulation' }, $true)
        # Module Appx absent sous PowerShell 7 : fonction de remplacement, toujours simulée.
        function Get-AppxPackage { param([string]$Name) $null = $Name }
        $script:simulationParameters = @{ RepoUrl = 'https://example.invalid/repo.git'; Branch = 'main'; Destination = 'C:\OSSetupTest\OS-Setup' }
    }

    BeforeEach {
        $global:OSSetupTestHost = [System.Collections.Generic.List[string]]::new()
        Mock Write-Host { $global:OSSetupTestHost.Add([string]$Object) }
        Mock Test-Elevated { $false }
        Mock Get-Command { $null }
        Mock Get-AppxPackage { $null }
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

    It 'sur une machine vierge, annonce les installations et le clonage puis s''arrête en expliquant pourquoi' {
        Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' | Should -BeNullOrEmpty
        $text = $global:OSSetupTestHost -join "`n"
        $text | Should -BeLike '*winget : serait installé*'
        $text | Should -BeLike '*Git.Git : serait installé*'
        $text | Should -BeLike '*PowerShell 7 (Store) : serait installé*'
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
        $allowed = 'Get-AppxPackage', 'Get-Command', 'Join-Path', 'Select-Object', 'Test-Elevated', 'Test-Path', 'Write-Host', 'Write-Step'
        $commands | Where-Object { $_ -notin $allowed } | Should -BeNullOrEmpty
    }

    It 'simule avant la relance en administrateur et avant toute installation' {
        $simulation = $script:bootstrapText.IndexOf('if (Test-WhatIfArgument -Argument $SetupArguments)')
        $simulation | Should -BeGreaterThan 0
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Relance en administrateur (validez')
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Initialize-Winget' + [Environment]::NewLine)
    }
}
