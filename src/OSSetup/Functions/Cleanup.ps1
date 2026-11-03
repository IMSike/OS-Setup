# Nettoyage de fin de setup : uniquement ce que le bootstrap a lui-même laissé (state/bootstrap.json).
# Une copie de développement du dépôt n'est jamais supprimée.

function Read-OSSetupBootstrapInfo {
    <#
    .SYNOPSIS
        Retourne ce que le bootstrap a laissé (ownsClone, bootstrapScript, installedTools), ou $null.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Root
    )
    $path = Join-Path -Path $Root -ChildPath 'state\bootstrap.json'
    if (-not (Test-Path -Path $path)) { return $null }
    $info = Get-Content -Path $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    @{
        ownsClone       = [bool]$info['ownsClone']
        bootstrapScript = $info['bootstrapScript']
        installedTools  = @($info['installedTools'] | Where-Object { $_ })
    }
}

function Get-OSSetupSelectedWingetId {
    <#
    .SYNOPSIS
        Identifiants winget installés par les éléments retenus (profils et choix).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ItemId
    )
    foreach ($id in $ItemId) {
        foreach ($action in $Data.Items[$id]['actions']) {
            if ($action['provider'] -eq 'winget') { $action['id'] }
        }
    }
}

function Get-OSSetupToolToRemove {
    <#
    .SYNOPSIS
        Outils installés par le bootstrap pour faire tourner le setup, et qu'aucun élément retenu ne demande.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$InstalledTool = @(),

        [AllowEmptyCollection()]
        [string[]]$SelectedWingetId = @()
    )
    # Un ancien bootstrap notait le MSI (Microsoft.PowerShell) ; winget rattache aussi cet identifiant
    # au PowerShell du Store, qu'il désinstallerait. Les deux désignent le même outil.
    $sameTool = @{ 'Microsoft.PowerShell' = '9MZ1SNWT0N5D' }
    foreach ($tool in $InstalledTool) {
        if ($tool -notin $SelectedWingetId -and $sameTool[$tool] -notin $SelectedWingetId) { $tool }
    }
}

function Save-OSSetupHistory {
    <#
    .SYNOPSIS
        Copie journal, réponses et sauvegardes de l'exécution dans %LOCALAPPDATA%\OS-Setup\<runId>.
        Retourne le dossier créé.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId,

        [string]$HistoryRoot = (Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'OS-Setup')
    )
    $target = Join-Path -Path $HistoryRoot -ChildPath $RunId
    if (-not $PSCmdlet.ShouldProcess($target, 'Conserver l''historique')) { return }
    New-Item -Path $target -ItemType Directory -Force | Out-Null
    $sources = @(
        Join-Path -Path $Root -ChildPath "logs\setup-$RunId.log"
        Join-Path -Path $Root -ChildPath 'state\answers-last.json'
    )
    foreach ($source in $sources) {
        if (Test-Path -Path $source) { Copy-Item -Path $source -Destination $target -Force }
    }
    $backups = Join-Path -Path $Root -ChildPath "state\backups\$RunId"
    if (Test-Path -Path $backups) {
        Copy-Item -Path $backups -Destination (Join-Path -Path $target -ChildPath 'backups') -Recurse -Force
    }
    $target
}

