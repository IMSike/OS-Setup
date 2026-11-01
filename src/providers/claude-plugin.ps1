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

    Test     = {
        param($Action, $Context)
        $id = "$($Action['plugin'])@$($Action['marketplace'])"
        [bool](Get-OSSetupClaudePlugin | Where-Object { $_.Id -eq $id -and $_.Enabled })
    }

    Invoke   = {
        param($Action, $Context)
        $id = "$($Action['plugin'])@$($Action['marketplace'])"
        # Déjà installé : la commande réussit sans rien changer.
        Invoke-OSSetupNativeCommand -FilePath claude -ArgumentList 'plugin', 'install', $Action['plugin'], '--marketplace', $Action['source'], '--scope', 'user' -Utf8 -Label 'claude plugin install'

        if (Get-OSSetupClaudePlugin | Where-Object { $_.Id -eq $id -and -not $_.Enabled }) {
            Invoke-OSSetupNativeCommand -FilePath claude -ArgumentList 'plugin', 'enable', $id -Utf8 -Label 'claude plugin enable'
        }
    }
}
