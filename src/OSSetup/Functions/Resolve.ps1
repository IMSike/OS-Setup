function Resolve-OSSetupProfileSet {
    <#
    .SYNOPSIS
        Retourne les profils demandés et ceux qu'ils étendent, parents en premier, sans doublon.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Data', Justification = 'Utilisé par le bloc de script récursif $visit.')]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [string[]]$ProfileId
    )
    $resolved = [System.Collections.Generic.List[string]]::new()
    $visiting = [System.Collections.Generic.HashSet[string]]::new()

    $visit = {
        param([string]$Id)
        if ($resolved.Contains($Id)) { return }
        if (-not $Data.Profiles.Contains($Id)) { throw "Profil inconnu : '$Id'." }
        if (-not $visiting.Add($Id)) { throw "Cycle d'héritage entre profils impliquant '$Id'." }
        foreach ($parent in $Data.Profiles[$Id]['extends']) {
            & $visit $parent
        }
        $resolved.Add($Id)
    }
    foreach ($id in $ProfileId) {
        & $visit $id
    }
    $resolved.ToArray()
}

function Get-OSSetupChoice {
    <#
    .SYNOPSIS
        Retourne les groupes de choix des profils donnés (profils déjà résolus).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [string[]]$ResolvedProfileId
    )
    foreach ($id in $ResolvedProfileId) {
        foreach ($choice in $Data.Profiles[$id]['choices']) {
            $choice
        }
    }
}

function Get-OSSetupChoiceBound {
    <#
    .SYNOPSIS
        Retourne les bornes effectives (Min, Max) d'un groupe de choix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Choice
    )
    $min = if ($null -ne $Choice['min']) { [int]$Choice['min'] } else { 0 }
    $max = if ($null -ne $Choice['max']) { [int]$Choice['max'] } else { @($Choice['options']).Count }
    if ($Choice['mode'] -eq 'single' -and $max -gt 1) { $max = 1 }
    [pscustomobject]@{ Min = $min; Max = $max }
}

function Test-OSSetupAnswer {
    <#
    .SYNOPSIS
        Vérifie la cohérence d'un fichier de réponses avec les données. Lève une erreur si incohérent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers
    )
    $problems = [System.Collections.Generic.List[string]]::new()
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    $choices = @(Get-OSSetupChoice -Data $Data -ResolvedProfileId $resolvedProfiles)
    $knownChoiceIds = @($choices | ForEach-Object { $_['id'] })

    if ($null -ne $Answers['choices']) {
        foreach ($answeredId in $Answers['choices'].Keys) {
            if ($answeredId -notin $knownChoiceIds) {
                $problems.Add("Le groupe de choix '$answeredId' n'appartient à aucun profil sélectionné.")
            }
        }
    }
    foreach ($choice in $choices) {
        $selected = @(Get-OSSetupSelectedOption -Choice $choice -Answers $Answers)
        $bound = Get-OSSetupChoiceBound -Choice $choice
        foreach ($option in $selected) {
            if ($option -notin $choice['options']) {
                $problems.Add("Choix '$($choice['id'])' : '$option' ne fait pas partie des options.")
            }
        }
        if ($selected.Count -lt $bound.Min -or $selected.Count -gt $bound.Max) {
            $problems.Add("Choix '$($choice['id'])' : $($selected.Count) sélection(s), attendu entre $($bound.Min) et $($bound.Max).")
        }
    }
    if ($problems.Count -gt 0) {
        throw "Réponses invalides :`n - " + ($problems -join "`n - ")
    }
}

function Get-OSSetupSelectedOption {
    <#
    .SYNOPSIS
        Retourne les options retenues pour un groupe : réponse explicite, sinon valeurs par défaut.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Choice,

        [Parameter(Mandatory)]
        [hashtable]$Answers
    )
    if ($null -ne $Answers['choices'] -and $Answers['choices'].Contains($Choice['id'])) {
        foreach ($option in $Answers['choices'][$Choice['id']]) { $option }
    }
    else {
        foreach ($option in $Choice['default']) { $option }
    }
}

function Get-OSSetupChoiceWarning {
    <#
    .SYNOPSIS
        Avertissements liés aux choix : élément coché qui a une conséquence à connaître (checkedWarning, ex. une
        suppression qui efface des données), ou élément proposé mais non coché (uncheckedWarning).
        -ChoiceId limite la recherche à un groupe de choix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [string]$ChoiceId
    )
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    foreach ($choice in Get-OSSetupChoice -Data $Data -ResolvedProfileId $resolvedProfiles) {
        if ($ChoiceId -and $choice['id'] -ne $ChoiceId) { continue }
        $selected = @(Get-OSSetupSelectedOption -Choice $choice -Answers $Answers)
        foreach ($option in $choice['options']) {
            $item = $Data.Items[$option]
            if (-not $item) { continue }
            $checked = $option -in $selected
            $message = if ($checked) { $item['checkedWarning'] } else { $item['uncheckedWarning'] }
            if ($message) {
                [pscustomobject]@{ ItemId = $option; ItemName = $item['name']; Checked = $checked; Message = $message }
            }
        }
    }
}

