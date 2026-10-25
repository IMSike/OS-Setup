function Get-OSSetupWizardStep {
    <#
    .SYNOPSIS
        Étapes de l'assistant pour les réponses courantes : profils, un groupe de choix par étape, emplacements.
        Les étapes dépendent des profils retenus : la liste est recalculée après chaque étape.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Facts,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        # Profils imposés en ligne de commande : pas d'étape « Profils ».
        [switch]$SkipProfiles
    )
    if (-not $SkipProfiles) {
        [pscustomobject]@{ Id = 'profiles'; Kind = 'profiles'; Title = 'Profils à installer'; Choice = $null; Options = @() }
    }
    if (-not $Answers['profiles']) { return }
    $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
    foreach ($choice in Get-OSSetupChoice -Data $Data -ResolvedProfileId $resolvedProfiles) {
        # Ne sont pas proposées : les options qui ne s'appliquent pas à cette machine, et celles qui dépendent d'un
        # élément proposé mais non retenu (ex. épingler un navigateur qui n'est pas installé).
        $available = @(Get-OSSetupAvailableOption -Data $Data -Answers $Answers -Choice $choice)
        $applicable = @($available | Where-Object { Test-OSSetupItemApplicable -Item $Data.Items[$_] -Facts $Facts })
        if ($applicable.Count -eq 0) { continue }
        [pscustomobject]@{ Id = "choice:$($choice['id'])"; Kind = 'choice'; Title = $choice['prompt']; Choice = $choice; Options = $applicable }
    }
    if ((Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles -Kind personal).Count -gt 0) {
        [pscustomobject]@{ Id = 'personal'; Kind = 'personal'; Title = 'Informations personnelles'; Choice = $null; Options = @() }
    }
    if ((Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles -Kind location).Count -gt 0) {
        [pscustomobject]@{ Id = 'locations'; Kind = 'locations'; Title = 'Emplacements'; Choice = $null; Options = @() }
    }
}

