# Provider path : ajout d'un dossier à la variable PATH (utilisateur ou machine), pour les logiciels
# dont l'installeur ne le fait pas lui-même (ex. outils portables).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'path'

    Describe = {
        param($Action, $Context)
        $scope = if ($Action['scope'] -eq 'machine') { 'machine' } else { 'utilisateur' }
        "ajouter $($Action['path']) au PATH ($scope)"
    }

    # Portée « user » ou « machine » du catalogue, transmise telle quelle (les fonctions du PATH ignorent la casse).
    Test     = {
        param($Action, $Context)
        $wanted = $Action['path'].TrimEnd('\')
        @(Get-OSSetupPathEntry -Scope ($Action['scope'] ?? 'user') | Where-Object { $_.TrimEnd('\') -eq $wanted }).Count -gt 0
    }

    Invoke   = {
        param($Action, $Context)
        Add-OSSetupPathEntry -Path $Action['path'] -Scope ($Action['scope'] ?? 'user') -Confirm:$false
    }
}
