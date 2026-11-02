# Provider win32-uninstall : désinstallation silencieuse d'un logiciel classique, d'après son entrée dans
# « Programmes et fonctionnalités » (nom affiché, caractères génériques acceptés). Un logiciel absent est conforme.
# Le PowerShell qui exécute le setup (ex. MSI de PowerShell 7) n'est pas désinstallé pendant le setup : la commande
# est confiée au nettoyage de fin, qui la lance après la fermeture du setup (statut « atclose »).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'win32-uninstall'

    Describe = {
        param($Action, $Context)
        $description = "désinstaller $($Action['displayName'])"
        # PowerShell qui exécute le setup : le désinstaller maintenant arrêterait le setup en cours.
        if (Get-OSSetupUninstallEntry -DisplayName $Action['displayName'] | Where-Object { Test-OSSetupUninstallEntryHostsSetup -Entry $_ }) {
            $description += ' (à la fermeture du setup, qui s''exécute sous ce PowerShell)'
        }
        $description
    }

    Test     = {
        param($Action, $Context)
        -not (Get-OSSetupUninstallEntry -DisplayName $Action['displayName'])
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{
            installed = @(Get-OSSetupUninstallEntry -DisplayName $Action['displayName'] | ForEach-Object {
                    [ordered]@{ displayName = $_.DisplayName; version = $_.DisplayVersion; uninstallString = $_.UninstallString }
                })
        }
    }

    Invoke   = {
        param($Action, $Context)
        $restart = $false
        $atClose = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in Get-OSSetupUninstallEntry -DisplayName $Action['displayName']) {
            $command = ConvertTo-OSSetupUninstallCommand -Entry $entry -Arguments $Action['arguments']
            if (Test-OSSetupUninstallEntryHostsSetup -Entry $entry) {
                # Le setup s'exécute sous ce logiciel (MSI de PowerShell 7) : le nettoyage de fin le désinstalle
                # après la fermeture du setup. Si un redémarrage intervient avant, la reprise tourne sous le
                # PowerShell du Store et la désinstallation se fait alors normalement.
                $atClose.Add([ordered]@{
                        displayName = [string]$entry.DisplayName
                        registryKey = [string]$entry.PSPath
                        filePath    = $command.FilePath
                        arguments   = $command.Arguments
                    })
                Write-OSSetupLog -Level Detail -Message "  « $($entry.DisplayName) » exécute le setup : désinstallation reportée à la fermeture du setup"
                continue
            }
            $process = Start-Process -FilePath $command.FilePath -ArgumentList $command.Arguments -Wait -PassThru -WindowStyle Hidden
            switch ($process.ExitCode) {
                0 { }
                3010 { $restart = $true }
                default {
                    # Certains désinstalleurs rendent un code trompeur ou finissent en arrière-plan (ex. OneDrive :
                    # partie « par compte » réussie, partie « machine » sans objet → 0x8004069B). Fait foi : l'entrée
                    # a-t-elle disparu de « Programmes et fonctionnalités » ?
                    $code = '0x{0:X8}' -f $process.ExitCode
                    if (-not (Wait-OSSetupUninstallEntryRemoval -DisplayName $entry.DisplayName -TimeoutSeconds 60)) {
                        throw "La désinstallation de « $($entry.DisplayName) » a échoué (code $code)."
                    }
                    Write-OSSetupLog -Level Detail -Message "  code de retour $code, mais le logiciel est bien désinstallé"
                }
            }
        }
        if ($restart) { @{ RebootRequired = $true } }
        if ($atClose.Count -gt 0) { @{ RunAtClose = $atClose.ToArray() } }
    }
}
