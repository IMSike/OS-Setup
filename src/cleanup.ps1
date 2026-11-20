<#
.SYNOPSIS
    Nettoyage de fin de setup, exécuté après la fermeture du setup (Windows PowerShell 5.1, processus détaché).
.DESCRIPTION
    Copié dans %ProgramFiles%\OS-Setup\cleanup (droits hérités de Program Files : modifiable par les seuls
    administrateurs, car il s'exécute élevé, ADR 0005) puis lancé par le setup : un script ne peut pas supprimer son
    propre dossier pendant qu'il s'exécute, et PowerShell 7 ne peut pas être désinstallé tant qu'il est en cours
    d'utilisation.
    Lit sa configuration (JSON) : processus à attendre, désinstallations reportées à la fermeture du setup
    (commande, entrée « Programmes et fonctionnalités »), paquets winget à désinstaller, chemins à supprimer,
    journal où consigner le résultat, fermeture de session. Supprime ensuite sa configuration et lui-même, puis ferme
    la session si demandé.
    Les chemins sont supprimés sans suivre les jonctions ni les liens symboliques : un lien placé dans le dépôt est
    retiré lui-même, jamais le contenu du dossier qu'il désigne (le nettoyage s'exécute en administrateur).
    Modules chargés depuis les seuls dossiers réservés aux administrateurs : voir PSModulePath ci-dessous.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
