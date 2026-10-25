# Provider win32-uninstall : désinstallation silencieuse d'un logiciel classique, d'après son entrée dans
# « Programmes et fonctionnalités » (nom affiché, caractères génériques acceptés). Un logiciel absent est conforme.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'win32-uninstall'

    Describe = {
        param($Action, $Context)
        "désinstaller $($Action['displayName'])"
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
        foreach ($entry in Get-OSSetupUninstallEntry -DisplayName $Action['displayName']) {
            $command = ConvertTo-OSSetupUninstallCommand -Entry $entry -Arguments $Action['arguments']
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
    }
}
