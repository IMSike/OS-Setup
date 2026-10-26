#Requires -Version 7.4
<#
.SYNOPSIS
    Copie l'état courant du dépôt dans la VM de test et y exécute bootstrap.ps1 comme un utilisateur réel.
.DESCRIPTION
    - Copie les fichiers suivis et non ignorés par Git (le travail non commité est donc testé).
    - Lance bootstrap.ps1 dans la session ouverte de l'utilisateur de test, via une tâche planifiée
      à droits élevés : mêmes conditions qu'un utilisateur devant l'écran (sans invite UAC).
      Une exécution directe via PowerShell Direct est impossible : winget n'y est pas utilisable.
    - Rapatrie les journaux dans logs/vm/<VM>-<horodatage>/ et retourne le code de sortie.
    À lancer en administrateur, ou depuis un compte membre du groupe « Administrateurs Hyper-V » (sans invite UAC).
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -Reset
    Repart du point de contrôle « prerequis » (bootstrap déjà passé) et rejoue answers/dev.example.json.
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -Reset -Only privacy, power
    Test ciblé : seuls les menus « privacy » et « power » du profil base, entièrement cochés.
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -Reset -AnswerFile $env:TEMP\terminal.json
    Test ciblé sur quelques éléments : fichier de réponses local, injecté dans la copie (answers/vm-only.json).
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -Reset -Baseline vierge
    Parcours complet depuis Windows fraîchement installé (bootstrap compris).
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -SetupArguments '-AnswerFile', 'answers\dev.example.json', '-WhatIf'
.EXAMPLE
    ./tests/vm/Invoke-TestVM.ps1 -Reset -PrepareOnly
    Test manuel : repart de l'état vierge et copie le dépôt, puis on lance soi-même bootstrap.ps1 dans la VM.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'Faux positif avec Invoke-Command -Session : les valeurs passent par -ArgumentList et le bloc param.')]
