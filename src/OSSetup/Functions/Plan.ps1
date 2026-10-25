function Get-OSSetupPlan {
    <#
    .SYNOPSIS
        Teste chaque action des éléments et retourne le plan : une étape par action, statut ok / todo / error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ItemId,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    foreach ($id in $ItemId) {
        $item = $Data.Items[$id]
        $index = 0
        foreach ($rawAction in $item['actions']) {
            # Action sans objet quand un autre élément retenu prend le relais (ex. ne pas supprimer le raccourci
            # posé par un installeur si l'utilisateur a demandé ce raccourci sur le bureau).
            if ($rawAction['unlessSelected'] -and $Context.ContainsKey('ItemIds') -and $rawAction['unlessSelected'] -in $Context.ItemIds) {
                continue
            }
            $index++
            $step = [pscustomobject]@{
                ItemId        = $id
                ItemName      = $item['name']
                RequiresAdmin = [bool]$item['requiresAdmin']
                RequiresReboot = [bool]$item['requiresReboot']
                RequiresLogoff = [bool]$item['requiresLogoff']
                DependsOn     = @($item['dependsOn'] | Where-Object { $_ })
                Index         = $index
                Provider      = $rawAction['provider']
                Action        = $null
                Description   = $null
                Status        = 'todo'
                Detail        = $null
            }
            # Information personnelle non renseignée (ex. nom pour Git) : l'action est ignorée plutôt qu'appliquée à vide.
            $missing = @(Get-OSSetupActionVariableName -Action $rawAction | Where-Object { $Context['MissingVariables'] -and $Context.MissingVariables.Contains($_) } |
                    ForEach-Object { $Context.MissingVariables[$_] } | Select-Object -Unique)
            if ($missing) {
                $step.Status = 'skipped'
                $step.Description = if ($rawAction['description']) { $rawAction['description'] } else { $rawAction['provider'] }
                $step.Detail = "non renseigné : $($missing -join ', ')"
                $step
                continue
            }
            try {
                $provider = Get-OSSetupProvider -Name $rawAction['provider']
                $step.Action = Expand-OSSetupAction -Action $rawAction -Variables $Context.Variables
                $step.Description = if ($step.Action['description']) { $step.Action['description'] } else { & $provider.Describe $step.Action $Context }
                if (& $provider.Test $step.Action $Context) {
                    $step.Status = 'ok'
                }
            }
            catch {
                $step.Status = 'error'
                $step.Detail = $_.Exception.Message
            }
            $step
        }
    }
}

function Show-OSSetupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan
    )
    $labels = @{ ok = '[ok]     '; todo = '[à faire]'; error = '[erreur] '; skipped = '[ignoré] ' }
    $levels = @{ ok = 'Detail'; todo = 'Info'; error = 'Error'; skipped = 'Warning' }
    Write-OSSetupLog -Message ''
    Write-OSSetupLog -Message '=== Plan ==='
    # Regroupement par élément en conservant l'ordre d'exécution (Group-Object trierait par nom).
    $itemIds = @($Plan | ForEach-Object { $_.ItemId } | Select-Object -Unique)
    foreach ($itemId in $itemIds) {
        $steps = @($Plan | Where-Object { $_.ItemId -eq $itemId })
        $admin = if ($steps[0].RequiresAdmin) { ' (admin)' } else { '' }
        Write-OSSetupLog -Message "$($steps[0].ItemName)$admin"
        foreach ($step in $steps) {
            $line = "    $($labels[$step.Status]) $($step.Description)"
            if ($step.Detail) { $line += " — $($step.Detail)" }
            Write-OSSetupLog -Level $levels[$step.Status] -Message $line
        }
    }
    $todo = @($Plan | Where-Object { $_.Status -eq 'todo' }).Count
    $ok = @($Plan | Where-Object { $_.Status -eq 'ok' }).Count
    Write-OSSetupLog -Message ''
    Write-OSSetupLog -Message "$todo action(s) à faire, $ok déjà conforme(s)."
}

