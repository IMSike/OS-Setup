BeforeDiscovery {
    $analyzerMissing = -not (Get-Module -ListAvailable -Name PSScriptAnalyzer)

    # Scripts exécutés par Windows PowerShell 5.1 : le bootstrap, le nettoyage détaché, les tâches du Store, et tout script
    # lancé par une action logon-task du catalogue (sa source dans dotfiles/ est celle de l'action file de même cible).
    $discoveryRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $windowsPowerShellScripts = [System.Collections.Generic.List[string]]@(
        'bootstrap.ps1'
        'src\cleanup.ps1'
        'src\resume.ps1'
        'src\store-update\StoreUpdate.System.ps1'
        'src\store-update\StoreUpdate.User.ps1'
        'src\store-update\StoreUpdate.Prompt.ps1'
        'src\store-update\StoreUpdate.Common.ps1'
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
        $findings = @(Get-AnalyzerFinding -Path 'tests' -Settings (Join-Path -Path $repoRoot -ChildPath 'tests\PSScriptAnalyzerSettings.psd1'))
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

Describe 'Manifeste du module' {
    It 'exporte toutes les fonctions du module, et seulement elles' {
        $moduleRoot = Join-Path -Path $repoRoot -ChildPath 'src\OSSetup'
        $files = @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Functions') -Filter '*.ps1') +
            @(Get-Item -Path (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psm1'))
        $defined = Select-String -Path $files.FullName -Pattern '^function ([\w-]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }
        $exported = (Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'OSSetup.psd1')).FunctionsToExport
        @($exported | Sort-Object) | Should -Be @($defined | Sort-Object)
    }
}
