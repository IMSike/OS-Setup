<#
.SYNOPSIS
    Amorçage d'OS-Setup sur une machine Windows vierge (Windows PowerShell 5.1, sans module externe).
.DESCRIPTION
    1. Vérifie l'OS.
    2. Se relance en administrateur (une seule invite UAC pour tout le setup) et vérifie que le compte
       administrateur est bien celui de la session ouverte.
    3. Installe winget depuis sa publication officielle (github.com/microsoft/winget-cli) s'il est absent.
    4. Installe Git et PowerShell 7 (MSI) via winget s'ils sont absents.
    5. Clone (ou met à jour) le dépôt, sauf si le script est lancé depuis un clone existant, et note dans
       state\bootstrap.json ce que le nettoyage de fin pourra retirer.
    6. Lance setup.ps1 sous PowerShell 7 en lui transmettant les arguments restants.
    Avec -WhatIf (simulation) : aucune de ces étapes n'est faite, ni élévation, ni installation, ni clonage, ni
    écriture de state\bootstrap.json ; le script affiche ce qu'il ferait, puis lance « setup.ps1 -WhatIf » si
    PowerShell 7 et une copie du dépôt sont déjà présents, sinon explique pourquoi la simulation s'arrête là.
.EXAMPLE
    Depuis une machine vierge (le fichier est téléchargé pour préserver l'encodage UTF-8) :
    cd $env:TEMP
    irm https://raw.githubusercontent.com/IMSike/OS-Setup/main/bootstrap.ps1 -OutFile bootstrap.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
.EXAMPLE
    Depuis un clone existant, en simulation :
    powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -WhatIf
#>
# PositionalBinding désactivé : sinon une valeur transmise sous forme de texte (ex. « -AnswerFile » venant
# d'un tableau) serait affectée à RepoUrl, Branch… au lieu d'être transmise à setup.ps1.
# Pas de SupportsShouldProcess : -WhatIf est un argument de setup.ps1 (SetupArguments). Test-WhatIfArgument le
# reconnaît et Show-BootstrapSimulation remplace alors toutes les étapes qui modifient la machine.
[CmdletBinding(PositionalBinding = $false)]
param(
    # Dépôt à cloner quand le script n'est pas lancé depuis une copie du dépôt.
    [string]$RepoUrl = 'https://github.com/IMSike/OS-Setup.git',

    # Branche à cloner, ou vers laquelle basculer une copie existante de Destination sans modification locale. Sans
    # effet quand le script est lancé depuis une copie du dépôt.
    [string]$Branch = 'main',

    # Dossier où cloner le dépôt (ou mettre à jour une copie existante).
    [string]$Destination = (Join-Path -Path $env:USERPROFILE -ChildPath 'OS-Setup'),

    # Ne pas attendre Entrée avant de fermer la fenêtre administrateur (transmis à la relance élevée).
    [switch]$NoPause,

    # Usage interne : indique que le script a été relancé dans une fenêtre administrateur.
    [switch]$Relaunched,

    # Arguments transmis à setup.ps1 (ex. -WhatIf, -AnswerFile <chemin>).
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$SetupArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WingetAlreadyInstalled = -1978335189  # 0x8A15002B : déjà installé, aucune mise à jour applicable

function Write-Step {
    [CmdletBinding()]
    param([string]$Message)
    Write-Host -Object "==> $Message" -ForegroundColor Cyan
}

function Test-Elevated {
    # Copie de Test-OSSetupElevated (src\OSSetup\Functions\Elevation.ps1) : le bootstrap tourne avant que le dépôt
    # soit là. À garder alignées.
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-PowerShellArgument {
    # Les noms de paramètres (-Nom) restent tels quels, les valeurs sont entre apostrophes.
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Value)
    if ($Value -match '^-[A-Za-z][A-Za-z0-9]*:?$') { return $Value }
    "'" + ($Value -replace "'", "''") + "'"
}

function Assert-InteractiveUser {
    <#
    Vérifie que le compte qui exécute le setup est celui de la session ouverte (propriétaire d'explorer.exe).
    Sinon (compte standard + identifiants d'un autre administrateur), les réglages « utilisateur »
    iraient dans le profil de l'administrateur au lieu de celui de l'utilisateur.
    Copie d'Assert-OSSetupInteractiveUser (src\OSSetup\Functions\Elevation.ps1), à garder alignée.
    #>
    [CmdletBinding()]
    param()
    # -IncludeUserName exige les droits administrateur (la fonction n'est appelée qu'une fois élevé).
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = Get-Process -Name 'explorer' -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId -and $_.UserName } |
        Select-Object -First 1
    if (-not $explorer) {
        Write-Warning 'Utilisateur de la session introuvable (explorer.exe absent) : vérification ignorée.'
        return
    }
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($explorer.UserName -ne $current) {
        throw ("La session est ouverte par « {0} » mais le setup s'exécute en tant que « {1} ». " +
            "Les réglages utilisateur seraient appliqués au mauvais profil. " +
            "Lancez le setup depuis un compte administrateur (ou ajoutez temporairement ce compte au groupe Administrateurs).") -f
            $explorer.UserName, $current
    }
}

function Update-SessionPath {
    # Recharge PATH depuis le registre (Machine puis User) pour voir les outils installés pendant la session, en
    # conservant les entrées propres à la session, sans doublon (casse et barre oblique finale ignorées). Même règle
    # que Update-OSSetupSessionPath (src\OSSetup\Functions\Path.ps1), à garder alignée.
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Ne modifie que le PATH du processus courant.')]
    param()
    $seen = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([StringComparer]::OrdinalIgnoreCase)
    $entries = foreach ($value in [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path) {
        foreach ($entry in "$value".Split(';')) {
            $entry = $entry.Trim()
            if ($entry -and $seen.Add($entry.TrimEnd('\'))) { $entry }
        }
    }
    $env:Path = @($entries) -join ';'
}

function Wait-Winget {
    [CmdletBinding()]
    [OutputType([bool])]
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        Update-SessionPath
        if (Get-Command -Name winget -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    $false
}

function Install-WingetFromGitHub {
    # Installe la dernière version publiée de winget (Microsoft.DesktopAppInstaller) et ses dépendances,
    # depuis https://github.com/microsoft/winget-cli/releases.
    [CmdletBinding()]
    param()
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'  # la barre de progression ralentit fortement les téléchargements en 5.1
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing
    $bundle = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
    $dependencies = $release.assets | Where-Object { $_.name -like '*Dependencies*.zip' } | Select-Object -First 1
    if (-not $bundle -or -not $dependencies) {
        throw "Publication winget $($release.tag_name) : paquet ou dépendances introuvables."
    }
    Write-Host -Object "    Téléchargement de winget $($release.tag_name)"
    $work = Join-Path -Path $env:TEMP -ChildPath "OSSetup-winget-$([guid]::NewGuid())"
    New-Item -Path $work -ItemType Directory -Force | Out-Null
    try {
        $bundlePath = Join-Path -Path $work -ChildPath $bundle.name
        $zipPath = Join-Path -Path $work -ChildPath $dependencies.name
        Invoke-WebRequest -Uri $bundle.browser_download_url -OutFile $bundlePath -UseBasicParsing
        Invoke-WebRequest -Uri $dependencies.browser_download_url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path -Path $work -ChildPath 'deps') -Force

        $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
        $appx = Get-ChildItem -LiteralPath (Join-Path -Path $work -ChildPath 'deps') -Filter '*.appx' -Recurse |
            Where-Object { $_.FullName -match "\\$architecture\\" }
        foreach ($package in $appx) {
            Write-Host -Object "    Dépendance : $($package.Name)"
            try {
                Add-AppxPackage -Path $package.FullName -ErrorAction Stop
            }
            catch {
                # Une version égale ou plus récente déjà installée n'est pas une erreur.
                Write-Host -Object "      ignorée : $($_.Exception.Message.Split([Environment]::NewLine)[0])"
            }
        }
        Write-Host -Object "    Installation de $($bundle.name)"
        Add-AppxPackage -Path $bundlePath -ErrorAction Stop
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-Winget {
    # Un Windows 10 installé depuis le média officiel contient une version de 2019 de « Programme d'installation
    # d'application », sans winget : winget n'arrive qu'avec la mise à jour par le Microsoft Store, en arrière-plan.
    [CmdletBinding()]
    param()
    if (Get-Command -Name winget -ErrorAction SilentlyContinue) { return }
    Write-Step "winget absent : installation depuis la publication officielle (github.com/microsoft/winget-cli)"
    Install-WingetFromGitHub
    if (-not (Wait-Winget -Seconds 60)) {
        throw "winget est introuvable après installation. Mettez à jour « Programme d'installation d'application » depuis le Microsoft Store, puis relancez."
    }
    Write-Host -Object '    winget disponible.'
}

$script:InstalledTools = @()

function Install-WingetPackage {
    # Un paquet installé ici est noté dans $script:InstalledTools : il sera désinstallé en fin de setup si aucun
    # élément choisi ne l'installe.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Command,
        [string]$InstallerType
    )
    if (Get-Command -Name $Command -ErrorAction SilentlyContinue) {
        Write-Host -Object "    $Id déjà présent."
        return
    }
    Write-Step "Installation de $Id"
    $arguments = @('install', '--id', $Id, '--exact', '--source', 'winget', '--silent', '--scope', 'machine',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($InstallerType) { $arguments += @('--installer-type', $InstallerType) }
    # Sortie non capturée : winget écrit directement dans la console (la capturer sous PowerShell 5.1 la
    # décoderait avec la page de code OEM et corromprait les accents).
    & winget @arguments
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $script:WingetAlreadyInstalled) {
        throw ("Échec de l'installation de {0} (code 0x{1:X8})." -f $Id, $LASTEXITCODE)
    }
    Update-SessionPath
    if (-not (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
        throw "$Id est installé mais '$Command' est introuvable dans le PATH."
    }
    $script:InstalledTools += $Id
}

function Initialize-BootstrapRepository {
    <#
    Copie du dépôt utilisée par le setup. Lancé depuis un clone (setup.ps1 à côté du script) : ce clone, tel quel.
    Sinon : clone dans Destination, ou mise à jour de la copie qui s'y trouve déjà. Avec -BranchRequested, une copie
    existante sur une autre branche y est d'abord basculée, seulement si elle n'a aucune modification locale (sinon
    arrêt avec un message : rien n'est écrasé).
    Retourne @{ Root = <dossier>; Cloned = <vrai si ce bootstrap vient de cloner> }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Destination,
        # Dossier du script : une copie du dépôt s'il contient setup.ps1.
        [AllowEmptyString()]
        [string]$ScriptRoot,
        # -Branch donné explicitement : sans lui, une copie existante reste sur sa branche courante.
        [switch]$BranchRequested
    )
    if ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path -Path $ScriptRoot -ChildPath 'setup.ps1'))) {
        if ($BranchRequested) {
            Write-Host -Object "    -Branch ignoré : le clone d'où le bootstrap est lancé est utilisé tel quel ($ScriptRoot)." -ForegroundColor Yellow
        }
        return @{ Root = $ScriptRoot; Cloned = $false }
    }
    if (Test-Path -LiteralPath (Join-Path -Path $Destination -ChildPath '.git')) {
        if ($BranchRequested) {
            $current = "$(& git -C $Destination rev-parse --abbrev-ref HEAD)".Trim()
            if ($LASTEXITCODE -ne 0) { throw "Branche de la copie du dépôt illisible ($Destination)." }
            if ($current -ne $Branch) {
                # Basculement sans risque seulement : aucune modification locale (fichiers suivis ou non) à perdre.
                $changes = @(& git -C $Destination status --porcelain)
                if ($LASTEXITCODE -ne 0) { throw "État de la copie du dépôt illisible ($Destination)." }
                if ($changes.Count -gt 0) {
                    throw ("La copie du dépôt dans {0} est sur la branche « {1} » et contient des modifications locales : " +
                        "elle n'est pas basculée sur « {2} ». Enregistrez ou mettez de côté ces modifications, ou changez " +
                        "de branche vous-même (git -C ""{0}"" switch {2}), puis relancez le bootstrap.") -f $Destination, $current, $Branch
                }
                Write-Step "Basculement du dépôt dans $Destination de la branche $current vers $Branch"
                & git -C $Destination fetch origin
                if ($LASTEXITCODE -eq 0) { & git -C $Destination checkout $Branch }
                if ($LASTEXITCODE -ne 0) { throw "Échec du basculement du dépôt sur la branche $Branch." }
            }
        }
        Write-Step "Mise à jour du dépôt dans $Destination"
        & git -C $Destination pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw 'Échec de la mise à jour du dépôt.' }
        return @{ Root = $Destination; Cloned = $false }
    }
    Write-Step "Clonage de $RepoUrl dans $Destination"
    & git clone --branch $Branch $RepoUrl $Destination
    if ($LASTEXITCODE -ne 0) { throw 'Échec du clonage du dépôt.' }
    @{ Root = $Destination; Cloned = $true }
}

function Save-BootstrapInfo {
    <#
    Informe le setup de ce que le bootstrap a laissé sur la machine, pour le nettoyage de fin : copie du dépôt créée
    par lui (supprimable), script du bootstrap hors dépôt, outils installés.
    Seule une copie clonée par le bootstrap (cette fois, ou lors d'un lancement précédent d'après le bootstrap.json
    déjà présent) lui appartient : jamais un clone de développement, même placé dans -Destination.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        # Vrai si ce bootstrap vient de cloner RepoRoot.
        [Parameter(Mandatory)][bool]$OwnsClone,
        [string[]]$InstalledTool = @(),
        # Script du bootstrap : noté pour être supprimé avec la copie s'il est hors du dépôt.
        [AllowEmptyString()]
        [string]$ScriptPath = $PSCommandPath
    )
    $stateRoot = Join-Path -Path $RepoRoot -ChildPath 'state'
    $path = Join-Path -Path $stateRoot -ChildPath 'bootstrap.json'
    $tools = @($InstalledTool)
    $owns = $OwnsClone
    if (Test-Path -LiteralPath $path) {
        $previous = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        # Un bootstrap relancé ne réinstalle rien : on garde la trace des outils installés la première fois.
        $previousTools = $previous.PSObject.Properties['installedTools']
        if ($previousTools) { $tools = @($tools + @($previousTools.Value) | Where-Object { $_ } | Select-Object -Unique) }
        # Copie clonée par un bootstrap précédent : elle lui appartient toujours.
        $previousOwns = $previous.PSObject.Properties['ownsClone']
        if ($previousOwns -and $previousOwns.Value -eq $true) { $owns = $true }
    }
    # Séparateur final : « C:\OS-Setup-outils\bootstrap.ps1 » n'est pas dans le dépôt « C:\OS-Setup ».
    $repoPrefix = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\') + '\'
    $bootstrapScript = if ($ScriptPath -and -not $ScriptPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) { $ScriptPath } else { $null }
    New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
    [ordered]@{ ownsClone = $owns; bootstrapScript = $bootstrapScript; installedTools = $tools } |
        ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}

# Argument transmis à setup.ps1 qui désigne -WhatIf, sous toutes les formes que PowerShell lie à ce paramètre :
# préfixe non ambigu (-Wh … -WhatIf ; -W seul est ambigu avec -WarningAction) ou alias -wi, sans tenir compte de la
# casse, introduit par un tiret ou par un tiret typographique (U+2013, U+2014, U+2015 : texte copié depuis une page
# web), avec ou sans valeur collée (« -WhatIf: » d'un appel depuis une session PowerShell).
$script:WhatIfArgumentPattern = '^[-\u2013\u2014\u2015](wh|wha|what|whati|whatif|wi)(:.*)?$'
# Valeur d'un -WhatIf:<valeur> transmise comme argument séparé : « powershell -File » et « pwsh -File » découpent
# « -WhatIf:$false » en « -WhatIf » puis « $false » (ou « False ») ; une session PowerShell transmet « -WhatIf: » puis
# la valeur.
$script:WhatIfValuePattern = '^(\$?(true|false)|\d+)$'

function Test-WhatIfArgument {
    # Vrai si -WhatIf fait partie des arguments transmis à setup.ps1 (voir WhatIfArgumentPattern). Sinon le bootstrap
    # ferait élévation et installations réelles, puis setup.ps1 accepterait l'argument comme -WhatIf. Une valeur,
    # même fausse (-WhatIf:$false), compte comme une simulation : dans le doute, rien n'est modifié.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Argument
    )
    foreach ($value in @($Argument)) {
        if ($value -match $script:WhatIfArgumentPattern) { return $true }
    }
    $false
}

function Get-SimulationSetupArgument {
    # Arguments de setup.ps1 pour la simulation : chaque forme de -WhatIf (et sa valeur transmise séparément) est
    # remplacée par un seul -WhatIf, que setup.ps1 reçoit toujours, sous une forme qu'il lie à coup sûr.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Argument
    )
    $values = @($Argument | Where-Object { $null -ne $_ })
    $result = @()
    for ($index = 0; $index -lt $values.Count; $index++) {
        $value = $values[$index]
        if ($value -match $script:WhatIfArgumentPattern) {
            # Sans valeur collée (« -WhatIf » ou « -WhatIf: ») : la valeur éventuelle est l'argument suivant.
            if ($value -notmatch ':.' -and $index + 1 -lt $values.Count -and $values[$index + 1] -match $script:WhatIfValuePattern) {
                $index++
            }
            continue
        }
        $result += $value
    }
    $result
    '-WhatIf'
}

function Show-BootstrapSimulation {
    <#
    Simulation (-WhatIf) : affiche ce que ferait le bootstrap, sans rien installer, cloner ni écrire, et sans élévation.
    Retourne de quoi lancer la simulation du setup (PowerShell 7 et copie du dépôt déjà présents), sinon $null
    après avoir expliqué pourquoi elle est impossible.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Destination,
        # Dossier du script : une copie du dépôt s'il contient setup.ps1.
        [AllowEmptyString()]
        [string]$ScriptRoot,
        # -Branch donné explicitement (comme pour Initialize-BootstrapRepository).
        [switch]$BranchRequested
    )
    Write-Step 'Simulation (-WhatIf) : rien n''est installé, cloné ni écrit.'
    if (-not (Test-Elevated)) { Write-Host -Object '    Relance en administrateur (invite UAC) : non faite en simulation.' }
    else { Write-Host -Object '    Vérification du compte de la session : non faite en simulation.' }

    $wingetState = if (Get-Command -Name winget -ErrorAction SilentlyContinue) { 'présent' } else { 'serait installé depuis github.com/microsoft/winget-cli' }
    Write-Host -Object "    winget : $wingetState"
    $gitState = if (Get-Command -Name git -ErrorAction SilentlyContinue) { 'présent' } else { 'serait installé (winget)' }
    Write-Host -Object "    Git.Git : $gitState"
    $pwshCommand = Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pwshState = if ($pwshCommand) { 'présent' } else { 'serait installé (winget)' }
    Write-Host -Object "    Microsoft.PowerShell : $pwshState"

    $repoRoot = $null
    if ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path -Path $ScriptRoot -ChildPath 'setup.ps1'))) {
        $repoRoot = $ScriptRoot
        Write-Host -Object "    Dépôt : copie utilisée telle quelle ($repoRoot)"
        if ($BranchRequested) { Write-Host -Object "    -Branch serait ignoré : le clone d'où le bootstrap est lancé est utilisé tel quel." }
    }
    elseif (Test-Path -LiteralPath (Join-Path -Path $Destination -ChildPath '.git')) {
        $repoRoot = $Destination
        # Comme Initialize-BootstrapRepository, en lecture seule : branche courante et modifications locales.
        $repositoryState = "serait mis à jour (git pull --ff-only) dans $repoRoot"
        if ($BranchRequested) {
            # Inconnus si git est absent (le vrai bootstrap l'installerait d'abord) : la simulation annonce alors les deux
            # issues possibles. Elle les annonce aussi si git échoue, mais le vrai bootstrap s'arrêterait alors sans rien
            # changer (« Branche de la copie du dépôt illisible », « État de la copie du dépôt illisible »).
            $current = $null
            $changes = $null
            if (Get-Command -Name git -ErrorAction SilentlyContinue) {
                # Pas de redirection de stderr : sous Windows PowerShell 5.1, elle ferait lever l'erreur de git.
                $current = "$(& git -C $Destination rev-parse --abbrev-ref HEAD)".Trim()
                if ($LASTEXITCODE -ne 0) { $current = $null }
                elseif ($current -ne $Branch) {
                    $changes = @(& git -C $Destination status --porcelain)
                    if ($LASTEXITCODE -ne 0) { $changes = $null }
                }
            }
            if (-not $current -or ($current -ne $Branch -and $null -eq $changes)) {
                $repositoryState = ("serait basculé sur la branche $Branch puis mis à jour dans $repoRoot, s'il n'a aucune " +
                    'modification locale (sinon le bootstrap s''arrêterait sans rien changer)')
            }
            elseif ($current -ne $Branch -and $changes.Count -gt 0) {
                $repositoryState = ("est sur la branche « $current » avec des modifications locales dans $repoRoot : le " +
                    "bootstrap s'arrêterait sans le basculer sur « $Branch »")
            }
            elseif ($current -ne $Branch) {
                $repositoryState = "serait basculé de la branche $current vers $Branch puis mis à jour dans $repoRoot"
            }
        }
        Write-Host -Object "    Dépôt : $repositoryState ; la simulation utilise la copie actuelle"
    }
    else {
        Write-Host -Object "    Dépôt : $RepoUrl (branche $Branch) serait cloné dans $Destination"
    }
    Write-Host -Object '    state\bootstrap.json : non écrit en simulation.'

    # Le pwsh du PATH, comme hors simulation.
    $pwsh = if ($pwshCommand) { $pwshCommand.Source } else { $null }
    $setupScript = if ($repoRoot) { Join-Path -Path $repoRoot -ChildPath 'setup.ps1' } else { $null }
    if (-not $pwsh -or -not $setupScript -or -not (Test-Path -LiteralPath $setupScript)) {
        $missing = @()
        if (-not $pwsh) { $missing += 'PowerShell 7 absent' }
        if (-not $setupScript -or -not (Test-Path -LiteralPath $setupScript)) { $missing += 'pas encore de copie du dépôt' }
        $message = ("Simulation du setup impossible ({0}) : elle ne peut tourner qu'une fois les outils et le dépôt en place. " +
            'Lancez le bootstrap sans -WhatIf (le plan est montré et validé avant toute modification), ' +
            'ou, depuis une copie du dépôt sous PowerShell 7 : ./setup.ps1 -WhatIf') -f ($missing -join ', ')
        Write-Host -Object ''
        Write-Host -Object $message -ForegroundColor Yellow
        return $null
    }
    @{ Pwsh = $pwsh; SetupScript = $setupScript }
}

