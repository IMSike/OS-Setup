function Invoke-OSSetupNativeCommand {
    <#
    .SYNOPSIS
        Lance une commande externe : sortie (standard et erreurs) journalisée ligne à ligne en Detail, exception si le
        code de sortie n'est pas 0 (« <Label> a échoué (code N). »).
    .PARAMETER Utf8
        L'outil écrit en UTF-8 : la console passe en UTF-8 le temps de l'appel (sinon PowerShell décode la sortie avec
        la page de code OEM et les accents sont corrompus dans le journal).
    .PARAMETER LogFilter
        Expression régulière : les lignes qui y correspondent ne sont pas journalisées (ex. barres de progression).
    .PARAMETER NoInput
        Entrée standard vide : aucune question de l'outil ne peut bloquer le setup.
    .PARAMETER NoThrow
        Pas d'exception en cas d'échec ; avec -PassThru, l'appelant lit le code de sortie.
    .PARAMETER PassThru
        Retourne la sortie et le code de sortie ({ Output; ExitCode }).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$Label,

        [switch]$Utf8,

        [string]$LogFilter,

        [switch]$NoInput,

        [switch]$NoThrow,

        [switch]$PassThru
    )
    $previousEncoding = [Console]::OutputEncoding
    try {
        if ($Utf8) { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
        $output = if ($NoInput) { $null | & $FilePath @ArgumentList 2>&1 } else { & $FilePath @ArgumentList 2>&1 }
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($Utf8) { [Console]::OutputEncoding = $previousEncoding }
    }
    foreach ($line in $output) {
        if ("$line".Trim() -and -not ($LogFilter -and "$line" -match $LogFilter)) { Write-OSSetupLog -Level Detail -Message "  $line" }
    }
    if ($exitCode -ne 0 -and -not $NoThrow) {
        if (-not $Label) { $Label = (@($FilePath) + @($ArgumentList | Select-Object -First 1)) -join ' ' }
        throw "$Label a échoué (code $exitCode)."
    }
    if ($PassThru) { [pscustomobject]@{ Output = @($output); ExitCode = $exitCode } }
}

# Préfixe des tâches ponctuelles d'Invoke-OSSetupUnelevatedCommand (suivi d'un identifiant propre à chaque exécution).
$script:UnelevatedTaskPrefix = 'OS-Setup - sans droits administrateur'

