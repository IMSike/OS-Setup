# Provider claude-plugin : plugin de Claude Code publié dans une marketplace GitHub, installé pour le compte par
# « claude plugin install » (la marketplace est ajoutée au passage), puis activé s'il a été désactivé.
# Présence lue avec « claude plugin list --json ».

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'claude-plugin'

    Describe = {
        param($Action, $Context)
        "claude plugin install $($Action['plugin'])@$($Action['marketplace']) (marketplace $($Action['source']))"
    }

    # Seule l'installation pour le compte (portée user) compte : une installation propre à un projet ne sert pas ailleurs.
    # Comparaison stricte : un champ scope ou enabled absent de la sortie de Claude Code (format changé) rend l'élément
    # non conforme, et le journal en donne la raison.
    Test     = {
        param($Action, $Context)
        $id = "$($Action['plugin'])@$($Action['marketplace'])"
        $plugins = @(Get-OSSetupClaudePlugin | Where-Object { $_.Id -eq $id })
        if ($plugins | Where-Object { $_.Scope -eq 'user' -and $_.Enabled -eq $true }) { return $true }
        foreach ($field in 'scope', 'enabled') {
            if ($plugins | Where-Object { $null -eq $_.$field }) {
                Write-OSSetupLogOnce -Key "claude-plugin:${id}:$field" -Level Detail `
                    -Message "  plugin $id : champ « $field » absent de « claude plugin list --json » : considéré comme non conforme"
            }
        }
        $false
    }

    Invoke   = {
        param($Action, $Context)
        $id = "$($Action['plugin'])@$($Action['marketplace'])"
        # Déjà installé : la commande réussit sans rien changer.
        Invoke-OSSetupNativeCommand -FilePath claude -ArgumentList 'plugin', 'install', $Action['plugin'], '--marketplace', $Action['source'], '--scope', 'user' -Utf8 -Label 'claude plugin install'

        if (Get-OSSetupClaudePlugin | Where-Object { $_.Id -eq $id -and $_.Scope -eq 'user' -and -not $_.Enabled }) {
            Invoke-OSSetupNativeCommand -FilePath claude -ArgumentList 'plugin', 'enable', $id -Utf8 -Label 'claude plugin enable'
        }
    }
}
