BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    # Outil externe factice : sortie, code de sortie et encodage de la console lus pendant l'appel.
    function global:Invoke-OSSetupTestTool {
        $global:OSSetupTestToolArgs = $args
        $global:OSSetupTestToolEncoding = [Console]::OutputEncoding.WebName
        if ($global:OSSetupTestToolThrow) { throw 'outil en panne' }
        $global:LASTEXITCODE = $global:OSSetupTestToolExitCode
        'première ligne', '', '   ', '|■■■■      | 40 %', 'dernière ligne'
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-OSSetupTestTool -ErrorAction SilentlyContinue
    Remove-Variable -Name OSSetupTestToolArgs, OSSetupTestToolEncoding, OSSetupTestToolThrow, OSSetupTestToolExitCode -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Invoke-OSSetupNativeCommand' {
    BeforeEach {
        $global:OSSetupTestToolExitCode = 0
        $global:OSSetupTestToolThrow = $false
        Mock -ModuleName OSSetup -CommandName Write-OSSetupLog
    }

    It 'passe les arguments et journalise les lignes non vides en Detail' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -ArgumentList 'install', 'a b'
        @($global:OSSetupTestToolArgs) | Should -Be @('install', 'a b')
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 3 -Exactly -ParameterFilter { $Level -eq 'Detail' }
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 1 -Exactly -ParameterFilter { $Message -eq '  première ligne' }
    }

    It 'ne journalise pas les lignes qui correspondent au filtre' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -LogFilter '^\|'
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 2 -Exactly
        Should -Invoke -ModuleName OSSetup -CommandName Write-OSSetupLog -Times 0 -Exactly -ParameterFilter { $Message -match '\|' }
    }

    It 'lève une exception avec le code de sortie en cas d''échec' {
        $global:OSSetupTestToolExitCode = 3
        { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -ArgumentList 'install' } |
            Should -Throw 'Invoke-OSSetupTestTool install a échoué (code 3).'
        { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Label 'outil factice' } |
            Should -Throw 'outil factice a échoué (code 3).'
    }

    It 'avec -NoThrow, retourne le code de sortie sans exception' {
        $global:OSSetupTestToolExitCode = 5
        $result = Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -NoThrow -PassThru
        $result.ExitCode | Should -Be 5
        $result.Output | Should -Contain 'dernière ligne'
    }

    It 'ne retourne rien sans -PassThru' {
        Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool | Should -BeNullOrEmpty
    }

    It 'passe la console en UTF-8 le temps de l''appel avec -Utf8, et restaure l''encodage, même en cas d''exception' {
        $before = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
            Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Utf8
            $global:OSSetupTestToolEncoding | Should -Be 'utf-8'
            [Console]::OutputEncoding.CodePage | Should -Be 850

            $global:OSSetupTestToolThrow = $true
            { Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool -Utf8 } | Should -Throw '*outil en panne*'
            [Console]::OutputEncoding.CodePage | Should -Be 850
        }
        finally {
            [Console]::OutputEncoding = $before
        }
    }

    It 'sans -Utf8, ne change pas l''encodage de la console' {
        $before = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(850)
            Invoke-OSSetupNativeCommand -FilePath Invoke-OSSetupTestTool
            $global:OSSetupTestToolEncoding | Should -Not -Be 'utf-8'
        }
        finally {
            [Console]::OutputEncoding = $before
        }
    }
}
