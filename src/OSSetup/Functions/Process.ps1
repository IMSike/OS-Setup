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
    .PARAMETER Command
        Commande Windows PowerShell, écrite dans un script lancé par -File (aucun échappement à prévoir). Pas
        -EncodedCommand : l'enfant écrirait alors ses erreurs en CLIXML, illisibles une fois redirigées.
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

        [int]$TimeoutSeconds = 900,

        [int]$PollSeconds = 2,

        [int]$StartGraceSeconds = 30,

        [string]$WorkRoot = [System.IO.Path]::GetTempPath()
    )
    if (-not $PSCmdlet.ShouldProcess($Label, 'Exécuter sans droits administrateur')) { return }
    $taskName = 'OS-Setup - sans droits administrateur'
    $work = Join-Path -Path $WorkRoot -ChildPath "os-setup-$([guid]::NewGuid().ToString('N'))"
    $wrapper = Join-Path -Path $work -ChildPath 'run.ps1'
    $log = Join-Path -Path $work -ChildPath 'output.log'
    $exitFile = Join-Path -Path $work -ChildPath 'exitcode.txt'
    $powershell = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'WindowsPowerShell\v1.0\powershell.exe'
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
            -ExecutionTimeLimit ([TimeSpan]::FromSeconds($TimeoutSeconds + 60))
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings `
            -Description 'OS-Setup : exécution ponctuelle sans droits administrateur (supprimée aussitôt après).' -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        $started = Get-Date
        $deadline = $started.AddSeconds($TimeoutSeconds)
        while (-not (Test-Path -LiteralPath $exitFile)) {
            if ((Get-Date) -ge $deadline) {
                $timedOut = $true
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                break
            }
            Start-Sleep -Seconds $PollSeconds
            $state = "$((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue).State)"
            # Tâche arrêtée (ou jamais lancée) sans code de sortie : inutile d'attendre la fin du délai.
            if ($state -notin 'Running', 'Queued' -and ((Get-Date) - $started).TotalSeconds -ge $StartGraceSeconds -and
                -not (Test-Path -LiteralPath $exitFile)) { break }
        }
        if (Test-Path -LiteralPath $log) {
            foreach ($line in Get-Content -LiteralPath $log -Encoding utf8) {
                if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" }
            }
        }
        if ($timedOut) {
            throw "$Label n'a pas fini en $(Format-OSSetupDuration -Seconds $TimeoutSeconds) : arrêté."
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
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
