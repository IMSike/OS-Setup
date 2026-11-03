# Entretien de Docker Desktop, lancé à l'ouverture de session par la tâche planifiée « OS-Setup - Docker (entretien) »
# (déployé par OS-Setup dans %ProgramFiles%\OS-Setup\docker, modifiable par les seuls administrateurs puisque la tâche
# l'exécute avec les droits les plus élevés ; modifier le dépôt, pas cette copie). Windows PowerShell 5.1, droits
# administrateur, compte de l'utilisateur : journal et état à côté du script, dans ce même dossier réservé aux
# administrateurs (lisible par les utilisateurs).
#
# Droits élevés : aucun chemin écrit ou exécuté ne vient d'une variable d'environnement (modifiable par l'utilisateur
# dans HKCU\Environment, elle détournerait docker.exe ou le journal) ; dossiers connus et exécutables de Windows par
# leur chemin complet. Contrôlé par tests/Data.Tests.ps1 (aucune variable $env: dans les scripts élevés).
#
# Le disque virtuel de Docker (docker_data.vhdx) grossit mais ne rétrécit jamais seul. Une fois par semaine au plus :
#   1. compactage du disque virtuel, tant que Docker et WSL sont arrêtés (diskpart, outil de Windows) ;
#   2. démarrage de Docker Desktop (à la place de son propre lancement automatique, qui est désactivé ici) ;
#   3. suppression des images orphelines (restes d'images reconstruites, jamais réutilisés).
# Les autres jours : démarrage de Docker Desktop seulement. Le réglage « démarrer avec Windows » de Docker Desktop est
# respecté : son entrée de démarrage absente, Docker n'est pas démarré.
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Force', Justification = 'Utilisé par la fonction Test-Due.')]
param(
    # Pour les tests : autre disque virtuel, entretien même si le dernier date de moins d'une semaine, sans Docker.
    [string]$VhdPath,
    [switch]$Force,
    [switch]$NoDocker
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Modules chargés à la demande : seulement ceux de Windows. Le dossier Modules du profil, prioritaire sous 5.1 et
# modifiable par l'utilisateur, remplacerait sinon une commande de ce script par la sienne, exécutée en administrateur.
[Environment]::SetEnvironmentVariable('PSModulePath', ((Join-Path -Path $PSHOME -ChildPath 'Modules') + ';' +
        (Join-Path -Path ([Environment]::GetFolderPath('ProgramFiles')) -ChildPath 'WindowsPowerShell\Modules')), 'Process')

# Journal et état à côté du script : %ProgramFiles%\OS-Setup\docker une fois déployé.
$stateRoot = $PSScriptRoot
$statePath = Join-Path -Path $stateRoot -ChildPath 'docker-maintenance.json'
$logPath = Join-Path -Path $stateRoot -ChildPath 'docker-maintenance.log'
$programFiles = [Environment]::GetFolderPath('ProgramFiles')
$system32 = [Environment]::SystemDirectory
$dockerExe = Join-Path -Path $programFiles -ChildPath 'Docker\Docker\Docker Desktop.exe'
$dockerCli = Join-Path -Path $programFiles -ChildPath 'Docker\Docker\resources\bin\docker.exe'
$diskpart = Join-Path -Path $system32 -ChildPath 'diskpart.exe'
$wsl = Join-Path -Path $system32 -ChildPath 'wsl.exe'
$explorer = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'explorer.exe'
# Disque virtuel de Docker : dans le profil de l'utilisateur, par nature (dossier de Docker Desktop).
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$approvedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$runName = 'Docker Desktop'
$intervalDays = 7

function Write-MaintenanceLog {
    [CmdletBinding()]
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message) -Encoding UTF8
}

function Get-MaintenanceState {
    [CmdletBinding()]
    param()
    $state = [pscustomobject]@{ lastCompaction = $null; lastPrune = $null }
    if (-not (Test-Path -LiteralPath $statePath)) { return $state }
    # Dates relues une à une : un fichier illisible ou incomplet vaut un entretien jamais fait.
    try {
        $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        foreach ($name in 'lastCompaction', 'lastPrune') {
            $value = $saved.PSObject.Properties[$name]
            $date = [datetime]::MinValue
            if ($value -and [datetime]::TryParse("$($value.Value)", [ref]$date)) { $state.$name = $date.ToString('o') }
        }
    }
    catch {
        Write-MaintenanceLog 'état illisible : entretien refait'
    }
    $state
}

function Test-Due {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()][object]$Date)
    $Force -or -not $Date -or ((Get-Date) - [datetime]$Date).TotalDays -ge $intervalDays
}

function Get-RunningWslDistribution {
    [CmdletBinding()]
    [OutputType([System.Object[]], [System.Array])]
    param()
    # wsl.exe écrit en UTF-16 : décodage adapté le temps de l'appel. Code de sortie non nul : aucune distribution en
    # marche, ou WSL absent (le message affiché n'est alors pas une liste de distributions).
    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        if (-not (Test-Path -LiteralPath $wsl)) { return @() }
        $output = @(& $wsl --list --running --quiet 2>$null)
        if ($LASTEXITCODE -ne 0) { return @() }
        @($output | Where-Object { $_ -and $_.Trim() })
    }
    finally {
        [Console]::OutputEncoding = $previous
    }
}

