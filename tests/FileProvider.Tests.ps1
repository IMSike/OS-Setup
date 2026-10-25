BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\src\OSSetup\OSSetup.psd1') -Force
}

Describe 'Provider file' {
    BeforeEach {
        $dotfiles = Join-Path -Path $TestDrive -ChildPath 'dotfiles'
        $target = Join-Path -Path $TestDrive -ChildPath 'home\app\config.txt'
        New-Item -Path $dotfiles -ItemType Directory -Force | Out-Null
        Remove-Item -Path (Join-Path -Path $TestDrive -ChildPath 'home') -Recurse -Force -ErrorAction SilentlyContinue
        # Source avec BOM : il doit être conservé après expansion.
        [System.IO.File]::WriteAllText((Join-Path -Path $dotfiles -ChildPath 'config.txt'), "root={{Root}}`n", [System.Text.UTF8Encoding]::new($true))

        $context = @{
            DotfilesRoot = $dotfiles
            BackupRoot   = Join-Path -Path $TestDrive -ChildPath 'backups'
            Variables    = @{ Root = 'D:\Dev' }
        }
        $action = [ordered]@{ provider = 'file'; source = 'config.txt'; target = $target; mode = 'template' }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'file' }
    }

    It 'signale un fichier absent comme non conforme' {
        & $provider.Test $action $context | Should -BeFalse
    }

    It 'déploie le gabarit expansé en conservant le BOM' {
        & $provider.Invoke $action $context
        $bytes = [System.IO.File]::ReadAllBytes($target)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        Get-Content -Path $target -Raw | Should -Be "root=D:\Dev`n"
        & $provider.Test $action $context | Should -BeTrue
    }

    It 'sauvegarde un fichier existant avant de le remplacer' {
        New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $target -Value 'ancien' -NoNewline
        & $provider.Invoke $action $context
        $backups = @(Get-ChildItem -Path $context.BackupRoot -Recurse -File)
        $backups.Count | Should -Be 1
        Get-Content -Path $backups[0].FullName -Raw | Should -Be 'ancien'
    }
}

Describe 'Provider file : fusion JSON (merge-json)' {
    BeforeEach {
        $dotfiles = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        New-Item -Path $dotfiles -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path -Path $dotfiles -ChildPath 'prefs.json') -Value '{ "distribution": { "do_not_create_desktop_shortcut": true }, "list": [1, 2] }'
        $target = Join-Path -Path $dotfiles -ChildPath 'app\initial_preferences'
        $context = @{ DotfilesRoot = $dotfiles; BackupRoot = Join-Path -Path $dotfiles -ChildPath 'backups'; Variables = @{} }
        $action = [ordered]@{ provider = 'file'; source = 'prefs.json'; target = $target; mode = 'merge-json' }
        $provider = InModuleScope OSSetup { Get-OSSetupProvider -Name 'file' }
    }

    It 'conserve les clés de la machine et ajoute celles du dépôt' {
        New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $target -Value '{ "homepage": "x", "distribution": { "import_bookmarks": false, "do_not_create_desktop_shortcut": false } }'
        & $provider.Test $action $context | Should -BeFalse
        & $provider.Invoke $action $context
        $json = Get-Content -Path $target -Raw | ConvertFrom-Json -AsHashtable
        $json['homepage'] | Should -Be 'x'
        $json['distribution']['import_bookmarks'] | Should -BeFalse
        $json['distribution']['do_not_create_desktop_shortcut'] | Should -BeTrue
        $json['list'] | Should -Be @(1, 2)
        @(Get-ChildItem -Path $context.BackupRoot -Recurse -File).Count | Should -Be 1
    }

    It 'est conforme quand les clés gérées ont leur valeur, quelle que soit la mise en forme' {
        New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
        Set-Content -Path $target -Value '{"other":1,"list":[1,2],"distribution":{"do_not_create_desktop_shortcut":true,"x":0}}'
        & $provider.Test $action $context | Should -BeTrue
    }

    It 'crée le fichier s''il n''existe pas' {
        & $provider.Invoke $action $context
        & $provider.Test $action $context | Should -BeTrue
    }
}
