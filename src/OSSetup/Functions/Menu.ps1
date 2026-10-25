# Menus console : sélection au clavier (flèches, Espace / Entrée), redessinés sur place.
# Une fois le menu validé, il est effacé et remplacé par une seule ligne de résumé : la console
# et le journal ne gardent que les choix, pas chaque étape de la navigation.
# Logique (état, touches, lignes) séparée de l'affichage pour être testable.

function New-OSSetupMenuState {
    <#
    .SYNOPSIS
        Crée l'état d'un menu.
    .DESCRIPTION
        Modes : multi (cases à cocher), single (un seul choix, ou aucun si Min = 0),
        action (Entrée choisit et valide immédiatement, sans ligne « Valider »).
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Crée un objet en mémoire, sans effet sur le système.')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        # Objets { Value; Label }
        [Parameter(Mandatory)]
        [object[]]$Option,

        [string[]]$Selected = @(),

        [ValidateSet('single', 'multi', 'action')]
        [string]$Mode = 'multi',

        [int]$Min = 0,

        [int]$Max = [int]::MaxValue,

        # Lignes d'information affichées sous le titre.
        [string[]]$Description = @(),

        # Ajoute une ligne « Retour » (et active Échap).
        [switch]$AllowBack,

        # Place le curseur sur « Valider » (étape déjà renseignée : Entrée suffit à la confirmer).
        [switch]$CursorOnValidate
    )
    $state = @{
        Title       = $Title
        Options     = @($Option)
        Selected    = [System.Collections.Generic.List[string]]::new()
        Mode        = $Mode
        Min         = $Min
        Max         = $Max
        Description = @($Description)
        AllowBack   = [bool]$AllowBack
        Cursor      = 0
        Message     = ''
    }
    foreach ($value in $Selected) { $state.Selected.Add($value) }
    if ($CursorOnValidate -and $Mode -ne 'action') { $state.Cursor = $state.Options.Count }
    $state
}

function Get-OSSetupMenuRow {
    <#
    .SYNOPSIS
        Lignes navigables du menu : options, puis « Valider » (sauf mode action), puis « Retour ».
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
    )
    for ($i = 0; $i -lt $State.Options.Count; $i++) { @{ Kind = 'option'; Index = $i } }
    if ($State.Mode -ne 'action') { @{ Kind = 'validate' } }
    if ($State.AllowBack) { @{ Kind = 'back' } }
}

function Invoke-OSSetupMenuKey {
    <#
    .SYNOPSIS
        Applique une touche à l'état du menu. Retourne $null pour continuer, ou le résultat
        { Action = 'next' | 'back'; Values = [string[]] } quand le menu se termine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [ConsoleKey]$Key
    )
    $rows = @(Get-OSSetupMenuRow -State $State)
    $State.Message = ''
    switch ($Key) {
        'UpArrow' { $State.Cursor = ($State.Cursor - 1 + $rows.Count) % $rows.Count; return }
        'DownArrow' { $State.Cursor = ($State.Cursor + 1) % $rows.Count; return }
        'Home' { $State.Cursor = 0; return }
        'End' { $State.Cursor = $rows.Count - 1; return }
        'Escape' {
            if ($State.AllowBack) { return @{ Action = 'back'; Values = @() } }
            return
        }
        { $_ -in 'Enter', 'Spacebar' } {
            $row = $rows[$State.Cursor]
            switch ($row.Kind) {
                'back' { return @{ Action = 'back'; Values = @() } }
                'validate' {
                    $count = $State.Selected.Count
                    if ($count -lt $State.Min -or $count -gt $State.Max) {
                        $State.Message = if ($State.Min -eq $State.Max) { "Sélectionnez $($State.Min) élément(s)." }
                        elseif ($State.Max -eq [int]::MaxValue) { "Sélectionnez au moins $($State.Min) élément(s)." }
                        else { "Sélectionnez entre $($State.Min) et $($State.Max) élément(s)." }
                        return
                    }
                    return @{ Action = 'next'; Values = $State.Selected.ToArray() }
                }
                'option' {
                    $value = $State.Options[$row.Index].Value
                    if ($State.Mode -eq 'action') {
                        return @{ Action = 'next'; Values = @($value) }
                    }
                    if ($State.Selected.Contains($value)) {
                        # En choix unique, décocher n'est possible que si « aucun » est autorisé.
                        if ($State.Mode -eq 'multi' -or $State.Min -eq 0) { [void]$State.Selected.Remove($value) }
                    }
                    elseif ($State.Mode -eq 'single') {
                        $State.Selected.Clear()
                        $State.Selected.Add($value)
                    }
                    elseif ($State.Selected.Count -ge $State.Max) {
                        $State.Message = "$($State.Max) élément(s) au maximum."
                    }
                    else {
                        $State.Selected.Add($value)
                    }
                    return
                }
            }
        }
    }
}