function Write-OSSetupChoiceWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [string]$ChoiceId
    )
    foreach ($warning in Get-OSSetupChoiceWarning @PSBoundParameters) {
        $state = if ($warning.Checked) { 'coché' } else { 'non coché' }
        Write-OSSetupLog -Level Warning -Message "  Attention, $state : $($warning.ItemName). $($warning.Message)"
    }
}

function Resolve-OSSetupItemList {
    <#
    .SYNOPSIS
        Calcule la liste ordonnée des éléments à traiter : profils + choix + dépendances, triés topologiquement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Facts
    )
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    $requested = [System.Collections.Generic.List[string]]::new()
    # Options proposées dans un menu : choisies ou non, jamais ajoutées en silence comme dépendance.
    $offered = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($profileId in $resolvedProfiles) {
        foreach ($itemId in $Data.Profiles[$profileId]['items']) { $requested.Add($itemId) }
    }
    foreach ($choice in Get-OSSetupChoice -Data $Data -ResolvedProfileId $resolvedProfiles) {
        foreach ($option in $choice['options']) { [void]$offered.Add($option) }
        foreach ($itemId in Get-OSSetupSelectedOption -Choice $choice -Answers $Answers) { $requested.Add($itemId) }
    }

    # Parcours en profondeur : les dépendances sont placées avant l'élément, l'ordre de déclaration est conservé.
    # Une dépendance technique (proposée dans aucun menu) est ajoutée ; une dépendance proposée mais non choisie
    # fait ignorer l'élément qui en dépend (et ses propres dépendants).
    $ordered = [System.Collections.Generic.List[string]]::new()
    $visiting = [System.Collections.Generic.HashSet[string]]::new()
    $skipped = [ordered]@{}
    $visit = {
        param([string]$Id)
        if ($ordered.Contains($Id)) { return $true }
        if ($skipped.Contains($Id)) { return $false }
        if (-not $Data.Items.Contains($Id)) { throw "Élément inconnu : '$Id'." }
        if (-not $visiting.Add($Id)) { throw "Cycle de dépendances impliquant l'élément '$Id'." }
        foreach ($dependency in $Data.Items[$Id]['dependsOn']) {
            if ($offered.Contains($dependency) -and -not $requested.Contains($dependency)) {
                $skipped[$Id] = "nécessite '$dependency', non choisi"
                return $false
            }
            if (-not (& $visit $dependency)) {
                $skipped[$Id] = "nécessite '$dependency', ignoré"
                return $false
            }
        }
        $ordered.Add($Id)
        $true
    }
    foreach ($id in $requested) {
        [void](& $visit $id)
    }
    foreach ($id in $skipped.Keys) {
        Write-OSSetupLog -Level Detail -Message "Élément '$id' ignoré : $($skipped[$id])."
    }

    # Les éléments « runLast » passent en fin de plan (ex. disposition de la barre des tâches : elle redémarre
    # l'Explorateur, ce qui rend effectifs les réglages appliqués avant elle).
    $sorted = @($ordered | Where-Object { -not $Data.Items[$_]['runLast'] }) + @($ordered | Where-Object { $Data.Items[$_]['runLast'] })
    foreach ($id in $sorted) {
        if (Test-OSSetupItemApplicable -Item $Data.Items[$id] -Facts $Facts) {
            $id
        }
        else {
            Write-OSSetupLog -Level Detail -Message "Élément '$id' ignoré : ne s'applique pas à cette machine."
        }
    }
}

function Get-OSSetupAvailableOption {
    <#
    .SYNOPSIS
        Options d'un groupe de choix à proposer : celles dont aucune dépendance n'est un élément proposé dans un menu
        mais non retenu (ex. « épingler Vivaldi » n'apparaît que si Vivaldi est choisi). Les réponses déjà données
        font foi, sinon les valeurs par défaut.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [Parameter(Mandatory)]
        $Choice
    )
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    $offered = [System.Collections.Generic.HashSet[string]]::new()
    $selected = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($other in Get-OSSetupChoice -Data $Data -ResolvedProfileId $resolvedProfiles) {
        foreach ($option in $other['options']) { [void]$offered.Add($option) }
        foreach ($option in Get-OSSetupSelectedOption -Choice $other -Answers $Answers) { [void]$selected.Add($option) }
    }
    foreach ($option in $Choice['options']) {
        $missing = @($Data.Items[$option]['dependsOn'] | Where-Object { $_ -and $offered.Contains($_) -and -not $selected.Contains($_) })
        if (-not $missing) { $option }
    }
}
