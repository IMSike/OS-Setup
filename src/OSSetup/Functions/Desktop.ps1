# Intégration au bureau : disposition de la barre des tâches et du menu Démarrer (Windows 10).
#
# Mécanisme officiel, sans API d'épinglage depuis 2018 : un fichier LayoutModification.xml appliqué par la stratégie
# « Start layout » verrouillée (prise en compte au redémarrage de l'Explorateur), puis déverrouillée et retirée :
# l'utilisateur garde la main, ses changements ultérieurs sont conservés (vérifié en VM).
# Les épingles remplacent celles de Windows et des installeurs (PinListPlacement="Replace").

$script:LayoutPolicyKey = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$script:LayoutMarkerKey = 'HKCU:\Software\OS-Setup'

function Get-OSSetupDesktopLayout {
    <#
    .SYNOPSIS
        Disposition voulue, agrégée depuis les éléments retenus : épingles (champ taskbarPin) et menu Démarrer
        (champ startLayout).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    $pins = [System.Collections.Generic.List[object]]::new()
    $emptyStart = $false
    foreach ($id in @($Context.ItemIds)) {
        $item = $Context.Data.Items[$id]
        $pin = $item['taskbarPin']
        if ($pin -and $pin['appId']) {
            $pins.Add([pscustomobject]@{ Name = $pin['name']; Link = $null; AppId = $pin['appId'] })
        }
        elseif ($pin) {
            $link = Expand-OSSetupString -Text $pin['link'] -Variables $Context.Variables
            $pins.Add([pscustomobject]@{ Name = [System.IO.Path]::GetFileNameWithoutExtension($link); Link = $link; AppId = $null })
        }
        if ($item['startLayout'] -eq 'empty') { $emptyStart = $true }
    }
    [pscustomobject]@{ Pins = $pins.ToArray(); EmptyStart = $emptyStart }
}

