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
    $json = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    # Fichier vide : Test-Json refuserait la chaîne vide par une erreur de liaison, sans nom de fichier.
    if ([string]::IsNullOrWhiteSpace($json)) {
        $Errors.Add("${Path} : fichier vide.")
        return $null
    }
    $result = Invoke-OSSetupJsonValidation -Json $json -SchemaPath $SchemaPath
    if (-not $result.Valid) {
        $Errors.Add((Format-OSSetupSchemaError -Path $Path -SchemaPath $SchemaPath -SchemaError $result.Errors))
        return $null
    }
    $json | ConvertFrom-Json -AsHashtable
}

function Invoke-OSSetupJsonValidation {
    <#
    .SYNOPSIS
        Valide un texte JSON contre un schéma : retourne { Valid; Errors }, ou lève une erreur si le schéma est illisible.
    .DESCRIPTION
        Seul endroit qui appelle Test-Json. Un schéma illisible est un défaut du dépôt, pas des données : une erreur
        nommant le schéma est levée aussitôt, au lieu d'accuser chaque fichier. Test-Json le signale de plusieurs façons
        (TestJsonCommand.cs, PowerShell 7.6), toutes reconnues ici à leur identifiant, jamais à leur texte :
        - InvalidJsonSchema, non terminante : schéma qui n'est pas du JSON ou mal formé (« { "type": 5 } ») ; Test-Json
          rend alors vrai, ce qui accepterait n'importe quel fichier ;
        - InvalidJsonSchema, terminante : schéma que la bibliothèque ne peut compiler (motif « ( » invalide…) ;
        - JsonSchemaFileOpenFailure, terminante : fichier de schéma absent ou impossible à ouvrir (SchemaFile) ;
        - UnresolvedJsonSchemaRef, non terminante (7.6.10) : référence « $ref » introuvable ; Test-Json rend faux.
          En 7.6.0, la même erreur sort en InvalidJson, l'identifiant d'un JSON de données invalide : elle n'en
          est distinguée que par sa cause, une exception de JsonSchema.Net (espace de noms Json.Schema).
        Toute autre erreur terminante est relancée telle quelle ; les autres erreurs non terminantes (InvalidJson,
        InvalidJsonAgainstSchemaDetailed) sont celles du fichier validé. Le texte est validé contre le fichier
        SchemaPath, ou contre Schema (schéma composé à partir de SchemaPath) s'il est donné.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Json,

        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [string]$Schema
    )
    # Erreur due au schéma et non au fichier validé (voir la description).
    $isSchemaError = {
        param([System.Management.Automation.ErrorRecord]$Record)
        $id = ($Record.FullyQualifiedErrorId -split ',')[0]
        $cause = $Record.Exception.InnerException ?? $Record.Exception
        $id -in 'InvalidJsonSchema', 'JsonSchemaFileOpenFailure', 'UnresolvedJsonSchemaRef' -or
            ($id -eq 'InvalidJson' -and $cause.GetType().Namespace -eq 'Json.Schema')
    }
    $result = $false
    $schemaErrors = $null
    $schemaSource = if ($Schema) { @{ Schema = $Schema } } else { @{ SchemaFile = $SchemaPath } }
    try {
        $result = Test-Json -Json $Json @schemaSource -ErrorVariable schemaErrors -ErrorAction SilentlyContinue
    }
    catch {
        # Une erreur terminante échappe à -ErrorAction et à -ErrorVariable.
        if (-not (& $isSchemaError $_)) { throw }
        $schemaErrors = @($_)
    }
    $unreadable = @($schemaErrors | Where-Object { $null -ne $_ -and (& $isSchemaError $_) })
    if ($unreadable.Count -gt 0) {
        $exception = $unreadable[0].Exception
        throw (Format-OSSetupUnreadableSchema -SchemaPath $SchemaPath -Detail ($exception.InnerException ?? $exception).Message)
    }
    [pscustomobject]@{
        # Valide seulement sans aucune erreur, quoi que rende Test-Json.
        Valid  = ($result -eq $true) -and @($schemaErrors).Count -eq 0
        Errors = @($schemaErrors)
    }
}

function Format-OSSetupUnreadableSchema {
    <#
    .SYNOPSIS
        Message d'un schéma illisible : il nomme le schéma, défaut du dépôt, et aucun fichier de données.
    .DESCRIPTION
        Un schéma absent est dit introuvable, sans détail : Test-Json (fichier seul) et la lecture du schéma composé
        (chemin groupé) l'expriment chacun à sa façon, le message reste le même.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SchemaPath,

        [string]$Detail
    )
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        return "${SchemaPath} : schéma introuvable, à corriger dans le dépôt (aucun fichier n'a pu être validé)."
    }
    $message = "${SchemaPath} : schéma illisible, à corriger dans le dépôt (aucun fichier n'a pu être validé)"
    if ([string]::IsNullOrWhiteSpace($Detail)) { return "${message}." }
    "${message} :`n     $($Detail.Trim())"
}

