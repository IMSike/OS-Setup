# Mises à jour encadrées des applications du Store (ADR 0004), fenêtre de l'utilisateur : tâche « OS-Setup - Store (fenêtre) »,
# à l'ouverture de session puis toutes les 15 minutes. Windows PowerShell 5.1.
# - Respecte le report choisi par l'utilisateur.
# - Fait vérifier par la tâche SYSTEM, au plus toutes les 4 heures, si le Store propose une mise à jour (check.json).
# - Mise à jour proposée pour une application fermée : la tâche SYSTEM l'installe sans rien demander.
# - Pour une application ouverte : propose « Mettre à jour maintenant » ou un report. « Maintenant » fait revérifier
#   auprès du Store (petite fenêtre « Vérification auprès du Store… » avec Annuler), et seulement si la mise à jour est
#   toujours proposée et que l'utilisateur n'a pas annulé, ferme l'application puis l'installe.
# - Avertit, au plus une fois par jour, quand les mises à jour d'une application n'ont pas pu être vérifiées depuis plus
#   de 14 jours (lastSuccess de check.json).
# Déployé par OS-Setup dans %ProgramFiles%\OS-Setup\store-update : modifier le dépôt, pas cette copie.
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TestChoice', Justification = 'Lu par les fonctions du script.')]
param(
    # Essais automatisés : choisit le bouton indiqué sans attendre l'utilisateur (Now, 10m, 1h, 5h, 24h). NowCancel :
    # « Maintenant », puis Annuler pendant la revérification. Ni fenêtre de revérification ni message en essai.
    [ValidateSet('', 'Now', 'NowCancel', '10m', '1h', '5h', '24h')]
    [string]$TestChoice = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$systemTask = 'OS-Setup - Store (système)'
# Tâche de reprise du setup ($script:ResumeTaskName du module) : tant qu'elle existe, la tâche SYSTEM ne fait que vérifier.
$resumeTask = 'OS-Setup - reprise'
# Tâche de reprise sans nouvelle passe depuis ce délai : ignorée (Get-ResumeOrphanReason).
$resumeHours = 48
# Exécutable système par son chemin complet, pas par le PATH.
$schtasks = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'schtasks.exe'
# Vérification auprès du Store au plus toutes les 4 heures.
$checkHours = 4
# Avertissement, au plus une fois par jour, au-delà de 14 jours sans vérification aboutie.
$warnDays = 14
$root = $PSScriptRoot
$log = Join-Path -Path $root -ChildPath 'store-update.log'
$stateFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'OS-Setup\store-update.json'
$title = 'Mise à jour du Store'
# Fenêtre « Vérification auprès du Store… » de la revérification de « Maintenant » : affichée (active), formulaire (form,
# absent en essai), bouton Annuler utilisé (cancelled). Table modifiée en place : pas de portée $script: à gérer.
$progress = @{ active = $false; cancelled = $false; form = $null }

# Copies (scripts autonomes) : Write-StoreUpdateLog aussi dans StoreUpdate.System.ps1 et StoreUpdate.User.ps1 (étiquette
# différente) ; Get-AppProcess et Get-AppVersion aussi dans StoreUpdate.System.ps1, en ligne dans StoreUpdate.User.ps1.
function Write-StoreUpdateLog {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}, fenêtre] {2}' -f (Get-Date), $env:USERNAME, $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -Path $Path)) { return $null }
    # Sous Windows PowerShell 5.1, ConvertFrom-Json rend un tableau JSON d'un bloc : passer par une variable l'énumère.
    try { $json = ConvertFrom-Json -InputObject (Get-Content -Path $Path -Raw -Encoding UTF8); $json } catch { $null }
}

function Save-State {
    param([Parameter(Mandatory)][object]$State)
    New-Item -Path (Split-Path -Path $stateFile -Parent) -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $State), [Text.UTF8Encoding]::new($false))
}

function Get-AppVersion {
    param([Parameter(Mandatory)][pscustomobject]$App)
    # Paquet absent : chaîne vide (sous StrictMode, lire Version sur $null lèverait une erreur).
    $package = Get-AppxPackage -Name $App.family.Split('_')[0] | Sort-Object -Property { [version]$_.Version } -Descending | Select-Object -First 1
    if ($package) { "$($package.Version)" } else { '' }
}

function Get-AppProcess {
    param([Parameter(Mandatory)][pscustomobject]$App)
    $pattern = '*\WindowsApps\' + $App.family.Split('_')[0] + '_*'
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern })
}

