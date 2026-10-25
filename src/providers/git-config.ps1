# Provider git-config : une clé de la configuration Git globale du compte (~/.gitconfig), réglée avec
# « git config --global ». Clé par clé : les autres réglages de l'utilisateur sont conservés.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'git-config'

    Describe = {
        param($Action, $Context)
        "git config --global $($Action['key']) $($Action['value'])"
    }

    Test     = {
        param($Action, $Context)
        $current = & git config --global --get $Action['key']
        $LASTEXITCODE -eq 0 -and "$current" -ceq $Action['value']
    }

    Read     = {
        param($Action, $Context)
        $current = & git config --global --get $Action['key']
        if ($LASTEXITCODE -eq 0) { [ordered]@{ exists = $true; value = "$current" } } else { [ordered]@{ exists = $false } }
    }

    Invoke   = {
        param($Action, $Context)
        & git config --global $Action['key'] $Action['value']
        if ($LASTEXITCODE -ne 0) { throw "git config a échoué (code $LASTEXITCODE)." }
    }
}
