# Provider windows-feature : activation (ou désactivation, enabled = false) d'une fonctionnalité facultative de Windows.
# dism.exe plutôt que le module Dism : toujours présent, sortie en anglais avec /English, code 3010 = redémarrage requis.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'windows-feature'

    Describe = {
        param($Action, $Context)
        $verb = if ($Action['enabled'] -eq $false) { 'désactiver' } else { 'activer' }
        "$verb la fonctionnalité Windows $($Action['name'])"
    }

    Test     = {
        param($Action, $Context)
        $wantEnabled = $Action['enabled'] -ne $false
        if (Test-OSSetupElevated) {
            # « Enable Pending » (activée, redémarrage en attente) n'est pas conforme : l'activation est relancée
            # et signale de nouveau le redémarrage nécessaire. Idem pour « Disable Pending ».
            $output = & dism.exe /English /Online /Get-FeatureInfo "/FeatureName:$($Action['name'])"
            if ($LASTEXITCODE -ne 0) { throw "Fonctionnalité '$($Action['name'])' introuvable (dism, code $LASTEXITCODE)." }
            if ($wantEnabled) { return [bool]($output -match '^State : Enabled$') }
            return [bool]($output -match '^State : Disabled')
        }
        # Sans droits administrateur (simulation) : lecture CIM, 1 = activée, 2 = désactivée.
        $feature = Get-CimInstance -ClassName Win32_OptionalFeature -Filter "Name='$($Action['name'])'"
        if (-not $feature) { throw "Fonctionnalité '$($Action['name'])' introuvable." }
        if ($wantEnabled) { $feature.InstallState -eq 1 } else { $feature.InstallState -ne 1 }
    }

    Read     = {
        param($Action, $Context)
        $output = & dism.exe /English /Online /Get-FeatureInfo "/FeatureName:$($Action['name'])"
        $state = $output | Where-Object { $_ -match '^State : ' } | Select-Object -First 1
        [ordered]@{ state = if ($state) { $state -replace '^State : ', '' } else { $null } }
    }

    Invoke   = {
        param($Action, $Context)
        $output = if ($Action['enabled'] -eq $false) {
            & dism.exe /English /Online /Disable-Feature "/FeatureName:$($Action['name'])" /NoRestart
        }
        else {
            & dism.exe /English /Online /Enable-Feature "/FeatureName:$($Action['name'])" /All /NoRestart
        }
        switch ($LASTEXITCODE) {
            0 { }
            3010 { @{ RebootRequired = $true } }
            default { throw "dism a échoué (code $LASTEXITCODE) : $(($output | Where-Object { $_ -match 'Error' }) -join ' ')" }
        }
    }
}
