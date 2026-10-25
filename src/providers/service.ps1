# Provider service : type de démarrage d'un service Windows (et arrêt s'il est désactivé).
# Un service absent est conforme : il n'y a rien à désactiver (certaines éditions ou versions ne l'ont pas).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'service'

    Describe = {
        param($Action, $Context)
        "service $($Action['name']) : démarrage $($Action['startupType'])"
    }

    Test     = {
        param($Action, $Context)
        $service = Get-Service -Name $Action['name'] -ErrorAction SilentlyContinue
        if (-not $service) { return $true }
        if ("$($service.StartType)" -ne $Action['startupType']) { return $false }
        $Action['startupType'] -ne 'Disabled' -or $service.Status -eq 'Stopped'
    }

    Read     = {
        param($Action, $Context)
        $service = Get-Service -Name $Action['name'] -ErrorAction SilentlyContinue
        if (-not $service) { return [ordered]@{ exists = $false } }
        [ordered]@{ exists = $true; startupType = "$($service.StartType)"; status = "$($service.Status)" }
    }

    Invoke   = {
        param($Action, $Context)
        Set-Service -Name $Action['name'] -StartupType $Action['startupType']
        if ($Action['startupType'] -eq 'Disabled') {
            Stop-Service -Name $Action['name'] -Force
        }
    }
}
