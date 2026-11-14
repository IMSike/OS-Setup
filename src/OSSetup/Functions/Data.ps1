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
    # Fichier vide : Test-Json refuserait la chaîne vide par une erreur de liaison, sans nom de fichier.
    if ([string]::IsNullOrWhiteSpace($json)) {
        $Errors.Add("${Path} : fichier vide.")
        return $null
    }
    $schemaErrors = $null
    $valid = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    if (-not $valid) {
        $Errors.Add((Format-OSSetupSchemaError -Path $Path -SchemaPath $SchemaPath -SchemaError $schemaErrors))
        return $null
    }
    $json | ConvertFrom-Json -AsHashtable
}

function Format-OSSetupSchemaError {
    <#
    .SYNOPSIS
        Message d'un fichier non conforme à son schéma : une ligne du moteur, puis les détails de Test-Json.
    .DESCRIPTION
        Les détails de Test-Json varient selon la version de PowerShell et sa langue : aucun pour l'échec d'un
        « oneOf » en 7.4, une ligne par branche essayée en 7.6.10 (plus de 70 pour un provider inconnu). La ligne
        du moteur est donc toujours présente ; les détails sont dédoublonnés et plafonnés.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$SchemaError,

        [int]$MaxDetail = 5
    )
    $message = "${Path} : non conforme au schéma $(Split-Path -Path $SchemaPath -Leaf)"
    $details = @($SchemaError | ForEach-Object { $_.Exception.Message } | Where-Object { $_ } | Select-Object -Unique)
    if ($details.Count -eq 0) {
        return "$message (vérifier notamment les actions et leur provider)."
    }
    $lines = @($details | Select-Object -First $MaxDetail)
    if ($details.Count -gt $MaxDetail) {
        $lines += "… $($details.Count - $MaxDetail) autre(s) détail(s)"
    }
    "${message} :" + (@($lines | ForEach-Object { "`n     $_" }) -join '')
}