function Get-OpenSnapshot {
    param([Parameter(Mandatory)][datetime]$Since)
    # open.json de la tâche SYSTEM s'il est complet et a été écrit depuis $Since, rien sinon.
    $seen = Read-JsonFile -Path (Join-Path -Path $root -ChildPath 'open.json')
    if (-not $seen -or -not $seen.PSObject.Properties['written'] -or -not $seen.PSObject.Properties['apps'] -or -not $seen.apps) { return }
    try { $written = [datetime]$seen.written } catch { return }
    if ($written -ge $Since -and $written -le (Get-Date).AddMinutes(1)) { $seen }
}

function Get-HiddenProcess {
    param([Parameter(Mandatory)][pscustomobject]$App, [Parameter(Mandatory)][datetime]$Since)
    # Processus de l'application que la tâche SYSTEM a vus ouverts (open.json, toutes sessions) et que cette fenêtre ne
    # voit pas : console administrateur, session d'un autre compte. open.json absent, incomplet ou écrit avant $Since :
    # rien (il peut dater d'une exécution précédente). Un processus fermé depuis n'est pas compté.
    $seen = Get-OpenSnapshot -Since $Since
    if (-not $seen) { return }
    $entry = $seen.apps.PSObject.Properties[$App.productId]
    if (-not $entry) { return }
    $mine = @(Get-AppProcess -App $App | ForEach-Object { $_.Id })
    foreach ($id in @($entry.Value | Where-Object { $null -ne $_ })) {
        if ($id -notin $mine -and (Get-Process -Id $id -ErrorAction SilentlyContinue)) { $id }
    }
}

function Get-PendingApp {
    param([object[]]$App)
    # Mise à jour proposée lors de la dernière vérification, et pas encore installée depuis.
    $check = Read-JsonFile -Path (Join-Path -Path $root -ChildPath 'check.json')
    foreach ($item in $App) {
        $entry = if ($check) { $check.PSObject.Properties[$item.productId] }
        # Entrée incomplète (check.json tronqué ou modifié) : traitée comme sans mise à jour, sans erreur (StrictMode).
        if (-not $entry -or -not $entry.Value -or -not $entry.Value.PSObject.Properties['available'] -or -not $entry.Value.PSObject.Properties['version']) { continue }
        if ($entry.Value.available -and $entry.Value.version -eq (Get-AppVersion -App $item)) { $item }
    }
}

function Get-UncheckedApp {
    param([object[]]$App)
    # Applications sans vérification aboutie depuis plus de $warnDays jours (le blocage reste en place : elles ne sont plus
    # mises à jour). Point de départ : lastSuccess de check.json ; sans aucune réussite (lastSuccess null, ou pas d'entrée :
    # la recherche n'a jamais tourné), la création de check.json, posé avec la garde. Entrée d'une version précédente,
    # sans le champ lastSuccess : ignorée, la prochaine recherche l'écrit. Renvoie l'application et le nombre de jours.
    $path = Join-Path -Path $root -ChildPath 'check.json'
    $file = Get-Item -Path $path -ErrorAction SilentlyContinue
    $check = Read-JsonFile -Path $path
    foreach ($item in $App) {
        $entry = if ($check) { $check.PSObject.Properties[$item.productId] }
        $since = $null
        if ($entry -and $entry.Value) {
            if (-not $entry.Value.PSObject.Properties['lastSuccess']) { continue }
            if ($entry.Value.lastSuccess) { try { $since = [datetime]$entry.Value.lastSuccess } catch { $since = $null } }
        }
        if (-not $since -and $file) { $since = $file.CreationTime }
        if (-not $since -or $since -gt (Get-Date)) { continue }
        $elapsed = ((Get-Date) - $since).TotalDays
        if ($elapsed -gt $warnDays) { [pscustomobject]@{ App = $item; Days = [int][math]::Floor($elapsed) } }
    }
}

function Test-CheckStale {
    param([object[]]$App)
    $check = Read-JsonFile -Path (Join-Path -Path $root -ChildPath 'check.json')
    foreach ($item in $App) {
        $entry = if ($check) { $check.PSObject.Properties[$item.productId] }
        # Entrée absente ou incomplète : vérification à refaire.
        if (-not $entry -or -not $entry.Value -or -not $entry.Value.PSObject.Properties['checked']) { return $true }
        $checked = [datetime]$entry.Value.checked
        if ($checked -gt (Get-Date) -or $checked -lt (Get-Date).AddHours(-$checkHours)) { return $true }
    }
    $false
}

