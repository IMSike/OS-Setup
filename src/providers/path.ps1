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

    Test     = {
        param($Action, $Context)
        $scope = if ($Action['scope'] -eq 'machine') { 'Machine' } else { 'User' }
        $wanted = $Action['path'].TrimEnd('\')
        [bool](Get-OSSetupPathEntry -Scope $scope | Where-Object { $_.TrimEnd('\') -eq $wanted })
    }

    Invoke   = {
        param($Action, $Context)
        $scope = if ($Action['scope'] -eq 'machine') { 'Machine' } else { 'User' }
        Add-OSSetupPathEntry -Path $Action['path'] -Scope $scope -Confirm:$false
    }
}
