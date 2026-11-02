# Provider install-script : logiciel installé par le script officiel de son éditeur (ex. irm https://herdr.dev/install.ps1
# | iex), quand il n'est pas dans winget ou que le script est la méthode recommandée (mises à jour automatiques).
# Le script est exécuté tel que servi par l'adresse au moment de l'installation, dans Windows PowerShell, sans droits
# administrateur (Invoke-OSSetupUnelevatedCommand : tâche planifiée ponctuelle à jeton limité) : il s'installe dans le
# profil du compte et n'a pas besoin des droits du setup. Seules des adresses https sont acceptées (schéma) ; elles sont
# relues à chaque ajout au catalogue.

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
        Invoke-OSSetupUnelevatedCommand -Command $command -Label "le script d'installation"
        Update-OSSetupSessionPath
    }
}