function Wait-Step {
    # Attente entre deux points sur la tâche SYSTEM. Pendant la fenêtre « Vérification auprès du Store… », attente par
    # tranches de 100 ms qui traitent ses messages (bouton Annuler) et s'arrête dès l'annulation.
    param([int]$Seconds)
    if (-not $progress.active) { Start-Sleep -Seconds $Seconds; return }
    if ($TestChoice -eq 'NowCancel') { $progress.cancelled = $true; return }
    $until = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $until) {
        if ($progress.form) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($progress.form.Tag -eq 'Cancel') { $progress.cancelled = $true }
        }
        if ($progress.cancelled) { return }
        Start-Sleep -Milliseconds 100
    }
}

function Show-Progress {
    # Petite fenêtre non modale pendant la revérification de « Maintenant » (jusqu'à 30 min). Annuler (ou Échap, ou sa
    # fermeture) arrête l'attente : rien n'est fermé. En essai (-TestChoice) : pas de fenêtre, NowCancel simule Annuler.
    $progress.active = $true
    $progress.cancelled = $false
    if ($TestChoice) { return }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object -TypeName System.Windows.Forms.Form
    $form.Text = $title
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.ControlBox = $false
    $form.AutoSize = $true
    $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object -TypeName System.Windows.Forms.Padding -ArgumentList 12
    $panel = New-Object -TypeName System.Windows.Forms.FlowLayoutPanel
    $panel.FlowDirection = 'TopDown'
    $panel.AutoSize = $true
    # GrowOnly (par défaut) garderait la taille initiale du volet (200 x 100) : fenêtre plus grande que son contenu.
    $panel.AutoSizeMode = 'GrowAndShrink'
    $panel.WrapContents = $false
    $label = New-Object -TypeName System.Windows.Forms.Label
    $label.AutoSize = $true
    $label.Text = 'Vérification auprès du Store…'
    $panel.Controls.Add($label)
    $button = New-Object -TypeName System.Windows.Forms.Button
    $button.Text = 'Annuler'
    $button.Name = 'buttonCancel'
    $button.AutoSize = $true
    $button.Margin = New-Object -TypeName System.Windows.Forms.Padding -ArgumentList 0, 12, 0, 0
    $button.Add_Click({ param($Source) $Source.FindForm().Tag = 'Cancel' })
    $panel.Controls.Add($button)
    $form.Controls.Add($panel)
    $form.CancelButton = $button
    # Fermée autrement que par Close-Progress (Alt+F4) : comme Annuler.
    $form.Add_FormClosing({ param($Source) if ($Source.Tag -ne 'Done') { $Source.Tag = 'Cancel' } })
    $form.Show()
    $form.Refresh()
    $progress.form = $form
}

function Close-Progress {
    $progress.active = $false
    if (-not $progress.form) { return }
    # Un clic sur Annuler encore en file compte aussi.
    [System.Windows.Forms.Application]::DoEvents()
    if ($progress.form.Tag -eq 'Cancel') { $progress.cancelled = $true }
    $progress.form.Tag = 'Done'
    $progress.form.Close()
    $progress.form.Dispose()
    $progress.form = $null
}

