# Provider windows-update : installe ce que Windows Update propose pour une catégorie (pour l'instant : pilotes),
# par l'API intégrée (objet COM), sans module tiers. Conforme quand Windows Update ne propose plus rien.
# Un redémarrage demandé par Windows est signalé au moteur (reprise automatique).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'windows-update'

    Describe = {
        param($Action, $Context)
        # La recherche est mémorisée : elle sert aussi au test qui suit.
        $titles = @(Find-OSSetupWindowsUpdate -Category $Action['category'] | ForEach-Object { [string]$_.Title })
        if ($titles.Count -eq 0) { return 'pilotes proposés par Windows Update : aucun' }
        "installer $($titles.Count) pilote(s) proposé(s) par Windows Update : $($titles -join ' ; ')"
    }

    Test     = {
        param($Action, $Context)
        @(Find-OSSetupWindowsUpdate -Category $Action['category']).Count -eq 0
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{ pending = @(Find-OSSetupWindowsUpdate -Category $Action['category'] | ForEach-Object { [string]$_.Title }) }
    }

    Invoke   = {
        param($Action, $Context)
        $updates = @(Find-OSSetupWindowsUpdate -Category $Action['category'])
        foreach ($update in $updates) { Write-OSSetupLog -Level Detail -Message "  $($update.Title)" }
        $outcome = Install-OSSetupWindowsUpdate -Update $updates -Confirm:$false
        if ($outcome.Failed.Count -gt 0) {
            throw "installation en échec : $($outcome.Failed -join ' ; ')"
        }
        if ($outcome.RebootRequired) { @{ RebootRequired = $true } }
    }
}
