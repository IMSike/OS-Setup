function Get-OSSetupBuiltinVariable {
    <#
    .SYNOPSIS
        Variables fournies par le moteur, utilisables partout sous la forme {{Nom}}.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )
    [ordered]@{
        RepoRoot        = $Root
        UserProfile     = [Environment]::GetFolderPath('UserProfile')
        Documents       = [Environment]::GetFolderPath('MyDocuments')
        AppData         = [Environment]::GetFolderPath('ApplicationData')
        LocalAppData    = [Environment]::GetFolderPath('LocalApplicationData')
        Temp            = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar)
        Windows         = [Environment]::GetFolderPath('Windows')
        ProgramFiles    = [Environment]::GetFolderPath('ProgramFiles')
        Desktop         = [Environment]::GetFolderPath('DesktopDirectory')
        PublicDesktop   = [Environment]::GetFolderPath('CommonDesktopDirectory')
        StartMenu       = [Environment]::GetFolderPath('Programs')
        CommonStartMenu = [Environment]::GetFolderPath('CommonPrograms')
    }
}

function Get-OSSetupVariableDefinition {
    <#
    .SYNOPSIS
        Retourne les variables déclarées par les profils résolus (nom → { prompt; default } ou { prompt; personal }).
    .DESCRIPTION
        Kind : location (emplacements, avec valeur par défaut), personal (informations personnelles, sans valeur par
        défaut dans le dépôt : ex. nom et adresse pour Git), all.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [string[]]$ResolvedProfileId,

        [ValidateSet('all', 'location', 'personal')]
        [string]$Kind = 'all'
    )
    $definitions = [ordered]@{}
    foreach ($id in $ResolvedProfileId) {
        $variables = $Data.Profiles[$id]['variables']
        if ($null -eq $variables) { continue }
        foreach ($name in $variables.Keys) {
            $personal = [bool]$variables[$name]['personal']
            if ($Kind -eq 'location' -and $personal) { continue }
            if ($Kind -eq 'personal' -and -not $personal) { continue }
            if (-not $definitions.Contains($name)) {
                $definitions[$name] = $variables[$name]
            }
        }
    }
    $definitions
}

function Get-OSSetupMissingVariable {
    <#
    .SYNOPSIS
        Informations personnelles non renseignées (nom → libellé) : les actions qui les utilisent sont ignorées.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers
    )
    $missing = [ordered]@{}
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    $definitions = Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles -Kind personal
    foreach ($name in $definitions.Keys) {
        $value = if ($null -ne $Answers['variables']) { $Answers['variables'][$name] } else { $null }
        if ([string]::IsNullOrWhiteSpace($value)) { $missing[$name] = $definitions[$name]['prompt'] }
    }
    $missing
}

function Get-OSSetupActionVariableName {
    <#
    .SYNOPSIS
        Noms des variables {{Nom}} utilisées par les valeurs texte d'une action.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action
    )
    foreach ($value in $Action.Values) {
        if ($value -isnot [string]) { continue }
        foreach ($match in [regex]::Matches($value, '\{\{([A-Za-z][A-Za-z0-9]*)\}\}')) { $match.Groups[1].Value }
    }
}

function Expand-OSSetupString {
    <#
    .SYNOPSIS
        Remplace les {{Nom}} d'une chaîne par la valeur des variables. Une variable inconnue lève une erreur.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Variables', Justification = 'Utilisé par le bloc d''évaluation passé à [regex]::Replace.')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Variables
    )
    [regex]::Replace($Text, '\{\{([A-Za-z][A-Za-z0-9]*)\}\}', {
            param($match)
            $name = $match.Groups[1].Value
            if (-not $Variables.Contains($name)) {
                throw "Variable inconnue : '{{$name}}'."
            }
            [string]$Variables[$name]
        })
}

function Resolve-OSSetupVariable {
    <#
    .SYNOPSIS
        Calcule la valeur finale des variables : intégrées, puis défauts des profils, puis réponses ; références résolues.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers
    )
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    $raw = Get-OSSetupBuiltinVariable -Root $Data.Root
    $definitions = Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles
    foreach ($name in $definitions.Keys) {
        # Information personnelle : pas de valeur par défaut, connue seulement si elle a été renseignée.
        if ($definitions[$name].Contains('default')) { $raw[$name] = $definitions[$name]['default'] }
    }
    if ($null -ne $Answers['variables']) {
        foreach ($name in $Answers['variables'].Keys) {
            $raw[$name] = $Answers['variables'][$name]
        }
    }

    # Les valeurs peuvent référencer d'autres variables : on itère jusqu'à stabilisation.
    $values = [ordered]@{}
    foreach ($name in $raw.Keys) { $values[$name] = [string]$raw[$name] }
    for ($pass = 0; $pass -lt 10; $pass++) {
        $changed = $false
        foreach ($name in @($values.Keys)) {
            $expanded = Expand-OSSetupString -Text $values[$name] -Variables $values
            if ($expanded -ne $values[$name]) {
                $values[$name] = $expanded
                $changed = $true
            }
        }
        if (-not $changed) { return $values }
    }
    throw 'Références circulaires entre variables.'
}

function Expand-OSSetupAction {
    <#
    .SYNOPSIS
        Retourne une copie de l'action dont toutes les valeurs texte ont été expansées.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Variables
    )
    $copy = [ordered]@{}
    foreach ($key in $Action.Keys) {
        $value = $Action[$key]
        $copy[$key] = if ($value -is [string]) { Expand-OSSetupString -Text $value -Variables $Variables } else { $value }
    }
    $copy
}
