# Provider herdr-plugin : plugin herdr publié sur GitHub, installé par « herdr plugin install » (clone géré par herdr,
# mis à jour par « herdr plugin update »). Présence lue dans %APPDATA%\herdr\plugins.json.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'herdr-plugin'

    Describe = {
        param($Action, $Context)
        "herdr plugin install $($Action['repo'])"
    }

    Test     = {
        param($Action, $Context)
        $path = Join-Path -Path $env:APPDATA -ChildPath 'herdr\plugins.json'
        if (-not (Test-Path -Path $path -PathType Leaf)) { return $false }
        $plugins = @(ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $path -Raw -Encoding utf8) -Name $path)
        [bool]($plugins | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['plugin_id'] -eq $Action['id'] })
    }

    Invoke   = {
        param($Action, $Context)
        # --yes : sans console interactive, herdr refuse d'installer sans confirmation (pas d'aperçu).
        $output = & herdr plugin install $Action['repo'] --yes 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
        if ($exitCode -ne 0) { throw "herdr plugin install a échoué (code $exitCode)." }
    }
}
