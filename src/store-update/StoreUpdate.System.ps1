# Mises à jour encadrées des applications du Store (ADR 0004), partie SYSTEM : tâche « OS-Setup - Store (système) »,
# chaque jour et à chaque ouverture de session, lancée aussi par la fenêtre de l'utilisateur. Windows PowerShell 5.1.
# - Garantit le blocage des mises à jour automatiques du Store (DoNotUpdate) des applications listées dans apps.json :
#   sans lui, le Store ferme de force une application ouverte pour la mettre à jour.
# - Application ouverte : lève son blocage le temps de demander au Store si une mise à jour existe, sans l'installer
#   (résultat dans check.json, lu par la fenêtre de l'utilisateur).
# - Note à chaque passage les processus ouverts qu'elle voit, toutes sessions comprises (open.json, lu par la fenêtre).
# - Application fermée : lève son blocage, demande la mise à jour au Store sans fermeture forcée, remet le blocage.
# La demande au Store se fait dans la session de l'utilisateur (tâche « OS-Setup - Store (recherche) ») : l'API du Store
# n'agit que pour le compte qui l'appelle. Le blocage est toujours remis, même en cas d'erreur.
# Déployé par OS-Setup dans %ProgramFiles%\OS-Setup\store-update : modifier le dépôt, pas cette copie.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$userTask = 'OS-Setup - Store (recherche)'
# Exécutables système par leur chemin complet : sous SYSTEM, ne pas dépendre de l'ordre du PATH.
$schtasks = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'schtasks.exe'
$icacls = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'icacls.exe'
$root = $PSScriptRoot
$log = Join-Path -Path $root -ChildPath 'store-update.log'
# Pont WMI du fournisseur MDM : même requête que Get-OSSetupDoNotUpdateInstance (src/OSSetup/Functions/StoreUpdate.ps1).
$namespace = 'root\cimv2\mdm\dmmap'
$class = 'MDM_EnterpriseModernAppManagement_AppManagement01_02'
# Tâche de reprise du setup ($script:ResumeTaskName de src/OSSetup/Functions/Resume.ps1, nom copié : script autonome),
# ignorée sans nouvelle passe depuis $resumeHours heures (Get-ResumeOrphanReason).
$resumeTask = 'OS-Setup - reprise'
$resumeHours = 48

# Copies (scripts autonomes) : Write-StoreUpdateLog aussi dans StoreUpdate.User.ps1 et StoreUpdate.Prompt.ps1 (étiquette
# différente) ; Get-AppProcess et Get-AppVersion aussi dans StoreUpdate.Prompt.ps1, en ligne dans StoreUpdate.User.ps1 ;
# Get-ResumeOrphanReason aussi dans StoreUpdate.Prompt.ps1.
function Get-ResumeOrphanReason {
    # Tâche de reprise présente mais qui ne reprendra plus rien : raison, sinon rien. Orpheline quand son setup.ps1, son
    # exécutable ou state\run.json (écrit à chaque passe, supprimé à la fin) n'existe plus (dépôt déplacé ou supprimé,
    # PowerShell retiré), ou quand aucune passe n'a eu lieu depuis $resumeHours heures. Sinon les applications encadrées
    # resteraient en vérification seule indéfiniment.
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

function Write-StoreUpdateLog {
    param([string]$Message)
    # Journal partagé avec les tâches de l'utilisateur : quelques essais si un autre écrit au même moment.
    $line = '{0:yyyy-MM-dd HH:mm:ss} [système] {1}' -f (Get-Date), $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Write-DoNotUpdate {
    param([string]$Family, [int]$Value)
    $instance = Get-CimInstance -Namespace $namespace -ClassName $class | Where-Object { $_.InstanceID -eq $Family }
    if ($instance -and $instance.DoNotUpdate -ne $Value) {
        $instance.DoNotUpdate = $Value
        Set-CimInstance -CimInstance $instance
    }
}

function Get-AppProcess {
    param([Parameter(Mandatory)][pscustomobject]$App)
    $pattern = '*\WindowsApps\' + $App.family.Split('_')[0] + '_*'
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern })
}

