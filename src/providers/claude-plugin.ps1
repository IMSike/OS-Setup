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
        $previousEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            # Déjà installé : la commande réussit sans rien changer.
            $output = & claude plugin install $Action['plugin'] --marketplace $Action['source'] --scope user 2>&1
            $exitCode = $LASTEXITCODE
            foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
            if ($exitCode -ne 0) { throw "claude plugin install a échoué (code $exitCode)." }

            if (Get-OSSetupClaudePlugin | Where-Object { $_.Id -eq $id -and -not $_.Enabled }) {
                $output = & claude plugin enable $id 2>&1
                $exitCode = $LASTEXITCODE
                foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
                if ($exitCode -ne 0) { throw "claude plugin enable a échoué (code $exitCode)." }
            }
        }
        finally {
            [Console]::OutputEncoding = $previousEncoding
        }
    }
}
