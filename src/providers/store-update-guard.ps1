# Provider store-update-guard : mises à jour d'une application du Store sans fermeture forcée (ADR 0004). Bloque ses
# mises à jour automatiques et confie la mise à jour à des tâches planifiées qui attendent qu'elle soit fermée, ou
# proposent de la fermer. Voir Functions/StoreUpdate.ps1.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'store-update-guard'

    Describe = {
        param($Action, $Context)
        "$($Action['name']) : mises à jour du Store sans fermeture forcée (blocage et tâches planifiées)"
    }

    Test     = {
        param($Action, $Context)
        # Le blocage ne se lit qu'avec les droits administrateur : sans eux (simulation), l'action reste à faire.
        if (-not (Test-OSSetupElevated)) { return $false }
        Test-OSSetupStoreUpdateGuard -Action $Action -SourceRoot (Join-Path -Path $Context.Root -ChildPath 'src\store-update')
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{
            doNotUpdate = if (Test-OSSetupElevated) { Get-OSSetupDoNotUpdate -Family $Action['family'] }
            tasks       = @(Get-ScheduledTask -TaskName 'OS-Setup - Store*' -ErrorAction SilentlyContinue | ForEach-Object { $_.TaskName })
        }
    }

    Invoke   = {
        param($Action, $Context)
        Install-OSSetupStoreUpdateGuard -Action $Action -SourceRoot (Join-Path -Path $Context.Root -ChildPath 'src\store-update')
    }
}
