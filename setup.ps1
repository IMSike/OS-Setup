#Requires -Version 7.4
<#
.SYNOPSIS
    Point d'entrée principal d'OS_Setup.
.DESCRIPTION
    Hors simulation (-WhatIf), le script se relance en administrateur s'il ne l'est pas déjà :
    une seule invite UAC pour toute l'exécution.
    Si des éléments nécessitent un redémarrage, l'état est enregistré dans state/run.json, une tâche planifiée
    relance le setup (-Resume) à la prochaine ouverture de session, et la machine redémarre.
.EXAMPLE
    ./setup.ps1
    Assistant interactif (profils, choix, emplacements), affichage du plan, validation, exécution.
.EXAMPLE
    ./setup.ps1 -AnswerFile answers/dev.example.json -WhatIf
    Rejoue un fichier de réponses en simulation.
.EXAMPLE
    ./setup.ps1 -Profiles base -AcceptDefaults -Yes
    Profil base avec les valeurs par défaut, sans aucune question (redémarrage immédiat si nécessaire).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Fichier de réponses à rejouer (aucune question posée).
    [string]$AnswerFile,

    # Profils à appliquer (saute le menu des profils).
    [string[]]$Profiles,

    # Utilise les valeurs par défaut des choix et variables au lieu des menus.
    [switch]$AcceptDefaults,

    # Enregistre les réponses de la session dans ce fichier.
    [string]$SaveAnswers,

    # Sans surveillance : applique le plan sans confirmation, redémarre sans compte à rebours si nécessaire et ferme
    # la fenêtre à la fin sans attendre.
    [switch]$Yes,

    # Ne pas attendre Entrée avant de fermer la fenêtre.
    [switch]$NoPause,

    # Usage interne : indique que le script a été relancé dans une fenêtre administrateur.
    [switch]$Relaunched,

    # Usage interne : reprise après redémarrage (lancée par la tâche planifiée), à partir de state/run.json.
    [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
Import-Module -Name (Join-Path -Path $root -ChildPath 'src\OSSetup\OSSetup.psd1') -Force

# Une seule élévation pour toute l'exécution (inutile en simulation, qui ne modifie rien).
if ($IsWindows -and -not $WhatIfPreference -and -not (Test-OSSetupElevated)) {
    Write-Host -Object 'Relance en administrateur (validez l''invite UAC) : le setup continue dans une nouvelle fenêtre.' -ForegroundColor Cyan
    $parameters = [ordered]@{}
    foreach ($key in $PSBoundParameters.Keys) { $parameters[$key] = $PSBoundParameters[$key] }
    $parameters['Relaunched'] = $true
    # Set-Location conserve le dossier courant (une fenêtre élevée démarre sinon dans System32).
    $command = "Set-Location -LiteralPath '$((Get-Location).Path -replace "'", "''")'; " +
        "& '$($PSCommandPath -replace "'", "''")' $(ConvertTo-OSSetupCommandArgument -Parameter $parameters); exit `$LASTEXITCODE"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait -PassThru `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded
    }
    catch {
        Write-Host -Object "Élévation refusée ou impossible : le setup nécessite les droits administrateur. ($($_.Exception.Message))" -ForegroundColor Red
        exit 1
    }
    exit $process.ExitCode
}

$stateRoot = Join-Path -Path $root -ChildPath 'state'
$runState = $null
if ($Resume) {
    $runState = Read-OSSetupRunState -StateRoot $stateRoot
}
# Une reprise poursuit le même journal que l'exécution d'origine.
$runId = if ($runState) { $runState['runId'] } else { Get-Date -Format 'yyyyMMdd-HHmmss' }
$logPath = Start-OSSetupLog -Directory (Join-Path -Path $root -ChildPath 'logs') -RunId $runId
Write-OSSetupLog -Message "OS_Setup — journal : $logPath"