# Le script s'exécute en administrateur et ses cmdlets (Get-Content, Remove-Item…) viennent de modules chargés à la
# demande. Un Windows PowerShell 5.1 enfant met en tête de PSModulePath Documents\WindowsPowerShell\Modules, modifiable
# par l'utilisateur : un module déposé là, exportant par exemple Get-Content, serait exécuté en administrateur à sa
# place. Liste fixe des dossiers réservés aux administrateurs (ADR 0005), posée en .NET avant toute autre cmdlet que
# celles de Microsoft.PowerShell.Core.
[Environment]::SetEnvironmentVariable('PSModulePath', (@(
            [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'WindowsPowerShell\Modules')
            [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\Modules')
        ) -join ';'), 'Process')
# Continue, pas Stop : chaque étape du nettoyage est indépendante, un échec (désinstallation, fichier verrouillé) ne
# doit pas empêcher les suivantes ni la suppression du script et de sa configuration.
$ErrorActionPreference = 'Continue'
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Get-CleanupSetting {
    # Valeur de la configuration, ou $null si elle est absente (StrictMode refuse une propriété inexistante).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $property = $config.PSObject.Properties[$Name]
    if ($property) { $property.Value } else { $null }
}

function Test-CleanupLink {
    # Vrai si un dossier du chemin, jusqu'à la racine du disque, est une jonction ou un lien symbolique ; avec
    # -Leaf, contrôle aussi l'élément lui-même (y compris lien physique). Le nettoyage s'exécute en administrateur
    # et ses chemins sont dans le dépôt de l'utilisateur : un lien placé par un programme lancé sous son compte
    # redirigerait l'écriture ou la suppression vers un dossier protégé (ADR 0005).
    # Même règle que Assert-OSSetupDataPath (src\OSSetup\Functions\Resume.ps1), à garder alignée : ce script tourne
    # sous Windows PowerShell 5.1 sans le module.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path, [switch]$Leaf)
    $current = [IO.Path]::GetFullPath($Path)
    if (-not $Leaf) { $current = [IO.Path]::GetDirectoryName($current) }
    # Lien physique : seulement pour l'élément lui-même (un dossier n'en a pas).
    $linkTypes = if ($Leaf) { 'Junction', 'SymbolicLink', 'HardLink' } else { 'Junction', 'SymbolicLink' }
    while ($current) {
        $entry = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($entry -and $entry.LinkType -in $linkTypes) { return $true }
        $linkTypes = 'Junction', 'SymbolicLink'
        $current = [IO.Path]::GetDirectoryName($current)
    }
    $false
}

function Write-CleanupLog {
    [CmdletBinding()]
    param([string]$Message)
    $logPath = Get-CleanupSetting -Name 'logPath'
    if ($logPath -and -not (Test-CleanupLink -Path $logPath -Leaf)) {
        $line = '{0:yyyy-MM-dd HH:mm:ss} [CLEANUP] {1}' -f (Get-Date), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
}

function Invoke-CleanupDeletion {
    # Supprime un fichier ou un dossier sans suivre les points d'analyse (jonctions, liens symboliques) : le lien
    # est supprimé, pas sa cible. Remove-Item -Recurse de Windows PowerShell 5.1 peut entrer dans une jonction et
    # vider le dossier qu'elle désigne. Exception au premier élément impossible à supprimer (nouvel essai à l'appelant).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $entry = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $reparse = [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if ($entry -is [IO.DirectoryInfo]) {
        if (-not $reparse) {
            foreach ($child in $entry.EnumerateFileSystemInfos()) { Invoke-CleanupDeletion -Path $child.FullName }
        }
        # Dossier vide, ou lien vers un dossier : Directory.Delete non récursif retire le lien sans toucher sa cible.
        # Attributs (lecture seule) retirés seulement sur un vrai dossier, jamais au travers d'un lien.
        if (-not $reparse) { $entry.Attributes = [IO.FileAttributes]::Directory }
        [IO.Directory]::Delete($entry.FullName, $false)
    }
    else {
        if (-not $reparse) { $entry.Attributes = [IO.FileAttributes]::Normal }
        [IO.File]::Delete($entry.FullName)
    }
}

# Attend la fin du setup (fenêtre fermée).
Wait-Process -Id (Get-CleanupSetting -Name 'waitPid') -ErrorAction SilentlyContinue

# Désinstallations reportées à la fermeture du setup (ex. MSI du PowerShell qui l'exécutait). Idempotent : une
# entrée déjà absente de « Programmes et fonctionnalités » n'est pas désinstallée une seconde fois.
foreach ($command in @(Get-CleanupSetting -Name 'run' | Where-Object { $_ })) {
    if (-not (Test-Path -LiteralPath $command.registryKey)) {
        Write-CleanupLog ('Désinstallation de {0} : déjà faite' -f $command.displayName)
        continue
    }
    try {
        $process = Start-Process -FilePath $command.filePath -ArgumentList $command.arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        $code = $process.ExitCode
    }
    catch {
        Write-CleanupLog ('Désinstallation de {0} : impossible ({1})' -f $command.displayName, $_.Exception.Message)
        continue
    }
    # Fait foi : l'entrée a-t-elle disparu ? (3010 : fichiers encore utilisés, retirés au prochain redémarrage.)
    $outcome = if (-not (Test-Path -LiteralPath $command.registryKey)) { 'faite' } else { 'toujours présent' }
    if ($code -eq 3010) { $outcome += ', redémarrage nécessaire pour terminer' }
    Write-CleanupLog ('Désinstallation de {0} : {1} (code {2})' -f $command.displayName, $outcome, $code)
}

foreach ($id in @(Get-CleanupSetting -Name 'uninstall' | Where-Object { $_ })) {
    & winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements | Out-Null
    Write-CleanupLog ('Désinstallation de {0} : code {1}' -f $id, $LASTEXITCODE)
}

foreach ($path in @(Get-CleanupSetting -Name 'remove' | Where-Object { $_ })) {
    # Un dossier parent devenu lien désignerait un autre dossier que celui prévu : rien n'est supprimé.
    if (Test-CleanupLink -Path $path) {
        Write-CleanupLog ('Suppression de {0} : refusée (un dossier du chemin est un lien)' -f $path)
        continue
    }
    # Quelques essais : un fichier peut rester verrouillé un court instant après la fermeture du setup.
    $removed = $false
    for ($attempt = 1; $attempt -le 15 -and -not $removed; $attempt++) {
        try {
            if (Test-Path -LiteralPath $path) { Invoke-CleanupDeletion -Path $path }
            $removed = $true
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    Write-CleanupLog ('Suppression de {0} : {1}' -f $path, $(if ($removed) { 'faite' } else { 'impossible' }))
}

Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue

# En dernier : fermer la session interromprait le nettoyage.
if (Get-CleanupSetting -Name 'logoff') {
    Write-CleanupLog 'Fermeture de la session'
    & (Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'shutdown.exe') /l
}