function Clear-OSSetupUnelevatedLeftover {
    <#
    .SYNOPSIS
        Supprime les restes d'une exécution sans droits administrateur qui avait dépassé son délai : tâches ponctuelles
        terminées et dossiers temporaires qu'aucune tâche en cours n'utilise plus.
    .DESCRIPTION
        Une commande qui dépasse le délai d'Invoke-OSSetupUnelevatedCommand n'est pas arrêtée : elle finit en arrière-plan
        et laisse sa tâche et son dossier, que ce nettoyage retire à l'exécution suivante. Une tâche encore en cours
        (ou en file) et son dossier sont gardés.
    .PARAMETER WorkRoot
        Dossier des fichiers temporaires (le même qu'Invoke-OSSetupUnelevatedCommand).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$WorkRoot = [System.IO.Path]::GetTempPath()
    )
    $inUse = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($task in @(Get-ScheduledTask -TaskName "$script:UnelevatedTaskPrefix*" -ErrorAction SilentlyContinue)) {
        if ("$($task.State)" -in 'Running', 'Queued') {
            foreach ($action in @($task.Actions)) {
                if ("$($action.Arguments)" -match '-File\s+"([^"]+)"') { $inUse.Add((Split-Path -Path $Matches[1] -Parent)) | Out-Null }
            }
            continue
        }
        if ($PSCmdlet.ShouldProcess($task.TaskName, 'Supprimer la tâche terminée')) {
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-Path -LiteralPath $WorkRoot)) { return }
    foreach ($folder in @(Get-ChildItem -LiteralPath $WorkRoot -Directory -Filter 'os-setup-*' -ErrorAction SilentlyContinue)) {
        if ($folder.Name -notmatch '^os-setup-[0-9a-f]{32}$' -or $inUse.Contains($folder.FullName)) { continue }
        if ($PSCmdlet.ShouldProcess($folder.FullName, 'Supprimer le dossier temporaire')) {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-OSSetupUnelevatedCommand {
    <#
    .SYNOPSIS
        Exécute une commande Windows PowerShell sans droits administrateur, dans la session de l'utilisateur, et attend
        sa fin : sortie journalisée ligne à ligne en Detail, exception si le code de sortie n'est pas 0
        (« <Label> a échoué (code N). »), si le délai est dépassé ou si la tâche s'arrête sans résultat.
    .DESCRIPTION
        Comme Start-OSSetupUnelevatedExplorer : tâche planifiée ponctuelle au nom de l'utilisateur de la session (jeton
        limité), supprimée ensuite avec ses fichiers temporaires, même en cas d'erreur. Aucune invite UAC.
        La tâche lance un script d'enveloppe (Windows PowerShell 5.1, fenêtre masquée) qui exécute la commande dans un
        Windows PowerShell enfant, écrit sa sortie dans un journal, puis son code de sortie dans un fichier : ce fichier
        marque la fin (l'heure de dernière exécution donnée par le Planificateur n'est pas fiable). Environnement : celui
        du profil de l'utilisateur (PATH relu dans le registre), pas celui du setup ; dossier de travail : le profil.
        Une ligne « toujours en cours » est écrite toutes les ProgressSeconds. Passé le délai, la commande n'est pas
        arrêtée (une installation interrompue serait pire qu'une installation lente) : l'élément échoue comme « non
        terminé », la commande finit en arrière-plan, et sa tâche et son dossier sont supprimés à l'exécution suivante
        (Clear-OSSetupUnelevatedLeftover, appelé au début de chaque exécution).
    .PARAMETER Command
        Commande Windows PowerShell, écrite dans un script lancé par -File (aucun échappement à prévoir). Pas
        -EncodedCommand : l'enfant écrirait alors ses erreurs en CLIXML, illisibles une fois redirigées.
    .PARAMETER TimeoutSeconds
        Attente maximale du setup (30 min par défaut). La tâche elle-même n'est arrêtée par le Planificateur qu'au bout
        de 4 h au moins (garde-fou contre une commande bloquée), ou à la fermeture de la session.
    .PARAMETER ProgressSeconds
        Intervalle entre deux lignes « toujours en cours (N min) ».
    .PARAMETER PollSeconds
        Intervalle entre deux lectures de l'état de la tâche et du fichier de code de sortie (2 s par défaut).
    .PARAMETER StartGraceSeconds
        Délai laissé à la tâche pour démarrer : passé ce délai, une tâche qui ne tourne plus sans avoir écrit son code de
        sortie est un échec.
    .PARAMETER WorkRoot
        Dossier des fichiers temporaires (%TEMP% de l'utilisateur, le même pour le setup et la tâche).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Label,

        [int]$TimeoutSeconds = 1800,

        [int]$ProgressSeconds = 300,

        [int]$PollSeconds = 2,

        [int]$StartGraceSeconds = 30,

        [string]$WorkRoot = [System.IO.Path]::GetTempPath()
    )
    if (-not $PSCmdlet.ShouldProcess($Label, 'Exécuter sans droits administrateur')) { return }
    Clear-OSSetupUnelevatedLeftover -WorkRoot $WorkRoot -Confirm:$false
    $id = [guid]::NewGuid().ToString('N')
    # Nom propre à chaque exécution : une commande d'une exécution précédente peut encore tourner sous son propre nom.
    $taskName = "$script:UnelevatedTaskPrefix ($($id.Substring(0, 8)))"
    $work = Join-Path -Path $WorkRoot -ChildPath "os-setup-$id"
    $wrapper = Join-Path -Path $work -ChildPath 'run.ps1'
    $log = Join-Path -Path $work -ChildPath 'output.log'
    $exitFile = Join-Path -Path $work -ChildPath 'exitcode.txt'
    $powershell = Get-OSSetupWindowsPowerShellPath
    $commandScript = Join-Path -Path $work -ChildPath 'command.ps1'
    $quote = { param([string]$Text) "'" + ($Text -replace "'", "''") + "'" }
    # Enveloppe : sortie en UTF-8 (sinon accents corrompus), code de sortie écrit en dernier, sous un nom temporaire
    # puis renommé (jamais lu à moitié écrit).
    $wrapperText = @(
        "`$ErrorActionPreference = 'Continue'"
        "`$log = $(& $quote $log)"
        "`$exitFile = $(& $quote $exitFile)"
        '$code = 1'
        'try {'
        '    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8'
        "    & $(& $quote $powershell) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $(& $quote $commandScript) 2>&1 |"
        '        ForEach-Object { Add-Content -LiteralPath $log -Value "$_" -Encoding UTF8 }'
        '    if ($null -ne $LASTEXITCODE) { $code = $LASTEXITCODE }'
        '}'
        'catch {'
        '    Add-Content -LiteralPath $log -Value $_.Exception.Message -Encoding UTF8'
        '}'
        'finally {'
        '    Set-Content -LiteralPath "$exitFile.tmp" -Value $code -Encoding ASCII'
        '    Move-Item -LiteralPath "$exitFile.tmp" -Destination $exitFile -Force'
        '}'
    ) -join "`r`n"
    $timedOut = $false
    try {
        New-Item -Path $work -ItemType Directory -Force | Out-Null
        # UTF-8 avec BOM : sinon Windows PowerShell 5.1 lit les scripts dans la page de code ANSI.
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($commandScript, "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`r`n$Command`r`n", $utf8Bom)
        [System.IO.File]::WriteAllText($wrapper, $wrapperText + "`r`n", $utf8Bom)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute $powershell -Argument (Get-OSSetupLogonTaskArgument -Script $wrapper) `
            -WorkingDirectory ([Environment]::GetFolderPath('UserProfile'))
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::FromSeconds([Math]::Max($TimeoutSeconds + 60, 4 * 3600)))
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings `
            -Description 'OS-Setup : exécution ponctuelle sans droits administrateur (supprimée après sa fin).' -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        $started = Get-Date
        $deadline = $started.AddSeconds($TimeoutSeconds)
        $nextProgress = $started.AddSeconds($ProgressSeconds)
        while (-not (Test-Path -LiteralPath $exitFile)) {
            if ((Get-Date) -ge $deadline) {
                $timedOut = $true
                break
            }
            Start-Sleep -Seconds $PollSeconds
            $state = "$((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State)"
            # Tâche arrêtée (ou jamais lancée) sans code de sortie : inutile d'attendre la fin du délai.
            if ($state -notin 'Running', 'Queued' -and ((Get-Date) - $started).TotalSeconds -ge $StartGraceSeconds -and
                -not (Test-Path -LiteralPath $exitFile)) { break }
            if ((Get-Date) -ge $nextProgress -and -not (Test-Path -LiteralPath $exitFile)) {
                Write-OSSetupLog -Message "  $Label : toujours en cours ($([int][Math]::Floor(((Get-Date) - $started).TotalMinutes)) min)"
                $nextProgress = $nextProgress.AddSeconds([Math]::Max($ProgressSeconds, 1))
            }
        }
        if (Test-Path -LiteralPath $log) {
            foreach ($line in Get-Content -LiteralPath $log -Encoding utf8) {
                if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" }
            }
        }
        if ($timedOut) {
            throw ("$Label non terminé après $(Format-OSSetupDuration -Seconds $TimeoutSeconds) : il continue en arrière-plan " +
                "(tâche « $taskName ») ; relancer le setup une fois qu'il a fini pour vérifier.")
        }
        if (-not (Test-Path -LiteralPath $exitFile)) {
            throw "$Label s'est arrêté sans code de sortie (tâche planifiée « $taskName »)."
        }
        $text = "$(Get-Content -LiteralPath $exitFile -Raw)".Trim()
        $exitCode = 0
        if (-not [int]::TryParse($text, [ref]$exitCode)) { throw "$Label : code de sortie illisible (« $text »)." }
        if ($exitCode -ne 0) { throw "$Label a échoué (code $exitCode)." }
    }
    finally {
        # Commande encore en cours après le délai : sa tâche et son dossier restent, supprimés à l'exécution suivante.
        if (-not $timedOut) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
