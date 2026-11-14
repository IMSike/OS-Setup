# Provider logon-task : tâche planifiée qui lance un script PowerShell à l'ouverture de session du compte, avec les
# droits les plus élevés (sans invite UAC). Script lancé par Windows PowerShell 5.1, toujours présent.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'logon-task'

    Describe = {
        param($Action, $Context)
        "tâche planifiée « $($Action['name']) » à l'ouverture de session : $(Split-Path -Path $Action['script'] -Leaf)"
    }

    Test     = {
        param($Action, $Context)
        $task = Get-OSSetupScheduledTask -TaskName $Action['name']
        if (-not $task) { return $false }
        $expected = Get-OSSetupLogonTaskArgument -Script $Action['script']
        @($task.Actions | Where-Object { $_.Arguments -eq $expected }).Count -eq 1 -and $task.Principal.RunLevel -eq 'Highest'
    }

    Read     = {
        param($Action, $Context)
        $task = Get-OSSetupScheduledTask -TaskName $Action['name']
        if ($task) { [ordered]@{ exists = $true; arguments = "$($task.Actions[0].Arguments)" } } else { [ordered]@{ exists = $false } }
    }

    Invoke   = {
        param($Action, $Context)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $powershell = Get-OSSetupWindowsPowerShellPath
        # Cmdlets CDXML (module ScheduledTasks) : elles n'héritent pas de $ErrorActionPreference du module, d'où
        # -ErrorAction Stop (sinon l'erreur reste non bloquante et sa cause se perd).
        $taskAction = New-ScheduledTaskAction -Execute $powershell -Argument (Get-OSSetupLogonTaskArgument -Script $Action['script']) -ErrorAction Stop
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user -ErrorAction Stop
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest -ErrorAction Stop
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromHours(1)) -ErrorAction Stop
        Register-ScheduledTask -TaskName $Action['name'] -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings `
            -Description $Action['description'] -Force -ErrorAction Stop | Out-Null
    }
}