function Read-OSSetupJsonFileSet {
    <#
    .SYNOPSIS
        Lit et valide plusieurs fichiers JSON contre le même schéma. Retourne { File; Data } pour chaque fichier
        valide, dans l'ordre donné ; les problèmes sont ajoutés à Errors, fichier par fichier.
    .DESCRIPTION
        Test-Json recompile le schéma à chaque appel : valider le catalogue fichier par fichier prenait plus d'une
        seconde de plus. Les fichiers sont donc validés ensemble, comme les éléments d'un tableau, en un seul appel ;
        en cas d'échec, chacun est revalidé seul pour que le message nomme le fichier fautif.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$File,

        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )
    # Un texte par fichier, à la même position (un fichier vide donne $null).
    $texts = [string[]]::new($File.Count)
    for ($i = 0; $i -lt $File.Count; $i++) {
        $texts[$i] = Get-Content -LiteralPath $File[$i].FullName -Raw -Encoding utf8
    }
    $valid = $false
    if ($File.Count -gt 0 -and -not @($texts | Where-Object { [string]::IsNullOrWhiteSpace($_) })) {
        # Schéma d'un fichier appliqué à chaque élément du tableau ; ses définitions restent à la racine, où les
        # références « #/definitions/… » les cherchent.
        $schema = Get-Content -LiteralPath $SchemaPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        $definitions = $schema['definitions']
        foreach ($key in '$schema', '$id', 'definitions') { $schema.Remove($key) }
        $arraySchema = [ordered]@{ '$schema' = 'http://json-schema.org/draft-07/schema#'; type = 'array'; items = $schema }
        if ($null -ne $definitions) { $arraySchema['definitions'] = $definitions }
        $json = '[' + ($texts -join ",`n") + ']'
        $valid = Test-Json -Json $json -Schema (ConvertTo-Json -InputObject $arraySchema -Depth 64) -ErrorAction SilentlyContinue
    }
    for ($i = 0; $i -lt $File.Count; $i++) {
        $data = $null
        if ($valid) {
            # Un fichier qui ne serait valide qu'au sein du tableau (ex. deux objets séparés par une virgule) échoue ici.
            $data = try { $texts[$i] | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { $null }
        }
        if ($null -eq $data) {
            $data = Read-OSSetupJsonFile -Path $File[$i].FullName -SchemaPath $SchemaPath -Errors $Errors
        }
        if ($null -ne $data) {
            [pscustomobject]@{ File = $File[$i]; Data = $data }
        }
    }
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
    $catalogFiles = @(Get-ChildItem -Path $catalogRoot -Filter '*.json' -Recurse | Sort-Object -Property FullName)
    foreach ($entry in Read-OSSetupJsonFileSet -File $catalogFiles -SchemaPath (Join-Path -Path $schemaRoot -ChildPath 'item.schema.json') -Errors $errors) {
        $file = $entry.File
        $item = $entry.Data
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
    $profileFiles = @(Get-ChildItem -Path $profileRoot -Filter '*.json' | Sort-Object -Property Name)
    foreach ($entry in Read-OSSetupJsonFileSet -File $profileFiles -SchemaPath (Join-Path -Path $schemaRoot -ChildPath 'profile.schema.json') -Errors $errors) {
        $file = $entry.File
        $setupProfile = $entry.Data
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
    # Élément sans action (épingle ou disposition seule) : $null traverse le pipeline, d'où le test de $_.
    [bool]($Item['actions'] | Where-Object { $_ -and $_['provider'] -in 'winget', 'windows-feature', 'appx', 'windows-capability', 'win32-uninstall', 'windows-update',
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
    $builtinNames = @((Get-OSSetupBuiltinVariable).Keys)
    foreach ($setupProfile in $Data.Profiles.Values) {
        $where = "profil '$($setupProfile['id'])'"
        foreach ($parent in $setupProfile['extends']) {
            if (-not $Data.Profiles.Contains($parent)) { "${where} : profil étendu inconnu '$parent'." }
        }
        if ($null -ne $setupProfile['variables']) {
            foreach ($name in $setupProfile['variables'].Keys) {
                # Insensible à la casse, comme la table des valeurs où la variable du profil remplacerait l'intégrée.
                if ($name -in $builtinNames) { "${where} : la variable '$name' porte le nom d'une variable intégrée." }
            }
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
            # Les valeurs par défaut s'appliquent telles quelles (-AcceptDefaults) : elles respectent les bornes du groupe.
            $bound = Get-OSSetupChoiceBound -Choice $choice
            $defaultCount = @($choice['default'] | Where-Object { $_ }).Count
            if ($defaultCount -lt $bound.Min -or $defaultCount -gt $bound.Max) {
                "${where} : choix '$($choice['id'])', $defaultCount valeur(s) par défaut, attendu entre $($bound.Min) et $($bound.Max)."
            }
        }
    }
    foreach ($item in $Data.Items.Values) {
        foreach ($dependency in $item['dependsOn']) {
            if (-not $Data.Items.Contains($dependency)) { "élément '$($item['id'])' : dépendance inconnue '$dependency'." }
            elseif ($Data.Items[$dependency]['runLast'] -and -not $item['runLast']) {
                # Les éléments « runLast » passent en fin de plan : l'élément serait traité avant sa dépendance.
                "élément '$($item['id'])' : la dépendance '$dependency' est traitée en dernier (runLast), après lui."
            }
        }
        foreach ($action in @($item['actions'] | Where-Object { $_ -and $_['unlessSelected'] })) {
            if (-not $Data.Items.Contains($action['unlessSelected'])) {
                "élément '$($item['id'])' : unlessSelected désigne un élément inconnu '$($action['unlessSelected'])'."
            }
        }
    }

    # Cycles de dépendances : détectés au chargement plutôt qu'au moment de la résolution des choix.
    $state = @{}
    $path = [System.Collections.Generic.List[string]]::new()
    $visit = {
        param([string]$Id)
        $state[$Id] = 'visiting'
        $path.Add($Id)
        foreach ($dependency in $Data.Items[$Id]['dependsOn']) {
            if (-not $Data.Items.Contains($dependency)) { continue }
            if ($state[$dependency] -eq 'visiting') {
                $cycle = @($path.GetRange($path.IndexOf($dependency), $path.Count - $path.IndexOf($dependency))) + $dependency
                "élément '$dependency' : cycle de dépendances ($($cycle -join ' → '))."
            }
            elseif (-not $state.ContainsKey($dependency)) {
                & $visit $dependency
            }
        }
        $path.RemoveAt($path.Count - 1)
        $state[$Id] = 'done'
    }
    foreach ($id in @($Data.Items.Keys)) {
        if (-not $state.ContainsKey($id)) { & $visit $id }
    }
}