function Invoke-OSSetupPlan {
    <#
    .SYNOPSIS
        Applique les étapes « todo » du plan. Un échec n'arrête que l'élément concerné et ceux qui en dépendent.
    .DESCRIPTION
        Redémarrage : une action peut le signaler (le provider retourne @{ RebootRequired = $true }), ou un élément
        le déclarer (requiresReboot). Les actions suivantes du même élément continuent ; les éléments qui en
        dépendent sont reportés (statut « deferred ») et seront traités après le redémarrage.
        Chaque résultat porte RebootRequired : vrai si un redémarrage est nécessaire pour terminer.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Plan,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    $failedItems = [System.Collections.Generic.HashSet[string]]::new()
    # Éléments qui attendent un redémarrage avant que leurs dépendants puissent être traités.
    $waitingItems = [System.Collections.Generic.HashSet[string]]::new()
    # Éléments dont une action vient d'être appliquée : leurs actions suivantes, et celles des éléments qui en dépendent,
    # jugées conformes au moment du plan sont revérifiées (ex. installation qui crée un raccourci que l'action suivante
    # doit supprimer, ou une entrée de démarrage qu'un autre élément doit désactiver).
    $changedItems = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($step in $Plan) {
        $changedDependency = @($step.DependsOn | Where-Object { $changedItems.Contains($_) })
        if ($step.Status -eq 'ok' -and ($changedItems.Contains($step.ItemId) -or $changedDependency)) {
            try {
                if (-not (& (Get-OSSetupProvider -Name $step.Provider).Test $step.Action $Context)) {
                    $step = $step.PSObject.Copy()
                    $step.Status = 'todo'
                }
            }
            catch {
                Write-OSSetupLog -Level Detail -Message "  revérification impossible : $($_.Exception.Message)"
            }
        }
        $result = [pscustomobject]@{
            ItemId         = $step.ItemId
            ItemName       = $step.ItemName
            Description    = $step.Description
            Status         = $step.Status
            Detail         = $step.Detail
            RebootRequired = $false
            RequiresLogoff = $step.RequiresLogoff
        }
        $blockedBy = @($step.DependsOn | Where-Object { $failedItems.Contains($_) })
        $waitingFor = @($step.DependsOn | Where-Object { $waitingItems.Contains($_) })
        if ($step.Status -eq 'skipped') {
            # Ignorée dès le plan (information non renseignée) : garde son motif ; ses dépendants sont ignorés aussi.
            $failedItems.Add($step.ItemId) | Out-Null
        }
        elseif ($failedItems.Contains($step.ItemId) -or $blockedBy) {
            $result.Status = 'skipped'
            $result.Detail = if ($blockedBy) { "dépendance en échec : $($blockedBy -join ', ')" } else { 'étape précédente en échec' }
            $failedItems.Add($step.ItemId) | Out-Null
        }
        elseif ($waitingFor) {
            $result.Status = 'deferred'
            $result.Detail = "après redémarrage (dépend de : $($waitingFor -join ', '))"
            $result.RebootRequired = $true
            # Ses propres dépendants attendront aussi.
            $waitingItems.Add($step.ItemId) | Out-Null
        }
        elseif ($step.Status -eq 'error') {
            $result.Status = 'failed'
            $failedItems.Add($step.ItemId) | Out-Null
        }
        elseif ($step.Status -eq 'todo') {
            if ($PSCmdlet.ShouldProcess($step.ItemName, $step.Description)) {
                Write-OSSetupLog -Message "→ $($step.ItemName) : $($step.Description)"
                try {
                    $provider = Get-OSSetupProvider -Name $step.Provider
                    if ($provider.ContainsKey('Read') -and $Context.ContainsKey('BackupRoot')) {
                        Save-OSSetupOriginalValue -BackupRoot $Context.BackupRoot -Step $step -Provider $provider -Context $Context -Confirm:$false
                    }
                    $outcome = @(& $provider.Invoke $step.Action $Context)
                    $signaled = [bool]($outcome | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['RebootRequired'] })
                    if ($signaled) {
                        # L'état final (ex. fonctionnalité « Enable Pending ») ne sera visible qu'après redémarrage.
                        $result.Status = 'reboot'
                        $result.RebootRequired = $true
                        $waitingItems.Add($step.ItemId) | Out-Null
                        Write-OSSetupLog -Level Warning -Message '  terminé, redémarrage nécessaire'
                    }
                    else {
                        if (-not (& $provider.Test $step.Action $Context)) {
                            throw "l'action s'est terminée mais l'état attendu n'est pas atteint."
                        }
                        $result.Status = 'done'
                        $changedItems.Add($step.ItemId) | Out-Null
                        if ($step.RequiresReboot) {
                            $result.RebootRequired = $true
                            $waitingItems.Add($step.ItemId) | Out-Null
                        }
                        Write-OSSetupLog -Level Success -Message '  terminé'
                    }
                }
                catch {
                    $result.Status = 'failed'
                    $result.Detail = $_.Exception.Message
                    $failedItems.Add($step.ItemId) | Out-Null
                    Write-OSSetupLog -Level Error -Message "  échec : $($result.Detail)"
                }
            }
            else {
                $result.Status = 'whatif'
            }
        }
        $result
    }
}

