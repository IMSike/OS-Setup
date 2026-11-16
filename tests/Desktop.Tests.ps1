BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force

    function New-DesktopContext {
        param([string[]]$ItemIds)
        $items = [ordered]@{
            'pin-a'   = [ordered]@{ id = 'pin-a'; taskbarPin = [ordered]@{ link = '{{StartMenu}}\App A.lnk' } }
            'pin-b'   = [ordered]@{ id = 'pin-b'; taskbarPin = [ordered]@{ link = '{{StartMenu}}\B & co.lnk' } }
            'pin-uwa' = [ordered]@{ id = 'pin-uwa'; taskbarPin = [ordered]@{ appId = 'Vendor.App_abc!App'; name = 'App du Store' } }
            'no-tile' = [ordered]@{ id = 'no-tile'; startLayout = 'empty' }
            'other'   = [ordered]@{ id = 'other'; actions = @() }
        }
        @{
            Data      = [pscustomobject]@{ Items = $items }
            ItemIds   = $ItemIds
            Variables = [ordered]@{ StartMenu = 'C:\Start' }
        }
    }
}

Describe 'Disposition de la barre des tâches et du menu Démarrer' {
    It 'agrège les épingles des éléments retenus, dans leur ordre, et la disposition du menu Démarrer' {
        $layout = Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'other', 'pin-b', 'no-tile', 'pin-a')
        $layout.Pins.Name | Should -Be @('B & co', 'App A')
        $layout.Pins[1].Link | Should -Be 'C:\Start\App A.lnk'
        $layout.EmptyStart | Should -BeTrue
    }

    It 'génère un fichier qui remplace la barre des tâches et vide le menu Démarrer' {
        $xml = ConvertTo-OSSetupLayoutXml -Layout (Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'pin-b', 'no-tile'))
        $doc = [xml]$xml
        $doc.LayoutModificationTemplate.CustomTaskbarLayoutCollection.PinListPlacement | Should -Be 'Replace'
        $xml | Should -Match 'DesktopApplicationLinkPath="C:\\Start\\B &amp; co\.lnk"'
        $xml | Should -Match 'DefaultLayoutOverride'
    }

    It 'épingle une application du Store par son identifiant' {
        $layout = Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'pin-a', 'pin-uwa')
        $layout.Pins.Name | Should -Be @('App A', 'App du Store')
        $xml = ConvertTo-OSSetupLayoutXml -Layout $layout
        $xml | Should -Match '<taskbar:UWA AppUserModelID="Vendor\.App_abc!App" />'
        ([xml]$xml).LayoutModificationTemplate.CustomTaskbarLayoutCollection.TaskbarLayout.TaskbarPinList.ChildNodes.Count | Should -Be 2
    }

    It 'ne touche pas à une partie qui n''est pas demandée' {
        $xml = ConvertTo-OSSetupLayoutXml -Layout (Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'pin-a'))
        $xml | Should -Not -Match 'DefaultLayoutOverride'
        $xml = ConvertTo-OSSetupLayoutXml -Layout (Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'no-tile'))
        $xml | Should -Not -Match 'CustomTaskbarLayoutCollection'
    }

    It 'est conforme sans rien à appliquer, ou quand la même disposition a déjà été appliquée' {
        InModuleScope OSSetup -Parameters @{ Context = (New-DesktopContext -ItemIds 'other') } {
            param($Context)
            & (Get-OSSetupProvider -Name 'desktop-layout').Test @{ provider = 'desktop-layout' } $Context | Should -BeTrue
        }
        $context = New-DesktopContext -ItemIds 'pin-a'
        $hash = Get-OSSetupLayoutHash -Xml (ConvertTo-OSSetupLayoutXml -Layout (Get-OSSetupDesktopLayout -Context $context))
        Mock -ModuleName OSSetup Get-OSSetupDesktopLayoutMarker -MockWith ([scriptblock]::Create("'$hash'"))
        InModuleScope OSSetup -Parameters @{ Context = $context } {
            param($Context)
            & (Get-OSSetupProvider -Name 'desktop-layout').Test @{ provider = 'desktop-layout' } $Context | Should -BeTrue
        }
        Mock -ModuleName OSSetup Get-OSSetupDesktopLayoutMarker { 'ancienne' }
        InModuleScope OSSetup -Parameters @{ Context = $context } {
            param($Context)
            & (Get-OSSetupProvider -Name 'desktop-layout').Test @{ provider = 'desktop-layout' } $Context | Should -BeFalse
        }
    }
}

