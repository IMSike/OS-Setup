# Reprise après redémarrage : tâche planifiée à l'ouverture de session, droits les plus élevés (ADR 0005).
#   %ProgramFiles%\OS-Setup\resume\        copie figée du setup (code, catalogue, dotfiles) et lanceur resume.ps1,
#                                          modifiables par les seuls administrateurs ; supprimée à la fin
#   %ProgramFiles%\OS-Setup\resume\state\run.json  exécution en cours, à reprendre (supprimé à la fin)
#   <dépôt>\state\last-result.json        résultat de la dernière exécution terminée (code de sortie)
# Journaux, sauvegardes et réponses restent dans le dépôt (dataRoot de run.json) : la reprise les écrit, ne les lit pas.

$script:ResumeTaskName = 'OS-Setup - reprise'
$script:MaxPasses = 5
# Entrées de la racine du dépôt que la copie figée ne reprend pas : inutiles à l'exécution, ou état de l'utilisateur.
$script:ResumeCopyExclude = @('.git', '.github', '.githooks', '.claude', '.maintainer', '.vscode', 'docs', 'logs', 'state', 'tests')

function Get-OSSetupResumeRoot {
    <#
    .SYNOPSIS
        Dossier de la copie figée de la reprise : %ProgramFiles%\OS-Setup\resume (chemin connu par l'API, pas par une
        variable d'environnement que l'utilisateur pourrait redéfinir).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'OS-Setup', 'resume')
}

function Copy-OSSetupResumeCode {
    <#
    .SYNOPSIS
        Copie le setup (code, catalogue, profils, schémas, dotfiles) dans le dossier de la reprise, avec le lanceur
        src\resume.ps1 à sa racine. Sans effet quand le setup s'exécute déjà depuis cette copie (reprise suivante).
    .DESCRIPTION
        Le dossier hérite des droits de Program Files : lecture seule pour les utilisateurs. Son sous-dossier state
        (run.json) est conservé ; le reste est remplacé. Les liens et jonctions de la racine du dépôt sont ignorés.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [string]$Destination = (Get-OSSetupResumeRoot)
    )
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($source -eq $target) { return }
    if (-not $PSCmdlet.ShouldProcess($target, 'Copier le setup pour la reprise')) { return }
    New-Item -Path $target -ItemType Directory -Force | Out-Null
    Get-ChildItem -LiteralPath $target -Force | Where-Object { $_.Name -ne 'state' } | Remove-Item -Recurse -Force
    foreach ($entry in Get-ChildItem -LiteralPath $source -Force) {
        if ($entry.Name -in $script:ResumeCopyExclude -or $entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        Copy-Item -LiteralPath $entry.FullName -Destination $target -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path -Path $source -ChildPath 'src\resume.ps1') -Destination (Join-Path -Path $target -ChildPath 'resume.ps1') -Force
    # Trace du bootstrap (outils à désinstaller, chemins à supprimer) : le nettoyage de fin de la reprise la lit ici,
    # pas dans le dépôt, que l'utilisateur peut modifier.
    $bootstrapInfo = Join-Path -Path $source -ChildPath 'state\bootstrap.json'
    $targetState = Join-Path -Path $target -ChildPath 'state'
    Remove-Item -LiteralPath (Join-Path -Path $targetState -ChildPath 'bootstrap.json') -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $bootstrapInfo -PathType Leaf) {
        New-Item -Path $targetState -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $bootstrapInfo -Destination $targetState -Force
    }
}

function Remove-OSSetupResumeCode {
    <#
    .SYNOPSIS
        Supprime la copie figée de la reprise (fin d'exécution, ou reste d'une exécution abandonnée).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = (Get-OSSetupResumeRoot)
    )
    if ((Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, 'Supprimer la copie de la reprise')) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Save-OSSetupRunState {
    <#
    .SYNOPSIS
        Enregistre l'exécution à reprendre après redémarrage.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot,

        [Parameter(Mandatory)]
        [hashtable]$State
    )
    $path = Join-Path -Path $StateRoot -ChildPath 'run.json'
    if ($PSCmdlet.ShouldProcess($path, 'Enregistrer l''état de reprise')) {
        New-Item -Path $StateRoot -ItemType Directory -Force | Out-Null
        # Fichier temporaire puis renommage : une coupure pendant l'écriture ne laisse jamais un état tronqué.
        $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$path.tmp" -Encoding utf8NoBOM
        Move-Item -LiteralPath "$path.tmp" -Destination $path -Force
    }
}

