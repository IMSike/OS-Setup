# Provider install-script : logiciel installé par le script officiel de son éditeur (ex. irm https://herdr.dev/install.ps1
# | iex), quand il n'est pas dans winget ou que le script est la méthode recommandée (mises à jour automatiques).
# Le script est exécuté tel que publié, dans Windows PowerShell : il s'installe dans le profil du compte. Seules des
# adresses https sont acceptées (schéma) ; elles sont relues à chaque ajout au catalogue.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'install-script'

    Describe = {
        param($Action, $Context)
        "script d'installation officiel $($Action['url'])"
    }

    Test     = {
        param($Action, $Context)
        # Un script lancé dans une autre session a pu modifier le PATH dans le registre.
        Update-OSSetupSessionPath
        [bool](Get-Command -Name $Action['command'] -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)
    }

    Invoke   = {
        param($Action, $Context)
        $command = "`$ProgressPreference = 'SilentlyContinue'; Invoke-RestMethod -Uri '$($Action['url'] -replace "'", "''")' | Invoke-Expression"
        # Sortie en UTF-8 (sinon accents et symboles corrompus dans le journal).
        $previousEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $command" 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            [Console]::OutputEncoding = $previousEncoding
        }
        foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
        if ($exitCode -ne 0) { throw "le script d'installation a échoué (code $exitCode)." }
        Update-OSSetupSessionPath
    }
}