function Get-OSSetupMenuLine {
    <#
    .SYNOPSIS
        Lignes à afficher pour l'état courant : objets { Text; Color }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
    )
    $help = if ($State.Mode -eq 'action') { '↑↓ déplacer · Entrée choisir' } else { '↑↓ déplacer · Espace ou Entrée cocher, ou valider sur « Valider »' }
    if ($State.AllowBack) { $help += ' · Échap retour' }

    $title = switch ($State.Mode) {
        'single' { "$($State.Title) (un seul choix)" }
        'multi' { "$($State.Title) (plusieurs choix possibles)" }
        default { $State.Title }
    }
    [pscustomobject]@{ Text = $title; Color = 'Cyan' }
    foreach ($line in $State.Description) { [pscustomobject]@{ Text = "  $line"; Color = 'Gray' } }
    [pscustomobject]@{ Text = "  $help"; Color = 'DarkGray' }
    [pscustomobject]@{ Text = ''; Color = 'Gray' }

    $rows = @(Get-OSSetupMenuRow -State $State)
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $pointer = if ($i -eq $State.Cursor) { '>' } else { ' ' }
        switch ($row.Kind) {
            'option' {
                $option = $State.Options[$row.Index]
                # Même case pour choix unique et multiple ; le choix unique est signalé dans le titre.
                $mark = if ($State.Mode -eq 'action') { '' } elseif ($State.Selected.Contains($option.Value)) { '[x] ' } else { '[ ] ' }
                $color = if ($i -eq $State.Cursor) { 'White' } else { 'Gray' }
                $line = [pscustomobject]@{ Text = "  $pointer $mark$($option.Label)"; Color = $color; Segments = $null }
                # Libellé « Sujet : état » : l'état en couleur, pour repérer le sujet d'un coup d'œil.
                $separator = $option.Label.IndexOf(' : ')
                if ($separator -gt 0) {
                    $detailColor = if ($i -eq $State.Cursor) { 'Cyan' } else { 'DarkCyan' }
                    $line.Segments = @(
                        [pscustomobject]@{ Text = "  $pointer $mark$($option.Label.Substring(0, $separator))"; Color = $color }
                        [pscustomobject]@{ Text = $option.Label.Substring($separator); Color = $detailColor }
                    )
                }
                $line
            }
            'validate' {
                [pscustomobject]@{ Text = ''; Color = 'Gray' }
                $color = if ($i -eq $State.Cursor) { 'Green' } else { 'DarkGreen' }
                [pscustomobject]@{ Text = "  $pointer [ Valider ]"; Color = $color }
            }
            'back' {
                $color = if ($i -eq $State.Cursor) { 'White' } else { 'DarkGray' }
                [pscustomobject]@{ Text = "  $pointer ← Retour"; Color = $color }
            }
        }
    }
    [pscustomobject]@{ Text = $(if ($State.Message) { "  $($State.Message)" } else { '' }); Color = 'Yellow' }
}

function Test-OSSetupInteractiveConsole {
    <#
    .SYNOPSIS
        Vrai si la console permet le rendu sur place (clavier et écran non redirigés).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if ($Host.Name -ne 'ConsoleHost' -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return $false }
    try {
        return [Console]::WindowWidth -gt 20
    }
    catch {
        return $false
    }
}

