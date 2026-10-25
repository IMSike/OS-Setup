BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
}

Describe 'ConvertTo-OSSetupPathList' {
    It 'supprime les entrées vides et les doublons (casse et \ final ignorés)' {
        ConvertTo-OSSetupPathList -Value 'C:\A;;c:\a\;C:\B; ;C:\B' | Should -Be @('C:\A', 'C:\B')
    }

    It 'accepte une valeur vide' {
        @(ConvertTo-OSSetupPathList -Value '').Count | Should -Be 0
    }
}

Describe 'Update-OSSetupSessionPath' {
    BeforeEach {
        $savedPath = $env:Path
    }
    AfterEach {
        $env:Path = $savedPath
    }

    It 'ajoute les entrées du registre et conserve celles propres à la session' {
        Mock -ModuleName OSSetup -CommandName Get-OSSetupPathEntry -ParameterFilter { $Scope -eq 'Machine' } -MockWith { 'C:\Machine', 'C:\Nouveau' }
        Mock -ModuleName OSSetup -CommandName Get-OSSetupPathEntry -ParameterFilter { $Scope -eq 'User' } -MockWith { 'C:\User' }
        $env:Path = 'C:\Machine;C:\Session'
        Update-OSSetupSessionPath
        $env:Path | Should -Be 'C:\Machine;C:\Nouveau;C:\User;C:\Session'
    }
}