Write-Step 'Vérification des prérequis'
if ([Environment]::OSVersion.Platform -ne 'Win32NT' -or [Environment]::OSVersion.Version.Major -lt 10) {
    throw 'OS-Setup nécessite Windows 10 ou plus récent.'
}

# Simulation : avant l'élévation, et sans aucune des étapes qui modifient la machine.
if (Test-WhatIfArgument -Argument $SetupArguments) {
    $simulation = Show-BootstrapSimulation -RepoUrl $RepoUrl -Branch $Branch -Destination $Destination -ScriptRoot $PSScriptRoot `
        -BranchRequested:($PSBoundParameters.ContainsKey('Branch'))
    if (-not $simulation) { exit 0 }
    Write-Host -Object ''
    Write-Step 'Simulation de setup.ps1 (PowerShell 7)'
    # Sortie non capturée, comme hors simulation (accents préservés).
    $simulationArguments = @(Get-SimulationSetupArgument -Argument $SetupArguments)
    & $simulation.Pwsh -NoProfile -ExecutionPolicy Bypass -File $simulation.SetupScript @simulationArguments
    exit $LASTEXITCODE
}

# Une seule élévation pour tout le setup : les processus lancés ensuite héritent des droits administrateur.
if (-not (Test-Elevated)) {
    Write-Step 'Relance en administrateur (validez l''invite UAC) : le setup continue dans une nouvelle fenêtre.'
    $forwarded = @('-Relaunched')
    foreach ($name in 'RepoUrl', 'Branch', 'Destination') {
        if ($PSBoundParameters.ContainsKey($name)) { $forwarded += @("-$name", $PSBoundParameters[$name]) }
    }
    if ($NoPause) { $forwarded += '-NoPause' }
    if ($SetupArguments) { $forwarded += $SetupArguments }

    # -EncodedCommand évite tout problème de guillemets ; Set-Location conserve le dossier courant
    # (une fenêtre élevée démarre sinon dans System32, ce qui casserait les chemins relatifs).
    $command = "Set-Location -LiteralPath $(ConvertTo-PowerShellArgument -Value (Get-Location).Path); " +
        "& $(ConvertTo-PowerShellArgument -Value $PSCommandPath) " +
        (($forwarded | ForEach-Object { ConvertTo-PowerShellArgument -Value $_ }) -join ' ') +
        '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
    }
    catch {
        throw "Élévation refusée ou impossible : le setup nécessite les droits administrateur. ($($_.Exception.Message))"
    }
    exit $process.ExitCode
}

$exitCode = 0
try {
    Assert-InteractiveUser

    Write-Host -Object 'Étape 1/2 — Préparation : outils indispensables au setup. Vos choix viendront à l''étape 2.' -ForegroundColor Cyan
    # La console d'origine peut avoir un PATH antérieur à des installations récentes.
    Update-SessionPath
    Initialize-Winget

    Install-WingetPackage -Id 'Git.Git' -Command 'git'
    # Le paquet par défaut est un MSIX, non installable pour toute la machine sous Windows 10 : on force le MSI.
    Install-WingetPackage -Id 'Microsoft.PowerShell' -Command 'pwsh' -InstallerType 'wix'

    # Lancé depuis un clone : on l'utilise tel quel. Sinon : clone ou mise à jour dans $Destination.
    $repository = Initialize-BootstrapRepository -RepoUrl $RepoUrl -Branch $Branch -Destination $Destination -ScriptRoot $PSScriptRoot `
        -BranchRequested:($PSBoundParameters.ContainsKey('Branch'))
    $repoRoot = $repository.Root
    # Seule une copie clonée par le bootstrap peut être supprimée en fin de setup : jamais un clone de développement,
    # qu'il soit lancé directement ou placé dans $Destination.
    Save-BootstrapInfo -RepoRoot $repoRoot -OwnsClone $repository.Cloned -InstalledTool $script:InstalledTools

    Write-Host -Object ''
    Write-Host -Object 'Étape 2/2 — Vos choix, puis le plan à valider avant toute modification.' -ForegroundColor Cyan
    Write-Step 'Lancement de setup.ps1 (PowerShell 7)'
    $setupScript = Join-Path -Path $repoRoot -ChildPath 'setup.ps1'
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $setupScript @SetupArguments
    $exitCode = $LASTEXITCODE
}
catch {
    Write-Host -Object "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
}

# La fenêtre administrateur ouverte par la relance se fermerait aussitôt : on laisse le temps de lire le résultat.
if ($Relaunched -and -not $NoPause) {
    Read-Host -Prompt 'Appuyez sur Entrée pour fermer cette fenêtre' | Out-Null
}
exit $exitCode