function Get-AppVersion {
    param([Parameter(Mandatory)][pscustomobject]$App)
    # Paquet absent : rien (sous StrictMode, lire Version sur $null lèverait une erreur).
    $package = Get-AppxPackage -AllUsers -Name $App.family.Split('_')[0] | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($package) { $package.Version }
}

function Save-OpenProcess {
    param([object[]]$App)
    # Processus de chaque application vus par SYSTEM, toutes sessions comprises (une console administrateur ou la session
    # d'un autre compte échappent à la fenêtre de l'utilisateur) : open.json, lu par la fenêtre, qui ne ferme rien si
    # SYSTEM en voit qu'elle ne voit pas. Écrit par SYSTEM seul, lisible par les utilisateurs (droits du dossier).
    $seen = [ordered]@{}
    foreach ($item in $App) { $seen[$item.productId] = @(Get-AppProcess -App $item | ForEach-Object { $_.Id }) }
    $content = [ordered]@{ written = (Get-Date).ToString('o'); apps = $seen }
    [IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'open.json'), (ConvertTo-Json -InputObject $content -Depth 4), [Text.UTF8Encoding]::new($false))
}

function Invoke-UserSearch {
    param([object[]]$App, [string]$Mode, [int]$TimeoutMinutes)
    # Le blocage est levé le temps de la demande au Store (il ne propose rien tant qu'il est en place), puis remis.
    # deadline : échéance de la recherche, une minute avant que l'attente ci-dessous s'arrête et remette le blocage.
    $request = [ordered]@{ mode = $Mode; productIds = @($App | ForEach-Object { $_.productId }); requested = (Get-Date).ToString('o')
        deadline = (Get-Date).AddMinutes($TimeoutMinutes - 1).ToString('o') }
    [IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'run.json'), (ConvertTo-Json -InputObject $request), [Text.UTF8Encoding]::new($false))
    try {
        foreach ($item in $App) { Write-DoNotUpdate -Family $item.family -Value 0 }
        # Exécution lancée par cette demande : vue en cours, LastRunTime changé, ou check.json écrit depuis (la recherche
        # l'écrit après chaque application). LastRunTime seul ne suffit pas : le Planificateur peut le dater de plusieurs
        # secondes trop tôt et ne pas le changer pour deux exécutions rapprochées (observé en VM).
        $previous = (Get-ScheduledTask -TaskName $userTask | Get-ScheduledTaskInfo).LastRunTime
        $checkPath = Join-Path -Path $root -ChildPath 'check.json'
        $started = Get-Date
        & $schtasks /run /tn $userTask | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-StoreUpdateLog "recherche non lancée (code $LASTEXITCODE)"
            return
        }
        # Attend une exécution démarrée après la demande, puis terminée (même condition que la fenêtre de l'utilisateur).
        $deadline = $started.AddMinutes($TimeoutMinutes)
        $ran = $false
        do {
            Start-Sleep -Seconds 1
            $task = Get-ScheduledTask -TaskName $userTask
            $ran = $ran -or $task.State -eq 'Running' -or ($task | Get-ScheduledTaskInfo).LastRunTime -ne $previous -or
                (Get-Item -Path $checkPath -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started })
            $done = $ran -and $task.State -ne 'Running'
            if (-not $ran -and (Get-Date) -ge $started.AddMinutes(1)) {
                # Demande ignorée (une recherche précédente tourne encore) ou session absente : pas de blocage levé pour rien.
                Write-StoreUpdateLog 'recherche non démarrée après 1 min'
                return
            }
        } until ($done -or (Get-Date) -ge $deadline)
        if (-not $done) { Write-StoreUpdateLog "recherche non terminée après $TimeoutMinutes min" }
    }
    finally {
        foreach ($item in $App) { Write-DoNotUpdate -Family $item.family -Value 1 }
    }
}

