# Profil PowerShell 7 — déployé par OS_Setup (ne pas modifier ici, modifier le dépôt).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'fnm env | Invoke-Expression : intégration documentée par fnm.')]
param()

$env:DEV_ROOT = '{{DevRoot}}'

function Set-DevLocation {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Change seulement le dossier courant de la session.')]
    param()
    Set-Location -Path $env:DEV_ROOT
}
Set-Alias -Name dev -Value Set-DevLocation

# Node.js (fnm) : en entrant dans un projet, la version qu'il demande (.nvmrc, .node-version) est utilisée (fnm propose
# de l'installer si elle manque) ; ailleurs, la version par défaut (LTS).
if (Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --version-file-strategy=recursive --shell powershell | Out-String | Invoke-Expression
}

# Playwright CLI : une session de navigateur propre à ce terminal (fenêtre, onglet, volet herdr). Les agents lancés ici
# en héritent : deux agents dans deux terminaux n'ouvrent jamais le même navigateur. Une session déjà choisie est gardée.
if (-not $env:PLAYWRIGHT_CLI_SESSION) {
    $env:PLAYWRIGHT_CLI_SESSION = "term-$PID"
}
