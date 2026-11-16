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

Describe 'Add-OSSetupPathEntry' {
    # Les clés Environment réelles sont remplacées par des clés jetables de TestRegistry: (lecture et écriture).
    BeforeEach {
        $userKey = "TestRegistry:\$([guid]::NewGuid())"
        $machineKey = "TestRegistry:\$([guid]::NewGuid())"
        New-Item -Path $userKey | Out-Null
        New-Item -Path $machineKey | Out-Null
        $keys = @{ 'HKCU:\Environment' = $userKey; 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' = $machineKey }
        # Sans filtre : un autre chemin lève une erreur au lieu d'atteindre le vrai registre.
        $redirect = { param($Path) if (-not $keys.ContainsKey("$Path")) { throw "Chemin inattendu : $Path" }; $keys["$Path"] }
        Mock -ModuleName OSSetup Get-Item { Microsoft.PowerShell.Management\Get-Item -LiteralPath (& $redirect $LiteralPath) }
        Mock -ModuleName OSSetup Set-ItemProperty {
            Microsoft.PowerShell.Management\Set-ItemProperty -LiteralPath (& $redirect $LiteralPath) -Name $Name -Value $Value -Type $Type
        }
        Mock -ModuleName OSSetup Send-OSSetupEnvironmentChange
        Mock -ModuleName OSSetup Update-OSSetupSessionPath
    }

    It 'ajoute le dossier en fin de PATH sans développer les %VARIABLES%, en gardant le type ExpandString' {
        New-ItemProperty -Path $userKey -Name 'Path' -PropertyType ExpandString -Value '%USERPROFILE%\bin;C:\Outils' | Out-Null
        Add-OSSetupPathEntry -Path 'C:\Nouveau' -Scope User
        $key = Get-Item -Path $userKey
        $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') | Should -Be '%USERPROFILE%\bin;C:\Outils;C:\Nouveau'
        $key.GetValueKind('Path') | Should -Be 'ExpandString'
        Should -Invoke -ModuleName OSSetup Send-OSSetupEnvironmentChange -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Update-OSSetupSessionPath -Times 1 -Exactly
    }

    It 'crée la valeur quand le PATH du compte n''existe pas encore' {
        Add-OSSetupPathEntry -Path 'C:\Nouveau' -Scope User
        $key = Get-Item -Path $userKey
        $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames') | Should -Be 'C:\Nouveau'
        $key.GetValueKind('Path') | Should -Be 'ExpandString'
    }

    It 'ne réécrit rien quand le dossier y est déjà, à la casse et au \ final près' {
        New-ItemProperty -Path $userKey -Name 'Path' -PropertyType String -Value 'c:\outils\;C:\Autre' | Out-Null
        Add-OSSetupPathEntry -Path 'C:\Outils' -Scope User
        Add-OSSetupPathEntry -Path 'C:\AUTRE\' -Scope User
        $key = Get-Item -Path $userKey
        $key.GetValue('Path') | Should -Be 'c:\outils\;C:\Autre'
        $key.GetValueKind('Path') | Should -Be 'String'
        Should -Invoke -ModuleName OSSetup Send-OSSetupEnvironmentChange -Times 0 -Exactly
    }

    It 'écrit dans le PATH de la machine pour la portée Machine, sans toucher à celui du compte' {
        New-ItemProperty -Path $machineKey -Name 'Path' -PropertyType ExpandString -Value '%SystemRoot%\system32' | Out-Null
        Add-OSSetupPathEntry -Path 'C:\Outils' -Scope Machine
        (Get-Item -Path $machineKey).GetValue('Path', '', 'DoNotExpandEnvironmentNames') | Should -Be '%SystemRoot%\system32;C:\Outils'
        (Get-Item -Path $userKey).GetValueNames() | Should -Not -Contain 'Path'
    }
}

Describe 'Provider path : ajout' {
    It 'transmet le dossier et la portée du catalogue, compte par défaut' {
        Mock -ModuleName OSSetup Add-OSSetupPathEntry
        InModuleScope OSSetup {
            $provider = Get-OSSetupProvider -Name 'path'
            & $provider.Invoke @{ path = 'C:\Outils' } @{}
            & $provider.Invoke @{ path = 'C:\Machine'; scope = 'machine' } @{}
        }
        Should -Invoke -ModuleName OSSetup Add-OSSetupPathEntry -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Outils' -and $Scope -eq 'User' }
        Should -Invoke -ModuleName OSSetup Add-OSSetupPathEntry -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Machine' -and $Scope -eq 'Machine' }
    }
}