function Invoke-OSSetupCleanup {
    <#
    .SYNOPSIS
        Fin de setup : exécute les commandes reportées à la fermeture du setup (ex. désinstallation du PowerShell
        qui l'exécute), désinstalle les outils du bootstrap non choisis et, si la copie du dépôt appartient au
        bootstrap, demande quoi garder (avec -Yes : l'historique). Le travail est fait par un processus détaché
        qui attend la fermeture du setup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Root,

        [Parameter(Mandatory)]
        [string]$RunId,

        # $null : liste inconnue (échec avant la résolution) ; aucun outil n'est alors désinstallé.
        [AllowNull()]
        [string[]]$SelectedWingetId,

        [switch]$Yes,

        # Commandes reportées par les actions (statut « atclose ») : { displayName; registryKey; filePath; arguments }.
        [AllowEmptyCollection()]
        [object[]]$RunAtClose = @(),

        # Ferme la session une fois le nettoyage fait (éléments effectifs à la prochaine ouverture de session).
        [switch]$Logoff,

        # Dossier du code dont src\cleanup.ps1 et la trace du bootstrap (state\bootstrap.json) sont lus : la copie de
        # la reprise pendant une reprise (le dépôt, modifiable par l'utilisateur, n'est pas relu), par défaut Root.
        [string]$CodeRoot = $Root,

        # Dossier où le script et sa configuration attendent la fermeture du setup : réservé aux administrateurs, car
        # ils sont exécutés avec les droits administrateur (commandes de désinstallation, chemins à supprimer).
        [string]$WorkRoot = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'OS-Setup', 'cleanup')
    )
    $info = Read-OSSetupBootstrapInfo -Root $CodeRoot

    # @(...) autour du if : sinon un résultat vide devient $null et un résultat unique une simple chaîne.
    $uninstall = @(if ($info -and $null -ne $SelectedWingetId) { Get-OSSetupToolToRemove -InstalledTool $info.installedTools -SelectedWingetId $SelectedWingetId })
    $remove = [System.Collections.Generic.List[string]]::new()
    $historyRoot = $null
    $logPath = $null

    if ($info -and $info.ownsClone) {
        $choice = if ($Yes) { 'history' } else {
            Write-OSSetupLog -Message ''
            $options = @(
                [pscustomobject]@{ Value = 'all'; Label = 'Tout supprimer (aucune trace, sauvegardes comprises)' }
                [pscustomobject]@{ Value = 'history'; Label = 'Garder l''historique : journal, réponses et sauvegardes des configurations remplacées' }
                [pscustomobject]@{ Value = 'keep'; Label = 'Tout garder (dépôt, journaux, état)' }
            )
            $state = New-OSSetupMenuState -Title "Fichiers du setup ($Root)" -Option $options -Mode action
            $state.Cursor = 1
            (Read-OSSetupMenu -State $state).Values[0]
        }
        if ($choice -eq 'history') {
            $historyRoot = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'OS-Setup'
            $logPath = Join-Path -Path $historyRoot -ChildPath "$RunId\setup-$RunId.log"
            Write-OSSetupLog -Message "√ Historique conservé : $(Split-Path -Path $logPath -Parent)"
        }
        if ($choice -ne 'keep') {
            $remove.Add($Root)
            if ($info.bootstrapScript) { $remove.Add($info.bootstrapScript) }
            Write-OSSetupLog -Message "√ Suppression à la fermeture : $($remove -join ', ')"
        }
        else {
            Write-OSSetupLog -Message "√ Fichiers conservés : $Root"
        }
    }
    $run = @($RunAtClose | Where-Object { $_ })
    if ($run.Count -gt 0) {
        Write-OSSetupLog -Message "√ Désinstallation à la fermeture du setup : $(@($run | ForEach-Object { $_['displayName'] }) -join ', ')"
    }
    if ($uninstall.Count -gt 0) {
        Write-OSSetupLog -Message "√ Désinstallation à la fermeture (outils du bootstrap non choisis) : $($uninstall -join ', ')"
    }
    # Copie en dernier : le journal conservé contient aussi les lignes ci-dessus.
    if ($logPath) {
        [void](Save-OSSetupHistory -Root $Root -RunId $RunId -HistoryRoot $historyRoot)
    }
    if ($run.Count -eq 0 -and $uninstall.Count -eq 0 -and $remove.Count -eq 0 -and -not $Logoff) { return }

    # Journal où le nettoyage consigne son résultat : l'historique conservé, sinon le journal du dépôt s'il reste
    # en place (clone non créé par le bootstrap, ou « tout garder »). Avec « tout supprimer », aucun.
    $cleanupLogPath = if ($logPath) { $logPath } elseif ($Root -notin $remove) { $script:LogPath } else { $null }

    if ($PSCmdlet.ShouldProcess('fin de setup', 'Lancer le nettoyage')) {
        $id = [guid]::NewGuid().ToString('N')
        New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null
        $script = Join-Path -Path $WorkRoot -ChildPath "OS-Setup-cleanup-$id.ps1"
        $config = Join-Path -Path $WorkRoot -ChildPath "OS-Setup-cleanup-$id.json"
        Copy-Item -Path (Join-Path -Path $CodeRoot -ChildPath 'src\cleanup.ps1') -Destination $script
        [ordered]@{ waitPid = $PID; run = $run; uninstall = $uninstall; remove = $remove.ToArray(); logPath = $cleanupLogPath; logoff = [bool]$Logoff } |
            ConvertTo-Json -Depth 4 | Set-Content -Path $config -Encoding utf8
        # Dossier de travail hors du dépôt : sinon le dossier à supprimer resterait verrouillé.
        Start-Process -FilePath ([IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell\v1.0\powershell.exe')) `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script`"", '-ConfigPath', "`"$config`"" `
            -WorkingDirectory ([System.IO.Path]::GetTempPath()) -WindowStyle Hidden
    }
}
