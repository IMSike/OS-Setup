# Provider winget : installation de paquets Windows.
# Présence : winget list --id, puis winget export en second avis (Test-OSSetupWingetInstalled).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'winget'

    Describe = {
        param($Action, $Context)
        "winget install $($Action['id'])"
    }

    Test     = {
        param($Action, $Context)
        Test-OSSetupWingetInstalled -Id $Action['id']
    }

    Invoke   = {
        param($Action, $Context)
        $arguments = @(
            'install', '--id', $Action['id'], '--exact', '--source', 'winget', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        if ($Action['scope']) { $arguments += @('--scope', $Action['scope']) }
        if ($Action['installerType']) { $arguments += @('--installer-type', $Action['installerType']) }
        if ($Action['location']) { $arguments += @('--location', $Action['location']) }
        if ($Action['override']) { $arguments += @('--override', $Action['override']) }

        # winget écrit en UTF-8 ; sans ce réglage, PowerShell décode sa sortie avec la page de code OEM (accents corrompus).
        $previousEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $output = & winget @arguments 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            [Console]::OutputEncoding = $previousEncoding
        }
        # 0x8A150019 : le paquet exige que winget lui-même soit lancé en administrateur (ex. MSI de PowerShell).
        if ($exitCode -eq -1978335207 -and -not (Test-OSSetupElevated)) {
            Write-OSSetupLog -Level Detail -Message '  droits administrateur requis : relance de winget en mode élevé.'
            $quoted = foreach ($argument in $arguments) { if ($argument -match '\s') { "`"$argument`"" } else { $argument } }
            $process = Start-Process -FilePath 'winget' -ArgumentList $quoted -Verb RunAs -Wait -PassThru
            $exitCode = $process.ExitCode
        }
        foreach ($line in $output) {
            $text = "$line".Trim()
            # Les barres de progression de winget n'ont pas d'intérêt dans le journal.
            if ($text -and $text -notmatch '^[\s\-\\|/█▒]+$|^\d+(\.\d+)? [KMG]?B / ') {
                Write-OSSetupLog -Level Detail -Message "  $text"
            }
        }
        # 0x8A150109 : installé, redémarrage nécessaire pour terminer ; 3010 : code MSI équivalent.
        $rebootRequired = $exitCode -in -1978334967, 3010
        # 0x8A15002B : déjà installé, aucune mise à jour applicable.
        if ($exitCode -ne 0 -and $exitCode -ne -1978335189 -and -not $rebootRequired) {
            throw ('winget a échoué (code 0x{0:X8}).' -f $exitCode)
        }
        # Certains installeurs rendent la main avant d'avoir fini (ex. Squirrel pour Discord : l'installation continue
        # en arrière-plan une dizaine de secondes) : attendre que le paquet soit détecté.
        $deadline = (Get-Date).AddSeconds(60)
        while (-not $rebootRequired -and (Get-Date) -lt $deadline) {
            if (Test-OSSetupWingetInstalled -Id $Action['id'] -Refresh) { break }
            Start-Sleep -Seconds 3
        }
        # L'installeur a pu modifier le PATH dans le registre : la session doit le voir pour les étapes suivantes.
        Update-OSSetupSessionPath
        if ($rebootRequired) { @{ RebootRequired = $true } }
    }
}
