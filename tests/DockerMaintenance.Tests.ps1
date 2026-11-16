BeforeAll {
    # Le script s'exécute tout entier quand on le lance (registre, Docker, WSL) : seules ses fonctions et les bornes du
    # journal sont reprises de son arbre syntaxique, et définies ici. $PSScriptRoot (dossier du script déployé) y est
    # remplacé par un dossier de test.
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\dotfiles\docker\docker-maintenance.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -Path $scriptPath).Path, [ref]$null, [ref]$null)
    foreach ($name in 'Write-MaintenanceLog', 'Invoke-VhdCompaction') {
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        . ([scriptblock]::Create($function.Extent.Text.Replace('$PSScriptRoot', '$MaintenanceRoot')))
    }
    foreach ($name in 'logMaxBytes', 'logKeepLines') {
        $assignment = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq $name
            }, $false)
        . ([scriptblock]::Create($assignment.Extent.Text))
    }

    # diskpart simulé : garde les commandes du script reçu (/s <fichier>) et rend le code de sortie demandé.
    function Invoke-FakeDiskpart {
        $global:OSSetupTestDiskpart.Add(@(Get-Content -LiteralPath $args[1]))
        $global:LASTEXITCODE = $global:OSSetupTestDiskpartExit
        'DiskPart a réussi.'
    }
}

Describe 'docker-maintenance.ps1 : journal borné' {
    BeforeEach {
        $MaintenanceRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path $MaintenanceRoot -ItemType Directory | Out-Null
        $logPath = Join-Path -Path $MaintenanceRoot -ChildPath 'docker-maintenance.log'
    }

    It 'garde les dernières lignes quand le journal dépasse sa taille maximale, puis ajoute la nouvelle' {
        $lines = 1..2000 | ForEach-Object { 'ligne {0:D4} {1}' -f $_, ('x' * 60) }
        Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
        (Get-Item -LiteralPath $logPath).Length | Should -BeGreaterThan $logMaxBytes
        Write-MaintenanceLog 'nouvelle entrée'
        $kept = @(Get-Content -LiteralPath $logPath -Encoding UTF8)
        $kept.Count | Should -Be ($logKeepLines + 1)
        $kept[0] | Should -BeLike ('ligne {0:D4} *' -f (2000 - $logKeepLines + 1))
        $kept[-2] | Should -BeLike 'ligne 2000 *'
        $kept[-1] | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} nouvelle entrée$'
    }

    It 'ne coupe pas un journal sous la taille maximale' {
        Set-Content -LiteralPath $logPath -Value (1..10 | ForEach-Object { "ligne $_" }) -Encoding UTF8
        Write-MaintenanceLog 'suite'
        @(Get-Content -LiteralPath $logPath -Encoding UTF8).Count | Should -Be 11
    }
}

Describe 'docker-maintenance.ps1 : compactage du disque virtuel' {
    BeforeEach {
        $MaintenanceRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path $MaintenanceRoot -ItemType Directory | Out-Null
        $logPath = Join-Path -Path $MaintenanceRoot -ChildPath 'docker-maintenance.log'
        $vhd = Join-Path -Path $MaintenanceRoot -ChildPath 'Hélène\docker_data.vhdx'
        New-Item -Path (Split-Path -Path $vhd -Parent) -ItemType Directory | Out-Null
        Set-Content -LiteralPath $vhd -Value 'disque'
        $diskpart = 'Invoke-FakeDiskpart'
        $global:OSSetupTestDiskpart = [System.Collections.Generic.List[object]]::new()
        $global:OSSetupTestDiskpartExit = 0
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestDiskpart, OSSetupTestDiskpartExit -Scope Global -ErrorAction SilentlyContinue
    }

    It 'attache le disque en lecture seule, le compacte et le détache, puis supprime le script de diskpart' {
        Invoke-VhdCompaction -Path $vhd
        $global:OSSetupTestDiskpart.Count | Should -Be 1
        $global:OSSetupTestDiskpart[0] | Should -Be @("select vdisk file=`"$vhd`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk')
        Join-Path -Path $MaintenanceRoot -ChildPath 'os-setup-compact.txt' | Should -Not -Exist
        Get-Content -LiteralPath $logPath -Encoding UTF8 | Should -BeLike '* compactage : *'
    }

    It 'refuse un chemin qui ajouterait des commandes au script de diskpart (<Case>)' -ForEach @(
        @{ Case = 'guillemet'; Suffix = '" detach' }
        @{ Case = 'retour à la ligne'; Suffix = "`nclean" }
    ) {
        { Invoke-VhdCompaction -Path "$vhd$Suffix" } | Should -Throw '*refusé*'
        $global:OSSetupTestDiskpart.Count | Should -Be 0
    }

    It 'en cas d''échec, détache le disque et échoue avec le code de diskpart, sans laisser de script' {
        $global:OSSetupTestDiskpartExit = 5
        { Invoke-VhdCompaction -Path $vhd } | Should -Throw '*diskpart a échoué (code 5)*'
        $global:OSSetupTestDiskpart.Count | Should -Be 2
        $global:OSSetupTestDiskpart[1] | Should -Be @("select vdisk file=`"$vhd`"", 'detach vdisk')
        Join-Path -Path $MaintenanceRoot -ChildPath 'os-setup-compact.txt' | Should -Not -Exist
    }
}
