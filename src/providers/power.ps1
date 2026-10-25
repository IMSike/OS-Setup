# Provider power : délai d'un paramètre d'alimentation du mode actif, sur secteur (ac) ou batterie (dc).
# Lecture par powercfg /query : les deux dernières valeurs hexadécimales sont l'index actuel secteur puis
# batterie, quelle que soit la langue de Windows. Valeur en secondes, 0 = jamais.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'power'

    Describe = {
        param($Action, $Context)
        $labels = @{ standby = 'mise en veille'; hibernate = 'veille prolongée'; display = 'extinction de l''écran' }
        $source = if ($Action['source'] -eq 'ac') { 'sur secteur' } else { 'sur batterie' }
        $delay = if ($Action['seconds'] -eq 0) { 'jamais' } else { "après $(Format-OSSetupDuration -Seconds $Action['seconds'])" }
        "$($labels[$Action['setting']]) $source : $delay"
    }

    Test     = {
        param($Action, $Context)
        (Get-OSSetupPowerValue -Setting $Action['setting'] -Source $Action['source']) -eq $Action['seconds']
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{ seconds = Get-OSSetupPowerValue -Setting $Action['setting'] -Source $Action['source'] }
    }

    Invoke   = {
        param($Action, $Context)
        Set-OSSetupPowerValue -Setting $Action['setting'] -Source $Action['source'] -Seconds $Action['seconds'] -Confirm:$false
    }
}
