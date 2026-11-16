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

    # Git écrit en UTF-8 : lue avec la page de code de la console, une valeur accentuée (ex. un nom) ne serait jamais
    # égale à celle du catalogue. La valeur lue n'est pas journalisée (lecture répétée à chaque test). Seule la sortie
    # standard est la valeur : un avertissement de Git (sortie d'erreur, mêlée à la sortie) n'en fait pas partie.
    Test     = {
        param($Action, $Context)
        if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
        $result = Invoke-OSSetupNativeCommand -FilePath git -ArgumentList 'config', '--global', '--get', $Action['key'] -Utf8 -NoThrow -PassThru -NoLog
        $value = @($result.Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
        $result.ExitCode -eq 0 -and $value -ceq $Action['value']
    }

    Read     = {
        param($Action, $Context)
        if (-not (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) { return [ordered]@{ exists = $false } }
        $result = Invoke-OSSetupNativeCommand -FilePath git -ArgumentList 'config', '--global', '--get', $Action['key'] -Utf8 -NoThrow -PassThru -NoLog
        $value = @($result.Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n"
        if ($result.ExitCode -eq 0) { [ordered]@{ exists = $true; value = $value } } else { [ordered]@{ exists = $false } }
    }

    Invoke   = {
        param($Action, $Context)
        Invoke-OSSetupNativeCommand -FilePath git -ArgumentList 'config', '--global', $Action['key'], $Action['value'] -Utf8 -Label 'git config'
    }
}
