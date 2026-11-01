# Mises à jour encadrées des applications du Store (ADR 0004, provider store-update-guard).
#
# Le Store ferme de force une application ouverte pour la mettre à jour (PowerShell 7, Windows Terminal : sessions et
# agents perdus). Ses mises à jour automatiques sont bloquées (DoNotUpdate, nœud EnterpriseModernAppManagement du
# fournisseur MDM, par son pont WMI) et trois tâches planifiées les font à la place, sans fermeture forcée :
# - « système » (SYSTEM, chaque jour et à l'ouverture de session) : met à jour les applications fermées, vérifie
#   seulement pour les applications ouvertes, garantit le blocage ;
# - « recherche » (utilisateur, sans déclencheur) : interroge le Store pour le compte de l'utilisateur ;
# - « fenêtre » (utilisateur, toutes les 15 min) : propose la mise à jour d'une application ouverte, ou un report.
# Scripts dans %ProgramFiles%\OS-Setup\store-update (src/store-update/), modifiables par les seuls administrateurs :
# la tâche SYSTEM les exécute.

$script:StoreUpdateTask = [ordered]@{
    System = 'OS-Setup - Store (système)'
    User   = 'OS-Setup - Store (recherche)'
    Prompt = 'OS-Setup - Store (fenêtre)'
}
$script:StoreUpdateScript = [ordered]@{
    System = 'StoreUpdate.System.ps1'
    User   = 'StoreUpdate.User.ps1'
    Prompt = 'StoreUpdate.Prompt.ps1'
}

function Get-OSSetupStoreUpdateRoot {
    <#
    .SYNOPSIS
        Dossier des scripts et des fichiers d'état des mises à jour encadrées.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Join-Path -Path ([Environment]::GetFolderPath('ProgramFiles')) -ChildPath 'OS-Setup\store-update'
}

function Get-OSSetupStoreUpdateTaskArgument {
    <#
    .SYNOPSIS
        Arguments de conhost.exe pour une tâche des mises à jour encadrées : Windows PowerShell 5.1 (l'API du Store n'est
        pas accessible depuis PowerShell 7), sans fenêtre visible (--headless).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('System', 'User', 'Prompt')]
        [string]$Role
    )
    $script = Join-Path -Path (Get-OSSetupStoreUpdateRoot) -ChildPath $script:StoreUpdateScript[$Role]
    "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
}

function Get-OSSetupDoNotUpdate {
    <#
    .SYNOPSIS
        Blocage des mises à jour automatiques du Store pour une famille de paquets : 1, 0, ou $null si le Store ne
        connaît pas (encore) le paquet.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Family
    )
    $instance = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01_02' |
        Where-Object { $_.InstanceID -eq $Family }
    if ($instance) { [int]$instance.DoNotUpdate }
}

function Set-OSSetupDoNotUpdate {
    <#
    .SYNOPSIS
        Pose le blocage des mises à jour automatiques du Store pour une famille de paquets. Juste après l'installation,
        le pont WMI peut ne pas encore exposer le paquet : attente d'une minute au plus.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Family,

        [int]$TimeoutSeconds = 60
    )
    if (-not $PSCmdlet.ShouldProcess($Family, 'Bloquer les mises à jour automatiques du Store')) { return }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $instance = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01_02' |
            Where-Object { $_.InstanceID -eq $Family }
        if ($instance -or (Get-Date) -ge $deadline) { break }
        Start-Sleep -Seconds 5
    }
    if (-not $instance) { throw "Le Store ne connaît pas le paquet $Family : l'application est-elle installée ?" }
    $instance.DoNotUpdate = 1
    Set-CimInstance -CimInstance $instance
}

function Get-OSSetupStoreUpdateApp {
    <#
    .SYNOPSIS
        Applications encadrées (apps.json) : famille de paquets, produit du Store, nom affiché, programmes à fermer avant.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $path = Join-Path -Path (Get-OSSetupStoreUpdateRoot) -ChildPath 'apps.json'
    if (Test-Path -Path $path -PathType Leaf) {
        @(Get-Content -Path $path -Raw -Encoding utf8 | ConvertFrom-Json)
    }
}

function ConvertTo-OSSetupStoreUpdateApp {
    <#
    .SYNOPSIS
        Entrée d'apps.json pour une action store-update-guard.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action
    )
    [ordered]@{
        family     = $Action['family']
        productId  = $Action['productId']
        name       = $Action['name']
        closeFirst = @($Action['closeFirst'] | Where-Object { $_ })
    }
}

function Test-OSSetupStoreUpdateGuard {
    <#
    .SYNOPSIS
        Conforme si les scripts déployés sont ceux du dépôt, l'application est listée, les trois tâches existent et le
        blocage est posé.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )
    $root = Get-OSSetupStoreUpdateRoot
    foreach ($name in $script:StoreUpdateScript.Values) {
        $target = Join-Path -Path $root -ChildPath $name
        if (-not (Test-Path -Path $target -PathType Leaf)) { return $false }
        if ((Get-FileHash -Path $target).Hash -ne (Get-FileHash -Path (Join-Path -Path $SourceRoot -ChildPath $name)).Hash) { return $false }
    }
    $expected = ConvertTo-Json -InputObject (ConvertTo-OSSetupStoreUpdateApp -Action $Action) -Compress
    $listed = @(Get-OSSetupStoreUpdateApp | Where-Object { (ConvertTo-Json -InputObject $_ -Compress) -eq $expected })
    if ($listed.Count -ne 1) { return $false }
    foreach ($role in $script:StoreUpdateTask.Keys) {
        $task = Get-ScheduledTask -TaskName $script:StoreUpdateTask[$role] -ErrorAction SilentlyContinue
        if (-not $task -or $task.Actions[0].Arguments -ne (Get-OSSetupStoreUpdateTaskArgument -Role $role)) { return $false }
    }
    (Get-OSSetupDoNotUpdate -Family $Action['family']) -eq 1
}

