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
        # Pendant le plan, l'export (lu une fois) est consulté avant winget list, lent pour chaque paquet.
        Test-OSSetupWingetInstalled -Id $Action['id'] -ExportFirst:([bool]$Context['Planning'])
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

        # winget écrit en UTF-8. Les barres de progression n'ont pas d'intérêt dans le journal : indicateur d'attente
        # (- \ | /), et barre suivie, sur la même ligne, de la taille téléchargée (« ███▒▒  1024 KB / 6.48 MB ») ou d'un
        # pourcentage. Le code de sortie est interprété ci-dessous (certains codes non nuls sont des succès).
        $progress = '^[\s\-\\|/█▒]+$|^[\s█▒]*\d+(\.\d+)?\s*[KMG]?B\s*/\s*\d+(\.\d+)?\s*[KMG]?B\s*$|^[\s█▒]*\d+\s*%\s*$'
        $exitCode = (Invoke-OSSetupNativeCommand -FilePath winget -ArgumentList $arguments -Utf8 -NoThrow -PassThru -LogFilter $progress).ExitCode
        # 0x8A150109 : installé, redémarrage nécessaire pour terminer ; 3010 : code MSI équivalent.
        $rebootRequired = $exitCode -in -1978334967, 3010
        # 0x8A15002B : déjà installé, aucune mise à jour applicable.
        if ($exitCode -ne 0 -and $exitCode -ne -1978335189 -and -not $rebootRequired) {
            throw ('winget a échoué (code 0x{0:X8}).' -f $exitCode)
        }
        # Certains installeurs rendent la main avant d'avoir fini (ex. Squirrel pour Discord : l'installation continue
        # en arrière-plan une dizaine de secondes) : attendre que le paquet soit détecté.
        # Le premier sondage relit l'export (paquet que seul l'export rattache) ; les suivants s'en tiennent à winget list,
        # l'export complet étant lourd. Il est relu une dernière fois si le paquet n'a pas été trouvé (cache à jour).
        $deadline = (Get-Date).AddSeconds(60)
        $found = $false
        $firstPoll = $true
        while (-not $rebootRequired -and (Get-Date) -lt $deadline) {
            $found = Test-OSSetupWingetInstalled -Id $Action['id'] -Refresh:$firstPoll -ListOnly:(-not $firstPoll)
            if ($found) { break }
            $firstPoll = $false
            Start-Sleep -Seconds 3
        }
        if (-not $rebootRequired -and -not $found -and -not $firstPoll) {
            Get-OSSetupWingetExportId -Refresh | Out-Null
        }
        # L'installeur a pu modifier le PATH dans le registre : la session doit le voir pour les étapes suivantes.
        Update-OSSetupSessionPath
        if ($rebootRequired) { @{ RebootRequired = $true } }
    }
}
