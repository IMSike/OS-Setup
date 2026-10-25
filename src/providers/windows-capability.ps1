# Provider windows-capability : retrait d'une capacité Windows (« Fonctionnalités facultatives » de Paramètres :
# Internet Explorer, WordPad…). Le nom est donné sans version (« Browser.InternetExplorer ») ; * accepté pour une
# partie propre à une version de Windows (« Hello.Face.* » pour « Hello.Face.18967 »). Admin requis.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'windows-capability'

    Describe = {
        param($Action, $Context)
        "retirer le composant Windows $($Action['name'])"
    }

    Test     = {
        param($Action, $Context)
        # La lecture des capacités exige les droits administrateur : sans eux (simulation), l'action reste à faire.
        if (-not (Test-OSSetupElevated)) { return $false }
        $matching = @(Get-WindowsCapability -Online | Where-Object { $_.Name -like "$($Action['name'])~*" })
        # Un nom qui ne correspond à aucune capacité (faute, nom propre à une version) ne doit pas passer pour conforme.
        if ($matching.Count -eq 0) { throw "Aucune capacité Windows ne correspond à '$($Action['name'])'." }
        -not ($matching | Where-Object { $_.State -eq 'Installed' })
    }

    Read     = {
        param($Action, $Context)
        [ordered]@{
            installed = @(Get-WindowsCapability -Online | Where-Object { $_.Name -like "$($Action['name'])~*" -and $_.State -eq 'Installed' } |
                    ForEach-Object { [string]$_.Name })
        }
    }

    Invoke   = {
        param($Action, $Context)
        $restart = $false
        foreach ($capability in Get-WindowsCapability -Online | Where-Object { $_.Name -like "$($Action['name'])~*" -and $_.State -eq 'Installed' }) {
            $result = Remove-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
            if ($result.RestartNeeded) { $restart = $true }
        }
        if ($restart) { @{ RebootRequired = $true } }
    }
}