param(
    [string]$Name = 'OSSetup-Win10',

    # Arguments transmis à bootstrap.ps1 puis setup.ps1 (chemins relatifs à la racine du dépôt).
    [string[]]$SetupArguments = @('-AnswerFile', 'answers\dev.example.json', '-Yes'),

    # Revient d'abord à un point de contrôle (voir -Baseline).
    [switch]$Reset,

    # Point de contrôle de -Reset : « prerequis » (par défaut : bootstrap déjà passé, plus rapide) ou « vierge »
    # (parcours complet, pour tester le bootstrap). Avec -PrepareOnly, « vierge » par défaut.
    [ValidateSet('prerequis', 'vierge')]
    [string]$Baseline,

    # Test ciblé : génère un fichier de réponses où seuls ces groupes de choix sont cochés (toutes leurs options),
    # les autres vides. Remplace -SetupArguments.
    [string[]]$Only,

    # Avec -Only : profils du fichier de réponses généré.
    [string[]]$Profiles = @('base'),

    # Test ciblé sur des éléments précis : fichier de réponses local (même hors dépôt), injecté dans la copie.
    # Remplace -SetupArguments.
    [string]$AnswerFile,

    # Copie seulement le dépôt dans la VM, sans rien lancer (test manuel des menus, de l'invite UAC…).
    [switch]$PrepareOnly,

    # Avec -PrepareOnly : la copie est traitée comme créée par le bootstrap (-Destination), pour tester le nettoyage
    # de fin (menu, suppression du dépôt). Les journaux ne pourront alors pas être rapatriés depuis la copie.
    [switch]$AsBootstrapClone,

    [int]$TimeoutMinutes = 60
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestVM.Common.ps1')
Assert-TestVMAdministrator -HyperVOnly

$repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$credential = Get-TestVMCredential

Set-TestVMHostAwake -Enabled $true
$testStarted = Get-Date
if (-not $Baseline) { $Baseline = if ($PrepareOnly) { $script:BaselineCheckpoint } else { $script:PrerequisiteCheckpoint } }
if ($Reset) {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Reset-TestVM.ps1') -Name $Name -Checkpoint $Baseline
}

# Test ciblé : fichier de réponses généré à partir des données du dépôt (profils et groupes de choix).
$onlyAnswers = $null
if ($Only) {
    Import-Module -Name (Join-Path -Path $repoRoot -ChildPath 'src\OSSetup\OSSetup.psd1') -Force
    $data = Import-OSSetupData -Root $repoRoot
    $choices = [ordered]@{}
    foreach ($choice in Get-OSSetupChoice -Data $data -ResolvedProfileId (Resolve-OSSetupProfileSet -Data $data -ProfileId $Profiles)) {
        # @(...) autour du if : sinon un groupe vide deviendrait $null au lieu d'une liste vide.
        $choices[$choice['id']] = @(if ($choice['id'] -in $Only) { $choice['options'] })
    }
    $unknown = @($Only | Where-Object { $_ -notin $choices.Keys })
    if ($unknown) { throw "Groupe(s) de choix inconnu(s) pour les profils $($Profiles -join ', ') : $($unknown -join ', ')." }
    $onlyAnswers = [ordered]@{ profiles = @($Profiles); choices = $choices } | ConvertTo-Json -Depth 5
    $SetupArguments = @('-AnswerFile', 'answers\vm-only.json', '-Yes')
}
elseif ($AnswerFile) {
    $onlyAnswers = Get-Content -Path $AnswerFile -Raw -ErrorAction Stop
    $SetupArguments = @('-AnswerFile', 'answers\vm-only.json', '-Yes')
}
if ((Get-VM -Name $Name).State -ne 'Running') {
    Write-TestVMStep "Démarrage de '$Name'"
    Start-VM -Name $Name
}
Write-TestVMStep 'Attente de la session de test'
Wait-TestVMReady -Name $Name

# --- Copie du dépôt ----------------------------------------------------------------------------
Write-TestVMStep 'Copie du dépôt dans la VM'
$files = & git -C $repoRoot ls-files --cached --others --exclude-standard
if ($LASTEXITCODE -ne 0) { throw 'Impossible de lister les fichiers du dépôt (git).' }
$archive = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "OSSetup-$([guid]::NewGuid()).zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($archive, 'Create')
try {
    foreach ($file in $files | Sort-Object -Unique) {
        $source = Join-Path -Path $repoRoot -ChildPath $file
        if (Test-Path -Path $source -PathType Leaf) {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, $file)
        }
    }
    if ($onlyAnswers) {
        $writer = [System.IO.StreamWriter]::new($zip.CreateEntry('answers/vm-only.json').Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($onlyAnswers) } finally { $writer.Dispose() }
    }
}
finally {
    $zip.Dispose()
}

