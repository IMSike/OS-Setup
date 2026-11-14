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
        if ($Action['present'] -eq $false) { return -not $exists }
        if (-not $exists) { return $false }
        # Un raccourci du même nom qui pointe ailleurs n'est pas conforme. Source absente (logiciel pas encore
        # installé) : rien à comparer, le raccourci présent est gardé.
        if (-not (Test-Path -LiteralPath $Action['from'])) { return $true }
        (Get-OSSetupShortcutTarget -Path $Action['path']) -eq (Get-OSSetupShortcutTarget -Path $Action['from'])
    }

    Read     = {
        param($Action, $Context)
        if (-not (Test-Path -LiteralPath $Action['path'])) { return [ordered]@{ exists = $false } }
        [ordered]@{ exists = $true; target = Get-OSSetupShortcutTarget -Path $Action['path'] }
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
        if (Test-Path -LiteralPath $Action['path']) {
            # Raccourci du même nom vers une autre cible : sauvegardé avant d'être remplacé.
            $backup = Backup-OSSetupFile -Path $Action['path'] -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
        }
        New-Item -Path (Split-Path -Path $Action['path'] -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $Action['from'] -Destination $Action['path'] -Force
    }
}
