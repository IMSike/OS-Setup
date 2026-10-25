# Provider manual : étape non automatisable (connexion à un compte, choix protégé par Windows…). Le moteur affiche les
# instructions, lance l'aide (page de Paramètres, commande à compléter) et vérifie le résultat avant de continuer.
# Les vérifications et les aides sont écrites dans le moteur (Manual.ps1) : les données ne choisissent que laquelle.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'manual'

    Describe = {
        param($Action, $Context)
        "étape manuelle : $($Action['instructions'])"
    }

    Test     = {
        param($Action, $Context)
        Test-OSSetupManualStep -Check $Action['check'] -Value $Action['value']
    }

    Invoke   = {
        param($Action, $Context)
        Invoke-OSSetupManualStep -Action $Action -Context $Context
    }
}