function Invoke-VhdCompaction {
    [CmdletBinding()]
    param([string]$Path)
    # Chemin écrit dans un script diskpart exécuté en administrateur : un guillemet ou un retour à la ligne (dossier
    # du profil choisi par l'utilisateur) y ajouterait des commandes.
    if ($Path -match '["\r\n]') { throw "chemin du disque virtuel refusé : $Path" }
    $before = (Get-Item -LiteralPath $Path).Length
    # Commandes diskpart (exécutées en administrateur) à côté de ce script, dans un dossier que seuls les
    # administrateurs modifient : dans %TEMP%, un programme de la session pourrait les remplacer avant leur exécution.
    $script = Join-Path -Path $PSScriptRoot -ChildPath 'os-setup-compact.txt'
    Set-Content -Path $script -Encoding ASCII -Value @(
        "select vdisk file=`"$Path`""
        'attach vdisk readonly'
        'compact vdisk'
        'detach vdisk'
    )
    $output = & $diskpart /s $script 2>&1
    $exitCode = $LASTEXITCODE
    Remove-Item -Path $script -Force
    if ($exitCode -ne 0) {
        # Le disque peut rester attaché si le compactage a échoué : le détacher pour que Docker démarre.
        Set-Content -Path $script -Encoding ASCII -Value @("select vdisk file=`"$Path`"", 'detach vdisk')
        & $diskpart /s $script 2>&1 | Out-Null
        Remove-Item -Path $script -Force
        throw "diskpart a échoué (code $exitCode) : $(($output | Select-Object -Last 3) -join ' ')"
    }
    $after = (Get-Item -LiteralPath $Path).Length
    Write-MaintenanceLog ('compactage : {0:N1} Go -> {1:N1} Go ({2:N1} Go rendus à Windows)' -f ($before / 1GB), ($after / 1GB), (($before - $after) / 1GB))
}

$state = Get-MaintenanceState
$dockerRunning = [bool](Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)
$autoStart = $null -ne (Get-ItemProperty -Path $runKey -Name $runName -ErrorAction SilentlyContinue)

# Le lancement automatique de Docker Desktop est fait ici, après le compactage : celui de Docker est désactivé comme le
# fait le Gestionnaire des tâches (l'entrée reste, Docker Desktop la recrée quand on change son réglage).
if ($autoStart) {
    if (-not (Test-Path -Path $approvedKey)) { New-Item -Path $approvedKey -Force | Out-Null }
    Set-ItemProperty -Path $approvedKey -Name $runName -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary
}

# 1. Compactage
try {
    if (Test-Due -Date $state.lastCompaction) {
        $candidates = if ($VhdPath) { @($VhdPath) } else {
            @(
                (Join-Path -Path $localAppData -ChildPath 'Docker\wsl\disk\docker_data.vhdx')
                (Join-Path -Path $localAppData -ChildPath 'Docker\wsl\data\ext4.vhdx')
            )
        }
        $vhd = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        $running = @(Get-RunningWslDistribution)
        if (-not $vhd) {
            Write-MaintenanceLog 'compactage : disque virtuel de Docker introuvable (Docker jamais démarré ?)'
        }
        elseif ($dockerRunning -or $running) {
            Write-MaintenanceLog "compactage reporté : Docker ou WSL déjà en marche ($($running -join ', '))"
        }
        else {
            Invoke-VhdCompaction -Path $vhd
            $state.lastCompaction = (Get-Date).ToString('o')
        }
    }
}
catch {
    Write-MaintenanceLog "compactage en échec : $($_.Exception.Message)"
}

if ($NoDocker) {
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
    return
}

# 2. Démarrage de Docker Desktop, sans droits administrateur (par l'Explorateur), si son réglage le demande.
if ($autoStart -and -not $dockerRunning -and (Test-Path -Path $dockerExe)) {
    Start-Process -FilePath $explorer -ArgumentList "`"$dockerExe`""
    Write-MaintenanceLog 'Docker Desktop démarré'
    $dockerRunning = $true
}

# 3. Images orphelines : moteur Docker prêt nécessaire (attente de 5 minutes au plus).
try {
    if ($dockerRunning -and (Test-Due -Date $state.lastPrune) -and (Test-Path -Path $dockerCli)) {
        $ready = $false
        for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
            & $dockerCli info 2>$null | Out-Null
            $ready = $LASTEXITCODE -eq 0
            if (-not $ready) { Start-Sleep -Seconds 5 }
        }
        if ($ready) {
            $output = & $dockerCli image prune --force 2>&1
            Write-MaintenanceLog "images orphelines : $(($output | Select-Object -Last 1))"
            $state.lastPrune = (Get-Date).ToString('o')
        }
        else {
            Write-MaintenanceLog 'images orphelines : moteur Docker pas prêt, reporté'
        }
    }
}
catch {
    Write-MaintenanceLog "images orphelines en échec : $($_.Exception.Message)"
}

$state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
