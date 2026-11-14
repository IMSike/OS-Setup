# Provider shortcut : raccourci (.lnk) présent ou absent. Présent : copie d'un raccourci existant (from, ex. celui
# du menu Démarrer créé par l'installeur). Absent : suppression, avec sauvegarde (ex. raccourci déposé sur le bureau
# par un installeur).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'shortcut'

    Describe = {
        param($Action, $Context)
        if ($Action['present'] -eq $false) { "supprimer le raccourci $($Action['path'])" } else { "créer le raccourci $($Action['path'])" }
    }

    Test     = {
        param($Action, $Context)
        $exists = Test-Path -LiteralPath $Action['path']
        if ($Action['present'] -eq $false) { -not $exists } else { $exists }
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{ exists = Test-Path -LiteralPath $Action['path'] }
    }

    Invoke   = {
        param($Action, $Context)
        if ($Action['present'] -eq $false) {
            # Raccourci retiré : sauvegardé avant, comme un fichier supprimé par le provider file.
            $backup = Backup-OSSetupFile -Path $Action['path'] -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
            Remove-Item -LiteralPath $Action['path'] -Force
            return
        }
        if (-not (Test-Path -LiteralPath $Action['from'])) { throw "Raccourci source introuvable : $($Action['from'])." }
        New-Item -Path (Split-Path -Path $Action['path'] -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $Action['from'] -Destination $Action['path'] -Force
    }
}