function Format-OSSetupSchemaError {
    <#
    .SYNOPSIS
        Message d'un fichier non conforme à son schéma : une ligne du moteur, puis les détails de Test-Json.
    .DESCRIPTION
        Les détails de Test-Json varient selon la version de PowerShell et sa langue : aucun pour un fichier de
        réponses fautif en 7.6.9, une ligne par branche essayée d'un « oneOf » en 7.6.10 (plus de 70 pour un provider
        inconnu). La ligne du moteur est donc toujours présente ; les détails sont dédoublonnés et plafonnés. Sans
        détail, un élément du catalogue reçoit une piste (ses actions, où sont presque tous les écarts) ; les autres
        schémas n'en ont pas.
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
    $schemaName = Split-Path -Path $SchemaPath -Leaf
    $message = "${Path} : non conforme au schéma ${schemaName}"
    # $null traverse le pipeline une fois : filtré avant de lire Exception (introuvable sous Set-StrictMode).
    $details = @($SchemaError | Where-Object { $null -ne $_ } | ForEach-Object { $_.Exception.Message } | Where-Object { $_ } | Select-Object -Unique)
    if ($details.Count -eq 0) {
        if ($schemaName -eq 'item.schema.json') {
            return "$message (vérifier notamment les actions et leur provider)."
        }
        return "${message}."
    }
    $lines = @($details | Select-Object -First $MaxDetail)
    if ($details.Count -gt $MaxDetail) {
        $lines += "… $($details.Count - $MaxDetail) autre(s) détail(s)"
    }
    "${message} :" + (@($lines | ForEach-Object { "`n     $_" }) -join '')
}

function Get-OSSetupArraySchema {
    <#
    .SYNOPSIS
        Texte d'un schéma « tableau » dont chaque élément suit le schéma d'un fichier ; les définitions de celui-ci
        restent à la racine, où les références « #/definitions/… » les cherchent.
    .DESCRIPTION
        Composé avec System.Text.Json, sans passer par les types PowerShell : un nombre garde son texte d'origine.
        ConvertFrom-Json lirait la borne QWord (18446744073709551615) comme un BigInteger, que ConvertTo-Json n'écrit
        en nombre que depuis PowerShell 7.5. Un fichier de schéma absent, qui n'est pas du JSON, ou dont la racine
        n'est pas un objet, lève l'erreur d'un schéma introuvable ou illisible.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$SchemaPath
    )
    try {
        $schema = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $SchemaPath -Raw -Encoding utf8)).AsObject()
    }
    catch {
        # Exception de .NET enveloppée par PowerShell (« Exception lors de l'appel de "Parse" ») : le détail est dedans.
        $exception = $_.Exception
        throw (Format-OSSetupUnreadableSchema -SchemaPath $SchemaPath -Detail ($exception.InnerException ?? $exception).Message)
    }
    $definitions = $null
    [void]$schema.TryGetPropertyValue('definitions', [ref]$definitions)
    foreach ($key in '$schema', '$id', 'definitions') { [void]$schema.Remove($key) }
    $arraySchema = [System.Text.Json.Nodes.JsonObject]::new()
    $arraySchema.Add('$schema', [System.Text.Json.Nodes.JsonValue]::Create('http://json-schema.org/draft-07/schema#'))
    $arraySchema.Add('type', [System.Text.Json.Nodes.JsonValue]::Create('array'))
    $arraySchema.Add('items', $schema)
    if ($null -ne $definitions) { $arraySchema.Add('definitions', $definitions) }
    $arraySchema.ToJsonString()
}

function Read-OSSetupJsonFileSet {
    <#
    .SYNOPSIS
        Lit et valide plusieurs fichiers JSON contre le même schéma. Retourne { File; Data } pour chaque fichier
        valide, dans l'ordre donné ; les problèmes sont ajoutés à Errors, fichier par fichier.
    .DESCRIPTION
        Test-Json recompile le schéma à chaque appel : valider le catalogue fichier par fichier prenait plus d'une
        seconde de plus. Les fichiers sont donc validés ensemble, comme les éléments d'un tableau, en un seul appel ;
        en cas d'échec, chacun est revalidé seul pour que le message nomme le fichier fautif. Le schéma de ce tableau
        est composé par Get-OSSetupArraySchema. Un schéma illisible lève aussitôt une erreur qui le nomme
        (Invoke-OSSetupJsonValidation), sans revalidation fichier par fichier.
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
    # Compte, pas valeur de vérité : un seul fichier vide donnerait @('') ou @($null), évalué faux.
    if ($File.Count -gt 0 -and @($texts | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        $json = '[' + ($texts -join ",`n") + ']'
        # Lot non conforme : chaque fichier est revalidé seul plus bas, contre le fichier de schéma lui-même.
        $valid = (Invoke-OSSetupJsonValidation -Json $json -SchemaPath $SchemaPath -Schema (Get-OSSetupArraySchema -SchemaPath $SchemaPath)).Valid
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
    $catalogFiles = @(Get-ChildItem -LiteralPath $catalogRoot -Filter '*.json' -Recurse | Sort-Object -Property FullName)
    # Catalogue vide : jamais normal (dossier mal lu, copie incomplète), au lieu d'un plan vide sans explication.
    if ($catalogFiles.Count -eq 0) { $errors.Add("${catalogRoot} : aucun élément dans le catalogue.") }
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
    $profileFiles = @(Get-ChildItem -LiteralPath $profileRoot -Filter '*.json' | Sort-Object -Property Name)
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
