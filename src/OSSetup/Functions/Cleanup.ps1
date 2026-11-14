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
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $info = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    @{
        ownsClone       = [bool]$info['ownsClone']
        bootstrapScript = $info['bootstrapScript']
        installedTools  = @($info['installedTools'] | Where-Object { $_ })
    }
}

function Test-OSSetupRemovableBootstrapScript {
    <#
    .SYNOPSIS
        Vrai si le script du bootstrap noté dans state/bootstrap.json peut être supprimé par le nettoyage de fin : un
        fichier .ps1 posé directement dans le dossier temporaire de l'utilisateur (%USERPROFILE%\AppData\Local\Temp)
        ou dans son dossier Téléchargements (%USERPROFILE%\Downloads).
    .DESCRIPTION
        bootstrap.json est dans la copie du dépôt, modifiable sans élévation, et le nettoyage de fin s'exécute en
        administrateur : sans ce contrôle, un programme de la session pourrait y inscrire n'importe quel chemin à
        supprimer. Le bootstrap se télécharge dans %TEMP% (procédure documentée) ou dans Téléchargements.
        Les deux dossiers sont déduits du seul dossier du profil, que l'utilisateur ne peut pas déplacer sans
        élévation : pas de la variable TMP ni des dossiers de l'Explorateur (HKCU\...\Shell Folders, lus aussi par
        l'API des dossiers connus), qu'un programme de la session pourrait faire pointer vers un dossier protégé. Un
        dossier temporaire ou Téléchargements déplacé ailleurs n'est donc pas reconnu : le script y est conservé.
    .PARAMETER UserProfile
        Dossier du profil de l'utilisateur (par défaut celui du compte qui exécute le setup).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [string]$UserProfile = [Environment]::GetFolderPath('UserProfile')
    )
    if (-not $Path -or -not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -ne '.ps1') { return $false }
    if (-not $UserProfile) { return $false }
    $parent = try { [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)).TrimEnd('\') } catch { return $false }
    foreach ($allowed in @([IO.Path]::Combine($UserProfile, 'AppData', 'Local', 'Temp'), [IO.Path]::Combine($UserProfile, 'Downloads'))) {
        $allowedPath = [IO.Path]::GetFullPath($allowed).TrimEnd('\')
        if ($parent.Equals($allowedPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Get-OSSetupSelectedWingetId {
    <#
    .SYNOPSIS
        Identifiants winget installés par les éléments retenus (profils et choix).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Catalogue chargé par Import-OSSetupData.
        [Parameter(Mandatory)]
        [pscustomobject]$Data,

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
    foreach ($tool in $InstalledTool) {
        if ($tool -notin $SelectedWingetId) { $tool }
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
    # Reprise élevée : ni la destination ni les sources ne passent par un lien (un lien parmi les sauvegardes ferait
    # copier un fichier protégé vers un dossier lisible par l'utilisateur).
    Assert-OSSetupDataPath -Path $target
    New-Item -Path $target -ItemType Directory -Force | Out-Null
    $sources = @(
        Join-Path -Path $Root -ChildPath "logs\setup-$RunId.log"
        Join-Path -Path $Root -ChildPath 'state\answers-last.json'
    )
    foreach ($source in $sources) {
        Assert-OSSetupDataPath -Path $source
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $target -Force }
    }
    $backups = Join-Path -Path $Root -ChildPath "state\backups\$RunId"
    Assert-OSSetupDataPath -Path $backups
    if (Test-Path -LiteralPath $backups) {
        # Tous les éléments : un lien physique n'a pas d'attribut qui le signale.
        foreach ($entry in @(Get-ChildItem -LiteralPath $backups -Recurse -Force)) {
            Assert-OSSetupDataPath -Path $entry.FullName
        }
        Copy-Item -LiteralPath $backups -Destination (Join-Path -Path $target -ChildPath 'backups') -Recurse -Force
    }
    $target
}

function Invoke-OSSetupCleanup {
    <#
    .SYNOPSIS
        Fin de setup : désinstalle les outils du bootstrap non choisis et, si la copie du dépôt appartient au
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

        # Ferme la session une fois le nettoyage fait (éléments effectifs à la prochaine ouverture de session).
        [switch]$Logoff,

        # Dossier du code dont src\cleanup.ps1 et la trace du bootstrap (state\bootstrap.json) sont lus : la copie de
        # la reprise pendant une reprise (le dépôt, modifiable par l'utilisateur, n'est pas relu), par défaut Root.
        [string]$CodeRoot = $Root,

        # Dossier où le script et sa configuration attendent la fermeture du setup : réservé aux administrateurs, car
        # ils sont exécutés avec les droits administrateur (commandes de désinstallation, chemins à supprimer).
        [string]$WorkRoot = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'OS-Setup', 'cleanup'),

        # Dossier de l'historique conservé (un sous-dossier par exécution).
        [string]$HistoryRoot = (Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'OS-Setup')
    )
    $info = Read-OSSetupBootstrapInfo -Root $CodeRoot

    # @(...) autour du if : sinon un résultat vide devient $null et un résultat unique une simple chaîne.
    $uninstall = @(if ($info -and $null -ne $SelectedWingetId) { Get-OSSetupToolToRemove -InstalledTool $info.installedTools -SelectedWingetId $SelectedWingetId })
    $remove = [System.Collections.Generic.List[string]]::new()
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
            $logPath = Join-Path -Path $HistoryRoot -ChildPath "$RunId\setup-$RunId.log"
            Write-OSSetupLog -Message "√ Historique conservé : $(Split-Path -Path $logPath -Parent)"
        }
        if ($choice -ne 'keep') {
            $remove.Add($Root)
            if ($info.bootstrapScript) {
                if (Test-OSSetupRemovableBootstrapScript -Path $info.bootstrapScript) { $remove.Add($info.bootstrapScript) }
                else { Write-OSSetupLog -Level Warning -Message "Script du bootstrap conservé (hors de %TEMP% et de Téléchargements) : $($info.bootstrapScript)" }
            }
            Write-OSSetupLog -Message "√ Suppression à la fermeture : $($remove -join ', ')"
        }
        else {
            Write-OSSetupLog -Message "√ Fichiers conservés : $Root"
        }
    }
    if ($uninstall.Count -gt 0) {
        Write-OSSetupLog -Message "√ Désinstallation à la fermeture (outils du bootstrap non choisis) : $($uninstall -join ', ')"
    }
    # Copie en dernier : le journal conservé contient aussi les lignes ci-dessus.
    if ($logPath) {
        [void](Save-OSSetupHistory -Root $Root -RunId $RunId -HistoryRoot $HistoryRoot)
    }
    if ($uninstall.Count -eq 0 -and $remove.Count -eq 0 -and -not $Logoff) { return }

    # Journal où le nettoyage consigne son résultat : l'historique conservé, sinon le journal du dépôt s'il reste
    # en place (clone non créé par le bootstrap, ou « tout garder »). Avec « tout supprimer », aucun.
    $cleanupLogPath = if ($logPath) { $logPath } elseif ($Root -notin $remove) { $script:LogPath } else { $null }

    if ($PSCmdlet.ShouldProcess('fin de setup', 'Lancer le nettoyage')) {
        $id = [guid]::NewGuid().ToString('N')
        New-Item -Path $WorkRoot -ItemType Directory -Force | Out-Null
        $script = Join-Path -Path $WorkRoot -ChildPath "OS-Setup-cleanup-$id.ps1"
        $config = Join-Path -Path $WorkRoot -ChildPath "OS-Setup-cleanup-$id.json"
        Copy-Item -LiteralPath (Join-Path -Path $CodeRoot -ChildPath 'src\cleanup.ps1') -Destination $script
        [ordered]@{ waitPid = $PID; uninstall = $uninstall; remove = $remove.ToArray(); logPath = $cleanupLogPath; logoff = [bool]$Logoff } |
            ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8
        # Dossier de travail hors du dépôt : sinon le dossier à supprimer resterait verrouillé.
        Start-Process -FilePath (Get-OSSetupWindowsPowerShellPath) `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$script`"", '-ConfigPath', "`"$config`"" `
            -WorkingDirectory ([System.IO.Path]::GetTempPath()) -WindowStyle Hidden
    }
}