function Install-OSSetupStoreUpdateGuard {
    <#
    .SYNOPSIS
        Déploie les scripts, ajoute l'application à apps.json, enregistre les trois tâches et pose le blocage.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )
    if (-not $PSCmdlet.ShouldProcess($Action['name'], 'Encadrer les mises à jour du Store')) { return }
    $root = Get-OSSetupStoreUpdateRoot
    # Sous Program Files, le dossier hérite de droits en lecture seule pour les utilisateurs : seuls les
    # administrateurs peuvent modifier les scripts que la tâche SYSTEM exécute.
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    foreach ($name in $script:StoreUpdateScript.Values) {
        Copy-Item -Path (Join-Path -Path $SourceRoot -ChildPath $name) -Destination $root -Force
    }
    # Journal commun et résultat des vérifications : écrits aussi par les tâches de l'utilisateur.
    foreach ($name in 'store-update.log', 'check.json') {
        $path = Join-Path -Path $root -ChildPath $name
        if (-not (Test-Path -Path $path -PathType Leaf)) {
            [System.IO.File]::WriteAllText($path, $(if ($name -like '*.json') { '{}' } else { '' }), [System.Text.UTF8Encoding]::new($false))
        }
        & icacls.exe $path /grant '*S-1-5-32-545:(M)' | Out-Null
    }
    $entry = ConvertTo-OSSetupStoreUpdateApp -Action $Action
    $apps = @(@(Get-OSSetupStoreUpdateApp | Where-Object { $_.family -ne $Action['family'] }) + $entry)
    [System.IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'apps.json'), (ConvertTo-Json -InputObject $apps -Depth 4), [System.Text.UTF8Encoding]::new($false))
    Register-OSSetupStoreUpdateTask
    Set-OSSetupDoNotUpdate -Family $Action['family']
}

function Register-OSSetupStoreUpdateTask {
    <#
    .SYNOPSIS
        Enregistre (ou remplace) les trois tâches des mises à jour encadrées, pour le compte qui lance le setup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('Planificateur de tâches', 'Enregistrer les tâches des mises à jour du Store')) { return }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Tâche SYSTEM : chaque jour (12 h, décalage aléatoire d'une heure, rattrapée si manquée) et à l'ouverture de
    # session. Par l'API COM : seule elle permet le descripteur de sécurité qui laisse les utilisateurs la lancer
    # (« Mettre à jour maintenant ») sans pouvoir la modifier.
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'OS-Setup : mises à jour des applications du Store sans fermeture forcée (PowerShell 7, Windows Terminal).'
    $daily = $definition.Triggers.Create(2)
    $daily.StartBoundary = (Get-Date).Date.AddHours(12).ToString('s')
    $daily.DaysInterval = 1
    $daily.RandomDelay = 'PT1H'
    [void]$definition.Triggers.Create(9)
    $taskAction = $definition.Actions.Create(0)
    $taskAction.Path = 'conhost.exe'
    $taskAction.Arguments = Get-OSSetupStoreUpdateTaskArgument -Role System
    $definition.Principal.UserId = 'S-1-5-18'
    $definition.Principal.LogonType = 5
    $definition.Principal.RunLevel = 1
    $definition.Settings.StartWhenAvailable = $true
    $definition.Settings.MultipleInstances = 2
    $definition.Settings.ExecutionTimeLimit = 'PT30M'
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    # Système et administrateurs : contrôle total ; utilisateurs authentifiés : lecture et exécution.
    [void]$service.GetFolder('\').RegisterTaskDefinition($script:StoreUpdateTask.System, $definition, 6, 'SYSTEM', $null, 5,
        'D:(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;AU)')

    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::FromMinutes(20))
    Register-ScheduledTask -TaskName $script:StoreUpdateTask.User -Principal $principal -Settings $settings -Force `
        -Action (New-ScheduledTaskAction -Execute 'conhost.exe' -Argument (Get-OSSetupStoreUpdateTaskArgument -Role User)) `
        -Description 'OS-Setup : interroge le Store pour la tâche « OS-Setup - Store (système) ».' | Out-Null

    $logon = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logon.Delay = 'PT2M'
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval ([TimeSpan]::FromMinutes(15))
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::FromHours(24))
    Register-ScheduledTask -TaskName $script:StoreUpdateTask.Prompt -Principal $principal -Settings $settings -Trigger $logon, $repeat -Force `
        -Action (New-ScheduledTaskAction -Execute 'conhost.exe' -Argument (Get-OSSetupStoreUpdateTaskArgument -Role Prompt)) `
        -Description 'OS-Setup : propose la mise à jour d''une application du Store ouverte (PowerShell 7, Windows Terminal), ou un report.' | Out-Null
}
