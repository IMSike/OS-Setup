BeforeDiscovery {
    $analyzerMissing = -not (Get-Module -ListAvailable -Name PSScriptAnalyzer)

    # Scripts exécutés par Windows PowerShell 5.1 : le bootstrap, le nettoyage détaché, la reprise après redémarrage,
    # le lanceur du bootstrap dans la VM de test, et tout script lancé par une action logon-task du catalogue (sa
    # source dans dotfiles/ est celle de l'action file de même cible).
    $discoveryRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $windowsPowerShellScripts = [System.Collections.Generic.List[string]]@(
        'bootstrap.ps1'
        'src\cleanup.ps1'
        'src\resume.ps1'
        'tests\vm\Start-GuestRun.ps1'
        'dotfiles\docker\docker-maintenance.ps1'
    )
    foreach ($file in Get-ChildItem -Path (Join-Path -Path $discoveryRoot -ChildPath 'catalog') -Filter '*.json' -Recurse) {
        $item = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        if (-not ($item -is [System.Collections.IDictionary]) -or -not $item['actions']) { continue }
        foreach ($task in @($item['actions'] | Where-Object { $_['provider'] -eq 'logon-task' })) {
            foreach ($copy in @($item['actions'] | Where-Object { $_['provider'] -eq 'file' -and $_['target'] -eq $task['script'] })) {
                $source = 'dotfiles\' + ($copy['source'] -replace '/', '\')
                if ($source -notin $windowsPowerShellScripts) { $windowsPowerShellScripts.Add($source) }
            }
        }
    }
}

BeforeAll {
    $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

    function Get-AnalyzerFinding {
        # Avertissements de PSScriptAnalyzer, une ligne lisible par avertissement (fichier:ligne [règle] message).
        param([string[]]$Path, [string]$Settings)
        foreach ($item in $Path) {
            Invoke-ScriptAnalyzer -Path (Join-Path -Path $repoRoot -ChildPath $item) -Recurse -Settings $Settings |
                ForEach-Object { '{0}:{1} [{2}] {3}' -f $_.ScriptPath.Substring($repoRoot.Length + 1), $_.Line, $_.RuleName, $_.Message }
        }
    }
}

Describe 'Qualité du code (PSScriptAnalyzer)' -Skip:$analyzerMissing {
    It 'le code du dépôt ne produit aucun avertissement' {
        $findings = @(Get-AnalyzerFinding -Path 'setup.ps1', 'bootstrap.ps1', 'src', 'dotfiles' `
                -Settings (Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'))
        $findings | Should -BeNullOrEmpty
    }

    It 'les tests ne produisent aucun avertissement' {
        # Tests Pester seulement : l'outillage des VM n'a pas besoin de leurs exclusions (test suivant).
        $testPaths = Get-ChildItem -Path (Join-Path -Path $repoRoot -ChildPath 'tests') -Exclude 'vm' |
            ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }
        $findings = @(Get-AnalyzerFinding -Path $testPaths -Settings (Join-Path -Path $repoRoot -ChildPath 'tests\PSScriptAnalyzerSettings.psd1'))
        $findings | Should -BeNullOrEmpty
    }

    It 'l''outillage des VM de test ne produit aucun avertissement' {
        $findings = @(Get-AnalyzerFinding -Path 'tests\vm' -Settings (Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'))
        $findings | Should -BeNullOrEmpty
    }
}

Describe 'Compatibilité Windows PowerShell 5.1' {
    It '<_> est analysable par Windows PowerShell 5.1, qui l''exécute' -ForEach $windowsPowerShellScripts {
        $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -Path $powershell)) { Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 absent'; return }
        $path = Join-Path -Path $repoRoot -ChildPath $_
        $path | Should -Exist
        $command = "`$e = `$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$path', [ref]`$null, [ref]`$e); `$e | ForEach-Object { `$_.Message }"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        @(& $powershell -NoProfile -NonInteractive -EncodedCommand $encoded) | Should -BeNullOrEmpty
    }
}

Describe 'Cmdlets qui n''héritent pas de la préférence d''erreur du module' {
    It 'chaque appel aux cmdlets ScheduledTasks (CDXML), Appx (relayées par Windows PowerShell) et DISM précise -ErrorAction' {
        # Constaté pour ScheduledTasks (CDXML) : appelée depuis le module, Get-ScheduledTask d'une tâche absente n'y lève
        # pas d'exception malgré $ErrorActionPreference = 'Stop'. Appx et DISM : même règle, sans compter sur la
        # préférence du module. Seule la présence de -ErrorAction est vérifiée, pas sa valeur : Stop pour échouer,
        # SilentlyContinue pour une absence tolérée.
        # Appx et DISM : seules les cmdlets appelées par src et setup.ps1 (les fonctionnalités facultatives passent par
        # dism.exe) ; une nouvelle cmdlet de ces familles est à ajouter ici.
        $names = @(Get-Command -Module ScheduledTasks -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) +
            @('Get-AppxPackage', 'Get-AppxProvisionedPackage', 'Remove-AppxPackage', 'Remove-AppxProvisionedPackage') +
            @('Get-WindowsCapability', 'Remove-WindowsCapability')
        $files = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Filter '*.ps1' -Recurse) +
            @(Get-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'setup.ps1'))
        $missing = foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($command.GetCommandName() -notin $names) { continue }
                $parameters = @($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
                        ForEach-Object { $_.ParameterName })
                if ('ErrorAction' -notin $parameters) { '{0}:{1} {2}' -f $file.Name, $command.Extent.StartLineNumber, $command.GetCommandName() }
            }
        }
        $names.Count | Should -BeGreaterThan 5
        $missing | Should -BeNullOrEmpty
    }
}

Describe 'Manifeste du module' {
    It 'exporte toutes les fonctions du module, et seulement elles' {
        $moduleRoot = Join-Path -Path $repoRoot -ChildPath 'src\OSSetup'
        $files = @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Functions') -Filter '*.ps1') +
            @(Get-Item -Path (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psm1'))
        $defined = Select-String -Path $files.FullName -Pattern '^function ([\w-]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }
        $exported = (Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psd1')).FunctionsToExport
        @($exported | Sort-Object) | Should -Be @($defined | Sort-Object)
    }

    It 'range chaque export dans la section de son fichier, sections et noms triés' {
        # Ordre attendu : une section « # <fichier> » par fichier de Functions (par nom), puis OSSetup.psm1 ; dans chaque
        # section, les fonctions définies par ce fichier, triées.
        $moduleRoot = Join-Path -Path $repoRoot -ChildPath 'src\OSSetup'
        $files = @(Get-ChildItem -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Functions') -Filter '*.ps1' | Sort-Object -Property Name) +
            @(Get-Item -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psm1'))
        $expected = foreach ($file in $files) {
            $names = @(Select-String -LiteralPath $file.FullName -Pattern '^function ([\w-]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object)
            if ($names.Count -eq 0) { continue }
            "# $($file.Name)"
            $names
        }
        # Lignes du bloc FunctionsToExport, commentaires de section compris.
        $text = Get-Content -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psd1') -Raw
        $block = [regex]::Match($text, '(?s)FunctionsToExport\s*=\s*@\((.*?)\n\s*\)').Groups[1].Value
        $actual = @($block -split '\r?\n' | ForEach-Object { $_.Trim().Trim("'") } | Where-Object { $_ })
        $actual | Should -Be @($expected)
    }
}