function Invoke-SystemRun {
    param([Parameter(Mandatory)][object]$State)
    # Lance la tâche SYSTEM (les utilisateurs ont le droit de l'exécuter, pas de la modifier) et attend sa fin.
    # Renvoie $true si une exécution lancée après la demande s'est terminée, $false sinon (délai dépassé, tâche absente,
    # Annuler dans la fenêtre « Vérification auprès du Store… » : $progress.cancelled).
    $State.lastRun = (Get-Date).ToString('o')
    Save-State -State $State
    # Attente bornée par la durée maximale d'une exécution de la tâche SYSTEM (ExecutionTimeLimit PT30M).
    $limit = 30
    # Une seule instance à la fois : une demande faite pendant une exécution déjà en cours (ouverture de session, tâche
    # quotidienne) serait ignorée. On attend d'abord sa fin.
    $wait = (Get-Date).AddMinutes($limit)
    # Tâche absente : pas d'attente (sous StrictMode, lire State sur $null lèverait une erreur).
    $running = Get-ScheduledTask -TaskName $systemTask -ErrorAction SilentlyContinue
    while ($running -and $running.State -eq 'Running' -and (Get-Date) -lt $wait) {
        Wait-Step -Seconds 3
        if ($progress.cancelled) { return $false }
        $running = Get-ScheduledTask -TaskName $systemTask -ErrorAction SilentlyContinue
    }
    # Exécution lancée par cette demande : vue en cours, LastRunTime changé, ou journal écrit depuis (la tâche SYSTEM y
    # écrit à chaque passage où elle a quelque chose à faire). LastRunTime seul ne suffit pas : le Planificateur peut le
    # dater de plusieurs secondes trop tôt et ne pas le changer pour deux exécutions rapprochées (observé en VM).
    $previous = if ($running) { ($running | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue).LastRunTime }
    $started = Get-Date
    $deadline = $started.AddMinutes($limit)
    & $schtasks /run /tn $systemTask | Out-Null
    $ran = $false
    do {
        Wait-Step -Seconds 2
        if ($progress.cancelled) { return $false }
        $task = Get-ScheduledTask -TaskName $systemTask -ErrorAction SilentlyContinue
        $info = if ($task) { $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue }
        $ran = [bool]($ran -or ($task -and $task.State -eq 'Running') -or ($info -and $info.LastRunTime -ne $previous) -or
            (Get-Item -Path $log -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started }))
        $done = [bool]($task -and $task.State -ne 'Running' -and $ran)
    } until ($done -or -not $task -or (Get-Date) -gt $deadline)
    if (-not $done) { Write-StoreUpdateLog 'tâche système non terminée' }
    $done
}

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

function Test-ResumePending {
    # Reprise du setup en attente et encore capable de reprendre (Get-ResumeOrphanReason).
    $task = Get-ScheduledTask -TaskName $resumeTask -ErrorAction SilentlyContinue
    [bool]($task -and -not (Get-ResumeOrphanReason -Task $task))
}

function Test-RecentRun {
    param([Parameter(Mandatory)][object]$State)
    $State.lastRun -and ([datetime]$State.lastRun) -gt (Get-Date).AddHours(-1) -and ([datetime]$State.lastRun) -le (Get-Date)
}

function Show-UpdatePrompt {
    param([object[]]$App)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object -TypeName System.Windows.Forms.Form
    $form.Text = $title
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.AutoSize = $true
    $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object -TypeName System.Windows.Forms.Padding -ArgumentList 12
    $panel = New-Object -TypeName System.Windows.Forms.FlowLayoutPanel
    $panel.FlowDirection = 'TopDown'
    $panel.AutoSize = $true
    # GrowOnly (par défaut) garderait la taille initiale du volet (200 x 100) : fenêtre plus grande que son contenu.
    $panel.AutoSizeMode = 'GrowAndShrink'
    $panel.WrapContents = $false
    $label = New-Object -TypeName System.Windows.Forms.Label
    $label.MaximumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 480, 0
    $label.AutoSize = $true
    $names = ($App | ForEach-Object { "$($_.name) (installé : $(Get-AppVersion -App $_))" }) -join ', '
    $others = @($App | ForEach-Object { $_.closeFirst } | Where-Object { $_ } | Select-Object -Unique)
    $count = @($App | ForEach-Object { Get-AppProcess -App $_ }).Count
    $label.Text = "Le Store propose une mise à jour : $names.`n`n" +
        "L'installer ferme ces applications ($count processus ouverts)" + $(if ($others) { ", ainsi que $($others -join ', ') et ce qui y tourne" }) +
        ". Enregistrez votre travail avant de continuer.`n`n" +
        'Fermer cette fenêtre reporte la question d''une heure. Sinon, la mise à jour se fera seule dès que ces applications seront fermées.'
    $panel.Controls.Add($label)
    $buttons = New-Object -TypeName System.Windows.Forms.FlowLayoutPanel
    $buttons.AutoSize = $true
    $buttons.AutoSizeMode = 'GrowAndShrink'
    $buttons.Margin = New-Object -TypeName System.Windows.Forms.Padding -ArgumentList 0, 12, 0, 0
    $form.Tag = '1h'
    foreach ($choice in @(@('Now', 'Mettre à jour maintenant'), @('10m', 'Dans 10 min'), @('1h', 'Dans 1 h'), @('5h', 'Dans 5 h'), @('24h', 'Demain'))) {
        $button = New-Object -TypeName System.Windows.Forms.Button
        $button.Text = $choice[1]
        $button.Tag = $choice[0]
        $button.Name = "button$($choice[0])"
        $button.AutoSize = $true
        $button.Add_Click({ param($Source) $form.Tag = $Source.Tag; $form.Close() })
        $buttons.Controls.Add($button)
    }
    $panel.Controls.Add($buttons)
    $form.Controls.Add($panel)
    # Entrée : le report le plus court, jamais la fermeture des applications.
    $form.AcceptButton = $buttons.Controls[1]
    if ($TestChoice) {
        $timer = New-Object -TypeName System.Windows.Forms.Timer
        $timer.Interval = 4000
        $timer.Add_Tick({ $timer.Stop(); $form.Tag = $(if ($TestChoice -eq 'NowCancel') { 'Now' } else { $TestChoice }); $form.Close() })
        $timer.Start()
    }
    [void]$form.ShowDialog()
    $form.Tag
}

