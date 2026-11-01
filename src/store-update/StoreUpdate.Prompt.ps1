# Mises à jour encadrées des applications du Store (ADR 0004), fenêtre de l'utilisateur : tâche « OS-Setup - Store (fenêtre) »,
# à l'ouverture de session puis toutes les 15 minutes. Windows PowerShell 5.1.
# - Respecte le report choisi par l'utilisateur.
# - Fait vérifier par la tâche SYSTEM, au plus toutes les 4 heures, si le Store propose une mise à jour (check.json).
# - Mise à jour proposée pour une application fermée : la tâche SYSTEM l'installe sans rien demander.
# - Pour une application ouverte : propose « Mettre à jour maintenant » ou un report. « Maintenant » fait revérifier
#   auprès du Store, et seulement si la mise à jour est toujours proposée, ferme l'application puis l'installe.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TestChoice', Justification = 'Lu par les fonctions du script.')]
param(
    # Essais automatisés : choisit le bouton indiqué sans attendre l'utilisateur (Now, 10m, 1h, 5h, 24h).
    [ValidateSet('', 'Now', '10m', '1h', '5h', '24h')]
    [string]$TestChoice = ''
)
$ErrorActionPreference = 'Stop'
$systemTask = 'OS-Setup - Store (système)'
# Vérification auprès du Store au plus toutes les 4 heures.
$checkHours = 4
$root = $PSScriptRoot
$log = Join-Path -Path $root -ChildPath 'store-update.log'
$stateFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'OS-Setup\store-update.json'
$title = 'Mise à jour du Store'

function Write-StoreUpdateLog([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}, fenêtre] {2}' -f (Get-Date), $env:USERNAME, $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -Path $Path)) { return $null }
    # Sous Windows PowerShell 5.1, ConvertFrom-Json rend un tableau JSON d'un bloc : passer par une variable l'énumère.
    try { $json = ConvertFrom-Json -InputObject (Get-Content -Path $Path -Raw -Encoding UTF8); $json } catch { $null }
}

function Save-State($State) {
    New-Item -Path (Split-Path -Path $stateFile -Parent) -ItemType Directory -Force | Out-Null
    [IO.File]::WriteAllText($stateFile, (ConvertTo-Json -InputObject $State), [Text.UTF8Encoding]::new($false))
}

function Get-AppVersion($App) {
    "$((Get-AppxPackage -Name $App.family.Split('_')[0] | Sort-Object -Property Version -Descending | Select-Object -First 1).Version)"
}

function Get-AppProcess($App) {
    $pattern = '*\WindowsApps\' + $App.family.Split('_')[0] + '_*'
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern })
}

function Get-PendingApp([object[]]$App) {
    # Mise à jour proposée lors de la dernière vérification, et pas encore installée depuis.
    $check = Read-JsonFile (Join-Path -Path $root -ChildPath 'check.json')
    foreach ($item in $App) {
        $entry = if ($check) { $check.PSObject.Properties[$item.productId] }
        if ($entry -and $entry.Value.available -and $entry.Value.version -eq (Get-AppVersion $item)) { $item }
    }
}

function Test-CheckStale([object[]]$App) {
    $check = Read-JsonFile (Join-Path -Path $root -ChildPath 'check.json')
    foreach ($item in $App) {
        $entry = if ($check) { $check.PSObject.Properties[$item.productId] }
        if (-not $entry) { return $true }
        $checked = [datetime]$entry.Value.checked
        if ($checked -gt (Get-Date) -or $checked -lt (Get-Date).AddHours(-$checkHours)) { return $true }
    }
    $false
}

function Invoke-SystemRun($State) {
    # Lance la tâche SYSTEM (les utilisateurs ont le droit de l'exécuter, pas de la modifier) et attend sa fin.
    $State.lastRun = (Get-Date).ToString('o')
    Save-State $State
    $started = Get-Date
    & schtasks.exe /run /tn $systemTask | Out-Null
    $deadline = $started.AddMinutes(20)
    do {
        Start-Sleep -Seconds 3
        $task = Get-ScheduledTask -TaskName $systemTask -ErrorAction SilentlyContinue
        $info = if ($task) { $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue }
        $done = $task -and $task.State -ne 'Running' -and $info -and $info.LastRunTime -ge $started.AddSeconds(-2)
    } until ($done -or -not $task -or (Get-Date) -gt $deadline)
}

function Test-RecentRun($State) {
    $State.lastRun -and ([datetime]$State.lastRun) -gt (Get-Date).AddHours(-1) -and ([datetime]$State.lastRun) -le (Get-Date)
}

