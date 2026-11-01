# Provider appx : suppression d'une application du Store, pour tous les comptes, et déprovisionnement (sinon elle
# revient pour chaque nouveau compte). Une application absente est conforme.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'appx'

    Describe = {
        param($Action, $Context)
        "supprimer l'application $($Action['name']) (tous les comptes)"
    }

    Test     = {
        param($Action, $Context)
        $presence = Get-OSSetupAppxPresence -Name $Action['name']
        $presence.Installed.Count -eq 0 -and $presence.Provisioned.Count -eq 0
    }

    Read     = {
        param($Action, $Context)
        $presence = Get-OSSetupAppxPresence -Name $Action['name']
        [ordered]@{ installed = $presence.Installed; provisioned = $presence.Provisioned }
    }

    Invoke   = {
        param($Action, $Context)
        # Une mise à jour du Store en attente ou en cours s'achèverait après la suppression et réinstallerait
        # l'application (nouvelle version, reprovisionnée) : l'annuler d'abord.
        $cancelled = @(Stop-OSSetupStoreUpdate -Name $Action['name'])
        if ($cancelled.Count -gt 0) {
            Write-OSSetupLog -Level Detail -Message "  mise à jour du Store annulée ($($cancelled -join ', '))"
        }
        $presence = Get-OSSetupAppxPresence -Name $Action['name']
        # Ordre imposé : tant qu'une application est provisionnée, sa suppression pour tous les comptes échoue
        # (0x80073CFA, « Échec de la suppression »). Déprovisionner d'abord.
        foreach ($package in $presence.Provisioned) {
            Remove-AppxProvisionedPackage -Online -PackageName $package -ErrorAction Stop | Out-Null
        }
        foreach ($package in $presence.Installed) {
            Remove-AppxPackage -Package $package -AllUsers -ErrorAction Stop
        }
    }
}
