BeforeAll {
    # Fonctions du bootstrap extraites du script (le script lui-même n'est pas exécuté).
    $path = Join-Path -Path $PSScriptRoot -ChildPath '..\bootstrap.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-Step' }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
    $script:bootstrapText = $ast.Extent.Text
}

Describe 'bootstrap.ps1 : installation de PowerShell 7 (Microsoft Store, repli sur le MSI)' {
    BeforeAll {
        foreach ($name in 'Install-WingetPackage', 'Install-PowerShell', 'Update-SessionPath') {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:WingetAlreadyInstalled = -1978335189
        # Module Appx non chargé sous PowerShell 7 : fonction de remplacement, toujours simulée.
        function Get-AppxPackage { [CmdletBinding()] param([string]$Name) $null = $Name }
        $script:storeAlias = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'
    }

    BeforeEach {
        # winget remplacé : aucune installation réelle. Code de sortie par source (msstore, winget).
        $global:OSSetupTestWinget = [System.Collections.Generic.List[string]]::new()
        $global:OSSetupTestWingetCode = @{ msstore = 0; winget = 0 }
        function winget {
            $line = $args -join ' '
            $global:OSSetupTestWinget.Add($line)
            $global:LASTEXITCODE = if ($line -like '*--source msstore*') { $global:OSSetupTestWingetCode.msstore } else { $global:OSSetupTestWingetCode.winget }
        }
        $global:OSSetupTestHost = [System.Collections.Generic.List[string]]::new()
        $script:InstalledTools = @()
        $script:SetupPwsh = $null
        Mock Write-Host { $global:OSSetupTestHost.Add([string]$Object) }
        Mock Update-SessionPath {}
        Mock Get-AppxPackage { $null }
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\PowerShell\7\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:storeAlias }
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestWinget, OSSetupTestWingetCode, OSSetupTestHost -Scope Global -ErrorAction SilentlyContinue
    }

    It 'installe depuis la source msstore, sans --scope, note le produit et lance le setup par l''alias du Store' {
        Install-PowerShell
        $global:OSSetupTestWinget.Count | Should -Be 1
        $global:OSSetupTestWinget[0] | Should -BeLike 'install --id 9MZ1SNWT0N5D --exact --source msstore --silent*'
        $global:OSSetupTestWinget[0] | Should -Not -BeLike '*--scope*'
        $script:InstalledTools | Should -Be @('9MZ1SNWT0N5D')
        $script:SetupPwsh | Should -Be $script:storeAlias
    }

    It 'n''installe rien quand le paquet du Store est déjà là, et ne retient pas le MSI qui passe avant dans le PATH' {
        Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerShell' } }
        Install-PowerShell
        $global:OSSetupTestWinget.Count | Should -Be 0
        $script:InstalledTools | Should -BeNullOrEmpty
        $script:SetupPwsh | Should -Be $script:storeAlias
    }

    It 'Store indisponible : prévient avec les causes probables, puis installe le MSI et lance le setup avec lui' {
        $global:OSSetupTestWingetCode.msstore = -1978335212
        # Aucun pwsh avant l'installation du MSI, puis celui du MSI.
        $global:OSSetupTestPwshCalls = 0
        Mock Get-Command {
            $global:OSSetupTestPwshCalls++
            if ($global:OSSetupTestPwshCalls -gt 1) { [pscustomobject]@{ Source = 'C:\OSSetupTest\PowerShell\7\pwsh.exe' } }
        } -ParameterFilter { $Name -eq 'pwsh' }
        try { Install-PowerShell }
        finally { Remove-Variable -Name OSSetupTestPwshCalls -Scope Global -ErrorAction SilentlyContinue }
        $global:OSSetupTestWinget.Count | Should -Be 2
        $global:OSSetupTestWinget[1] | Should -BeLike 'install --id Microsoft.PowerShell --exact --source winget --silent*--scope machine --installer-type wix'
        $script:InstalledTools | Should -Be @('Microsoft.PowerShell')
        $script:SetupPwsh | Should -Be 'C:\OSSetupTest\PowerShell\7\pwsh.exe'
        $text = $global:OSSetupTestHost -join "`n"
        $text | Should -BeLike '*ATTENTION*Microsoft Store*9MZ1SNWT0N5D (code 0x8A150014)*'
        foreach ($cause in 'LTSC', 'debloat', 'winget source list', 'winget source reset --force', 'pare-feu', 'Repli*MSI de PowerShell 7') {
            $text | Should -BeLike "*$cause*"
        }
    }

    It 'Store indisponible sur un poste qui a déjà le MSI : le garde sans rien installer' {
        $global:OSSetupTestWingetCode.msstore = -1978335212
        Install-PowerShell
        $global:OSSetupTestWinget.Count | Should -Be 1
        $script:InstalledTools | Should -BeNullOrEmpty
        $script:SetupPwsh | Should -Be 'C:\OSSetupTest\PowerShell\7\pwsh.exe'
    }

    It 'se replie aussi quand le paquet du Store s''installe sans son alias d''exécution' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -eq $script:storeAlias }
        Install-PowerShell
        $script:SetupPwsh | Should -Be 'C:\OSSetupTest\PowerShell\7\pwsh.exe'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*Alias d''exécution du PowerShell du Store introuvable*'
    }

    It 'ne s''arrête que si le Store et le MSI échouent tous les deux, en donnant les deux codes' {
        $global:OSSetupTestWingetCode.msstore = -1978335212
        $global:OSSetupTestWingetCode.winget = -1978335216
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'pwsh' }
        { Install-PowerShell } | Should -Throw -ExpectedMessage '*ni depuis le Microsoft Store (*0x8A150014*) ni par son MSI (*0x8A150010*)*'
        $script:SetupPwsh | Should -BeNullOrEmpty
    }

    It 'garde la source winget et la portée machine par défaut (Git)' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
        { Install-WingetPackage -Id 'Git.Git' -Command 'git' } | Should -Throw '*introuvable dans le PATH*'
        $global:OSSetupTestWinget[0] | Should -BeLike 'install --id Git.Git --exact --source winget --silent*--scope machine'
    }

    It 'lance le setup par le pwsh retenu, jamais par le premier pwsh du PATH' {
        $script:bootstrapText | Should -Match '& \$script:SetupPwsh -NoProfile -ExecutionPolicy Bypass -File \$setupScript @SetupArguments'
        $script:bootstrapText | Should -Not -Match '& pwsh '
    }
}

