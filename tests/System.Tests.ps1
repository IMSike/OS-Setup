[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Providers et méthodes factices : mêmes signatures que les vrais.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    function Invoke-TestProviderTest {
        param([string]$Name, [hashtable]$Action)
        InModuleScope OSSetup -Parameters @{ Name = $Name; Action = $Action } {
            param($Name, $Action)
            & (Get-OSSetupProvider -Name $Name).Test $Action @{}
        }
    }
}

Describe 'Split-OSSetupTaskPath' {
    It 'sépare <Task> en <Path> et <Name>' -ForEach @(
        @{ Task = '\Microsoft\Windows\Autochk\Proxy'; Path = '\Microsoft\Windows\Autochk\'; Name = 'Proxy' }
        @{ Task = '\Racine'; Path = '\'; Name = 'Racine' }
    ) {
        Split-OSSetupTaskPath -Task $Task | Should -Be @($Path, $Name)
    }
}

Describe 'Format-OSSetupDuration' {
    It 'affiche <Seconds> s en « <Expected> »' -ForEach @(
        @{ Seconds = 45; Expected = '45 s' }
        @{ Seconds = 1200; Expected = '20 min' }
        @{ Seconds = 270; Expected = '4 min 30 s' }
    ) {
        Format-OSSetupDuration -Seconds $Seconds | Should -Be $Expected
    }
}

Describe 'ConvertFrom-OSSetupPowerQuery' {
    It 'lit les index actuels secteur et batterie, quelle que soit la langue' {
        $output = @(
            "    GUID du paramètre d’alimentation : 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e  (Éteindre l’affichage après)"
            '      Valeur minimale possible : 0x00000000'
            '      Valeur maximale possible : 0xffffffff'
            '      Incrément possible des paramètres : 0x00000001'
            '    Index actuel du paramètre de courant alternatif : 0x00000258'
            '    Index actuel du paramètre de courant continu : 0x0000012c'
            ''
        )
        $values = ConvertFrom-OSSetupPowerQuery -Output $output
        $values['ac'] | Should -Be 600
        $values['dc'] | Should -Be 300
    }

    It 'lève une erreur sur une sortie inattendue' {
        { ConvertFrom-OSSetupPowerQuery -Output @('Paramètres non valides') } | Should -Throw '*inattendue*'
    }
}

Describe 'Provider service' {
    It 'est conforme si le service est absent' {
        Mock -ModuleName OSSetup Get-Service {}
        Invoke-TestProviderTest -Name service -Action @{ name = 'Nope'; startupType = 'Disabled' } | Should -BeTrue
    }

    It 'exige un service désactivé et arrêté' {
        Mock -ModuleName OSSetup Get-Service { [pscustomobject]@{ StartType = 'Disabled'; Status = 'Running' } }
        Invoke-TestProviderTest -Name service -Action @{ name = 'DiagTrack'; startupType = 'Disabled' } | Should -BeFalse
        Mock -ModuleName OSSetup Get-Service { [pscustomobject]@{ StartType = 'Disabled'; Status = 'Stopped' } }
        Invoke-TestProviderTest -Name service -Action @{ name = 'DiagTrack'; startupType = 'Disabled' } | Should -BeTrue
    }

    It 'n''est pas conforme si le type de démarrage diffère' {
        Mock -ModuleName OSSetup Get-Service { [pscustomobject]@{ StartType = 'Automatic'; Status = 'Stopped' } }
        Invoke-TestProviderTest -Name service -Action @{ name = 'DiagTrack'; startupType = 'Disabled' } | Should -BeFalse
    }
}

Describe 'Provider scheduled-task' {
    It 'est conforme si une tâche à désactiver est absente' {
        Mock -ModuleName OSSetup Get-ScheduledTask {}
        Invoke-TestProviderTest -Name scheduled-task -Action @{ task = '\X\Y'; enabled = $false } | Should -BeTrue
    }

    It 'lève une erreur si une tâche à activer est absente' {
        Mock -ModuleName OSSetup Get-ScheduledTask {}
        { Invoke-TestProviderTest -Name scheduled-task -Action @{ task = '\X\Y'; enabled = $true } } | Should -Throw '*introuvable*'
    }

    It 'compare l''état de la tâche' {
        Mock -ModuleName OSSetup Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } } -ParameterFilter { $TaskPath -eq '\X\' -and $TaskName -eq 'Y' }
        Invoke-TestProviderTest -Name scheduled-task -Action @{ task = '\X\Y'; enabled = $false } | Should -BeFalse
        Invoke-TestProviderTest -Name scheduled-task -Action @{ task = '\X\Y'; enabled = $true } | Should -BeTrue
    }
}

Describe 'ConvertTo-OSSetupUninstallCommand' {
    It 'désinstalle un MSI sans interaction' {
        $entry = [pscustomobject]@{ DisplayName = 'App'; UninstallString = 'MsiExec.exe /I{12345678-1234-1234-1234-123456789ABC}' }
        $command = ConvertTo-OSSetupUninstallCommand -Entry $entry
        $command.FilePath | Should -Be 'msiexec.exe'
        $command.Arguments | Should -Be '/x {12345678-1234-1234-1234-123456789ABC} /qn /norestart'
    }

    It 'préfère la commande silencieuse déclarée' {
        $entry = [pscustomobject]@{ DisplayName = 'App'; UninstallString = '"C:\App\uninst.exe"'; QuietUninstallString = '"C:\App\uninst.exe" /S' }
        $command = ConvertTo-OSSetupUninstallCommand -Entry $entry
        $command.FilePath | Should -Be 'C:\App\uninst.exe'
        $command.Arguments | Should -Be '/S'
    }

    It 'complète la commande ordinaire avec les arguments du catalogue' {
        $entry = [pscustomobject]@{ DisplayName = 'OneDrive'; UninstallString = 'C:\Users\u\AppData\Local\Microsoft\OneDrive\25.1\OneDriveSetup.exe  /uninstall ' }
        $command = ConvertTo-OSSetupUninstallCommand -Entry $entry -Arguments '/silent'
        $command.FilePath | Should -Be 'C:\Users\u\AppData\Local\Microsoft\OneDrive\25.1\OneDriveSetup.exe'
        $command.Arguments | Should -Be '/uninstall /silent'
    }

    It 'lève une erreur sans commande de désinstallation' {
        { ConvertTo-OSSetupUninstallCommand -Entry ([pscustomobject]@{ DisplayName = 'App'; UninstallString = $null }) } | Should -Throw '*Aucune commande*'
    }
}

Describe 'Wait-OSSetupUninstallEntryRemoval' {
    It 'confirme une désinstallation terminée malgré un code de retour trompeur' {
        Mock -ModuleName OSSetup Get-OSSetupUninstallEntry {}
        Wait-OSSetupUninstallEntryRemoval -DisplayName 'Microsoft OneDrive' -TimeoutSeconds 1 | Should -BeTrue
    }

    It 'signale un logiciel toujours présent' {
        Mock -ModuleName OSSetup Get-OSSetupUninstallEntry { [pscustomobject]@{ DisplayName = 'Microsoft OneDrive' } }
        Mock -ModuleName OSSetup Start-Sleep {}
        Wait-OSSetupUninstallEntryRemoval -DisplayName 'Microsoft OneDrive' -TimeoutSeconds 0 | Should -BeFalse
    }
}

Describe 'Provider appx' {
    It 'est conforme quand l''application n''est ni installée ni provisionnée' {
        Mock -ModuleName OSSetup Get-OSSetupAppxPresence { [pscustomobject]@{ Installed = @(); Provisioned = @() } }
        Invoke-TestProviderTest -Name appx -Action @{ name = 'Microsoft.BingWeather' } | Should -BeTrue
    }

    It 'n''est pas conforme si elle reste provisionnée pour les nouveaux comptes' {
        Mock -ModuleName OSSetup Get-OSSetupAppxPresence { [pscustomobject]@{ Installed = @(); Provisioned = @('Microsoft.BingWeather_1_neutral_~_8wekyb3d8bbwe') } }
        Invoke-TestProviderTest -Name appx -Action @{ name = 'Microsoft.BingWeather' } | Should -BeFalse
    }
}

Describe 'Provider windows-capability' {
    It 'compare l''état des capacités dont le nom commence par le nom donné' {
        Mock -ModuleName OSSetup Test-OSSetupElevated { $true }
        Mock -ModuleName OSSetup Get-WindowsCapability {
            [pscustomobject]@{ Name = 'Browser.InternetExplorer~~~~0.0.11.0'; State = 'Installed' }
            [pscustomobject]@{ Name = 'App.StepsRecorder~~~~0.0.1.0'; State = 'NotPresent' }
        }
        Invoke-TestProviderTest -Name windows-capability -Action @{ name = 'Browser.InternetExplorer' } | Should -BeFalse
        Invoke-TestProviderTest -Name windows-capability -Action @{ name = 'App.StepsRecorder' } | Should -BeTrue
    }

    It 'accepte un caractère générique pour la partie propre à une version, et refuse un nom inconnu' {
        Mock -ModuleName OSSetup Test-OSSetupElevated { $true }
        Mock -ModuleName OSSetup Get-WindowsCapability { [pscustomobject]@{ Name = 'Hello.Face.18967~~~~0.0.1.0'; State = 'Installed' } }
        Invoke-TestProviderTest -Name windows-capability -Action @{ name = 'Hello.Face.*' } | Should -BeFalse
        { Invoke-TestProviderTest -Name windows-capability -Action @{ name = 'Hello.Face' } } | Should -Throw '*Aucune capacité*'
    }

    It 'reste à faire sans droits administrateur (lecture impossible)' {
        Mock -ModuleName OSSetup Test-OSSetupElevated { $false }
        Invoke-TestProviderTest -Name windows-capability -Action @{ name = 'Browser.InternetExplorer' } | Should -BeFalse
    }
}

Describe 'Provider win32-uninstall' {
    It 'est conforme quand aucune entrée ne correspond' {
        Mock -ModuleName OSSetup Get-OSSetupUninstallEntry {}
        Invoke-TestProviderTest -Name win32-uninstall -Action @{ displayName = 'Microsoft OneDrive' } | Should -BeTrue
        Mock -ModuleName OSSetup Get-OSSetupUninstallEntry { [pscustomobject]@{ DisplayName = 'Microsoft OneDrive' } }
        Invoke-TestProviderTest -Name win32-uninstall -Action @{ displayName = 'Microsoft OneDrive' } | Should -BeFalse
    }
}

Describe 'Provider power' {
    It 'compare la valeur actuelle du paramètre' {
        Mock -ModuleName OSSetup Get-OSSetupPowerValue { 270 } -ParameterFilter { $Setting -eq 'display' -and $Source -eq 'ac' }
        Invoke-TestProviderTest -Name power -Action @{ setting = 'display'; source = 'ac'; seconds = 270 } | Should -BeTrue
        Invoke-TestProviderTest -Name power -Action @{ setting = 'display'; source = 'ac'; seconds = 0 } | Should -BeFalse
    }
}

Describe 'Show-OSSetupSummary : ouverture de session' {
    BeforeEach {
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        function New-TestResult([string]$Name, [string]$Status, [bool]$Logoff, [bool]$Reboot = $false) {
            [pscustomobject]@{ ItemId = $Name; ItemName = $Name; Description = 'x'; Status = $Status; Detail = $null; RebootRequired = $Reboot; RequiresLogoff = $Logoff }
        }
    }

    It 'signale les réglages appliqués qui attendent une nouvelle session' {
        Show-OSSetupSummary -Result @(
            (New-TestResult -Name 'A' -Status 'done' -Logoff $true)
            (New-TestResult -Name 'A' -Status 'done' -Logoff $true)
            (New-TestResult -Name 'B' -Status 'ok' -Logoff $true)
            (New-TestResult -Name 'C' -Status 'done' -Logoff $false)
        )
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 1 -ParameterFilter { $Message -eq 'Effectif à la prochaine ouverture de session : A.' }
    }

    It 'ne le signale pas quand un redémarrage est prévu' {
        Show-OSSetupSummary -Result @(
            (New-TestResult -Name 'A' -Status 'done' -Logoff $true)
            (New-TestResult -Name 'R' -Status 'reboot' -Logoff $false -Reboot $true)
        )
        Should -Invoke -ModuleName OSSetup Write-OSSetupLog -Times 0 -ParameterFilter { $Message -like 'Effectif*' }
    }
}

Describe 'Valeurs d''origine' {
    BeforeAll {
        InModuleScope OSSetup {
            $script:Providers['fake-read'] = @{
                Name     = 'fake-read'
                Describe = { param($Action, $Context) "fake $($Action['key'])" }
                Test     = { param($Action, $Context) [bool]$global:OSSetupTestApplied[$Action['key']] }
                Read     = { param($Action, $Context) if ($Action['key'] -eq 'broken') { throw 'illisible' }; [ordered]@{ value = "avant-$($Action['key'])" } }
                Invoke   = { param($Action, $Context) $global:OSSetupTestApplied[$Action['key']] = $true }
            }
        }
        function New-ReadStep([string]$Key) {
            [pscustomobject]@{
                ItemId = 'item'; ItemName = 'Item'; RequiresAdmin = $false; RequiresReboot = $false; RequiresLogoff = $false
                DependsOn = @(); Index = 1; Provider = 'fake-read'; Action = @{ provider = 'fake-read'; key = $Key }
                Description = "fake $Key"; Status = 'todo'; Detail = $null
            }
        }
    }

    BeforeEach {
        $global:OSSetupTestApplied = @{}
        Mock -ModuleName OSSetup Write-OSSetupLog {}
        $backupRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
    }

    AfterAll {
        Remove-Variable -Name OSSetupTestApplied -Scope Global -ErrorAction SilentlyContinue
    }

    It 'enregistre l''état avant chaque action appliquée, y compris en cas d''erreur de lecture' {
        $plan = @((New-ReadStep 'a'), (New-ReadStep 'broken'))
        $results = @(Invoke-OSSetupPlan -Plan $plan -Context @{ BackupRoot = $backupRoot })
        $results.Status | Should -Be @('done', 'done')
        $entries = @(Get-Content -Path (Join-Path -Path $backupRoot -ChildPath 'original-values.json') -Raw | ConvertFrom-Json)
        $entries.Count | Should -Be 2
        $entries[0].before.value | Should -Be 'avant-a'
        $entries[0].action.key | Should -Be 'a'
        $entries[1].before.readError | Should -Be 'illisible'

        # Une passe suivante (après redémarrage) complète le même fichier.
        $null = Invoke-OSSetupPlan -Plan @(New-ReadStep 'c') -Context @{ BackupRoot = $backupRoot }
        @(Get-Content -Path (Join-Path -Path $backupRoot -ChildPath 'original-values.json') -Raw | ConvertFrom-Json).Count | Should -Be 3
    }

    It 'n''enregistre rien pour une action déjà conforme' {
        $step = New-ReadStep 'a'
        $step.Status = 'ok'
        $null = Invoke-OSSetupPlan -Plan @($step) -Context @{ BackupRoot = $backupRoot }
        Test-Path -Path (Join-Path -Path $backupRoot -ChildPath 'original-values.json') | Should -BeFalse
    }
}

Describe 'Provider startup-entry' {
    It 'est conforme quand toutes les entrées correspondantes sont désactivées, ou qu''il n''y en a pas' {
        Mock -ModuleName OSSetup Get-OSSetupStartupEntry {}
        Invoke-TestProviderTest -Name startup-entry -Action @{ name = 'MicrosoftEdgeAutoLaunch_*'; enabled = $false } | Should -BeTrue
        Mock -ModuleName OSSetup Get-OSSetupStartupEntry { [pscustomobject]@{ Name = 'BraveSoftware Update'; Enabled = $false; ApprovedKey = 'x' } }
        Invoke-TestProviderTest -Name startup-entry -Action @{ name = 'BraveSoftware Update'; enabled = $false } | Should -BeTrue
    }

    It 'n''est pas conforme si une entrée est encore active' {
        Mock -ModuleName OSSetup Get-OSSetupStartupEntry {
            [pscustomobject]@{ Name = 'MicrosoftEdgeAutoLaunch_A'; Enabled = $false; ApprovedKey = 'x' }
            [pscustomobject]@{ Name = 'MicrosoftEdgeAutoLaunch_B'; Enabled = $true; ApprovedKey = 'x' }
        }
        Invoke-TestProviderTest -Name startup-entry -Action @{ name = 'MicrosoftEdgeAutoLaunch_*'; enabled = $false } | Should -BeFalse
    }
}

Describe 'Get-OSSetupStartupEntry' {
    BeforeAll {
        function New-FakeKey([hashtable]$Values) {
            $key = [pscustomobject]@{ Values = $Values }
            $key | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { [string[]]$this.Values.Keys }
            # La virgule garde le tableau d'octets intact, comme la méthode .NET réelle.
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($Name, $Default) , $this.Values[$Name] }
            $key
        }
    }

    It 'lit l''état « désactivé » d''une valeur binaire (premier octet impair)' {
        $run = New-FakeKey @{ 'BraveSoftware Update' = 'brave.exe'; 'OneDrive' = 'onedrive.exe'; 'Autre' = 'x.exe' }
        $approved = New-FakeKey @{ 'BraveSoftware Update' = [byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8); 'OneDrive' = [byte[]](2, 0, 0, 0) }
        Mock -ModuleName OSSetup Test-Path { $true }
        Mock -ModuleName OSSetup Get-Item { $run } -ParameterFilter { $Path -like '*\CurrentVersion\Run' }
        Mock -ModuleName OSSetup Get-Item { $approved } -ParameterFilter { $Path -like '*StartupApproved\Run' }
        $entries = @(InModuleScope OSSetup { Get-OSSetupStartupEntry -Name '*' -Scope user })
        ($entries | Where-Object Name -eq 'BraveSoftware Update').Enabled | Should -BeFalse
        ($entries | Where-Object Name -eq 'OneDrive').Enabled | Should -BeTrue
        ($entries | Where-Object Name -eq 'Autre').Enabled | Should -BeTrue
    }
}

