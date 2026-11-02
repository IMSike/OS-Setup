# Provider file : déploiement d'un fichier de dotfiles/ (copie, gabarit ou fusion JSON), avec sauvegarde de l'existant ;
# present = false : suppression du fichier (sauvegardé avant).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'file'

    Describe = {
        param($Action, $Context)
        if ($Action['present'] -eq $false) { return "supprimer $($Action['target'])" }
        "déployer $($Action['source']) → $($Action['target'])"
    }

    Test     = {
        param($Action, $Context)
        if ($Action['present'] -eq $false) { return -not (Test-Path -Path $Action['target'] -PathType Leaf) }
        if (-not (Test-Path -Path $Action['target'] -PathType Leaf)) { return $false }
        if ($Action['mode'] -eq 'merge-json') {
            # Conforme si les clés gérées ont déjà leur valeur, même si l'application a reformaté le fichier.
            $sourcePath = Join-Path -Path $Context.DotfilesRoot -ChildPath $Action['source']
            $managed = ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $sourcePath -Raw -Encoding utf8) -Name $sourcePath
            $current = ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $Action['target'] -Raw -Encoding utf8) -Name $Action['target']
            return Test-OSSetupJsonSubset -Json $current -Subset $managed
        }
        $expected = Get-OSSetupFileContent -Action $Action -Context $Context
        $current = [System.IO.File]::ReadAllBytes($Action['target'])
        [System.Linq.Enumerable]::SequenceEqual($expected, $current)
    }

    Invoke   = {
        param($Action, $Context)
        if ($Action['present'] -eq $false) {
            # Fichier retiré (ex. ancienne copie d'un script déplacé) : sauvegardé avant, comme un fichier remplacé.
            $backup = Backup-OSSetupFile -Path $Action['target'] -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
            Remove-Item -LiteralPath $Action['target'] -Force
            return
        }
        $expected = Get-OSSetupFileContent -Action $Action -Context $Context
        if (Test-Path -Path $Action['target'] -PathType Leaf) {
            $backup = Backup-OSSetupFile -Path $Action['target'] -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
        }
        New-Item -Path (Split-Path -Path $Action['target'] -Parent) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes($Action['target'], $expected)
    }
}