$exitCode = 0
# Vrai quand le setup s'arrête pour redémarrer (ou attend un redémarrage reporté) : l'exécution n'est pas terminée.
$waitingForRestart = $false
$logoff = $false
try {
    if ($Resume) {
        if (-not $runState) {
            Unregister-OSSetupResumeTask
            throw 'Reprise demandée, mais aucune exécution en attente (state/run.json absent).'
        }
        $runState['pass']++
        Write-OSSetupLog -Message ''
        Write-OSSetupLog -Message "=== Reprise après redémarrage (passe $($runState['pass'])) ==="
        if ($runState['pass'] -gt (Get-OSSetupMaxPass)) {
            Unregister-OSSetupResumeTask
            Remove-OSSetupRunState -StateRoot $stateRoot
            throw "Trop de redémarrages successifs ($($runState['pass'] - 1)) : arrêt pour éviter une boucle. Voir le journal."
        }
        Wait-OSSetupUserSession
    }

    if (Test-OSSetupElevated) {
        Assert-OSSetupInteractiveUser
    }

    $data = Import-OSSetupData -Root $root
    Write-OSSetupLog -Level Detail -Message "$($data.Items.Count) élément(s), $($data.Profiles.Count) profil(s) chargés et validés."

    $facts = Get-OSSetupFact
    Write-OSSetupLog -Message 'Machine détectée :'
    foreach ($name in $facts.Keys) {
        Write-OSSetupLog -Level Detail -Message ('  {0,-22} {1}' -f $name, (@($facts[$name]) -join ', '))
    }

    if ($runState) {
        # Choix déjà validés avant le redémarrage : aucune question.
        $answers = $runState['answers']
        $Yes = [bool]$runState['yes']
    }
    elseif ($AnswerFile) {
        $answers = Read-OSSetupAnswerFile -Path $AnswerFile -Root $root
        Write-OSSetupChoiceWarning -Data $data -Answers $answers
    }
    elseif ($AcceptDefaults) {
        if (-not $Profiles) { throw '-AcceptDefaults nécessite -Profiles.' }
        $answers = New-OSSetupDefaultAnswer -ProfileId $Profiles
        Write-OSSetupChoiceWarning -Data $data -Answers $answers
    }
    else {
        $answers = Read-OSSetupAnswer -Data $data -Facts $facts -ProfileId $Profiles
    }

    # Plan, puis validation : appliquer, modifier une étape (retour dans l'assistant) ou annuler.
    while ($true) {
        Test-OSSetupAnswer -Data $data -Answers $answers

        # Les réponses sont toujours conservées pour pouvoir être rejouées.
        Save-OSSetupAnswerFile -Answers $answers -Path (Join-Path -Path $stateRoot -ChildPath 'answers-last.json') -WhatIf:$false
        if ($SaveAnswers) {
            Save-OSSetupAnswerFile -Answers $answers -Path $SaveAnswers -WhatIf:$false
        }

        $context = @{
            Root         = $root
            DotfilesRoot = Join-Path -Path $root -ChildPath 'dotfiles'
            BackupRoot   = Join-Path -Path $stateRoot -ChildPath "backups\$runId"
            Variables    = Resolve-OSSetupVariable -Data $data -Answers $answers
            MissingVariables = Get-OSSetupMissingVariable -Data $data -Answers $answers
            # Une étape manuelle n'est guidée que si quelqu'un est devant la console.
            Interactive  = -not $Yes -and (Test-OSSetupInteractiveConsole)
        }
        $itemIds = @(Resolve-OSSetupItemList -Data $data -Answers $answers -Facts $facts)
        # Certains providers agrègent les déclarations de tous les éléments retenus (ex. épingles de la barre des tâches).
        $context.Data = $data
        $context.ItemIds = $itemIds
        $plan = @(Get-OSSetupPlan -Data $data -ItemId $itemIds -Context $context)
        Show-OSSetupPlan -Plan $plan
        Write-OSSetupDiskSpaceWarning
        $nothingToDo = -not ($plan | Where-Object { $_.Status -ne 'ok' })

        if ($WhatIfPreference -or $Yes -or $runState) {
            if ($nothingToDo) {
                Write-OSSetupLog -Level Success -Message 'Rien à faire : la machine est conforme.'
                return
            }
            break
        }

        $steps = @(Get-OSSetupWizardStep -Data $data -Facts $facts -Answers $answers -SkipProfiles:([bool]$Profiles))
        $decision = Read-OSSetupConfirmation -Step $steps -NothingToDo:$nothingToDo
        if ($decision -eq 'apply') { break }
        if ($decision -eq 'cancel') {
            if ($nothingToDo) { Write-OSSetupLog -Level Success -Message 'Rien à faire : la machine est conforme.' }
            else { Write-OSSetupLog -Level Warning -Message 'Annulé par l''utilisateur : rien n''a été modifié.' }
            return
        }
        $answers = Read-OSSetupAnswer -Data $data -Facts $facts -ProfileId $Profiles -Answers $answers -StartStep $decision
    }

    $results = @(Invoke-OSSetupPlan -Plan $plan -Context $context -WhatIf:$WhatIfPreference)
    Show-OSSetupSummary -Result $results
    # Ce qui reste à faire à la main côté matériel (hors simulation).
    if (-not $WhatIfPreference) { Write-OSSetupDeviceReport }
    $failed = [bool]($results | Where-Object { $_.Status -eq 'failed' })
    # Les échecs des passes précédentes comptent dans le code de sortie final.
    if ($failed -or ($runState -and $runState['failed'])) {
        $exitCode = 1
    }

    if (-not $WhatIfPreference -and ($results | Where-Object { $_.RebootRequired })) {
        $waitingForRestart = $true
        $nextState = @{
            runId   = $runId
            pass    = if ($runState) { $runState['pass'] } else { 1 }
            yes     = [bool]$Yes
            failed  = ($exitCode -ne 0)
            answers = $answers
        }
        Save-OSSetupRunState -StateRoot $stateRoot -State $nextState
        Register-OSSetupResumeTask -SetupPath $PSCommandPath
        Write-OSSetupLog -Message ''
        Write-OSSetupLog -Level Warning -Message 'Un redémarrage est nécessaire pour terminer. Le setup reprendra automatiquement à l''ouverture de session.'
        # Reporté : l'état et la tâche restent en place, la reprise aura lieu après le prochain redémarrage.
        [void](Request-OSSetupRestart -Immediate:$Yes)
    }
    elseif (-not $WhatIfPreference -and (Test-OSSetupElevated) -and
        ($results | Where-Object { $_.Status -eq 'done' -and $_.RequiresLogoff })) {
        # Environnement prêt à l'emploi : la session est fermée par le nettoyage de fin, après la fermeture du setup.
        Write-OSSetupLog -Message ''
        Write-OSSetupLog -Level Warning -Message 'La session va être fermée pour terminer : enregistrez le travail ouvert dans les autres fenêtres.'
        $logoff = Request-OSSetupLogoff -Immediate:$Yes
    }
}
catch {
    Write-OSSetupLog -Level Error -Message $_.Exception.Message
    $exitCode = 1
}
finally {
    if (-not $waitingForRestart -and -not $WhatIfPreference) {
        # Exécution terminée : le résultat est écrit avant de retirer l'état de reprise (ordre lu par les tests en VM).
        Write-OSSetupRunResult -StateRoot $stateRoot -RunId $runId -ExitCode $exitCode
        if (Test-OSSetupElevated) {
            Unregister-OSSetupResumeTask
            Remove-OSSetupRunState -StateRoot $stateRoot
            # Outils du bootstrap à garder : ceux que les éléments retenus installent. Liste inconnue (échec avant
            # la résolution) : $null, aucun outil n'est désinstallé.
            $selectedWingetIds = $null
            if ((Get-Variable -Name itemIds -ErrorAction SilentlyContinue) -and (Get-Variable -Name data -ErrorAction SilentlyContinue)) {
                $selectedWingetIds = [string[]]@(Get-OSSetupSelectedWingetId -Data $data -ItemId $itemIds)
            }
            try {
                Invoke-OSSetupCleanup -Root $root -RunId $runId -SelectedWingetId $selectedWingetIds -Yes:$Yes -Logoff:$logoff
            }
            catch {
                Write-OSSetupLog -Level Warning -Message "Nettoyage de fin impossible : $($_.Exception.Message)"
            }
        }
    }
    elseif ($WhatIfPreference) {
        Write-OSSetupRunResult -StateRoot $stateRoot -RunId $runId -ExitCode $exitCode -WhatIf:$false
    }
    # Fenêtre ouverte par la relance ou par la reprise : elle se fermerait aussitôt, on laisse le temps de lire.
    # Avec -Yes (sans surveillance), rien n'attend une personne : la fenêtre se ferme et le nettoyage de fin
    # (qui attend la fermeture du setup) peut s'exécuter, y compris après une reprise.
    # Session fermée juste après : pas d'attente (le récapitulatif reste dans le journal).
    if (($Relaunched -or $Resume) -and -not $NoPause -and -not $Yes -and -not $logoff) {
        Read-Host -Prompt 'Appuyez sur Entrée pour fermer cette fenêtre' | Out-Null
    }
}
exit $exitCode
