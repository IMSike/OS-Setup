# Fonctions d'appui du provider vscode-extension.

function Get-OSSetupEditorExtension {
    <#
    .SYNOPSIS
        Extensions installées d'un éditeur (« code » pour VS Code, « cursor » pour Cursor), d'après « --list-extensions »
        lu une fois par passe et par éditeur (cache vidé par Clear-OSSetupStateCache, donc après chaque action
        exécutée). Vide si l'éditeur est absent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('code', 'cursor')]
        [string]$Command
    )
    $cacheKey = "EditorExtensions:$Command"
    if (-not $script:StateCache.ContainsKey($cacheKey)) {
        $script:StateCache[$cacheKey] = @(
            if (Get-Command -Name $Command -CommandType Application -ErrorAction SilentlyContinue) {
                & $Command --list-extensions 2>$null
            }
        )
    }
    $script:StateCache[$cacheKey]
}
