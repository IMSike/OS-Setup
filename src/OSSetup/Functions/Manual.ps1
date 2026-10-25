function Get-OSSetupWslDistribution {
    <#
    .SYNOPSIS
        Distributions WSL enregistrées pour le compte courant (registre Lxss) : nom et utilisateur par défaut (0 : root,
        compte Linux pas encore créé).
    #>
    [CmdletBinding()]
    param()
    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path -Path $root)) { return }
    foreach ($key in Get-ChildItem -Path $root) {
        $name = $key.GetValue('DistributionName')
        if (-not $name) { continue }
        [pscustomobject]@{ Name = $name; DefaultUid = [int]$key.GetValue('DefaultUid', 0) }
    }
}

function Test-OSSetupManualStep {
    <#
    .SYNOPSIS
        Vérifie le résultat d'une étape manuelle. Chaque vérification est écrite dans le moteur (pas de code dans les données).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Value
    )
    switch ($Check) {
        'gh-auth' {
            if (-not (Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
            & gh auth status --hostname github.com *> $null
            return ($LASTEXITCODE -eq 0)
        }
        'default-browser' {
            # Navigateur par défaut : programme associé au protocole https (choix de l'utilisateur, protégé par Windows).
            $choice = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue
            return [bool]($choice -and $choice.PSObject.Properties['ProgId'] -and $choice.ProgId -like $Value)
        }
        'wsl-user' {
            return [bool](Get-OSSetupWslDistribution | Where-Object { $_.Name -eq $Value -and $_.DefaultUid -ne 0 })
        }
        default { throw "Vérification inconnue : '$Check'." }
    }
}

function Start-OSSetupManualAssist {
    <#
    .SYNOPSIS
        Lance l'aide d'une étape manuelle : la page de Paramètres concernée, ou la commande à compléter.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Value
    )
    if (-not $PSCmdlet.ShouldProcess($Check, 'Lancer l''aide de l''étape manuelle')) { return }
    switch ($Check) {
        'gh-auth' {
            # Dans cette console : gh affiche un code à usage unique puis ouvre la page de connexion. Le navigateur est
            # ouvert par l'Explorateur, donc sans les droits administrateur du setup.
            $previous = $env:GH_BROWSER
            try {
                $env:GH_BROWSER = 'explorer.exe'
                & gh auth login --hostname github.com --git-protocol https --web
            }
            finally {
                $env:GH_BROWSER = $previous
            }
        }
        'default-browser' {
            Start-Process -FilePath 'ms-settings:defaultapps'
        }
        'wsl-user' {
            # Nouvelle fenêtre : installation de la distribution si besoin, puis, à son premier lancement, création du
            # compte Linux (nom et mot de passe demandés par la distribution elle-même).
            $arguments = if (Get-OSSetupWslDistribution | Where-Object { $_.Name -eq $Value }) { @('--distribution', $Value) }
            else { @('--install', '--distribution', $Value) }
            Start-Process -FilePath 'wsl.exe' -ArgumentList $arguments
        }
        default { throw "Vérification inconnue : '$Check'." }
    }
}

function Invoke-OSSetupManualStep {
    <#
    .SYNOPSIS
        Étape manuelle guidée : affiche les instructions, lance l'aide, puis vérifie le résultat quand l'utilisateur le
        demande. Sans surveillance (-Yes, fichier de réponses rejoué sans console), l'étape est signalée à faire plus tard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    if (-not $Context['Interactive']) {
        throw "étape manuelle, à faire plus tard (exécution sans surveillance) : $($Action['instructions'])"
    }
    Write-Host -Object ''
    Write-Host -Object "Étape manuelle : $($Action['instructions'])" -ForegroundColor Cyan
    Start-OSSetupManualAssist -Check $Action['check'] -Value $Action['value'] -Confirm:$false
    while ($true) {
        $options = @(
            [pscustomobject]@{ Value = 'check'; Label = 'C''est fait : vérifier' }
            [pscustomobject]@{ Value = 'assist'; Label = 'Relancer l''aide' }
            [pscustomobject]@{ Value = 'skip'; Label = 'Passer (à faire plus tard)' }
        )
        $result = Read-OSSetupMenu -State (New-OSSetupMenuState -Title 'Étape manuelle' -Option $options -Mode action)
        switch ($result.Values[0]) {
            'check' {
                if (Test-OSSetupManualStep -Check $Action['check'] -Value $Action['value']) { return }
                Write-Host -Object 'Pas encore fait : vérifiez les instructions ci-dessus.' -ForegroundColor Yellow
            }
            'assist' { Start-OSSetupManualAssist -Check $Action['check'] -Value $Action['value'] -Confirm:$false }
            'skip' { throw 'étape manuelle passée, à faire plus tard.' }
        }
    }
}
