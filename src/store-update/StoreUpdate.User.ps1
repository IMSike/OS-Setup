# Mises à jour encadrées des applications du Store (ADR 0004), partie utilisateur : tâche « OS-Setup - Store (recherche) »,
# sans déclencheur, lancée par la tâche SYSTEM qui a levé le blocage des applications concernées (run.json).
# - mode check : demande au Store si une mise à jour existe, sans rien télécharger, puis retire la demande de sa file.
# - mode update : demande la mise à jour sans fermeture forcée (AllowForcedAppRestart = false) et attend sa fin.
# Résultat de chaque application dans check.json, lu par la fenêtre de l'utilisateur. Windows PowerShell 5.1 : l'API du
# Store (WinRT) n'est pas accessible depuis PowerShell 7.
# Déployé par OS-Setup dans %ProgramFiles%\OS-Setup\store-update : modifier le dépôt, pas cette copie.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$log = Join-Path -Path $root -ChildPath 'store-update.log'
$checkFile = Join-Path -Path $root -ChildPath 'check.json'

function Write-StoreUpdateLog {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $env:USERNAME, $Message
    foreach ($attempt in 1..10) {
        try { Add-Content -Path $log -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Wait-StoreOperation {
    # Opération asynchrone WinRT (IAsyncOperation) : pas de type PowerShell plus précis.
    param([Parameter(Mandatory)][object]$Operation)
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod([Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallItem]).Invoke($null, @($Operation))
    [void]$task.Wait()
    $task.Result
}

try {
    $request = Get-Content -Path (Join-Path -Path $root -ChildPath 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Sous Windows PowerShell 5.1, ConvertFrom-Json rend un tableau JSON d'un bloc : l'affectation puis @() le déplient.
    $apps = ConvertFrom-Json -InputObject (Get-Content -Path (Join-Path -Path $root -ChildPath 'apps.json') -Raw -Encoding UTF8)
    $apps = @($apps)
    $results = [ordered]@{}
    if (Test-Path -Path $checkFile) {
        try { (Get-Content -Path $checkFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $results[$_.Name] = $_.Value } } catch { $results = [ordered]@{} }
    }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [void][Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager, Windows.ApplicationModel.Store.Preview, ContentType = WindowsRuntime]
    $manager = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager]::new()
    $activeStates = 'Pending', 'Starting', 'AcquiringLicense', 'Downloading', 'Installing', 'RestoringData'

    # Échéance commune à toutes les applications, avant que la tâche SYSTEM remette le blocage (deadline de run.json).
    $deadline = (Get-Date).AddMinutes(12)
    if ($request.PSObject.Properties['deadline'] -and $request.deadline -and [datetime]$request.deadline -lt $deadline) { $deadline = [datetime]$request.deadline }

    foreach ($app in @($apps | Where-Object { $_.productId -in $request.productIds })) {
        $id = $app.productId
        $version = ''
        try {
            $packageName = $app.family.Split('_')[0]
            $version = "$((Get-AppxPackage -Name $packageName | Sort-Object -Property Version -Descending | Select-Object -First 1).Version)"
            $available = $false
            $state = ''
            $queued = @($manager.AppInstallItems | Where-Object { $_.ProductId -eq $id })
            $item = $queued | Where-Object { "$($_.GetCurrentStatus().InstallState)" -in $activeStates } | Select-Object -First 1
            if (-not $item -and $queued) {
                # Un élément resté dans la file (recherche sans installation, échec) masquerait la mise à jour : retiré d'abord.
                $manager.Cancel($id)
                Start-Sleep -Seconds 3
            }
            $pattern = "*\WindowsApps\$($packageName)_*"
            $open = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $pattern }).Count -gt 0
            if ($request.mode -eq 'check' -or $open) {
                # Application ouverte : une installation serait reportée, puis forcée. On demande seulement si elle existe.
                if ($item) {
                    $available = $true
                    $state = "$($item.GetCurrentStatus().InstallState)"
                    if ($open) {
                        # Mise à jour lancée par le Store pendant la levée du blocage : reportée puis forcée si l'application
                        # reste ouverte, donc retirée. La fenêtre la redemande, application fermée.
                        $manager.Cancel($id)
                        $state += ', annulée'
                    }
                }
                else {
                    $options = [Windows.ApplicationModel.Store.Preview.InstallControl.AppUpdateOptions]::new()
                    $options.AllowForcedAppRestart = $false
                    $options.AutomaticallyDownloadAndInstallUpdateIfFound = $false
                    $found = Wait-StoreOperation -Operation ($manager.SearchForUpdatesAsync($id, '', '', '', $options))
                    if ($found) {
                        $available = $true
                        $state = 'proposée'
                        $manager.Cancel($id)
                    }
                }
                Write-StoreUpdateLog "$($app.name) $version : $(if ($available) { "mise à jour proposée ($state)" } else { 'à jour' })"
            }
            else {
                if (-not $item) {
                    $options = [Windows.ApplicationModel.Store.Preview.InstallControl.AppUpdateOptions]::new()
                    $options.AllowForcedAppRestart = $false
                    $options.AutomaticallyDownloadAndInstallUpdateIfFound = $true
                    $item = Wait-StoreOperation -Operation ($manager.SearchForUpdatesAsync($id, '', '', '', $options))
                }
                if ($item) {
                    do {
                        Start-Sleep -Seconds 3
                        $status = $item.GetCurrentStatus()
                    } while ("$($status.InstallState)" -notin 'Completed', 'Canceled', 'Error' -and (Get-Date) -lt $deadline)
                    $state = "$($status.InstallState)"
                    $available = $state -ne 'Completed'
                    $after = "$((Get-AppxPackage -Name $packageName | Sort-Object -Property Version -Descending | Select-Object -First 1).Version)"
                    $code = if ($status.ErrorCode) { ', code 0x{0:X8}' -f $status.ErrorCode.HResult }
                    Write-StoreUpdateLog "$($app.name) $version -> $after : $state$code"
                    $version = $after
                }
                else { Write-StoreUpdateLog "$($app.name) $version : à jour" }
            }
        }
        catch {
            # Une application en échec n'empêche pas les autres. Le résultat horodaté évite de relancer à chaque passage.
            Write-StoreUpdateLog "$($app.name) : ERREUR $($_.Exception.Message)"
            $available = $false
            $state = 'Erreur'
        }
        $results[$id] = [ordered]@{ name = $app.name; version = $version; available = $available; state = $state; checked = (Get-Date).ToString('o') }
        # Écrit après chaque application : un résultat obtenu n'est pas perdu si la suite échoue ou dépasse le délai.
        [IO.File]::WriteAllText($checkFile, (ConvertTo-Json -InputObject $results), [Text.UTF8Encoding]::new($false))
    }
}
catch {
    Write-StoreUpdateLog "ERREUR $($_.Exception.Message)"
}