# Lu par le catch : une erreur avant la lecture d'apps.json ne doit pas en provoquer une autre (StrictMode).
$apps = @()
try {
    if ((Test-Path -Path $log) -and (Get-Item -Path $log).Length -gt 1MB) {
        # Nouveau journal, modifiable par les utilisateurs comme le précédent (le dossier leur est en lecture seule).
        Move-Item -Path $log -Destination "$log.old" -Force
        New-Item -Path $log -ItemType File | Out-Null
        & $icacls $log /grant '*S-1-5-32-545:(M)' | Out-Null
    }
    $checkFile = Join-Path -Path $root -ChildPath 'check.json'
    if (-not (Test-Path -Path $checkFile)) {
        # Résultat des vérifications supprimé : recréé, modifiable par les utilisateurs (la tâche de recherche l'écrit).
        [IO.File]::WriteAllText($checkFile, '{}', [Text.UTF8Encoding]::new($false))
        & $icacls $checkFile /grant '*S-1-5-32-545:(M)' | Out-Null
    }
    # Sous Windows PowerShell 5.1, ConvertFrom-Json rend un tableau JSON d'un bloc : l'affectation puis @() le déplient.
    $apps = ConvertFrom-Json -InputObject (Get-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Raw -Encoding UTF8)
    $apps = @($apps)
    # Application encadrée puis désinstallée : elle reste dans apps.json mais n'apparaîtra jamais dans le pont WMI.
    $present = @($apps | Where-Object { Get-AppVersion -App $_ })
    # Juste après le démarrage, le pont WMI du Store peut ne pas encore exposer les paquets : on les attend 3 min au plus.
    $deadline = (Get-Date).AddMinutes(3)
    while ($true) {
        $known = @(Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction SilentlyContinue | ForEach-Object { $_.InstanceID })
        $installed = @($present | Where-Object { $_.family -in $known })
        if ($installed.Count -eq $present.Count -or (Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 10
    }
    # Garde-fou : le blocage doit être en place en dehors des demandes au Store.
    foreach ($app in $installed) { Write-DoNotUpdate -Family $app.family -Value 1 }
    # À chaque passage, avant toute demande au Store : la fenêtre s'y fie seulement s'il a été écrit après sa demande.
    try { Save-OpenProcess -App $installed } catch { Write-StoreUpdateLog "ERREUR open.json : $($_.Exception.Message)" }
    if (-not $installed) { return }
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Write-StoreUpdateLog 'aucune session ouverte : rien à demander au Store'
        return
    }

    $open = @($installed | Where-Object { @(Get-AppProcess -App $_).Count -gt 0 })
    $closed = @($installed | Where-Object { $_ -notin $open })
    # Reprise du setup en attente : elle lance PowerShell 7 à l'ouverture de session, peut-être pendant sa mise à jour.
    # Vérification seule jusqu'à la fin du setup. Tâche orpheline : ignorée (ligne dans le journal).
    $resume = if ($closed) { Get-ScheduledTask -TaskName $resumeTask -ErrorAction SilentlyContinue }
    if ($resume) {
        $orphan = Get-ResumeOrphanReason -Task $resume
        if ($orphan) {
            Write-StoreUpdateLog "tâche de reprise du setup ignorée : $orphan"
        }
        else {
            Write-StoreUpdateLog 'reprise du setup en attente : vérification seule'
            $open = $installed
            $closed = @()
        }
    }
    if ($open) {
        Write-StoreUpdateLog "ouvertes, vérification seule : $(($open | ForEach-Object { $_.name }) -join ', ')"
        Invoke-UserSearch -App $open -Mode 'check' -TimeoutMinutes 3
    }
    if ($closed) {
        $before = @($closed | ForEach-Object { "$($_.name) $(Get-AppVersion -App $_)" }) -join ', '
        Write-StoreUpdateLog "fermées, mise à jour : $before"
        Invoke-UserSearch -App $closed -Mode 'update' -TimeoutMinutes 15
        Write-StoreUpdateLog "après : $(@($closed | ForEach-Object { "$($_.name) $(Get-AppVersion -App $_)" }) -join ', ')"
    }
}
catch {
    Write-StoreUpdateLog "ERREUR $($_.Exception.Message)"
    foreach ($app in $apps) {
        try { Write-DoNotUpdate -Family $app.family -Value 1 } catch { Write-StoreUpdateLog "ERREUR blocage $($app.family) : $($_.Exception.Message)" }
    }
}