function Read-OSSetupAnswer {
    <#
    .SYNOPSIS
        Assistant interactif (profils, choix, emplacements) avec retour arrière. Retourne les réponses.
    .DESCRIPTION
        Chaque étape validée laisse une seule ligne de résumé dans la console et le journal.
        Avec -Answers, les réponses existantes sont reprises (modification depuis l'écran de validation)
        et l'assistant commence à l'étape -StartStep.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Facts,

        # Profils déjà imposés (l'étape des profils est alors sautée).
        [string[]]$ProfileId,

        [hashtable]$Answers,

        [string]$StartStep
    )
    # Nom distinct de $Answers : les noms de variables PowerShell ne tiennent pas compte de la casse.
    $collected = @{
        profiles  = @(if ($ProfileId) { $ProfileId } elseif ($Answers) { $Answers['profiles'] } else { 'base' })
        choices   = [ordered]@{}
        variables = [ordered]@{}
    }
    if ($Answers -and $Answers['choices']) {
        foreach ($key in $Answers['choices'].Keys) { $collected.choices[$key] = @($Answers['choices'][$key]) }
    }
    if ($Answers -and $Answers['variables']) {
        foreach ($key in $Answers['variables'].Keys) { $collected.variables[$key] = $Answers['variables'][$key] }
    }
    $skipProfiles = [bool]$ProfileId

    # Étapes déjà renseignées (sauf celle qu'on vient modifier) : le curseur démarre sur « Valider ».
    $visited = [System.Collections.Generic.HashSet[string]]::new()
    if ($Answers) {
        foreach ($step in Get-OSSetupWizardStep -Data $Data -Facts $Facts -Answers $collected -SkipProfiles:$skipProfiles) {
            if ($step.Id -ne $StartStep) { [void]$visited.Add($step.Id) }
        }
    }

    $index = 0
    if ($StartStep) {
        $steps = @(Get-OSSetupWizardStep -Data $Data -Facts $Facts -Answers $collected -SkipProfiles:$skipProfiles)
        $index = [Math]::Max(0, [array]::IndexOf(@($steps.Id), $StartStep))
    }

    while ($true) {
        $steps = @(Get-OSSetupWizardStep -Data $Data -Facts $Facts -Answers $collected -SkipProfiles:$skipProfiles)
        if ($index -ge $steps.Count) { break }
        $step = $steps[$index]
        $label = 'Étape {0}/{1} — {2}' -f ($index + 1), $steps.Count, $step.Title
        $outcome = Read-OSSetupWizardStep -Data $Data -Step $step -Answers $collected -Title $label `
            -AllowBack:($index -gt 0) -Revisit:($visited.Contains($step.Id))
        if ($outcome -eq 'back') {
            $index--
            continue
        }
        [void]$visited.Add($step.Id)
        $index++
    }

    # Choix des groupes qui n'appartiennent plus aux profils retenus : retirés.
    $currentChoiceIds = @(Get-OSSetupWizardStep -Data $Data -Facts $Facts -Answers $collected -SkipProfiles |
        Where-Object { $_.Kind -eq 'choice' } | ForEach-Object { $_.Choice['id'] })
    foreach ($key in @($collected.choices.Keys)) {
        if ($key -notin $currentChoiceIds) { $collected.choices.Remove($key) }
    }
    $collected
}

function Read-OSSetupWizardStep {
    <#
    .SYNOPSIS
        Pose la question d'une étape et met à jour les réponses. Retourne 'next' ou 'back'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        $Step,

        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [Parameter(Mandatory)]
        [string]$Title,

        [switch]$AllowBack,

        [switch]$Revisit
    )
    switch ($Step.Kind) {
        'profiles' {
            $options = foreach ($setupProfile in $Data.Profiles.Values) {
                $optionLabel = $setupProfile['name']
                if ($setupProfile['description']) { $optionLabel += " — $($setupProfile['description'])" }
                [pscustomobject]@{ Value = $setupProfile['id']; Label = $optionLabel }
            }
            $state = New-OSSetupMenuState -Title $Title -Option @($options) -Selected $Answers['profiles'] -Mode multi -Min 1 `
                -AllowBack:$AllowBack -CursorOnValidate:$Revisit
            $result = Read-OSSetupMenu -State $state
            if ($result.Action -eq 'back') { return 'back' }
            $Answers['profiles'] = @($result.Values)
            $names = foreach ($id in $result.Values) { $Data.Profiles[$id]['name'] }
            Write-OSSetupLog -Level Success -Message "√ $($Step.Title) : $($names -join ', ')"
            return 'next'
        }
        'choice' {
            $choice = $Step.Choice
            $options = foreach ($itemId in $Step.Options) {
                [pscustomobject]@{ Value = $itemId; Label = $Data.Items[$itemId]['name'] }
            }
            $current = if ($Answers['choices'].Contains($choice['id'])) { @($Answers['choices'][$choice['id']]) } else { @($choice['default']) }
            $bound = Get-OSSetupChoiceBound -Choice $choice
            $state = New-OSSetupMenuState -Title $Title -Option @($options) -Selected @($current | Where-Object { $_ -in $Step.Options }) `
                -Mode $choice['mode'] -Min ([Math]::Min($bound.Min, $Step.Options.Count)) -Max $bound.Max `
                -AllowBack:$AllowBack -CursorOnValidate:$Revisit
            $result = Read-OSSetupMenu -State $state
            if ($result.Action -eq 'back') { return 'back' }
            $Answers['choices'][$choice['id']] = @($result.Values)
            # Au-delà de quelques éléments, un décompte garde la ligne lisible (le plan les détaille ensuite).
            $names = if ($result.Values.Count -eq 0) { 'aucun' }
            elseif ($result.Values.Count -gt 4) { "$($result.Values.Count) sur $($Step.Options.Count)" }
            else { ($result.Values | ForEach-Object { $Data.Items[$_]['name'] }) -join ', ' }
            Write-OSSetupLog -Level Success -Message "√ $($Step.Title) : $names"
            Write-OSSetupChoiceWarning -Data $Data -Answers $Answers -ChoiceId $choice['id']
            return 'next'
        }
        'locations' {
            # Une seule question globale : on garde les valeurs actuelles, ou on les personnalise une par une.
            $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
            $definitions = Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles -Kind location
            $current = Resolve-OSSetupVariable -Data $Data -Answers $Answers
            $description = foreach ($name in $definitions.Keys) { "$($definitions[$name]['prompt']) : $($current[$name])" }
            $options = @(
                [pscustomobject]@{ Value = 'keep'; Label = 'Garder ces emplacements' }
                [pscustomobject]@{ Value = 'customize'; Label = 'Personnaliser…' }
            )
            $state = New-OSSetupMenuState -Title $Title -Option $options -Mode action -Description @($description) -AllowBack:$AllowBack
            $result = Read-OSSetupMenu -State $state
            if ($result.Action -eq 'back') { return 'back' }
            if ($result.Values[0] -eq 'customize') {
                Write-Host -Object "$Title (Entrée garde la valeur entre crochets)" -ForegroundColor Cyan
                foreach ($name in $definitions.Keys) {
                    $value = Read-Host -Prompt "  $($definitions[$name]['prompt']) [$($current[$name])]"
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $Answers['variables'][$name] = $value.Trim()
                    }
                }
                $current = Resolve-OSSetupVariable -Data $Data -Answers $Answers
            }
            foreach ($name in $definitions.Keys) {
                Write-OSSetupLog -Level Success -Message "√ $($definitions[$name]['prompt']) : $($current[$name])"
            }
            return 'next'
        }
        'personal' {
            # Jamais de valeur par défaut dans le dépôt : à renseigner à chaque session (ou dans un fichier de réponses
            # personnel). Non renseignée, les actions qui l'utilisent sont ignorées.
            $resolvedProfiles = Resolve-OSSetupProfileSet -Data $Data -ProfileId $Answers['profiles']
            $definitions = Get-OSSetupVariableDefinition -Data $Data -ResolvedProfileId $resolvedProfiles -Kind personal
            $display = { param($name) if ($Answers['variables'][$name]) { $Answers['variables'][$name] } else { '(non renseigné)' } }
            $description = foreach ($name in $definitions.Keys) { "$($definitions[$name]['prompt']) : $(& $display $name)" }
            $missing = @($definitions.Keys | Where-Object { -not $Answers['variables'][$_] })
            $options = @(
                if ($missing) { [pscustomobject]@{ Value = 'customize'; Label = 'Renseigner…' } }
                [pscustomobject]@{ Value = 'keep'; Label = $(if ($missing) { 'Continuer sans (les réglages concernés sont ignorés)' } else { 'Garder ces informations' }) }
                if (-not $missing) { [pscustomobject]@{ Value = 'customize'; Label = 'Modifier…' } }
            )
            $state = New-OSSetupMenuState -Title $Title -Option $options -Mode action -Description @($description) -AllowBack:$AllowBack
            $result = Read-OSSetupMenu -State $state
            if ($result.Action -eq 'back') { return 'back' }
            if ($result.Values[0] -eq 'customize') {
                Write-Host -Object "$Title (Entrée garde la valeur entre crochets)" -ForegroundColor Cyan
                foreach ($name in $definitions.Keys) {
                    $value = Read-Host -Prompt "  $($definitions[$name]['prompt']) [$($Answers['variables'][$name])]"
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $Answers['variables'][$name] = $value.Trim()
                    }
                }
            }
            foreach ($name in $definitions.Keys) {
                Write-OSSetupLog -Level Success -Message "√ $($definitions[$name]['prompt']) : $(& $display $name)"
            }
            return 'next'
        }
    }
}

