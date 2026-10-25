# Provider startup-entry : lancement d'un logiciel à l'ouverture de session (clé Run), désactivé comme le fait le
# Gestionnaire des tâches (onglet Démarrage) : l'entrée reste, une valeur de StartupApproved la marque « désactivée ».
# Un logiciel qui recrée son entrée à chaque mise à jour reste ainsi désactivé. Nom avec * accepté (ex. Edge :
# MicrosoftEdgeAutoLaunch_<empreinte>). Aucune entrée correspondante : conforme (rien à lancer).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'startup-entry'

    Describe = {
        param($Action, $Context)
        $scope = if ($Action['scope'] -eq 'machine') { 'tous les comptes' } else { 'compte courant' }
        "ne pas lancer « $($Action['name']) » à l'ouverture de session ($scope)"
    }

    Test     = {
        param($Action, $Context)
        foreach ($entry in Get-OSSetupStartupEntry -Name $Action['name'] -Scope $(if ($Action['scope']) { $Action['scope'] } else { 'user' })) {
            if ($entry.Enabled) { return $false }
        }
        $true
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{
            entries = @(Get-OSSetupStartupEntry -Name $Action['name'] -Scope $(if ($Action['scope']) { $Action['scope'] } else { 'user' }) |
                    ForEach-Object { [ordered]@{ name = $_.Name; enabled = $_.Enabled; approvedKey = $_.ApprovedKey } })
        }
    }

    Invoke   = {
        param($Action, $Context)
        foreach ($entry in Get-OSSetupStartupEntry -Name $Action['name'] -Scope $(if ($Action['scope']) { $Action['scope'] } else { 'user' }) | Where-Object Enabled) {
            Disable-OSSetupStartupEntry -Entry $entry -Confirm:$false
        }
    }
}