function Save-OSSetupOriginalValue {
    <#
    .SYNOPSIS
        Ajoute à original-values.json (dossier des sauvegardes de l'exécution) l'état d'une action avant sa
        modification, lu par le provider (Read). Sert à revenir en arrière à la main. Un échec de lecture
        n'empêche pas l'action : il est consigné à la place de la valeur.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        $Step,

        [Parameter(Mandatory)]
        [hashtable]$Provider,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    $path = Join-Path -Path $BackupRoot -ChildPath 'original-values.json'
    $before = try { & $Provider.Read $Step.Action $Context } catch { [ordered]@{ readError = $_.Exception.Message } }
    $entry = [ordered]@{
        at          = (Get-Date).ToString('o')
        item        = $Step.ItemId
        description = $Step.Description
        action      = $Step.Action
        before      = $before
    }
    if (-not $PSCmdlet.ShouldProcess($path, 'Enregistrer la valeur d''origine')) { return }
    $entries = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -Path $path) {
        foreach ($existing in @(Get-Content -Path $path -Raw -Encoding utf8 | ConvertFrom-Json)) { $entries.Add($existing) }
    }
    $entries.Add($entry)
    New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null
    ConvertTo-Json -InputObject $entries.ToArray() -Depth 6 | Set-Content -Path $path -Encoding utf8NoBOM
}

function Show-OSSetupSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result
    )
    $labels = [ordered]@{
        done     = 'appliquées'
        reboot   = 'appliquées, redémarrage nécessaire pour terminer'
        ok       = 'déjà conformes'
        deferred = 'reportées après le redémarrage'
        whatif   = 'simulées (-WhatIf)'
        skipped  = 'ignorées'
        failed   = 'en échec'
    }
    Write-OSSetupLog -Message ''
    Write-OSSetupLog -Message '=== Récapitulatif ==='
    foreach ($status in $labels.Keys) {
        $count = @($Result | Where-Object { $_.Status -eq $status }).Count
        if ($count -gt 0) {
            $level = switch ($status) { 'done' { 'Success' } 'failed' { 'Error' } { $_ -in 'skipped', 'reboot', 'deferred' } { 'Warning' } default { 'Info' } }
            Write-OSSetupLog -Level $level -Message "$count action(s) $($labels[$status])"
        }
    }
    foreach ($entry in $Result | Where-Object { $_.Status -in 'failed', 'skipped', 'deferred' }) {
        Write-OSSetupLog -Level Warning -Message "  $($entry.ItemName) : $($entry.Description) — $($entry.Detail)"
    }
    # Un redémarrage ouvre de toute façon une nouvelle session : inutile de le signaler dans ce cas.
    $logoff = @($Result | Where-Object { $_.Status -eq 'done' -and $_.RequiresLogoff } | ForEach-Object { $_.ItemName } | Select-Object -Unique)
    if ($logoff -and -not ($Result | Where-Object { $_.RebootRequired })) {
        Write-OSSetupLog -Level Warning -Message "Effectif à la prochaine ouverture de session : $($logoff -join ', ')."
    }
}