function Read-OSSetupRunState {
    <#
    .SYNOPSIS
        Retourne l'exécution à reprendre, ou $null s'il n'y en a pas.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot
    )
    $path = Join-Path -Path $StateRoot -ChildPath 'run.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $state = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    # Les tableaux JSON arrivent en List : les réponses attendent des tableaux.
    $answers = $state['answers']
    $answers['profiles'] = @($answers['profiles'])
    if ($null -eq $answers['choices']) { $answers['choices'] = @{} }
    foreach ($key in @($answers['choices'].Keys)) { $answers['choices'][$key] = @($answers['choices'][$key]) }
    if ($null -eq $answers['variables']) { $answers['variables'] = @{} }
    $state
}

function Remove-OSSetupRunState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot
    )
    $path = Join-Path -Path $StateRoot -ChildPath 'run.json'
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Supprimer l''état de reprise')) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Write-OSSetupRunResult {
    <#
    .SYNOPSIS
        Écrit le résultat d'une exécution terminée (lu notamment par les tests en VM).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot,

        [Parameter(Mandatory)]
        [string]$RunId,

        [Parameter(Mandatory)]
        [int]$ExitCode
    )
    $path = Join-Path -Path $StateRoot -ChildPath 'last-result.json'
    if ($PSCmdlet.ShouldProcess($path, 'Enregistrer le résultat')) {
        Assert-OSSetupDataPath -Path $path
        New-Item -Path $StateRoot -ItemType Directory -Force | Out-Null
        [ordered]@{ runId = $RunId; exitCode = $ExitCode; finishedAt = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    }
}

# Vrai pendant la reprise élevée : chaque écriture de données est alors contrôlée (Assert-OSSetupDataPath).
$script:DataGuardEnabled = $false

function Enable-OSSetupDataGuard {
    <#
    .SYNOPSIS
        Active, pour la reprise élevée, la vérification des chemins écrits (ADR 0005).
    .DESCRIPTION
        Le contrôle porte sur tout chemin écrit, pas seulement sur le dépôt : l'historique, hors du dépôt, est
        protégé de la même façon. D'où l'absence de dossier racine.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'État du module seulement.')]
    param()
    $script:DataGuardEnabled = $true
}

function Assert-OSSetupDataPath {
    <#
    .SYNOPSIS
        Pendant la reprise élevée, refuse d'écrire dans un chemin dont un dossier est une jonction ou un lien
        symbolique, ou dont le fichier est un lien.
    .DESCRIPTION
        La reprise s'exécute en administrateur depuis une copie protégée (ADR 0005), mais écrit ses données (journal,
        sauvegardes, réponses, résultat) dans le dépôt de l'utilisateur. Un programme lancé sous son compte, sans
        droits administrateur, pourrait y remplacer un dossier par une jonction et faire écrire le setup dans un
        dossier protégé. Tout le chemin est contrôlé, jusqu'à la racine du disque, juste avant chaque écriture ; reste
        l'intervalle entre le contrôle et l'écriture. Les autres points d'analyse (fichiers OneDrive à la demande)
        sont acceptés. Sans effet hors reprise : le code du premier passage vient de toute façon du dépôt.
        Même règle que Test-CleanupLink (src\cleanup.ps1, sans le module), à garder alignée.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not $script:DataGuardEnabled) { return }
    $current = [IO.Path]::GetFullPath($Path)
    $leaf = $true
    while ($current) {
        $attributes = try { [IO.File]::GetAttributes($current) } catch { $null }
        if ($null -ne $attributes) {
            $isDirectory = [bool]($attributes -band [IO.FileAttributes]::Directory)
            # Lien physique : seulement pour le fichier écrit (un dossier n'en a pas).
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or ($leaf -and -not $isDirectory)) {
                $linkType = (Get-Item -LiteralPath $current -Force).LinkType
                if ($linkType -in 'Junction', 'SymbolicLink', 'HardLink') {
                    throw "Écriture refusée par sécurité : $current est un lien ($linkType) ; la reprise élevée n'écrit pas au travers d'un lien (ADR 0005)."
                }
            }
        }
        $leaf = $false
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-OSSetupPwshPath {
    <#
    .SYNOPSIS
        Exécutable PowerShell de la relance élevée : l'alias d'exécution du PowerShell du Store
        (%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe) dès qu'il existe, quel que soit le PowerShell courant ;
        sinon celui du processus courant.
    .DESCRIPTION
        Le chemin du paquet du Store contient sa version et change à chaque mise à jour ; l'alias d'exécution reste.
        Sur un ancien poste lancé depuis un MSI de PowerShell 7, que l'élément pwsh désinstalle, la relance ne doit
        pas dépendre de ce MSI. La tâche de reprise, elle, n'utilise pas l'alias, modifiable par l'utilisateur : voir
        src\resume.ps1 (ADR 0005).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $alias = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'Microsoft', 'WindowsApps', 'pwsh.exe')
    if (Test-Path -LiteralPath $alias) { return $alias }
    $pwsh = (Get-Process -Id $PID).Path
    # Alias absent mais PowerShell du Store en cours (cas improbable) : le chemin versionné ne survivrait pas à une mise à jour.
    if ($pwsh -like '*\WindowsApps\Microsoft.PowerShell_*') { return $alias }
    $pwsh
}

