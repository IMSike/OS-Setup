# Provider fnm-node : version de Node.js par défaut installée avec fnm (gestionnaire de versions). Seule « lts » est
# prise en charge : dernière version LTS, utilisée hors des projets qui demandent une autre version (.nvmrc,
# .node-version, installée à la demande par fnm).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'fnm-node'

    Describe = {
        param($Action, $Context)
        'Node.js : dernière version LTS, version par défaut (fnm)'
    }

    Test     = {
        param($Action, $Context)
        if (-not (Get-Command -Name fnm -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
        & fnm default *> $null
        $LASTEXITCODE -eq 0
    }

    Read     = {
        param($Action, $Context)
        $versions = @(& fnm list 2>$null)
        [ordered]@{ installed = $versions }
    }

    Invoke   = {
        param($Action, $Context)
        foreach ($arguments in @(@('install', '--lts'), @('default', 'lts-latest'))) {
            $output = & fnm @arguments 2>&1
            $exitCode = $LASTEXITCODE
            foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
            if ($exitCode -ne 0) { throw "fnm $($arguments -join ' ') a échoué (code $exitCode)." }
        }
    }
}
