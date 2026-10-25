# Provider docker-build-cache : plafond du cache de build de Docker (builder.gc dans %USERPROFILE%\.docker\daemon.json),
# calculé selon la taille du disque système. Fusion : les autres réglages du moteur Docker sont conservés.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'docker-build-cache'

    Describe = {
        param($Action, $Context)
        $limit = Get-OSSetupDockerBuildCacheLimit -Action $Action
        "Docker : cache de build limité à $($limit.GB) Go (au plus $($Action['maxGB']) Go, $($Action['diskPercent']) % du disque)"
    }

    Test     = {
        param($Action, $Context)
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.docker\daemon.json'
        if (-not (Test-Path -Path $path -PathType Leaf)) { return $false }
        $current = ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $path -Raw -Encoding utf8) -Name $path
        Test-OSSetupJsonSubset -Json $current -Subset (Get-OSSetupDockerBuildCacheSetting -Action $Action)
    }

    Read     = {
        param($Action, $Context)
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.docker\daemon.json'
        if (Test-Path -Path $path -PathType Leaf) { [ordered]@{ exists = $true; content = Get-Content -Path $path -Raw -Encoding utf8 } } else { [ordered]@{ exists = $false } }
    }

    Invoke   = {
        param($Action, $Context)
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.docker\daemon.json'
        $current = [ordered]@{}
        if (Test-Path -Path $path -PathType Leaf) {
            $backup = Backup-OSSetupFile -Path $path -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
            $current = ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $path -Raw -Encoding utf8) -Name $path
        }
        $limit = Get-OSSetupDockerBuildCacheLimit -Action $Action
        if ($limit.Clamped) {
            Write-OSSetupLog -Level Warning -Message "  disque de $([math]::Round($limit.DiskGB)) Go : cache de build ramené à $($limit.GB) Go ($($Action['diskPercent']) % du disque)."
        }
        $merged = Merge-OSSetupJson -Target $current -Source (Get-OSSetupDockerBuildCacheSetting -Action $Action)
        New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $merged -Depth 32) + "`n", [System.Text.UTF8Encoding]::new($false))
        Write-OSSetupLog -Level Detail -Message '  pris en compte au prochain démarrage de Docker Desktop'
    }
}
