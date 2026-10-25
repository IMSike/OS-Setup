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

Describe 'Provider shortcut' {
    It 'teste la présence ou l''absence du raccourci' {
        $path = Join-Path -Path $TestDrive -ChildPath 'App.lnk'
        InModuleScope OSSetup -Parameters @{ Path = $path } {
            param($Path)
            $provider = Get-OSSetupProvider -Name 'shortcut'
            & $provider.Test @{ path = $Path; present = $false } @{} | Should -BeTrue
            & $provider.Test @{ path = $Path } @{} | Should -BeFalse
            Set-Content -Path $Path -Value 'x'
            & $provider.Test @{ path = $Path; present = $false } @{} | Should -BeFalse
            & $provider.Test @{ path = $Path } @{} | Should -BeTrue
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
