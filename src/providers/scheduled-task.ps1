# Provider scheduled-task : activation ou désactivation d'une tâche planifiée existante.
# Une tâche absente est conforme quand on veut la désactiver (elle n'existe pas sur toutes les versions).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'scheduled-task'

    Describe = {
        param($Action, $Context)
        $verb = if ($Action['enabled']) { 'activer' } else { 'désactiver' }
        "$verb la tâche planifiée $($Action['task'])"
    }

    Test     = {
        param($Action, $Context)
        $path, $name = Split-OSSetupTaskPath -Task $Action['task']
        $task = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue
        if (-not $task) {
            if ($Action['enabled']) { throw "Tâche planifiée introuvable : $($Action['task'])." }
            return $true
        }
        ($task.State -ne 'Disabled') -eq [bool]$Action['enabled']
    }

    Read     = {
        param($Action, $Context)
        $path, $name = Split-OSSetupTaskPath -Task $Action['task']
        $task = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue
        if (-not $task) { return [ordered]@{ exists = $false } }
        [ordered]@{ exists = $true; state = "$($task.State)" }
    }

    Invoke   = {
        param($Action, $Context)
        $path, $name = Split-OSSetupTaskPath -Task $Action['task']
        if ($Action['enabled']) {
            Enable-ScheduledTask -TaskPath $path -TaskName $name | Out-Null
        }
        else {
            Disable-ScheduledTask -TaskPath $path -TaskName $name | Out-Null
        }
    }
}
