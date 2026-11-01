# Mises à jour encadrées des applications du Store (ADR 0004), partie SYSTEM : tâche « OS-Setup - Store (système) »,
# chaque jour et à chaque ouverture de session, lancée aussi par la fenêtre de l'utilisateur. Windows PowerShell 5.1.
# - Garantit le blocage des mises à jour automatiques du Store (DoNotUpdate) des applications listées dans apps.json :
#   sans lui, le Store ferme de force une application ouverte pour la mettre à jour.
# - Application ouverte : lève son blocage le temps de demander au Store si une mise à jour existe, sans l'installer
#   (résultat dans check.json, lu par la fenêtre de l'utilisateur).
# - Application fermée : lève son blocage, demande la mise à jour au Store sans fermeture forcée, remet le blocage.
# La demande au Store se fait dans la session de l'utilisateur (tâche « OS-Setup - Store (recherche) ») : l'API du Store
# n'agit que pour le compte qui l'appelle. Le blocage est toujours remis, même en cas d'erreur.

$ErrorActionPreference = 'Stop'
$userTask = 'OS-Setup - Store (recherche)'
$root = $PSScriptRoot
$log = Join-Path -Path $root -ChildPath 'store-update.log'
$namespace = 'root\cimv2\mdm\dmmap'
$class = 'MDM_EnterpriseModernAppManagement_AppManagement01_02'

function Write-StoreUpdateLog([string]$Message) {
    # Journal partagé avec les tâches de l'utilisateur : quelques essais si un autre écrit au même moment.
    $line = '{0:yyyy-MM-dd HH:mm:ss} [système] {1}' -f (Get-Date), $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Write-DoNotUpdate([string]$Family, [int]$Value) {
    $instance = Get-CimInstance -Namespace $namespace -ClassName $class | Where-Object { $_.InstanceID -eq $Family }
    if ($instance -and $instance.DoNotUpdate -ne $Value) {
        $instance.DoNotUpdate = $Value
        Set-CimInstance -CimInstance $instance
    }
}

function Get-AppProcess($App) {
    $pattern = '*\WindowsApps\' + $App.family.Split('_')[0] + '_*'
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern })
}

function Get-AppVersion($App) {
    (Get-AppxPackage -AllUsers -Name $App.family.Split('_')[0] | Sort-Object -Property Version -Descending | Select-Object -First 1).Version
}

function Invoke-UserSearch([object[]]$App, [string]$Mode, [int]$TimeoutMinutes) {
    # Le blocage est levé le temps de la demande au Store (il ne propose rien tant qu'il est en place), puis remis.
    # deadline : échéance de la recherche, une minute avant que l'attente ci-dessous s'arrête et remette le blocage.
    $request = [ordered]@{ mode = $Mode; productIds = @($App | ForEach-Object { $_.productId }); requested = (Get-Date).ToString('o')
        deadline = (Get-Date).AddMinutes($TimeoutMinutes - 1).ToString('o') }
    [IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'run.json'), (ConvertTo-Json -InputObject $request), [Text.UTF8Encoding]::new($false))
    try {
        foreach ($item in $App) { Write-DoNotUpdate -Family $item.family -Value 0 }
        $started = Get-Date
        & schtasks.exe /run /tn $userTask | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-StoreUpdateLog "recherche non lancée (code $LASTEXITCODE)"
            return
        }
        # Attend une exécution démarrée après la demande, puis terminée (même condition que la fenêtre de l'utilisateur).
        $deadline = $started.AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds 2
            $task = Get-ScheduledTask -TaskName $userTask
            $ran = ($task | Get-ScheduledTaskInfo).LastRunTime -ge $started.AddSeconds(-2)
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

try {
    if ((Test-Path -Path $log) -and (Get-Item -Path $log).Length -gt 1MB) {
        # Nouveau journal, modifiable par les utilisateurs comme le précédent (le dossier leur est en lecture seule).
        Move-Item -Path $log -Destination "$log.old" -Force
        New-Item -Path $log -ItemType File | Out-Null
        & icacls.exe $log /grant '*S-1-5-32-545:(M)' | Out-Null
    }
    # Sous Windows PowerShell 5.1, ConvertFrom-Json rend un tableau JSON d'un bloc : l'affectation puis @() le déplient.
    $apps = ConvertFrom-Json -InputObject (Get-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Raw -Encoding UTF8)
    $apps = @($apps)
    # Application encadrée puis désinstallée : elle reste dans apps.json mais n'apparaîtra jamais dans le pont WMI.
    $present = @($apps | Where-Object { Get-AppVersion $_ })
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
    if (-not $installed) { return }
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Write-StoreUpdateLog 'aucune session ouverte : rien à demander au Store'
        return
    }

    $open = @($installed | Where-Object { (Get-AppProcess $_).Count -gt 0 })
    $closed = @($installed | Where-Object { $_ -notin $open })
    if ($open) {
        Write-StoreUpdateLog "ouvertes, vérification seule : $(($open | ForEach-Object { $_.name }) -join ', ')"
        Invoke-UserSearch -App $open -Mode 'check' -TimeoutMinutes 3
    }
    if ($closed) {
        $before = @($closed | ForEach-Object { "$($_.name) $(Get-AppVersion $_)" }) -join ', '
        Write-StoreUpdateLog "fermées, mise à jour : $before"
        Invoke-UserSearch -App $closed -Mode 'update' -TimeoutMinutes 15
        Write-StoreUpdateLog "après : $(@($closed | ForEach-Object { "$($_.name) $(Get-AppVersion $_)" }) -join ', ')"
    }
}
catch {
    Write-StoreUpdateLog "ERREUR $($_.Exception.Message)"
    foreach ($app in $apps) {
        try { Write-DoNotUpdate -Family $app.family -Value 1 } catch { Write-StoreUpdateLog "ERREUR blocage $($app.family) : $($_.Exception.Message)" }
    }
}
