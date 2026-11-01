# Reprise après redémarrage : état persisté dans state/, tâche planifiée à l'ouverture de session.
#   state/run.json         exécution en cours, à reprendre (supprimé à la fin)
#   state/last-result.json résultat de la dernière exécution terminée (code de sortie)

$script:ResumeTaskName = 'OS-Setup - reprise'
$script:MaxPasses = 5

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
        $State | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding utf8NoBOM
    }
}

function Read-OSSetupRunState {
    <#
    .SYNOPSIS
        Retourne l'exécution à reprendre, ou $null s'il n'y en a pas.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StateRoot
    )
    $path = Join-Path -Path $StateRoot -ChildPath 'run.json'
    if (-not (Test-Path -Path $path)) { return $null }
    $state = Get-Content -Path $path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
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
    if ((Test-Path -Path $path) -and $PSCmdlet.ShouldProcess($path, 'Supprimer l''état de reprise')) {
        Remove-Item -Path $path -Force
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
        New-Item -Path $StateRoot -ItemType Directory -Force | Out-Null
        [ordered]@{ runId = $RunId; exitCode = $ExitCode; finishedAt = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -Path $path -Encoding utf8NoBOM
    }
}

function Register-OSSetupResumeTask {
    <#
    .SYNOPSIS
        Tâche planifiée qui relance le setup (-Resume) à l'ouverture de session de l'utilisateur courant,
        avec les droits les plus élevés : aucune nouvelle invite UAC.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SetupPath
    )
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $pwsh = (Get-Process -Id $PID).Path
    # PowerShell du Store : le chemin du paquet contient sa version et change à chaque mise à jour ; l'alias d'exécution reste.
    if ($pwsh -like '*\WindowsApps\Microsoft.PowerShell_*') {
        $pwsh = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\pwsh.exe'
    }
    $action = New-ScheduledTaskAction -Execute $pwsh -WorkingDirectory (Split-Path -Path $SetupPath -Parent) `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$SetupPath`" -Resume"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    if ($PSCmdlet.ShouldProcess($script:ResumeTaskName, 'Créer la tâche de reprise')) {
        Register-ScheduledTask -TaskName $script:ResumeTaskName -Action $action -Trigger $trigger -Principal $principal `
            -Settings $settings -Description 'Reprise d''OS-Setup après redémarrage (supprimée à la fin).' -Force | Out-Null
    }
}

function Unregister-OSSetupResumeTask {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $task = Get-ScheduledTask -TaskName $script:ResumeTaskName -ErrorAction SilentlyContinue
    if ($task -and $PSCmdlet.ShouldProcess($script:ResumeTaskName, 'Supprimer la tâche de reprise')) {
        Unregister-ScheduledTask -TaskName $script:ResumeTaskName -Confirm:$false
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
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [switch]$Immediate,

        [int]$Seconds = 10
    )
    if (-not $Immediate -and
        -not (Wait-OSSetupCountdown -Label 'Redémarrage' -Hint ' — appuyez sur une touche pour le reporter' -Seconds $Seconds)) {
        Write-OSSetupLog -Level Warning -Message ('Redémarrage reporté. Le setup reprendra automatiquement à la prochaine ' +
            'ouverture de session, après un redémarrage.')
        return $false
    }
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Redémarrer')) {
        Write-OSSetupLog -Message 'Redémarrage…'
        Restart-Computer -Force
        return $true
    }
    $false
}