$session = New-PSSession -VMName $Name -Credential $credential
try {
    $guestArchive = 'C:\Windows\Temp\OSSetup.zip'
    Copy-Item -Path $archive -Destination $guestArchive -ToSession $session -Force
    $bootstrapHash = (Get-FileHash -Path (Join-Path -Path $repoRoot -ChildPath 'bootstrap.ps1') -Algorithm SHA256).Hash
    $staleBootstrap = Invoke-Command -Session $session -ArgumentList $guestArchive, $script:GuestRepoRoot, $script:GuestTestRoot, $bootstrapHash -ScriptBlock {
        param($Archive, $Destination, $TestRoot, $Hash)
        Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $Archive -DestinationPath $Destination -Force
        Remove-Item -Path $Archive -Force
        # Point de contrôle « prerequis » : trace des outils installés par le bootstrap, pour que le nettoyage de
        # fin se comporte comme sur une vraie machine (le bootstrap relancé n'installe plus rien).
        $saved = Join-Path -Path $TestRoot -ChildPath 'bootstrap.json'
        if (Test-Path -Path $saved) {
            $state = Join-Path -Path $Destination -ChildPath 'state'
            New-Item -Path $state -ItemType Directory -Force | Out-Null
            Copy-Item -Path $saved -Destination $state -Force
            $recorded = Join-Path -Path $TestRoot -ChildPath 'bootstrap.sha256'
            return (Test-Path -Path $recorded) -and (Get-Content -Path $recorded -Raw).Trim() -ne $Hash
        }
        $false
    }
    if ($staleBootstrap) {
        Write-Warning (("bootstrap.ps1 a changé depuis la création du point de contrôle « {0} » : le recréer " +
            "(New-TestVMPrerequisite.ps1) ou tester avec -Baseline vierge.") -f $script:PrerequisiteCheckpoint)
    }
    if ($PrepareOnly) {
        # Raccourci sur le bureau de l'utilisateur de test : un double-clic lance le bootstrap comme un vrai utilisateur.
        Invoke-Command -Session $session -ArgumentList $script:GuestRepoRoot, $AsBootstrapClone.IsPresent -ScriptBlock {
            param($RepoRoot, $Owned)
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut((Join-Path -Path ([Environment]::GetFolderPath('Desktop')) -ChildPath 'Lancer OS-Setup.lnk'))
            $shortcut.TargetPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$RepoRoot\bootstrap.ps1`""
            if ($Owned) { $shortcut.Arguments += " -Destination `"$RepoRoot`"" }
            $shortcut.WorkingDirectory = $RepoRoot
            $shortcut.Save()
        }
        Write-TestVMStep "Dépôt copié dans $script:GuestRepoRoot. Dans la VM : double-cliquer sur « Lancer OS-Setup » (bureau)."
        return
    }

    # --- Exécution dans la session de l'utilisateur ----------------------------------------------
    Write-TestVMStep "Lancement de bootstrap.ps1 $($SetupArguments -join ' ')"
    Invoke-Command -Session $session -ArgumentList $script:GuestRepoRoot, $script:TestUserName, $SetupArguments -ScriptBlock {
        param($RepoRoot, $UserName, $Arguments)
        $quoted = foreach ($argument in $Arguments) { if ($argument -match '\s') { "`"$argument`"" } else { $argument } }
        $runner = Join-Path -Path $RepoRoot -ChildPath 'tests\vm\Start-GuestRun.ps1'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $RepoRoot `
            -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"$runner`" " + ($quoted -join ' '))
        $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$UserName" -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'OSSetup-Test' -Action $action -Principal $principal -Force | Out-Null

        # Start-ScheduledTask échoue silencieusement via PowerShell Direct : schtasks /run fonctionne.
        # Après un retour à l'état vierge, le Planificateur met un temps variable à considérer la session
        # comme ouverte : on réessaie jusqu'à 2 minutes en vérifiant que la tâche a réellement démarré.
        wevtutil.exe set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true
        $since = Get-Date
        for ($attempt = 1; $attempt -le 12; $attempt++) {
            & schtasks.exe /run /tn 'OSSetup-Test' | Out-Null
            Start-Sleep -Seconds 10
            # Démarrée : en cours, ou déjà passée. Ne jamais relancer une tâche démarrée (le setup tournerait deux fois).
            $task = Get-ScheduledTask -TaskName 'OSSetup-Test'
            $info = $task | Get-ScheduledTaskInfo
            if ($task.State -eq 'Running' -or $info.LastRunTime -gt $since) { return }
        }
        $events = Get-WinEvent -LogName Microsoft-Windows-TaskScheduler/Operational -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -ge $since } | Select-Object -First 10 |
            ForEach-Object { '  {0:HH:mm:ss} [{1}] {2}' -f $_.TimeCreated, $_.Id, ($_.Message -split "`n")[0] }
        throw ("La tâche de test n'a pas démarré dans la VM (dernier résultat 0x{0:X}). Événements du Planificateur :`n{1}" -f
            $info.LastTaskResult, ($events -join "`n"))
    }

    # --- Attente de la fin, redémarrages compris ---------------------------------------------------
    # Fin d'exécution : state\last-result.json (écrit par setup.ps1 quand tout est terminé). À défaut, le code
    # de sortie de Start-GuestRun.ps1 sans reprise en attente (state\run.json) : échec avant le setup.
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $started = Get-Date
    $exitCode = $null
    $lastNote = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        try {
            if (-not $session -or $session.State -ne 'Opened') {
                if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
                $session = $null
                $session = New-PSSession -VMName $Name -Credential $credential -ErrorAction Stop
            }
            # Interrogation bornée dans le temps : une VM qui ne répond plus est signalée au lieu de figer le script.
            $job = Invoke-Command -Session $session -ArgumentList $script:GuestRepoRoot -AsJob -ScriptBlock {
                param($Root)
                $result = Join-Path -Path $Root -ChildPath 'state\last-result.json'
                $pending = Join-Path -Path $Root -ChildPath 'state\run.json'
                $guestExit = Join-Path -Path $Root -ChildPath 'logs\guest-exitcode.txt'
                if (Test-Path -Path $result) {
                    return @{ Finished = $true; ExitCode = [int](Get-Content -Path $result -Raw | ConvertFrom-Json).exitCode }
                }
                if ((Test-Path -Path $guestExit) -and -not (Test-Path -Path $pending)) {
                    return @{ Finished = $true; ExitCode = [int](Get-Content -Path $guestExit -Raw).Trim() }
                }
                # run.json porte le numéro de la dernière passe terminée.
                $note = if (Test-Path -Path $pending) { "redémarrage demandé : reprise attendue (passe $(1 + (Get-Content -Path $pending -Raw | ConvertFrom-Json).pass))" } else { '' }
                @{ Finished = $false; Note = $note }
            }
            if (-not (Wait-Job -Job $job -Timeout 60)) {
                Remove-Job -Job $job -Force
                throw 'pas de réponse en 60 s'
            }
            $status = Receive-Job -Job $job -ErrorAction Stop
            Remove-Job -Job $job -Force
        }
        catch {
            # Normal pendant un redémarrage de la VM : on réessaie avec une nouvelle session.
            Write-Host -Object ('  VM indisponible ({0}, {1}), nouvel essai… {2:mm\:ss}' -f (Get-VM -Name $Name).State, $_.Exception.Message, ((Get-Date) - $started))
            if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
            $session = $null
            continue
        }
        if ($status.Finished) {
            $exitCode = $status.ExitCode
            break
        }
        if ($status.Note -and $status.Note -ne $lastNote) {
            Write-TestVMStep $status.Note
            $lastNote = $status.Note
        }
        Write-Host -Object ('  en cours… {0:mm\:ss}' -f ((Get-Date) - $started))
    }

    # --- Journaux ----------------------------------------------------------------------------------
    if (-not $session -or $session.State -ne 'Opened') {
        $session = New-PSSession -VMName $Name -Credential $credential
    }
    $hostLogs = Join-Path -Path $repoRoot -ChildPath ("logs\vm\{0}-{1:yyyyMMdd-HHmmss}" -f $Name, (Get-Date))
    New-Item -Path $hostLogs -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $script:GuestRepoRoot -ChildPath 'logs\*') -Destination $hostLogs -FromSession $session -Recurse -Force -ErrorAction SilentlyContinue
    # Sauvegardes et valeurs d'origine (state\backups\<date>\original-values.json).
    Copy-Item -Path (Join-Path -Path $script:GuestRepoRoot -ChildPath 'state\backups') -Destination $hostLogs -FromSession $session -Recurse -Force -ErrorAction SilentlyContinue
    Write-TestVMStep "Journaux rapatriés dans $hostLogs"
    Write-TestVMStep ('Durée totale : {0:mm\:ss}' -f ((Get-Date) - $testStarted))
}
finally {
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    Remove-Item -Path $archive -Force -ErrorAction SilentlyContinue
    Set-TestVMHostAwake -Enabled $false
}

if ($null -eq $exitCode) {
    Write-Warning "Pas de fin d'exécution après $TimeoutMinutes minutes (voir la VM et les journaux)."
    exit 2
}
Write-TestVMStep "Code de sortie dans la VM : $exitCode"
exit [int]$exitCode
