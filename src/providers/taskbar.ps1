# Provider taskbar : comportement de la barre des tâches, réglé par l'API prévue pour (SHAppBarMessage) comme le fait
# la case de Paramètres : effet immédiat, mémorisé par l'Explorateur. Écrire la valeur binaire StuckRects3 (qui contient
# aussi la position et la taille de la barre) ne prendrait effet qu'au redémarrage de l'Explorateur, qui la réécrit
# lui-même en se fermant : le réglage pourrait être perdu.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'taskbar'

    Describe = {
        param($Action, $Context)
        "barre des tâches : masquage automatique $(if ($Action['autoHide']) { 'activé' } else { 'désactivé' })"
    }

    Test     = {
        param($Action, $Context)
        (Get-OSSetupTaskbarAutoHide) -eq [bool]$Action['autoHide']
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{ autoHide = Get-OSSetupTaskbarAutoHide }
    }

    Invoke   = {
        param($Action, $Context)
        Set-OSSetupTaskbarAutoHide -Enabled ([bool]$Action['autoHide']) -Confirm:$false
    }
}
