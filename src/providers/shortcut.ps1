# Provider shortcut : raccourci (.lnk) présent ou absent. Présent : copie d'un raccourci existant (from, ex. celui
# du menu Démarrer créé par l'installeur) ou création vers une cible (target). Absent : suppression (ex. raccourci
# déposé sur le bureau par un installeur).

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
            Remove-Item -LiteralPath $Action['path'] -Force
            return
        }
        New-Item -Path (Split-Path -Path $Action['path'] -Parent) -ItemType Directory -Force | Out-Null
        if ($Action['from']) {
            if (-not (Test-Path -LiteralPath $Action['from'])) { throw "Raccourci source introuvable : $($Action['from'])." }
            Copy-Item -LiteralPath $Action['from'] -Destination $Action['path'] -Force
            return
        }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($Action['path'])
        $shortcut.TargetPath = $Action['target']
        if ($Action['arguments']) { $shortcut.Arguments = $Action['arguments'] }
        $shortcut.Save()
    }
}
