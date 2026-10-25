function Get-OSSetupPlatform {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } else { 'unsupported' }
}

function Read-OSSetupJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )
    $json = Get-Content -Path $Path -Raw -Encoding utf8
    $schemaErrors = $null
    $valid = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    if (-not $valid) {
        # Test-Json ne fournit pas toujours de message (ex. échec d'un « oneOf ») : l'erreur doit être signalée quand même.
        $messages = @($schemaErrors | ForEach-Object { $_.Exception.Message } | Where-Object { $_ })
        if ($messages.Count -eq 0) {
            $messages = @("non conforme au schéma $(Split-Path -Path $SchemaPath -Leaf) (vérifier notamment les actions et leur provider)")
        }
        foreach ($message in $messages) {
            $Errors.Add("${Path} : $message")
        }
        return $null
    }
    $json | ConvertFrom-Json -AsHashtable
}

function Import-OSSetupData {
    <#
    .SYNOPSIS
        Charge et valide le catalogue et les profils. Lève une erreur listant tous les problèmes trouvés.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $schemaRoot = Join-Path -Path $Root -ChildPath 'schemas'
    $items = [ordered]@{}
    $profiles = [ordered]@{}

    $catalogRoot = Join-Path -Path $Root -ChildPath 'catalog'
    foreach ($file in Get-ChildItem -Path $catalogRoot -Filter '*.json' -Recurse | Sort-Object -Property FullName) {
        $item = Read-OSSetupJsonFile -Path $file.FullName -SchemaPath (Join-Path -Path $schemaRoot -ChildPath 'item.schema.json') -Errors $errors
        if ($null -eq $item) { continue }
        if ($item['id'] -ne $file.BaseName) {
            $errors.Add("$($file.FullName) : l'id '$($item['id'])' doit correspondre au nom du fichier.")
        }
        if ($item['category'] -ne $file.Directory.Name) {
            $errors.Add("$($file.FullName) : la catégorie '$($item['category'])' doit correspondre au dossier '$($file.Directory.Name)'.")
        }
        if ($items.Contains($item['id'])) {
            $errors.Add("$($file.FullName) : id '$($item['id'])' en double dans le catalogue.")
            continue
        }
        if (-not $item['actions'] -and -not $item['taskbarPin'] -and -not $item['startLayout']) {
            $errors.Add("$($file.FullName) : l'élément ne fait rien (ni action, ni épingle, ni disposition du menu Démarrer).")
        }
        $pin = $item['taskbarPin']
        if ($pin -and -not (($pin['link'] -and -not $pin['appId']) -or ($pin['appId'] -and $pin['name'] -and -not $pin['link']))) {
            $errors.Add("$($file.FullName) : taskbarPin doit indiquer soit link, soit appId avec name.")
        }
        $items[$item['id']] = $item
    }

    $profileRoot = Join-Path -Path $Root -ChildPath 'profiles'
    foreach ($file in Get-ChildItem -Path $profileRoot -Filter '*.json' | Sort-Object -Property Name) {
        $setupProfile = Read-OSSetupJsonFile -Path $file.FullName -SchemaPath (Join-Path -Path $schemaRoot -ChildPath 'profile.schema.json') -Errors $errors
        if ($null -eq $setupProfile) { continue }
        if ($setupProfile['id'] -ne $file.BaseName) {
            $errors.Add("$($file.FullName) : l'id '$($setupProfile['id'])' doit correspondre au nom du fichier.")
        }
        $profiles[$setupProfile['id']] = $setupProfile
    }

    $data = [pscustomobject]@{
        Root     = $Root
        Items    = $items
        Profiles = $profiles
    }
    foreach ($problem in Test-OSSetupDataReference -Data $data) {
        $errors.Add($problem)
    }
    if ($errors.Count -gt 0) {
        throw "Données invalides :`n - " + ($errors -join "`n - ")
    }
    $data
}

function Test-OSSetupItemInstall {
    <#
    .SYNOPSIS
        Vrai si l'élément installe ou supprime quelque chose (paquet, application, composant ou fonctionnalité de Windows)
        plutôt que de régler ou configurer.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $Item
    )
    [bool]($Item['actions'] | Where-Object { $_['provider'] -in 'winget', 'windows-feature', 'appx', 'windows-capability', 'win32-uninstall', 'windows-update',
        'vscode-extension', 'install-script', 'fnm-node', 'npm-global', 'gh-extension', 'herdr-plugin', 'claude-plugin' })
}

function Test-OSSetupDataReference {
    <#
    .SYNOPSIS
        Vérifie les références croisées (éléments, profils, choix) et retourne la liste des problèmes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Data
    )
    $choiceOwners = @{}
    foreach ($setupProfile in $Data.Profiles.Values) {
        $where = "profil '$($setupProfile['id'])'"
        foreach ($parent in $setupProfile['extends']) {
            if (-not $Data.Profiles.Contains($parent)) { "${where} : profil étendu inconnu '$parent'." }
        }
        foreach ($itemId in $setupProfile['items']) {
            if (-not $Data.Items.Contains($itemId)) { "${where} : élément inconnu '$itemId'." }
            elseif (Test-OSSetupItemInstall -Item $Data.Items[$itemId]) {
                # Règle : tout ce qui s'installe ou se supprime est choisi explicitement dans un menu.
                "${where} : l'élément '$itemId' installe ou supprime un logiciel ou une fonctionnalité : il doit être proposé dans un groupe de choix, pas dans 'items'."
            }
        }
        foreach ($choice in $setupProfile['choices']) {
            if ($choiceOwners.ContainsKey($choice['id'])) {
                "${where} : groupe de choix '$($choice['id'])' déjà défini par le profil '$($choiceOwners[$choice['id']])'."
            }
            $choiceOwners[$choice['id']] = $setupProfile['id']
            foreach ($option in $choice['options']) {
                if (-not $Data.Items.Contains($option)) { "${where} : choix '$($choice['id'])', élément inconnu '$option'." }
            }
            foreach ($default in $choice['default']) {
                if ($default -notin $choice['options']) { "${where} : choix '$($choice['id'])', défaut '$default' absent des options." }
            }
        }
    }
    foreach ($item in $Data.Items.Values) {
        foreach ($dependency in $item['dependsOn']) {
            if (-not $Data.Items.Contains($dependency)) { "élément '$($item['id'])' : dépendance inconnue '$dependency'." }
        }
    }
}