function Read-OSSetupConfirmation {
    <#
    .SYNOPSIS
        Écran de validation après le plan : appliquer, modifier une étape, ou annuler.
        Retourne 'apply', 'cancel' ou l'identifiant de l'étape à modifier.
    #>
    [CmdletBinding()]
    param(
        # Étapes modifiables (sortie de Get-OSSetupWizardStep).
        [object[]]$Step = @(),

        # Rien à appliquer : seules la modification et la sortie sont proposées.
        [switch]$NothingToDo
    )
    $options = @(
        if (-not $NothingToDo) { [pscustomobject]@{ Value = 'apply'; Label = 'Appliquer ce plan' } }
        foreach ($wizardStep in $Step) { [pscustomobject]@{ Value = $wizardStep.Id; Label = "Modifier : $($wizardStep.Title)" } }
        [pscustomobject]@{ Value = 'cancel'; Label = $(if ($NothingToDo) { 'Quitter' } else { 'Annuler (rien n''est modifié)' }) }
    )
    $state = New-OSSetupMenuState -Title 'Que faire ?' -Option $options -Mode action
    $result = Read-OSSetupMenu -State $state
    $choice = $result.Values[0]
    $label = ($options | Where-Object { $_.Value -eq $choice }).Label
    Write-OSSetupLog -Message "√ $label"
    $choice
}

function New-OSSetupDefaultAnswer {
    <#
    .SYNOPSIS
        Réponses par défaut (aucune question posée) pour les profils donnés.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire, sans effet sur le système.')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ProfileId
    )
    @{ profiles = @($ProfileId); choices = [ordered]@{}; variables = [ordered]@{} }
}

function Read-OSSetupAnswerFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $answers = Read-OSSetupJsonFile -Path $Path -SchemaPath (Join-Path -Path $Root -ChildPath 'schemas\answers.schema.json') -Errors $errors
    if ($errors.Count -gt 0) {
        throw "Fichier de réponses invalide :`n - " + ($errors -join "`n - ")
    }
    [hashtable]$answers
}

function Save-OSSetupAnswerFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Answers,

        [Parameter(Mandatory)]
        [string]$Path
    )
    $document = [ordered]@{
        '$schema'   = 'https://raw.githubusercontent.com/IMSike/OS-Setup/main/schemas/answers.schema.json'
        profiles    = $Answers['profiles']
        choices     = $Answers['choices']
        variables   = $Answers['variables']
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Enregistrer le fichier de réponses')) {
        New-Item -Path (Split-Path -Path $Path -Parent) -ItemType Directory -Force -WhatIf:$false | Out-Null
        $document | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8NoBOM -WhatIf:$false
    }
}
