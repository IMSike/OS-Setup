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