function ConvertTo-OSSetupLayoutXml {
    <#
    .SYNOPSIS
        Fichier LayoutModification.xml : menu Démarrer sans vignette (si demandé), barre des tâches remplacée (si des
        épingles sont demandées). Une partie absente du fichier n'est pas modifiée.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Layout
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">')
    $lines.Add('  <LayoutOptions StartTileGroupCellWidth="6" />')
    if ($Layout.EmptyStart) {
        $lines.Add('  <DefaultLayoutOverride>')
        $lines.Add('    <StartLayoutCollection>')
        $lines.Add('      <defaultlayout:StartLayout GroupCellWidth="6" />')
        $lines.Add('    </StartLayoutCollection>')
        $lines.Add('  </DefaultLayoutOverride>')
    }
    if (@($Layout.Pins).Count -gt 0) {
        $lines.Add('  <CustomTaskbarLayoutCollection PinListPlacement="Replace">')
        $lines.Add('    <defaultlayout:TaskbarLayout>')
        $lines.Add('      <taskbar:TaskbarPinList>')
        foreach ($pin in $Layout.Pins) {
            if ($pin.AppId) {
                $lines.Add("        <taskbar:UWA AppUserModelID=`"$([System.Security.SecurityElement]::Escape($pin.AppId))`" />")
            }
            else {
                $lines.Add("        <taskbar:DesktopApp DesktopApplicationLinkPath=`"$([System.Security.SecurityElement]::Escape($pin.Link))`" />")
            }
        }
        $lines.Add('      </taskbar:TaskbarPinList>')
        $lines.Add('    </defaultlayout:TaskbarLayout>')
        $lines.Add('  </CustomTaskbarLayoutCollection>')
    }
    $lines.Add('</LayoutModificationTemplate>')
    $lines -join "`r`n"
}

function Get-OSSetupLayoutHash {
    <#
    .SYNOPSIS
        Empreinte (SHA-256, hexadécimal) d'un fichier de disposition : enregistrée une fois la disposition appliquée,
        elle indique si la même disposition l'a déjà été.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Xml
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-OSSetupTaskbarPinName {
    <#
    .SYNOPSIS
        Noms des raccourcis épinglés à la barre des tâches (logiciels classiques ; les applications du Store
        épinglées n'y figurent pas).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $folder = Join-Path -Path ([Environment]::GetFolderPath('ApplicationData')) -ChildPath 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName }
}

function Wait-OSSetupTaskbarPin {
    <#
    .SYNOPSIS
        Attend que les raccourcis donnés soient épinglés à la barre des tâches (relue au démarrage de l'Explorateur).
        Retourne les noms toujours absents au bout du délai (rien si tous sont là).
    .DESCRIPTION
        Seules les épingles de raccourcis .lnk sont visibles dans le dossier lu (Get-OSSetupTaskbarPinName) : celles
        des applications du Store ne doivent pas être passées ici, elles ne seraient jamais trouvées.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Name,

        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $pinned = @(Get-OSSetupTaskbarPinName)
        $missing = @($Name | Where-Object { $_ -notin $pinned })
        if ($missing.Count -eq 0 -or (Get-Date) -ge $deadline) {
            foreach ($pin in $missing) { [string]$pin }
            return
        }
        Start-Sleep -Seconds 2
    }
}

function Get-OSSetupSessionExplorer {
    <#
    .SYNOPSIS
        Processus de l'Explorateur de la session courante. Élevé, le setup voit aussi ceux des autres sessions ouvertes
        sur la machine : il ne doit ni les arrêter ni se satisfaire de leur présence.
    #>
    [CmdletBinding()]
    param()
    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }
}

function Restart-OSSetupExplorer {
    <#
    .SYNOPSIS
        Redémarre l'Explorateur (barre des tâches, bureau). Windows le relance de lui-même dans la session de
        l'utilisateur, sans les droits administrateur du setup.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$TimeoutSeconds = 30
    )
    if (-not $PSCmdlet.ShouldProcess('Explorateur', 'Redémarrer')) { return }
    # Arrêté de force, l'Explorateur n'enregistre pas l'état de la barre des tâches (il le fait en se fermant
    # normalement) : un masquage automatique réglé pendant le setup serait perdu. Il est rétabli après le redémarrage.
    $autoHide = try { Get-OSSetupTaskbarAutoHide } catch { $false }
    Get-OSSetupSessionExplorer | Stop-Process -Force
    if (Wait-OSSetupExplorer -TimeoutSeconds $TimeoutSeconds) {
        Restore-OSSetupTaskbarAutoHide -Enabled $autoHide
        return
    }
    # Windows ne l'a pas relancé (constaté une fois pendant qu'un installeur créait ses raccourcis) : le lancer
    # nous-mêmes, sans les droits administrateur du setup (sinon tout ce qui serait ouvert depuis le bureau le serait).
    Write-OSSetupLog -Level Warning -Message "L'Explorateur n'a pas redémarré de lui-même en $TimeoutSeconds s : lancement par le setup."
    Start-OSSetupUnelevatedExplorer
    if (-not (Wait-OSSetupExplorer -TimeoutSeconds $TimeoutSeconds)) {
        throw "L'Explorateur n'a pas redémarré : fermer puis rouvrir la session."
    }
    Restore-OSSetupTaskbarAutoHide -Enabled $autoHide
}

function Restore-OSSetupTaskbarAutoHide {
    <#
    .SYNOPSIS
        Rétablit le masquage automatique de la barre des tâches après un redémarrage forcé de l'Explorateur.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )
    if (-not $Enabled) { return }
    try {
        if (-not (Get-OSSetupTaskbarAutoHide)) { Set-OSSetupTaskbarAutoHide -Enabled $true -Confirm:$false }
    }
    catch {
        Write-OSSetupLog -Level Warning -Message "Masquage automatique de la barre des tâches non rétabli : $($_.Exception.Message)"
    }
}

function Wait-OSSetupExplorer {
    <#
    .SYNOPSIS
        Attend que l'Explorateur tourne, puis laisse la barre des tâches se charger (et lire la disposition).
        Retourne $false si le délai est dépassé.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [int]$TimeoutSeconds = 30
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Get-OSSetupSessionExplorer) {
            Start-Sleep -Seconds 5
            return $true
        }
    }
    $false
}

