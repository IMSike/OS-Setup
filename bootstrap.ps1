<#
.SYNOPSIS
    Amorçage d'OS_Setup sur une machine Windows vierge (Windows PowerShell 5.1, sans module externe).
.DESCRIPTION
    1. Vérifie l'OS et winget.
    2. Se relance en administrateur (une seule invite UAC pour tout le setup) et vérifie que le compte
       administrateur est bien celui de la session ouverte.
    3. Installe Git et PowerShell 7 via winget s'ils sont absents.
    4. Clone (ou met à jour) le dépôt, sauf si le script est lancé depuis un clone existant.
    5. Lance setup.ps1 sous PowerShell 7 en lui transmettant les arguments restants.
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
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$RepoUrl = 'https://github.com/IMSike/OS-Setup.git',

    [string]$Branch = 'main',

    [string]$Destination = (Join-Path -Path $env:USERPROFILE -ChildPath 'OS-Setup'),

    # Ne pas attendre Entrée avant de fermer la fenêtre administrateur.
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
    #>
    [CmdletBinding()]
    param()
    # -IncludeUserName exige les droits administrateur (la fonction n'est appelée qu'une fois élevé).
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = Get-Process -Name 'explorer' -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId -and $_.UserName } |
        Select-Object -First 1
    if (-not $explorer) {
        Write-Warning "Impossible d'identifier l'utilisateur de la session (explorer.exe absent) : vérification ignorée."
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
    # Recharge PATH depuis le registre pour voir les outils installés pendant la session.
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Ne modifie que le PATH du processus courant.')]
    param()
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
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
        Expand-Archive -Path $zipPath -DestinationPath (Join-Path -Path $work -ChildPath 'deps') -Force

        $architecture = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
        $appx = Get-ChildItem -Path (Join-Path -Path $work -ChildPath 'deps') -Filter '*.appx' -Recurse |
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
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
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
    Sinon : clone dans Destination, ou mise à jour de la copie qui s'y trouve déjà.
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
        [string]$ScriptRoot
    )
    if ($ScriptRoot -and (Test-Path -LiteralPath (Join-Path -Path $ScriptRoot -ChildPath 'setup.ps1'))) {
        return @{ Root = $ScriptRoot; Cloned = $false }
    }
    if (Test-Path -LiteralPath (Join-Path -Path $Destination -ChildPath '.git')) {
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

function Test-WhatIfArgument {
    # Vrai si -WhatIf (ou -WhatIf:$true) fait partie des arguments transmis à setup.ps1.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Argument
    )
    foreach ($value in @($Argument)) {
        if ($value -match '^-WhatIf(:\$?true)?$') { return $true }
    }
    $false
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
        [string]$ScriptRoot
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
    }
    elseif (Test-Path -LiteralPath (Join-Path -Path $Destination -ChildPath '.git')) {
        $repoRoot = $Destination
        Write-Host -Object "    Dépôt : serait mis à jour (git pull --ff-only) dans $repoRoot ; la simulation utilise la copie actuelle"
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
    throw 'OS_Setup nécessite Windows 10 ou plus récent.'
}

# Simulation : avant l'élévation, et sans aucune des étapes qui modifient la machine.
if (Test-WhatIfArgument -Argument $SetupArguments) {
    $simulation = Show-BootstrapSimulation -RepoUrl $RepoUrl -Branch $Branch -Destination $Destination -ScriptRoot $PSScriptRoot
    if (-not $simulation) { exit 0 }
    Write-Host -Object ''
    Write-Step 'Simulation de setup.ps1 (PowerShell 7)'
    # Sortie non capturée, comme hors simulation (accents préservés).
    & $simulation.Pwsh -NoProfile -ExecutionPolicy Bypass -File $simulation.SetupScript @SetupArguments
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
    $repository = Initialize-BootstrapRepository -RepoUrl $RepoUrl -Branch $Branch -Destination $Destination -ScriptRoot $PSScriptRoot
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