function Show-UpdatePrompt([object[]]$App) {
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
    $panel.WrapContents = $false
    $label = New-Object -TypeName System.Windows.Forms.Label
    $label.MaximumSize = New-Object -TypeName System.Drawing.Size -ArgumentList 480, 0
    $label.AutoSize = $true
    $names = ($App | ForEach-Object { "$($_.name) (installé : $(Get-AppVersion $_))" }) -join ', '
    $others = @($App | ForEach-Object { $_.closeFirst } | Where-Object { $_ } | Select-Object -Unique)
    $count = @($App | ForEach-Object { Get-AppProcess $_ }).Count
    $label.Text = "Le Store propose une mise à jour : $names.`n`n" +
        "L'installer ferme ces applications ($count processus ouverts)" + $(if ($others) { ", ainsi que $($others -join ', ') et ce qui y tourne" }) +
        ". Enregistrez votre travail avant de continuer.`n`n" +
        'Fermer cette fenêtre reporte la question d''une heure. Sinon, la mise à jour se fera seule dès que ces applications seront fermées.'
    $panel.Controls.Add($label)
    $buttons = New-Object -TypeName System.Windows.Forms.FlowLayoutPanel
    $buttons.AutoSize = $true
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
        $timer.Add_Tick({ $timer.Stop(); $form.Tag = $TestChoice; $form.Close() })
        $timer.Start()
    }
    [void]$form.ShowDialog()
    $form.Tag
}

function Show-Message([string]$Text) {
    Write-StoreUpdateLog "message : $Text"
    if ($TestChoice) { return }
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Text, $title, 'OK', 'Information')
}

try {
    $saved = Read-JsonFile $stateFile
    $state = [pscustomobject]@{
        # $(…) : Windows PowerShell 5.1 n'accepte pas un if nu comme valeur d'une table de hachage.
        snoozeUntil = $(if ($saved -and $saved.PSObject.Properties['snoozeUntil']) { $saved.snoozeUntil })
        lastRun     = $(if ($saved -and $saved.PSObject.Properties['lastRun']) { $saved.lastRun })
    }
    if ($state.snoozeUntil -and (Get-Date) -lt [datetime]$state.snoozeUntil) { return }
    $apps = @(Read-JsonFile (Join-Path -Path $root -ChildPath 'apps.json') | Where-Object { Get-AppVersion $_ })
    if (-not $apps) { return }

    if ((Test-CheckStale $apps) -and -not (Test-RecentRun $state)) {
        Invoke-SystemRun $state
    }
    $pending = @(Get-PendingApp $apps)
    if (-not $pending) { return }
    $open = @($pending | Where-Object { (Get-AppProcess $_).Count -gt 0 })
    if ($open.Count -lt $pending.Count -and -not (Test-RecentRun $state)) {
        # Applications fermées depuis la vérification : la tâche SYSTEM les met à jour sans rien demander.
        Invoke-SystemRun $state
        $open = @(Get-PendingApp $apps | Where-Object { (Get-AppProcess $_).Count -gt 0 })
    }
    if (-not $open) { return }

    $choice = Show-UpdatePrompt $open
    Write-StoreUpdateLog "choix : $choice ($(($open | ForEach-Object { $_.name }) -join ', '))"
    if ($choice -ne 'Now') {
        $delay = @{ '10m' = [timespan]::FromMinutes(10); '1h' = [timespan]::FromHours(1); '5h' = [timespan]::FromHours(5); '24h' = [timespan]::FromHours(24) }[$choice]
        if (-not $delay) { $delay = [timespan]::FromHours(1) }
        $state.snoozeUntil = (Get-Date).Add($delay).ToString('o')
        Save-State $state
        return
    }

    $state.snoozeUntil = $null
    # Vérification auprès du Store juste avant de fermer quoi que ce soit : la mise à jour est-elle toujours proposée ?
    Invoke-SystemRun $state
    $targets = @(Get-PendingApp $open)
    if (-not $targets) {
        Show-Message 'Le Store ne propose plus de mise à jour pour ces applications : rien n''a été fermé.'
        return
    }
    $before = @{}
    foreach ($app in $targets) { $before[$app.productId] = Get-AppVersion $app }
    # Un programme qui relance aussitôt l'application fermée (herdr relance le shell d'un volet) est fermé d'abord.
    $others = @($targets | ForEach-Object { $_.closeFirst } | Where-Object { $_ } | Select-Object -Unique)
    $deadline = (Get-Date).AddSeconds(30)
    do {
        foreach ($name in $others) { Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
        $targets | ForEach-Object { Get-AppProcess $_ } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $left = @($targets | ForEach-Object { Get-AppProcess $_ })
    } while ($left -and (Get-Date) -lt $deadline)
    if ($left) { Write-StoreUpdateLog "encore ouverts après fermeture : $(($left | ForEach-Object { $_.Name }) -join ', ')" }
    Invoke-SystemRun $state
    $failed = @($targets | Where-Object { (Get-AppVersion $_) -eq $before[$_.productId] })
    if ($failed) {
        $state.snoozeUntil = (Get-Date).AddHours(1).ToString('o')
        Save-State $state
        Show-Message "La mise à jour n'a pas abouti pour : $(($failed | ForEach-Object { $_.name }) -join ', '). Nouvel essai dans 1 heure."
    }
    else {
        Show-Message "À jour : $(($targets | ForEach-Object { "$($_.name) $(Get-AppVersion $_)" }) -join ', ')."
    }
}
catch {
    Write-StoreUpdateLog "ERREUR $($_.Exception.Message)"
}