Describe 'bootstrap.ps1 : PATH de la session' {
    BeforeAll {
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Update-SessionPath' }, $true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    It 'recharge le PATH du registre en gardant les entrées propres à la session, sans doublon' {
        $previous = $env:Path
        $machineFirst = @([Environment]::GetEnvironmentVariable('Path', 'Machine').Split(';') | Where-Object { $_.Trim() })[0]
        try {
            # Seul le PATH du processus est modifié ; le registre est seulement lu.
            $env:Path = "C:\session-seulement;$($machineFirst.ToUpperInvariant())\"
            Update-SessionPath
            $entries = @($env:Path.Split(';'))
            $entries | Should -Contain 'C:\session-seulement'
            @($entries | Where-Object { $_.TrimEnd('\') -eq $machineFirst.TrimEnd('\') }).Count | Should -Be 1
            $entries[0] | Should -Be $machineFirst.Trim()
        }
        finally {
            $env:Path = $previous
        }
    }
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
        foreach ($name in 'Test-WhatIfArgument', 'Get-SimulationSetupArgument', 'Show-BootstrapSimulation', 'Test-Elevated') {
            $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        foreach ($variable in 'WhatIfArgumentPattern', 'WhatIfValuePattern') {
            $assignment = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($node.Left)" -eq "`$script:$variable" }, $true)
            . ([scriptblock]::Create($assignment.Extent.Text))
        }
        $script:simulationAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-BootstrapSimulation' }, $true)
        $script:simulationParameters = @{ RepoUrl = 'https://example.invalid/repo.git'; Branch = 'main'; Destination = 'C:\OSSetupTest\OS-Setup' }
        # Module Appx non chargé sous PowerShell 7 : fonction de remplacement, toujours simulée.
        function Get-AppxPackage { [CmdletBinding()] param([string]$Name) $null = $Name }
        $script:storeAlias = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'
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
        Test-WhatIfArgument -Argument 'WhatIf' | Should -BeFalse
        Test-WhatIfArgument -Argument $null | Should -BeFalse
    }

    It 'reconnaît aussi <_>, que setup.ps1 accepte comme -WhatIf' -ForEach @('-What', '-wh', '-WHATI', '-wi', '-WhatIf:', '-wi:', '-WhatIf:$true') {
        Test-WhatIfArgument -Argument '-Profiles', 'base', $_ | Should -BeTrue
    }

    It 'reconnaît -WhatIf introduit par le tiret typographique U+<_> (texte copié depuis une page web)' -ForEach @('2013', '2014', '2015') {
        $dash = [string][char][Convert]::ToInt32($_, 16)
        Test-WhatIfArgument -Argument "${dash}WhatIf" | Should -BeTrue
        Test-WhatIfArgument -Argument "${dash}wi" | Should -BeTrue
        Get-SimulationSetupArgument -Argument '-Yes', "${dash}WhatIf" | Should -Be @('-Yes', '-WhatIf')
    }

    It 'dans le doute, simule aussi avec une valeur fausse (<_>)' -ForEach @('-WhatIf:$false', '-What:$false', '-wi:0') {
        Test-WhatIfArgument -Argument $_ | Should -BeTrue
    }

    It 'ne prend pas pour -WhatIf <_>' -ForEach @('-W', '-wa', '-WarningAction', '-WhatIfX', 'x-WhatIf') {
        Test-WhatIfArgument -Argument $_ | Should -BeFalse
    }

    It 'transmet à setup.ps1 un seul -WhatIf, sans la valeur reçue séparément' {
        Get-SimulationSetupArgument -Argument '-WhatIf', '$false', '-Yes' | Should -Be @('-Yes', '-WhatIf')
        Get-SimulationSetupArgument -Argument '-WhatIf:', 'True', '-Profiles', 'base' | Should -Be @('-Profiles', 'base', '-WhatIf')
        Get-SimulationSetupArgument -Argument '-wi', '0' | Should -Be @('-WhatIf')
        # Valeur collée : l'argument suivant n'est pas une valeur de -WhatIf.
        Get-SimulationSetupArgument -Argument '-WhatIf:$true', '1' | Should -Be @('1', '-WhatIf')
        Get-SimulationSetupArgument -Argument '-AnswerFile', 'true.json', '-WhatIf' | Should -Be @('-AnswerFile', 'true.json', '-WhatIf')
        Get-SimulationSetupArgument -Argument $null | Should -Be @('-WhatIf')
    }

    It 'reconnaît -WhatIf avec une valeur tel que le reçoit le bootstrap lancé par <_> -File' -ForEach @('powershell.exe', 'pwsh.exe') {
        # Script témoin déclaré comme le bootstrap : ses arguments restants, tels que PowerShell les lui remet.
        $probe = Join-Path -Path $TestDrive -ChildPath 'remaining.ps1'
        Set-Content -LiteralPath $probe -Encoding utf8 -Value @(
            '[CmdletBinding(PositionalBinding = $false)]'
            'param([string]$Branch, [Parameter(ValueFromRemainingArguments)][string[]]$SetupArguments)'
            '$SetupArguments | ConvertTo-Json -Compress'
        )
        # Get-Command est remplacé dans ce bloc : chemins connus.
        $exe = if ($_ -eq 'pwsh.exe') { (Get-Process -Id $PID).Path } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
        foreach ($form in '-WhatIf:$false', '-WhatIf:$true', '-wi:0') {
            $received = @(& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe '-Yes' $form | ConvertFrom-Json)
            # Découpé en deux arguments : nom, puis valeur.
            $received.Count | Should -Be 3 -Because $form
            Test-WhatIfArgument -Argument $received | Should -BeTrue -Because $form
            Get-SimulationSetupArgument -Argument $received | Should -Be @('-Yes', '-WhatIf') -Because $form
        }
    }

    It 'reconnaît exactement les formes que PowerShell lie au paramètre WhatIf d''un script' {
        # Script témoin avec SupportsShouldProcess, comme setup.ps1 (paramètres communs WarningAction… compris).
        $probe = Join-Path -Path $TestDrive -ChildPath 'probe.ps1'
        Set-Content -LiteralPath $probe -Value '[CmdletBinding(SupportsShouldProcess)] param() [bool]$WhatIfPreference'
        foreach ($form in '-What', '-wh', '-wi', '-WhatIf') {
            & ([scriptblock]::Create("& '$($probe -replace "'", "''")' $form")) | Should -BeTrue -Because $form
            Test-WhatIfArgument -Argument $form | Should -BeTrue -Because $form
        }
        { & ([scriptblock]::Create("& '$($probe -replace "'", "''")' -W")) } | Should -Throw '*ambigu*'
    }

    It 'sur une machine vierge, annonce les installations et le clonage puis s''arrête en expliquant pourquoi' {
        Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' | Should -BeNullOrEmpty
        $text = $global:OSSetupTestHost -join "`n"
        $text | Should -BeLike '*winget : serait installé*'
        $text | Should -BeLike '*Git.Git : serait installé*'
        $text | Should -BeLike '*PowerShell 7 (Store) : serait installé (Microsoft Store) ; si le Store est indisponible, repli : le MSI de PowerShell 7 serait installé (winget)*'
        $text | Should -BeLike '*serait cloné dans C:\OSSetupTest\OS-Setup*'
        $text | Should -BeLike '*Simulation du setup impossible (PowerShell 7 absent, pas encore de copie du dépôt)*'
    }

    It 'lance la simulation du setup par le PowerShell 7 du Store quand son paquet est présent, même avec un autre pwsh dans le PATH' {
        Mock Get-AppxPackage { [pscustomobject]@{ Name = 'Microsoft.PowerShell' } }
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -in 'C:\OSSetupTest\clone\setup.ps1', $script:storeAlias }
        $result = Show-BootstrapSimulation @script:simulationParameters -ScriptRoot 'C:\OSSetupTest\clone'
        $result.Pwsh | Should -Be $script:storeAlias
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*PowerShell 7 (Store) : présent*'
    }

    It 'sans le paquet du Store, l''annonce à installer et simule le setup avec le PowerShell 7 du PATH' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'C:\OSSetupTest\clone\setup.ps1' }
        $result = Show-BootstrapSimulation @script:simulationParameters -ScriptRoot 'C:\OSSetupTest\clone'
        $result.Pwsh | Should -Be 'C:\OSSetupTest\pwsh.exe'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*PowerShell 7 (Store) : serait installé (Microsoft Store) ; si le Store est indisponible, repli : un PowerShell 7 est déjà présent (C:\OSSetupTest\pwsh.exe)*'
        $result.SetupScript | Should -Be 'C:\OSSetupTest\clone\setup.ps1'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*copie utilisée telle quelle (C:\OSSetupTest\clone)*'
        $global:OSSetupTestHost -join "`n" | Should -Not -BeLike '*-Branch serait ignoré*'
    }

    It 'annonce que -Branch serait ignoré quand il est lancé depuis un clone' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'C:\OSSetupTest\clone\setup.ps1' }
        (Show-BootstrapSimulation @script:simulationParameters -ScriptRoot 'C:\OSSetupTest\clone' -BranchRequested).SetupScript |
            Should -Be 'C:\OSSetupTest\clone\setup.ps1'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*-Branch serait ignoré : le clone d''où le bootstrap est lancé est utilisé tel quel*'
    }

    It 'utilise la copie existante dans la destination sans la mettre à jour' {
        Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\pwsh.exe' } } -ParameterFilter { $Name -eq 'pwsh' }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'C:\OSSetupTest\OS-Setup\*' }
        (Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '').SetupScript | Should -Be 'C:\OSSetupTest\OS-Setup\setup.ps1'
        $global:OSSetupTestHost -join "`n" | Should -BeLike '*serait mis à jour (git pull --ff-only)*'
    }

    Context 'copie existante dans la destination et -Branch donné' {
        BeforeEach {
            Mock Get-Command { [pscustomobject]@{ Source = 'C:\OSSetupTest\tool.exe' } } -ParameterFilter { $Name -in 'pwsh', 'git' }
            Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like 'C:\OSSetupTest\OS-Setup\*' }
            $global:OSSetupTestGitStatus = @()
            Mock git {
                $global:LASTEXITCODE = 0
                if ($args -contains 'rev-parse') { return 'dev' }
                if ($args -contains 'status') { return $global:OSSetupTestGitStatus }
            }
        }

        AfterEach {
            Remove-Variable -Name OSSetupTestGitStatus -Scope Global -ErrorAction SilentlyContinue
        }

        It 'annonce le basculement d''une copie sans modification locale' {
            Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' -BranchRequested | Out-Null
            $global:OSSetupTestHost -join "`n" | Should -BeLike '*serait basculé de la branche « dev » vers « main » puis mis à jour*'
        }

        It 'annonce l''arrêt quand la copie a des modifications locales' {
            $global:OSSetupTestGitStatus = @(' M setup.ps1')
            Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' -BranchRequested | Out-Null
            $text = $global:OSSetupTestHost -join "`n"
            $text | Should -BeLike '*branche « dev » avec des modifications locales*s''arrêterait sans le basculer sur « main »*'
            $text | Should -Not -BeLike '*serait mis à jour*'
        }

        It 'annonce seulement la mise à jour d''une copie déjà sur la branche demandée' {
            Show-BootstrapSimulation @script:simulationParameters -Branch 'dev' -ScriptRoot '' -BranchRequested | Out-Null
            $global:OSSetupTestHost -join "`n" | Should -BeLike '*Dépôt : serait mis à jour (git pull --ff-only)*'
        }

        It 'sans git, annonce les deux issues possibles' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
            Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' -BranchRequested | Out-Null
            $global:OSSetupTestHost -join "`n" | Should -BeLike '*serait basculé sur la branche « main »*s''il n''a aucune modification locale*'
            Should -Invoke git -Times 0
        }

        It 'annonce les deux issues possibles quand git échoue (<Case>)' -ForEach @(
            @{ Case = 'branche courante illisible'; Failing = 'rev-parse'; Calls = 1 }
            @{ Case = 'état de la copie illisible'; Failing = 'status'; Calls = 2 }
        ) {
            $global:OSSetupTestGitFailing = $Failing
            Mock git {
                $global:LASTEXITCODE = if ($args -contains $global:OSSetupTestGitFailing) { 128 } else { 0 }
                if ($args -contains 'rev-parse') { return 'dev' }
            }
            try {
                Show-BootstrapSimulation @script:simulationParameters -ScriptRoot '' -BranchRequested | Out-Null
            }
            finally {
                Remove-Variable -Name OSSetupTestGitFailing -Scope Global -ErrorAction SilentlyContinue
            }
            $text = $global:OSSetupTestHost -join "`n"
            $text | Should -BeLike '*serait basculé sur la branche « main »*s''il n''a aucune modification locale*'
            $text | Should -Not -BeLike '*branche « dev » vers « main »*'
            Should -Invoke git -Times $Calls -Exactly
        }
    }

    It 'n''appelle aucune commande qui modifie la machine' {
        $commands = $script:simulationAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        $names = $commands | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique
        $allowed = 'Get-AppxPackage', 'Get-Command', 'git', 'Join-Path', 'Select-Object', 'Test-Elevated', 'Test-Path', 'Write-Host', 'Write-Step'
        $names | Where-Object { $_ -notin $allowed } | Should -BeNullOrEmpty
        # git en lecture seule.
        $gitCalls = @($commands | Where-Object { $_.GetCommandName() -eq 'git' } | ForEach-Object { "$($_.CommandElements[3])" })
        $gitCalls | Where-Object { $_ -notin 'rev-parse', 'status' } | Should -BeNullOrEmpty
        $gitCalls.Count | Should -BeGreaterThan 0
    }

    It 'simule avant la relance en administrateur et avant toute installation' {
        $simulation = $script:bootstrapText.IndexOf('if (Test-WhatIfArgument -Argument $SetupArguments)')
        $simulation | Should -BeGreaterThan 0
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Relance en administrateur (validez')
        $simulation | Should -BeLessThan $script:bootstrapText.IndexOf('Initialize-Winget' + [Environment]::NewLine)
    }
}