function Start-OSSetupUnelevatedExplorer {
    <#
    .SYNOPSIS
        Lance l'Explorateur dans la session de l'utilisateur, sans droits administrateur : par une tâche planifiée
        temporaire (niveau d'exécution limité), supprimée aussitôt après.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('Explorateur', 'Lancer sans droits administrateur')) { return }
    $taskName = 'OS-Setup - Explorateur'
    # Dossiers de Windows lus auprès du système, pas dans %WINDIR% : l'utilisateur peut redéfinir cette variable
    # (HKCU\Environment) sans droits administrateur, et schtasks.exe est lancé avec ceux du setup.
    $systemDirectory = [Environment]::SystemDirectory
    $explorer = Join-Path -Path (Split-Path -Path $systemDirectory -Parent) -ChildPath 'explorer.exe'
    # Cmdlets CDXML (module ScheduledTasks) : elles n'héritent pas de $ErrorActionPreference du module, d'où
    # -ErrorAction Stop (sinon l'erreur reste non bloquante et sa cause se perd).
    $action = New-ScheduledTaskAction -Execute $explorer -ErrorAction Stop
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited -ErrorAction Stop
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force -ErrorAction Stop | Out-Null
    try {
        # Un échec ici n'est pas fatal en soi : l'appelant vérifie ensuite que l'Explorateur tourne.
        Invoke-OSSetupNativeCommand -FilePath (Join-Path -Path $systemDirectory -ChildPath 'schtasks.exe') -ArgumentList '/run', '/tn', $taskName -NoThrow
        Start-Sleep -Seconds 2
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    }
}

function Set-OSSetupDesktopLayout {
    <#
    .SYNOPSIS
        Applique la disposition : stratégie verrouillée, redémarrage de l'Explorateur, puis déverrouillage et
        retrait de la stratégie (l'utilisateur garde la main). Enregistre l'empreinte de la disposition appliquée,
        seulement si les épingles attendues sont bien là : sinon, erreur, et la disposition sera réappliquée.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        $Layout
    )
    $xml = ConvertTo-OSSetupLayoutXml -Layout $Layout
    if (-not $PSCmdlet.ShouldProcess('barre des tâches et menu Démarrer', 'Appliquer la disposition')) { return }
    $file = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'OS-Setup\StartLayout.xml'
    New-Item -Path (Split-Path -Path $file -Parent) -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath $file -Value $xml -Encoding utf8
    # Jamais New-Item -Force sur une clé existante : il la recrée vide (d'autres réglages y sont rangés).
    if (-not (Test-Path -LiteralPath $script:LayoutPolicyKey)) { New-Item -Path $script:LayoutPolicyKey -Force | Out-Null }
    # Épingles présentes avant la pose de la stratégie : leur raccourci .lnk existe déjà, il ne prouve pas que
    # l'Explorateur a relu la disposition. Seules les épingles nouvelles sont attendues après le redémarrage.
    $pinnedBefore = @(Get-OSSetupTaskbarPinName)
    try {
        Set-ItemProperty -LiteralPath $script:LayoutPolicyKey -Name StartLayoutFile -Type ExpandString -Value $file
        Set-ItemProperty -LiteralPath $script:LayoutPolicyKey -Name LockedStartLayout -Type DWord -Value 1
        Restart-OSSetupExplorer -Confirm:$false
        # La barre des tâches est relue au démarrage de l'Explorateur : on attend que les épingles soient là. Seules
        # celles des raccourcis .lnk sont visibles dans le dossier lu ; celles des applications du Store n'y figurent pas.
        # Aucune épingle nouvelle attendue : pas d'attente.
        $expected = @($Layout.Pins | Where-Object { $_.Link -and $_.Name -notin $pinnedBefore } | ForEach-Object { $_.Name })
        if ($expected.Count -gt 0) {
            $missing = @(Wait-OSSetupTaskbarPin -Name $expected -TimeoutSeconds 30)
            if ($missing.Count -gt 0) {
                throw "Disposition non appliquée : épingle(s) absente(s) de la barre des tâches après 30 s ($($missing -join ', ')). Elle sera réappliquée au prochain lancement."
            }
        }
    }
    finally {
        # Le retrait de la stratégie et du fichier est garanti, même si le déverrouillage ou le redémarrage échoue :
        # sinon la disposition resterait imposée (verrouillée) à chaque ouverture de session.
        try {
            # Déverrouillage, pris en compte au redémarrage de l'Explorateur : la disposition reste, l'utilisateur
            # peut de nouveau la modifier.
            Set-ItemProperty -LiteralPath $script:LayoutPolicyKey -Name LockedStartLayout -Type DWord -Value 0
            Restart-OSSetupExplorer -Confirm:$false
        }
        finally {
            Remove-ItemProperty -LiteralPath $script:LayoutPolicyKey -Name StartLayoutFile, LockedStartLayout -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-Path -LiteralPath $script:LayoutMarkerKey)) { New-Item -Path $script:LayoutMarkerKey -Force | Out-Null }
    Set-ItemProperty -LiteralPath $script:LayoutMarkerKey -Name DesktopLayout -Type String -Value (Get-OSSetupLayoutHash -Xml $xml)
}

function Get-OSSetupDesktopLayoutMarker {
    <#
    .SYNOPSIS
        Empreinte de la dernière disposition appliquée (HKCU\Software\OS-Setup, valeur DesktopLayout) ; $null si aucune.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $values = Get-ItemProperty -LiteralPath $script:LayoutMarkerKey -ErrorAction SilentlyContinue
    if ($values -and $values.PSObject.Properties['DesktopLayout']) { $values.DesktopLayout } else { $null }
}

function Initialize-OSSetupAppBarApi {
    <#
    .SYNOPSIS
        Déclare une fois par session les fonctions Windows de la barre des tâches (SHAppBarMessage, FindWindow) et
        leurs structures, utilisées pour lire et régler son masquage automatique.
    #>
    [CmdletBinding()]
    param()
    if ('OSSetup.AppBar' -as [type]) { return }
    Add-Type -Namespace OSSetup -Name AppBar -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
[DllImport("shell32.dll")]
public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
'@
}

function Get-OSSetupTaskbarAutoHide {
    <#
    .SYNOPSIS
        Vrai si la barre des tâches se masque automatiquement (API SHAppBarMessage, ABM_GETSTATE).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    Initialize-OSSetupAppBarApi
    $data = New-Object -TypeName OSSetup.AppBar+APPBARDATA
    $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)
    # ABM_GETSTATE = 4 ; ABS_AUTOHIDE = 1
    ([OSSetup.AppBar]::SHAppBarMessage(4, [ref]$data).ToUInt64() -band 1) -ne 0
}

function Set-OSSetupTaskbarAutoHide {
    <#
    .SYNOPSIS
        Active ou désactive le masquage automatique de la barre des tâches, comme la case de Paramètres : effet immédiat,
        mémorisé par l'Explorateur.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )
    Initialize-OSSetupAppBarApi
    $data = New-Object -TypeName OSSetup.AppBar+APPBARDATA
    $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)
    $data.hWnd = [OSSetup.AppBar]::FindWindow('Shell_TrayWnd', $null)
    if ($data.hWnd -eq [IntPtr]::Zero) { throw 'Barre des tâches introuvable (Explorateur arrêté ?).' }
    $state = [OSSetup.AppBar]::SHAppBarMessage(4, [ref]$data).ToUInt64()
    $state = if ($Enabled) { $state -bor 1 } else { $state -band (-bnot [uint64]1) }
    $data.lParam = [IntPtr][int64]$state
    if ($PSCmdlet.ShouldProcess('barre des tâches', "masquage automatique : $Enabled")) {
        # ABM_SETSTATE = 10
        [void][OSSetup.AppBar]::SHAppBarMessage(10, [ref]$data)
    }
}