Describe 'Set-OSSetupDesktopLayout' {
    BeforeEach {
        # Toutes les écritures (fichier, registre) sont simulées, sans filtre : rien n'atteint le système.
        Mock -ModuleName OSSetup New-Item {}
        Mock -ModuleName OSSetup Set-Content {}
        Mock -ModuleName OSSetup Test-Path { $true }
        Mock -ModuleName OSSetup Set-ItemProperty {}
        Mock -ModuleName OSSetup Remove-ItemProperty {}
        Mock -ModuleName OSSetup Remove-Item {}
        Mock -ModuleName OSSetup Restart-OSSetupExplorer {}
        Mock -ModuleName OSSetup Get-OSSetupTaskbarPinName {}
        $layout = Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'pin-a', 'pin-uwa')
    }

    AfterEach {
        Remove-Variable -Name OSSetupTestRestartCount -Scope Global -ErrorAction SilentlyContinue
    }

    It 'n''attend que les épingles de raccourcis, puis enregistre l''empreinte et retire la stratégie' {
        Mock -ModuleName OSSetup Wait-OSSetupTaskbarPin {}
        Set-OSSetupDesktopLayout -Layout $layout -Confirm:$false
        Should -Invoke -ModuleName OSSetup Wait-OSSetupTaskbarPin -Times 1 -Exactly -ParameterFilter { ($Name -join '|') -eq 'App A' }
        Should -Invoke -ModuleName OSSetup Set-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'DesktopLayout' }
        Should -Invoke -ModuleName OSSetup Remove-ItemProperty -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Remove-Item -Times 1 -Exactly
    }

    It 'n''attend rien quand seules des applications du Store sont épinglées' {
        Mock -ModuleName OSSetup Wait-OSSetupTaskbarPin {}
        Set-OSSetupDesktopLayout -Layout (Get-OSSetupDesktopLayout -Context (New-DesktopContext -ItemIds 'pin-uwa')) -Confirm:$false
        Should -Invoke -ModuleName OSSetup Wait-OSSetupTaskbarPin -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Set-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'DesktopLayout' }
    }

    It 'n''attend pas les épingles déjà présentes avant la pose de la stratégie' {
        # Leur raccourci existait déjà : il serait trouvé tout de suite, avant que l'Explorateur relise la disposition.
        Mock -ModuleName OSSetup Get-OSSetupTaskbarPinName { 'App A' }
        Mock -ModuleName OSSetup Wait-OSSetupTaskbarPin {}
        Set-OSSetupDesktopLayout -Layout $layout -Confirm:$false
        Should -Invoke -ModuleName OSSetup Wait-OSSetupTaskbarPin -Times 0 -Exactly
        Should -Invoke -ModuleName OSSetup Get-OSSetupTaskbarPinName -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Set-ItemProperty -Times 1 -Exactly -ParameterFilter { $Name -eq 'DesktopLayout' }
    }

    It 'échoue sans enregistrer l''empreinte quand une épingle n''est pas apparue, et retire la stratégie' {
        Mock -ModuleName OSSetup Wait-OSSetupTaskbarPin { 'App A' }
        { Set-OSSetupDesktopLayout -Layout $layout -Confirm:$false } | Should -Throw '*App A*'
        Should -Invoke -ModuleName OSSetup Set-ItemProperty -Times 0 -Exactly -ParameterFilter { $Name -eq 'DesktopLayout' }
        Should -Invoke -ModuleName OSSetup Remove-ItemProperty -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Remove-Item -Times 1 -Exactly
    }

    It 'retire la stratégie et le fichier même si le second redémarrage de l''Explorateur échoue' {
        Mock -ModuleName OSSetup Wait-OSSetupTaskbarPin {}
        $global:OSSetupTestRestartCount = 0
        Mock -ModuleName OSSetup Restart-OSSetupExplorer {
            $global:OSSetupTestRestartCount++
            if ($global:OSSetupTestRestartCount -eq 2) { throw 'Explorateur bloqué' }
        }
        { Set-OSSetupDesktopLayout -Layout $layout -Confirm:$false } | Should -Throw '*Explorateur bloqué*'
        Should -Invoke -ModuleName OSSetup Remove-ItemProperty -Times 1 -Exactly -ParameterFilter { 'StartLayoutFile' -in $Name -and 'LockedStartLayout' -in $Name }
        Should -Invoke -ModuleName OSSetup Remove-Item -Times 1 -Exactly
        Should -Invoke -ModuleName OSSetup Set-ItemProperty -Times 0 -Exactly -ParameterFilter { $Name -eq 'DesktopLayout' }
    }
}