Describe 'bootstrap.ps1 -WhatIf : lancement de la simulation du setup' {
    BeforeAll {
        # Copie du bootstrap coupée juste après le bloc de simulation (élévation, installations et clonage retirés,
        # remplacés par « exit 99 »), lancée depuis un faux clone dont setup.ps1 affiche seulement ses arguments.
        $whatIfBlock = $ast.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.IfStatementAst] -and
            $_.Clauses[0].Item1.Extent.Text -eq 'Test-WhatIfArgument -Argument $SetupArguments'
        }
        $whatIfBlock | Should -HaveCount 1
        $script:truncatedBootstrap = $ast.Extent.Text.Substring(0, $whatIfBlock.Extent.EndOffset) + "`r`nexit 99`r`n"
        $script:powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    BeforeEach {
        $clone = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
        New-Item -Path $clone -ItemType Directory | Out-Null
        Set-Content -LiteralPath "$clone\bootstrap.ps1" -Value $script:truncatedBootstrap -Encoding utf8BOM -NoNewline
        Set-Content -LiteralPath "$clone\setup.ps1" -Value '"SETUP-ARGS=$($args -join ''|'')"; exit 7'
        # PowerShell 7 des tests en tête du PATH de l'enfant : le bootstrap le trouve comme sur une machine équipée.
        $previousPath = $env:Path
        $env:Path = "$(Split-Path -Path (Get-Process -Id $PID).Path -Parent);$env:Path"
    }

    AfterEach {
        $env:Path = $previousPath
    }

    It 'transmet à setup.ps1 les arguments de simulation et signale -Branch ignoré (<Case>)' -ForEach @(
        @{ Case = 'avec -Branch'; Branch = @('-Branch', 'dev'); Ignored = $true }
        @{ Case = 'sans -Branch'; Branch = @(); Ignored = $false }
    ) {
        $arguments = @($Branch) + @('-Destination', "$clone\absent", '-Yes', '-WhatIf:$false')
        $output = $null | & $script:powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$clone\bootstrap.ps1" @arguments 2>&1
        $LASTEXITCODE | Should -Be 7 -Because "$output"
        "$output" | Should -Match 'SETUP-ARGS=-Yes\|-WhatIf( |$)'
        if ($Ignored) { "$output" | Should -BeLike '*-Branch serait ignor*' }
        else { "$output" | Should -Not -BeLike '*-Branch serait ignor*' }
    }
}
