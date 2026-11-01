# Provider npm-global : paquet npm installé globalement (commande disponible partout, ex. tsc), pour la version de
# Node.js par défaut. Une autre version de Node.js (projet, fnm) a ses propres paquets globaux.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', '', Justification = 'npm est une commande externe : ses arguments ne sont pas des paramètres PowerShell.')]
param()

@{
    Name     = 'npm-global'

    Describe = {
        param($Action, $Context)
        "npm install --global $($Action['package'])"
    }

    Test     = {
        param($Action, $Context)
        if (-not (Get-Command -Name npm -ErrorAction SilentlyContinue)) { return $false }
        & npm ls --global $Action['package'] --depth=0 *> $null
        $LASTEXITCODE -eq 0
    }

    Invoke   = {
        param($Action, $Context)
        Invoke-OSSetupNativeCommand -FilePath npm -ArgumentList 'install', '--global', $Action['package'] -Label 'npm install'
    }
}
