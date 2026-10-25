BeforeDiscovery {
    $analyzerMissing = -not (Get-Module -ListAvailable -Name PSScriptAnalyzer)
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