Describe 'Wait-OSSetupTaskbarPin' {
    It 'retourne les épingles toujours absentes au bout du délai' {
        Mock -ModuleName OSSetup Get-OSSetupTaskbarPinName { 'App A' }
        Mock -ModuleName OSSetup Start-Sleep {}
        Wait-OSSetupTaskbarPin -Name 'App A', 'Brave' -TimeoutSeconds 0 | Should -Be 'Brave'
    }

    It 'ne retourne rien quand toutes les épingles sont là' {
        Mock -ModuleName OSSetup Get-OSSetupTaskbarPinName { 'Brave'; 'App A' }
        Wait-OSSetupTaskbarPin -Name 'App A', 'Brave' -TimeoutSeconds 0 | Should -BeNullOrEmpty
    }
}

Describe 'Get-OSSetupSessionExplorer' {
    It 'ne retient que l''Explorateur de la session courante' {
        $session = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
        Mock -ModuleName OSSetup Get-Process -ParameterFilter { $Name -eq 'explorer' } -MockWith ([scriptblock]::Create(@"
[pscustomobject]@{ Id = 1; SessionId = $session }
[pscustomobject]@{ Id = 2; SessionId = $($session + 1) }
"@))
        @(Get-OSSetupSessionExplorer).Id | Should -Be @(1)
    }
}

Describe 'Start-OSSetupUnelevatedExplorer' {
    It 'lance explorer.exe et schtasks.exe depuis les dossiers du système, pas depuis %WINDIR%' {
        # New-ScheduledTaskAction et New-ScheduledTaskPrincipal ne créent que des objets en mémoire.
        Mock -ModuleName OSSetup Register-ScheduledTask {}
        Mock -ModuleName OSSetup Unregister-ScheduledTask {}
        Mock -ModuleName OSSetup Start-Sleep {}
        Mock -ModuleName OSSetup Invoke-OSSetupNativeCommand {}
        $saved = $env:WINDIR
        try {
            $env:WINDIR = Join-Path -Path $TestDrive -ChildPath 'faux'
            Start-OSSetupUnelevatedExplorer -Confirm:$false
        }
        finally {
            $env:WINDIR = $saved
        }
        $explorer = Join-Path -Path (Split-Path -Path ([Environment]::SystemDirectory) -Parent) -ChildPath 'explorer.exe'
        Should -Invoke -ModuleName OSSetup Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $Action[0].Execute -eq $explorer }
        $schtasks = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'schtasks.exe'
        Should -Invoke -ModuleName OSSetup Invoke-OSSetupNativeCommand -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq $schtasks -and ($ArgumentList -join ' ') -eq '/run /tn OS-Setup - Explorateur'
        }
        Should -Invoke -ModuleName OSSetup Unregister-ScheduledTask -Times 1 -Exactly
    }
}

