# Pilotes : Windows Update (API intégrée, objet COM Microsoft.Update.Session) et bilan des périphériques.

# Résultats de recherche mémorisés pendant l'exécution (la recherche est lente), effacés après une installation.
$script:WindowsUpdateCache = @{}

$script:WindowsUpdateCriteria = @{
    # Pilotes non installés, applicables au matériel présent, non masqués par l'utilisateur.
    drivers = "IsInstalled=0 and Type='Driver' and IsHidden=0"
}

function Find-OSSetupWindowsUpdate {
    <#
    .SYNOPSIS
        Mises à jour proposées par Windows Update pour une catégorie (objets IUpdate). La recherche interroge les
        serveurs de Microsoft : compter d'une à quelques minutes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('drivers')]
        [string]$Category
    )
    if (-not $script:WindowsUpdateCache.ContainsKey($Category)) {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'OS-Setup'
        $result = $session.CreateUpdateSearcher().Search($script:WindowsUpdateCriteria[$Category])
        $script:WindowsUpdateCache[$Category] = @(foreach ($update in $result.Updates) { $update })
    }
    $script:WindowsUpdateCache[$Category]
}

function Install-OSSetupWindowsUpdate {
    <#
    .SYNOPSIS
        Télécharge et installe des mises à jour Windows Update. Retourne @{ RebootRequired; Failed } (titres en échec).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Update
    )
    $outcome = [pscustomobject]@{ RebootRequired = $false; Failed = @() }
    if ($Update.Count -eq 0 -or -not $PSCmdlet.ShouldProcess("$($Update.Count) mise(s) à jour", 'Installer')) { return $outcome }
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'OS-Setup'
    $collection = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($item in $Update) {
        if (-not $item.EulaAccepted) { $item.AcceptEula() }
        [void]$collection.Add($item)
    }
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $collection
    [void]$downloader.Download()
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $collection
    $result = $installer.Install()
    # Les résultats mémorisés ne sont plus à jour.
    $script:WindowsUpdateCache.Clear()
    $outcome.RebootRequired = [bool]$result.RebootRequired
    # ResultCode : 2 = réussi, 3 = réussi avec erreurs, 4 = échec, 5 = annulé.
    $outcome.Failed = @(for ($i = 0; $i -lt $collection.Count; $i++) {
            if ($result.GetUpdateResult($i).ResultCode -ge 4) { $collection.Item($i).Title }
        })
    $outcome
}

function Get-OSSetupDeviceProblem {
    <#
    .SYNOPSIS
        Périphériques signalés en erreur par le Gestionnaire de périphériques (sans pilote, en erreur, désactivés).
    #>
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { return }
    $labels = @{ 1 = 'mal configuré'; 10 = 'ne peut pas démarrer'; 22 = 'désactivé'; 28 = 'aucun pilote installé'; 31 = 'pilote en erreur'; 43 = 'arrêté après un problème signalé' }
    foreach ($device in Get-CimInstance -ClassName Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0') {
        $code = [int]$device.ConfigManagerErrorCode
        $label = if ($labels.ContainsKey($code)) { $labels[$code] } else { "erreur (code $code)" }
        $name = if ($device.Name) { $device.Name } else { $device.DeviceID }
        [pscustomobject]@{ Name = $name; Code = $code; Problem = $label }
    }
}

function Write-OSSetupDeviceReport {
    <#
    .SYNOPSIS
        Ajoute au récapitulatif les périphériques sans pilote ou en erreur : ce qui reste à faire à la main.
    #>
    [CmdletBinding()]
    param()
    $problems = @(Get-OSSetupDeviceProblem)
    if ($problems.Count -eq 0) {
        Write-OSSetupLog -Level Success -Message 'Périphériques : aucun sans pilote ni en erreur.'
        return
    }
    Write-OSSetupLog -Level Warning -Message "Périphériques à vérifier (Gestionnaire de périphériques) : $($problems.Count)"
    foreach ($problem in $problems) {
        Write-OSSetupLog -Level Warning -Message "  $($problem.Name) : $($problem.Problem)"
    }
}
