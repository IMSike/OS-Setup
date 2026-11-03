# Mises à jour encadrées des applications du Store (ADR 0004) : variables et fonctions communes aux trois scripts des
# tâches (StoreUpdate.System.ps1, StoreUpdate.User.ps1, StoreUpdate.Prompt.ps1), qui le chargent avec un point.
# Windows PowerShell 5.1, sous le StrictMode du script qui le charge. Aucun effet au chargement : il ne définit que des
# variables et des fonctions.
# Exécuté aussi par la tâche SYSTEM : déployé avec les scripts, modifiable par les seuls administrateurs et contrôlé par
# son empreinte comme eux.
# Déployé par OS-Setup dans %ProgramFiles%\OS-Setup\store-update : modifier le dépôt, pas cette copie.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'schtasks', Justification = 'Lu par les scripts qui chargent ce fichier.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'resumeTask', Justification = 'Lu par les scripts qui chargent ce fichier.')]
param()

$root = $PSScriptRoot
# Journal partagé par les trois tâches. Chaque ligne porte l'étiquette $logLabel, définie par le script qui charge ce
# fichier (système, compte de l'utilisateur, fenêtre).
$log = Join-Path -Path $root -ChildPath 'store-update.log'
# Exécutable système par son chemin complet : sous SYSTEM, ne pas dépendre de l'ordre du PATH.
$schtasks = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'schtasks.exe'
# Tâche de reprise du setup ($script:ResumeTaskName de src/OSSetup/Functions/Resume.ps1, nom recopié : les scripts
# déployés ne chargent pas le module). Tant qu'elle existe, la tâche SYSTEM ne fait que vérifier ; ignorée sans nouvelle
# passe depuis $resumeHours heures (Get-ResumeOrphanReason).
$resumeTask = 'OS-Setup - reprise'
$resumeHours = 48

function Write-StoreUpdateLog {
    [CmdletBinding()]
    param([string]$Message)
    # Journal partagé entre les tâches : quelques essais si une autre écrit au même moment.
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $logLabel, $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Get-AppVersion {
    # Version installée la plus récente de l'application, en texte ; paquet absent : chaîne vide (sous StrictMode, lire
    # Version sur $null lèverait une erreur). Comparée comme version : en texte, 7.5.9.0 passerait devant 7.5.10.0.
    # -AllUsers : paquets de tous les comptes, pour la tâche SYSTEM (qui n'a pas de paquets à elle). Réservé aux
    # administrateurs : les tâches de l'utilisateur lisent les paquets de leur compte.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject]$App, [switch]$AllUsers)
    $package = Get-AppxPackage -AllUsers:$AllUsers -Name $App.family.Split('_')[0] | Sort-Object -Property { [version]$_.Version } -Descending | Select-Object -First 1
    if ($package) { "$($package.Version)" } else { '' }
}

function Get-AppProcess {
    # Processus de l'application visibles du compte qui appelle (tous les comptes pour SYSTEM).
    [CmdletBinding()]
    [OutputType([array])]
    param([Parameter(Mandatory)][pscustomobject]$App)
    $pattern = '*\WindowsApps\' + $App.family.Split('_')[0] + '_*'
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern })
}

function Get-ResumeOrphanReason {
    # Tâche de reprise présente mais qui ne reprendra plus rien : raison, sinon rien. Orpheline quand son setup.ps1, son
    # exécutable ou state\run.json (écrit à chaque passe, supprimé à la fin) n'existe plus (dépôt déplacé ou supprimé,
    # PowerShell retiré), ou quand aucune passe n'a eu lieu depuis $resumeHours heures. Sinon les applications encadrées
    # resteraient en vérification seule indéfiniment.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Task)
    $action = @($Task.Actions)[0]
    $setup = $null
    if ($action -and "$($action.Arguments)" -match '-File\s+"([^"]+)"') { $setup = $Matches[1] }
    if (-not $setup -or -not (Test-Path -LiteralPath $setup)) { return 'setup.ps1 introuvable' }
    $runState = Join-Path -Path (Split-Path -Path $setup -Parent) -ChildPath 'state\run.json'
    if (-not (Test-Path -LiteralPath $runState)) { return 'aucune exécution en attente (state\run.json absent)' }
    $execute = "$($action.Execute)".Trim('"')
    if (-not $execute -or -not (Test-Path -LiteralPath $execute)) { return "exécutable introuvable ($execute)" }
    if ((Get-Item -LiteralPath $runState).LastWriteTime -lt (Get-Date).AddHours(-$resumeHours)) { return "aucune passe depuis plus de $resumeHours h" }
}