Describe 'Provider shortcut' {
    It 'teste la présence ou l''absence du raccourci' {
        $path = Join-Path -Path $TestDrive -ChildPath 'App.lnk'
        InModuleScope OSSetup -Parameters @{ Path = $path } {
            param($Path)
            $provider = Get-OSSetupProvider -Name 'shortcut'
            & $provider.Test @{ path = $Path; present = $false } @{} | Should -BeTrue
            # Source absente (logiciel pas encore installé) : seule la présence compte.
            $from = Join-Path -Path (Split-Path -Path $Path -Parent) -ChildPath 'absent.lnk'
            & $provider.Test @{ path = $Path; from = $from } @{} | Should -BeFalse
            Set-Content -Path $Path -Value 'x'
            & $provider.Test @{ path = $Path; present = $false } @{} | Should -BeFalse
            & $provider.Test @{ path = $Path; from = $from } @{} | Should -BeTrue
        }
    }

    It 'copie un raccourci existant' {
        $source = Join-Path -Path $TestDrive -ChildPath 'source.lnk'
        $target = Join-Path -Path $TestDrive -ChildPath 'Bureau\App.lnk'
        Set-Content -Path $source -Value 'lnk'
        InModuleScope OSSetup -Parameters @{ Source = $source; Target = $target } {
            param($Source, $Target)
            & (Get-OSSetupProvider -Name 'shortcut').Invoke @{ path = $Target; from = $Source } @{}
        }
        Get-Content -Path $target | Should -Be 'lnk'
    }
}

Describe 'Get-OSSetupPlan : unlessSelected' {
    It 'ignore une action quand l''élément indiqué est retenu' {
        $data = [pscustomobject]@{
            Items = @{
                app = [ordered]@{ id = 'app'; name = 'App'; actions = @(
                        [ordered]@{ provider = 'shortcut'; path = 'C:\Nope\App.lnk'; present = $false; unlessSelected = 'desktop-app' }
                    )
                }
            }
        }
        $context = @{ Variables = [ordered]@{}; ItemIds = @('app', 'desktop-app') }
        @(Get-OSSetupPlan -Data $data -ItemId 'app' -Context $context).Count | Should -Be 0
        $context.ItemIds = @('app')
        @(Get-OSSetupPlan -Data $data -ItemId 'app' -Context $context).Count | Should -Be 1
    }
}

Describe 'Get-OSSetupPlan : contexte de plan' {
    AfterEach {
        Remove-Variable -Name OSSetupTestPlanning -Scope Global -ErrorAction SilentlyContinue
    }

    It 'signale le plan aux tests de présence (Planning), puis le retire du contexte' {
        $data = [pscustomobject]@{
            Items = @{
                app = [ordered]@{ id = 'app'; name = 'App'; actions = @([ordered]@{ provider = 'shortcut'; path = 'C:\Nope\App.lnk'; present = $false }) }
            }
        }
        $global:OSSetupTestPlanning = $null
        Mock -ModuleName OSSetup Get-OSSetupProvider {
            # Interface des providers : Test reçoit l'action puis le contexte ; seul le contexte compte ici.
            @{ Describe = { 'test' }; Test = { $global:OSSetupTestPlanning = $args[1]['Planning']; $true } }
        }
        $context = @{ Variables = [ordered]@{} }
        @(Get-OSSetupPlan -Data $data -ItemId 'app' -Context $context)[0].Status | Should -Be 'ok'
        $global:OSSetupTestPlanning | Should -BeTrue
        $context.ContainsKey('Planning') | Should -BeFalse
    }
}