function Write-OSSetupMenuFrame {
    # Écrit les lignes à partir de la ligne $Top, en effaçant le reste de chaque ligne et les lignes en trop.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Top,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Line,

        [int]$ClearCount = 0
    )
    $width = [Math]::Max(1, [Console]::WindowWidth - 1)
    [Console]::SetCursorPosition(0, $Top)
    $count = [Math]::Max($Line.Count, $ClearCount)
    for ($i = 0; $i -lt $count; $i++) {
        if ($i -lt $Line.Count) {
            # Ligne en une couleur, ou en plusieurs morceaux (Segments) ; tronquée à la largeur de la console.
            $segments = if ($Line[$i].PSObject.Properties['Segments'] -and $Line[$i].Segments) { @($Line[$i].Segments) } else { @($Line[$i]) }
            $remaining = $width
            foreach ($segment in $segments) {
                if ($remaining -le 0) { break }
                $text = $segment.Text
                if ($text.Length -gt $remaining) { $text = $text.Substring(0, $remaining - 1) + '…' }
                Write-Host -Object $text -ForegroundColor $segment.Color -NoNewline
                $remaining -= $text.Length
            }
            Write-Host -Object (' ' * $remaining)
        }
        else {
            Write-Host -Object (' ' * $width)
        }
    }
}

function Read-OSSetupMenu {
    <#
    .SYNOPSIS
        Affiche un menu et retourne { Action = 'next' | 'back'; Values }.
        Console interactive : navigation au clavier, menu redessiné sur place puis effacé.
        Sinon (console redirigée) : saisie de numéros.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
    )
    if (-not (Test-OSSetupInteractiveConsole)) {
        return Read-OSSetupMenuText -State $State
    }

    $lines = @(Get-OSSetupMenuLine -State $State)
    # Réserve la place du menu : si la console défile, la position de départ est recalculée.
    Write-Host -Object ("`n" * ($lines.Count - 1))
    $top = [Math]::Max(0, [Console]::CursorTop - $lines.Count)
    $previousCount = 0
    $cursorVisible = $true
    try { $cursorVisible = [Console]::CursorVisible } catch { Write-Verbose -Message 'Visibilité du curseur non lisible.' }
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $lines = @(Get-OSSetupMenuLine -State $State)
            Write-OSSetupMenuFrame -Top $top -Line $lines -ClearCount $previousCount
            $previousCount = $lines.Count
            $key = [Console]::ReadKey($true)
            $result = Invoke-OSSetupMenuKey -State $State -Key $key.Key
            if ($result) {
                Write-OSSetupMenuFrame -Top $top -Line @() -ClearCount $previousCount
                [Console]::SetCursorPosition(0, $top)
                return $result
            }
        }
    }
    finally {
        [Console]::CursorVisible = $cursorVisible
    }
}

function Read-OSSetupMenuText {
    <#
    .SYNOPSIS
        Variante texte (console redirigée) : menu affiché une fois, saisie de numéros.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State
    )
    Write-Host -Object $State.Title -ForegroundColor Cyan
    foreach ($line in $State.Description) { Write-Host -Object "  $line" }
    for ($i = 0; $i -lt $State.Options.Count; $i++) {
        $mark = if ($State.Selected.Contains($State.Options[$i].Value)) { ' (actuel)' } else { '' }
        Write-Host -Object ('  {0,2}. {1}{2}' -f ($i + 1), $State.Options[$i].Label, $mark)
    }
    $hint = if ($State.Mode -eq 'multi') { 'Numéros (ex. 1 3)' } else { 'Numéro' }
    if ($State.Mode -ne 'action') { $hint += ', Entrée pour garder l''actuel' }
    if ($State.AllowBack) { $hint += ', r pour revenir' }

    while ($true) {
        $userInput = (Read-Host -Prompt $hint).Trim()
        if ($State.AllowBack -and $userInput -match '^r(etour)?$') { return @{ Action = 'back'; Values = @() } }
        if (-not $userInput) {
            if ($State.Mode -eq 'action') { continue }
            $values = $State.Selected.ToArray()
        }
        else {
            $values = foreach ($token in $userInput -split '[\s,;]+' | Where-Object { $_ }) {
                $index = 0
                if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $State.Options.Count) {
                    $State.Options[$index - 1].Value
                }
                else {
                    Write-Host -Object "Entrée ignorée : '$token'." -ForegroundColor Yellow
                }
            }
            $values = @($values | Select-Object -Unique)
        }
        $max = if ($State.Mode -eq 'multi') { $State.Max } else { 1 }
        if ($values.Count -lt $State.Min -or $values.Count -gt $max -or ($State.Mode -eq 'action' -and $values.Count -ne 1)) {
            Write-Host -Object "Sélection invalide (entre $($State.Min) et $max élément(s))." -ForegroundColor Yellow
            continue
        }
        return @{ Action = 'next'; Values = @($values) }
    }
}