function Register-OSSetupResumeTask {
    <#
    .SYNOPSIS
        Tâche planifiée qui relance le setup (-Resume) à l'ouverture de session de l'utilisateur courant,
        avec les droits les plus élevés : aucune nouvelle invite UAC.
    .DESCRIPTION
        Elle exécute Windows PowerShell 5.1 (System32) sur le lanceur resume.ps1 de la copie figée (ResumeRoot) :
        exécutable, script et état modifiables par les seuls administrateurs (ADR 0005). Le lanceur retrouve à chaque
        reprise le pwsh.exe du paquet du Store, dont le chemin change à chaque mise à jour, à défaut celui du MSI de
        PowerShell 7 sous Program Files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ResumeRoot = (Get-OSSetupResumeRoot)
    )
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $powershell = Get-OSSetupWindowsPowerShellPath
    $launcher = Join-Path -Path $ResumeRoot -ChildPath 'resume.ps1'
    # Cmdlets CDXML (module ScheduledTasks) : elles n'héritent pas de $ErrorActionPreference du module, d'où
    # -ErrorAction Stop. Un échec doit lever : setup.ps1 retire alors la copie et l'état au lieu d'attendre une reprise
    # sans tâche.
    $action = New-ScheduledTaskAction -Execute $powershell -WorkingDirectory (Split-Path -Path $ResumeRoot -Parent) `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`"" -ErrorAction Stop
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user -ErrorAction Stop
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest -ErrorAction Stop
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -ErrorAction Stop
    if ($PSCmdlet.ShouldProcess($script:ResumeTaskName, 'Créer la tâche de reprise')) {
        Register-ScheduledTask -TaskName $script:ResumeTaskName -Action $action -Trigger $trigger -Principal $principal `
            -Settings $settings -Description 'Reprise d''OS-Setup après redémarrage (supprimée à la fin).' -Force -ErrorAction Stop | Out-Null
    }
}

function Get-OSSetupResumePwshPath {
    <#
    .SYNOPSIS
        pwsh.exe que le lanceur de la reprise exécutera : celui du paquet du PowerShell 7 du Store installé pour le
        compte (version la plus récente), sinon celui du MSI de PowerShell 7 (%ProgramFiles%\PowerShell\7), sinon $null.
    .DESCRIPTION
        Les deux sont modifiables par les seuls administrateurs (ADR 0005) ; un paquet inscrit en mode développeur,
        depuis un dossier quelconque, est écarté. Même règle que Get-ResumePwshPath (src\resume.ps1), qui ne charge pas
        le module et relit les paquets à chaque reprise (le dossier du paquet change à chaque mise à jour) : garder les
        deux alignés.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $found = $null
    $foundVersion = $null
    try {
        Import-OSSetupAppxModule
        foreach ($package in @(Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction Stop)) {
            if ($package.IsDevelopmentMode -or -not $package.InstallLocation) { continue }
            $exe = Join-Path -Path $package.InstallLocation -ChildPath 'pwsh.exe'
            $version = [version]$package.Version
            if ([IO.File]::Exists($exe) -and ($null -eq $foundVersion -or $version -gt $foundVersion)) {
                $found = $exe
                $foundVersion = $version
            }
        }
    }
    catch {
        Write-OSSetupLog -Level Detail -Message "Paquets du Store illisibles : $($_.Exception.Message)"
    }
    if ($found) { return $found }
    $msi = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'PowerShell', '7', 'pwsh.exe')
    if ([IO.File]::Exists($msi)) { return $msi }
    $null
}

function Test-OSSetupResumePwsh {
    <#
    .SYNOPSIS
        Vrai si la reprise automatique est possible : le lanceur trouvera un pwsh.exe modifiable par les seuls
        administrateurs (paquet du Store ou MSI). Faux pour un PowerShell 7 installé autrement (archive, dotnet tool…).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    [bool](Get-OSSetupResumePwshPath)
}

function Unregister-OSSetupResumeTask {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $task = Get-ScheduledTask -TaskName $script:ResumeTaskName -ErrorAction SilentlyContinue
    if ($task -and $PSCmdlet.ShouldProcess($script:ResumeTaskName, 'Supprimer la tâche de reprise')) {
        # Appelée en fin d'exécution et quand une reprise est abandonnée : un échec est signalé sans interrompre la
        # suite (état, nettoyage). -ErrorAction Stop : cmdlet CDXML, qui n'hérite pas de la préférence du module.
        try {
            Unregister-ScheduledTask -TaskName $script:ResumeTaskName -Confirm:$false -ErrorAction Stop
        }
        catch {
            Write-OSSetupLog -Level Warning -Message ("Tâche de reprise « $($script:ResumeTaskName) » non supprimée : " +
                "$($_.Exception.Message) Supprimez-la dans le Planificateur de tâches.")
        }
    }
}

function Get-OSSetupMaxPass {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    $script:MaxPasses
}

function Wait-OSSetupUserSession {
    <#
    .SYNOPSIS
        À la reprise, la tâche démarre dès l'ouverture de session : on attend que le bureau soit chargé.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { return }
        Start-Sleep -Seconds 2
    }
}

function Wait-OSSetupCountdown {
    <#
    .SYNOPSIS
        Affiche un compte à rebours seconde par seconde ; dans une console interactive, une touche l'interrompt.
        Retourne $true s'il arrive à son terme, $false si une touche l'a interrompu.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        # Texte ajouté au décompte quand une touche peut l'interrompre (console interactive).
        [Parameter(Mandatory)]
        [string]$Hint,

        [int]$Seconds = 10
    )
    $interactive = Test-OSSetupInteractiveConsole
    $shownHint = if ($interactive) { $Hint } else { '' }
    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        Write-Host -Object ("`r$Label dans $remaining s$shownHint ") -NoNewline -ForegroundColor Yellow
        $deadline = (Get-Date).AddSeconds(1)
        while ((Get-Date) -lt $deadline) {
            if ($interactive -and [Console]::KeyAvailable) {
                [void][Console]::ReadKey($true)
                Write-Host ''
                return $false
            }
            Start-Sleep -Milliseconds 100
        }
    }
    Write-Host ''
    $true
}