function Show-Message {
    param([string]$Text)
    Write-StoreUpdateLog "message : $Text"
    if ($TestChoice) { return }
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Text, $title, 'OK', 'Information')
}

function Invoke-StoreUpdatePrompt {
    # Corps de la fenêtre, dans une fonction : chargé avec un point (tests), le script définit ses fonctions sans rien lancer.
    try {
        $saved = Read-JsonFile -Path $stateFile
        # Valeurs absentes : $null explicite (sous Windows PowerShell 5.1, un $(…) vide s'écrirait {} en JSON).
        $state = [pscustomobject]@{ snoozeUntil = $null; lastRun = $null; lastWarning = $null }
        foreach ($name in 'snoozeUntil', 'lastRun', 'lastWarning') {
            if ($saved -and $saved.PSObject.Properties[$name] -and ($saved.$name -is [string] -or $saved.$name -is [datetime])) { $state.$name = "$($saved.$name)" }
        }
        $apps = @(Read-JsonFile -Path (Join-Path -Path $root -ChildPath 'apps.json') | Where-Object { Get-AppVersion -App $_ })
        if (-not $apps) { return }

        # Vérifications en échec depuis plus de 14 jours : avertissement au plus une fois par jour, même pendant un report
        # ou une reprise du setup (le blocage reste en place, l'application n'est plus mise à jour).
        $lastWarning = $null
        if ($state.lastWarning) { try { $lastWarning = [datetime]$state.lastWarning } catch { $lastWarning = $null } }
        if (-not $lastWarning -or $lastWarning -lt (Get-Date).AddDays(-1) -or $lastWarning -gt (Get-Date)) {
            $unchecked = @(Get-UncheckedApp -App $apps)
            if ($unchecked) {
                $state.lastWarning = (Get-Date).ToString('o')
                Save-State -State $state
                Show-Message -Text (@($unchecked | ForEach-Object { "Les mises à jour de $($_.App.name) n'ont pas pu être vérifiées depuis $($_.Days) jours : voir le journal $log" }) -join "`n")
            }
        }
        # Reprise du setup en attente : la tâche SYSTEM ne ferait que vérifier, « Maintenant » fermerait les applications
        # pour rien (et peut-être le PowerShell 7 de la reprise). Rien n'est proposé avant la fin du setup.
        if (Test-ResumePending) { return }
        if ($state.snoozeUntil -and (Get-Date) -lt [datetime]$state.snoozeUntil) { return }

        if ((Test-CheckStale -App $apps) -and -not (Test-RecentRun -State $state)) {
            [void](Invoke-SystemRun -State $state)
        }
        $pending = @(Get-PendingApp -App $apps)
        if (-not $pending) { return }
        $open = @($pending | Where-Object { @(Get-AppProcess -App $_).Count -gt 0 })
        # Vue fermée d'ici mais ouverte pour la tâche SYSTEM (console administrateur, autre compte) : elle ne ferait que
        # vérifier. Pas de relance toutes les heures : la vérification normale, toutes les 4 heures, suffit.
        $elsewhere = @($pending | Where-Object { $_ -notin $open -and @(Get-HiddenProcess -App $_ -Since (Get-Date).AddHours(-$checkHours)).Count -gt 0 })
        if ($open.Count + $elsewhere.Count -lt $pending.Count -and -not (Test-RecentRun -State $state)) {
            # Applications fermées depuis la vérification : la tâche SYSTEM les met à jour sans rien demander.
            [void](Invoke-SystemRun -State $state)
            $open = @(Get-PendingApp -App $apps | Where-Object { @(Get-AppProcess -App $_).Count -gt 0 })
        }
        if (-not $open) { return }

        $choice = Show-UpdatePrompt -App $open
        Write-StoreUpdateLog "choix : $choice ($(($open | ForEach-Object { $_.name }) -join ', '))"
        if ($choice -ne 'Now') {
            $delay = @{ '10m' = [timespan]::FromMinutes(10); '1h' = [timespan]::FromHours(1); '5h' = [timespan]::FromHours(5); '24h' = [timespan]::FromHours(24) }[$choice]
            if (-not $delay) { $delay = [timespan]::FromHours(1) }
            $state.snoozeUntil = (Get-Date).Add($delay).ToString('o')
            Save-State -State $state
            return
        }

        $state.snoozeUntil = $null
        # Vérification auprès du Store juste avant de fermer quoi que ce soit : la mise à jour est-elle toujours proposée ?
        # Petite fenêtre pendant l'attente : Annuler ne ferme rien et repose la question dans 10 min.
        $requested = Get-Date
        Show-Progress
        try { $checked = Invoke-SystemRun -State $state } finally { Close-Progress }
        if ($progress.cancelled) {
            Write-StoreUpdateLog 'vérification annulée par l''utilisateur : rien n''est fermé, nouvelle question dans 10 min'
            $state.snoozeUntil = (Get-Date).AddMinutes(10).ToString('o')
            Save-State -State $state
            return
        }
        if (-not $checked) {
            # Vérification non terminée : rien n'est fermé, la question revient au passage suivant.
            $state.snoozeUntil = (Get-Date).AddMinutes(10).ToString('o')
            Save-State -State $state
            return
        }
        $targets = @(Get-PendingApp -App $open)
        if (-not $targets) {
            Show-Message -Text 'Le Store ne propose plus de mise à jour pour ces applications : rien n''a été fermé.'
            return
        }
        # La tâche SYSTEM fait foi : un processus qu'elle voit (open.json écrit pendant la revérification) et que cette
        # fenêtre ne voit pas (console administrateur, session d'un autre compte) ne serait pas fermé d'ici, et la mise à
        # jour échouerait après avoir fermé le reste. Rien n'est fermé, herdr compris.
        if (-not (Get-OpenSnapshot -Since $requested)) {
            Write-StoreUpdateLog 'open.json absent ou antérieur à la revérification : processus des autres sessions non vérifiés'
        }
        $elsewhere = @($targets | Where-Object { @(Get-HiddenProcess -App $_ -Since $requested).Count -gt 0 })
        if ($elsewhere) {
            $state.snoozeUntil = (Get-Date).AddMinutes(10).ToString('o')
            Save-State -State $state
            Show-Message -Text "Une fenêtre administrateur ou la session d'un autre utilisateur utilise $(($elsewhere | ForEach-Object { $_.name }) -join ', ') : fermez-la, la mise à jour se fera ensuite."
            return
        }
        $before = @{}
        foreach ($app in $targets) { $before[$app.productId] = Get-AppVersion -App $app }
        # Un programme qui relance aussitôt l'application fermée (herdr relance le shell d'un volet) est fermé d'abord.
        $others = @($targets | ForEach-Object { $_.closeFirst } | Where-Object { $_ } | Select-Object -Unique)
        $deadline = (Get-Date).AddSeconds(30)
        do {
            foreach ($name in $others) { Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
            $targets | ForEach-Object { Get-AppProcess -App $_ } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $left = @($targets | ForEach-Object { Get-AppProcess -App $_ })
        } while ($left -and (Get-Date) -lt $deadline)
        if ($left) { Write-StoreUpdateLog "encore ouverts après fermeture : $(($left | ForEach-Object { $_.Name }) -join ', ')" }
        if (-not (Invoke-SystemRun -State $state)) {
            # Mise à jour peut-être encore en cours : pas de conclusion à un échec, nouveau point au passage suivant.
            $state.snoozeUntil = (Get-Date).AddMinutes(10).ToString('o')
            Save-State -State $state
            return
        }
        $failed = @($targets | Where-Object { (Get-AppVersion -App $_) -eq $before[$_.productId] })
        if ($failed) {
            $state.snoozeUntil = (Get-Date).AddHours(1).ToString('o')
            Save-State -State $state
            Show-Message -Text "La mise à jour n'a pas abouti pour : $(($failed | ForEach-Object { $_.name }) -join ', '). Nouvel essai dans 1 heure."
        }
        else {
            Show-Message -Text "À jour : $(($targets | ForEach-Object { "$($_.name) $(Get-AppVersion -App $_)" }) -join ', ')."
        }
    }
    catch {
        Write-StoreUpdateLog "ERREUR $($_.Exception.Message)"
    }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-StoreUpdatePrompt }