Describe 'Provider windows-update' {
    It 'est conforme quand Windows Update ne propose plus de pilote' {
        Mock -ModuleName OSSetup Find-OSSetupWindowsUpdate {}
        Invoke-TestProviderTest -Name windows-update -Action @{ category = 'drivers' } | Should -BeTrue
        Mock -ModuleName OSSetup Find-OSSetupWindowsUpdate { [pscustomobject]@{ Title = 'Intel - Display - 31.0.101.4502' } }
        Invoke-TestProviderTest -Name windows-update -Action @{ category = 'drivers' } | Should -BeFalse
    }
}

Describe 'Get-OSSetupDeviceProblem' {
    It 'liste les périphériques en erreur avec un libellé lisible' -Skip:(-not $IsWindows) {
        Mock -ModuleName OSSetup Get-CimInstance {
            [pscustomobject]@{ Name = 'Contrôleur Ethernet'; DeviceID = 'PCI\1'; ConfigManagerErrorCode = 28 }
            [pscustomobject]@{ Name = $null; DeviceID = 'USB\2'; ConfigManagerErrorCode = 99 }
        }
        $problems = @(InModuleScope OSSetup { Get-OSSetupDeviceProblem })
        $problems[0].Problem | Should -Be 'aucun pilote installé'
        $problems[1].Name | Should -Be 'USB\2'
        $problems[1].Problem | Should -Be 'erreur (code 99)'
    }
}

Describe 'Test-OSSetupWingetInstalled' {
    It 'reconnaît un paquet que winget list --id ne trouve pas mais que winget export rattache' {
        Mock -ModuleName OSSetup winget { $global:LASTEXITCODE = -1978335212 }
        Mock -ModuleName OSSetup Get-OSSetupWingetExportId { @('Microsoft.PowerShell') }
        InModuleScope OSSetup { Test-OSSetupWingetInstalled -Id 'Microsoft.PowerShell' } | Should -BeTrue
        InModuleScope OSSetup { Test-OSSetupWingetInstalled -Id 'Microsoft.VisualStudioCode' } | Should -BeFalse
    }

    It 'ne lit pas l''export quand winget list --id trouve le paquet' {
        Mock -ModuleName OSSetup winget { $global:LASTEXITCODE = 0 }
        Mock -ModuleName OSSetup Get-OSSetupWingetExportId { @() }
        InModuleScope OSSetup { Test-OSSetupWingetInstalled -Id 'Git.Git' } | Should -BeTrue
        Should -Invoke -ModuleName OSSetup Get-OSSetupWingetExportId -Times 0
    }
}