function Request-OSSetupLogoff {
    <#
    .SYNOPSIS
        Demande la fermeture de la session en fin de setup. Sans -Immediate : compte à rebours de 10 secondes, une
        touche la reporte. Retourne $true si elle doit avoir lieu (faite par le nettoyage de fin, après la
        fermeture du setup), $false si elle est reportée.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [switch]$Immediate,

        [int]$Seconds = 10
    )
    if (-not $Immediate -and
        -not (Wait-OSSetupCountdown -Label 'Fermeture de la session' -Hint ' — appuyez sur une touche pour la reporter' -Seconds $Seconds)) {
        Write-OSSetupLog -Level Warning -Message 'Fermeture de la session reportée : à faire avant d''utiliser ces éléments.'
        return $false
    }
    if ($PSCmdlet.ShouldProcess($env:USERNAME, 'Fermer la session')) {
        Write-OSSetupLog -Message 'Fermeture de la session à la fin du setup…'
        return $true
    }
    $false
}

function Request-OSSetupRestart {
    <#
    .SYNOPSIS
        Redémarre la machine. Sans -Immediate : compte à rebours de 10 secondes, une touche le reporte.
        Retourne $true si le redémarrage est lancé, $false s'il est reporté.
    .PARAMETER Manual
        Aucune reprise automatique n'est prévue : le message d'un redémarrage reporté demande de relancer le setup à la
        main après le redémarrage.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [switch]$Immediate,

        [int]$Seconds = 10,

        [switch]$Manual
    )
    if (-not $Immediate -and
        -not (Wait-OSSetupCountdown -Label 'Redémarrage' -Hint ' — appuyez sur une touche pour le reporter' -Seconds $Seconds)) {
        $next = if ($Manual) { 'Relancez le setup à la main après un redémarrage pour terminer.' }
        else { 'Le setup reprendra automatiquement à la prochaine ouverture de session, après un redémarrage.' }
        Write-OSSetupLog -Level Warning -Message "Redémarrage reporté. $next"
        return $false
    }
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Redémarrer')) {
        Write-OSSetupLog -Message 'Redémarrage…'
        Restart-Computer -Force
        return $true
    }
    $false
}
