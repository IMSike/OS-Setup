# Provider desktop-layout : barre des tâches et menu Démarrer, d'après les éléments retenus (champs taskbarPin et
# startLayout). Une seule action pour toute la disposition : Windows 10 ne sait l'appliquer qu'en bloc.
# Conforme quand la disposition voulue a déjà été appliquée (empreinte enregistrée) : les changements faits ensuite
# par l'utilisateur sont respectés, tant que les choix du setup ne changent pas.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'desktop-layout'

    Describe = {
        param($Action, $Context)
        $layout = Get-OSSetupDesktopLayout -Context $Context
        $parts = @()
        if (@($layout.Pins).Count -gt 0) { $parts += "barre des tâches : $(($layout.Pins | ForEach-Object { $_.Name }) -join ', ')" }
        if ($layout.EmptyStart) { $parts += 'menu Démarrer sans vignette' }
        if (-not $parts) { return 'disposition de la barre des tâches et du menu Démarrer : rien à changer' }
        $parts -join ' ; '
    }

    Test     = {
        param($Action, $Context)
        $layout = Get-OSSetupDesktopLayout -Context $Context
        if (@($layout.Pins).Count -eq 0 -and -not $layout.EmptyStart) { return $true }
        (Get-OSSetupDesktopLayoutMarker) -eq (Get-OSSetupLayoutHash -Xml (ConvertTo-OSSetupLayoutXml -Layout $layout))
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{ taskbarPins = @(Get-OSSetupTaskbarPinName); appliedLayout = Get-OSSetupDesktopLayoutMarker }
    }

    Invoke   = {
        param($Action, $Context)
        $layout = Get-OSSetupDesktopLayout -Context $Context
        Write-OSSetupLog -Level Detail -Message "  redémarrage de l'Explorateur (les fenêtres de l'Explorateur ouvertes se ferment)"
        Set-OSSetupDesktopLayout -Layout $layout -Confirm:$false
    }
}
