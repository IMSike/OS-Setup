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

    # Conforme quand le plugin est enregistré et activé (champ enabled de plugins.json), comme claude-plugin. Comparaison
    # stricte : un champ enabled absent (format changé) rend l'élément non conforme, et le journal en donne la raison.
    Test     = {
        param($Action, $Context)
        $path = Join-Path -Path $env:APPDATA -ChildPath 'herdr\plugins.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        $plugins = @(ConvertFrom-OSSetupJsonText -Text (Get-Content -LiteralPath $path -Raw -Encoding utf8) -Name $path |
                Where-Object { $_ -is [System.Collections.IDictionary] -and $_['plugin_id'] -eq $Action['id'] })
        if ($plugins | Where-Object { $_['enabled'] -eq $true }) { return $true }
        if ($plugins | Where-Object { -not $_.Contains('enabled') }) {
            Write-OSSetupLogOnce -Key "herdr-plugin:$($Action['id']):enabled" -Level Detail `
                -Message "  plugin $($Action['id']) : champ « enabled » absent de $path : considéré comme non conforme"
        }
        $false
    }

    Invoke   = {
        param($Action, $Context)
        $path = Join-Path -Path $env:APPDATA -ChildPath 'herdr\plugins.json'
        $plugins = @(if (Test-Path -LiteralPath $path -PathType Leaf) { ConvertFrom-OSSetupJsonText -Text (Get-Content -LiteralPath $path -Raw -Encoding utf8) -Name $path })
        if ($plugins | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['plugin_id'] -eq $Action['id'] }) {
            # Déjà installé mais désactivé : réactivé, sans réinstallation.
            Invoke-OSSetupNativeCommand -FilePath herdr -ArgumentList 'plugin', 'enable', $Action['id'] -Utf8 -Label 'herdr plugin enable'
            return
        }
        # --yes : sans console interactive, herdr refuse d'installer sans confirmation (pas d'aperçu).
        Invoke-OSSetupNativeCommand -FilePath herdr -ArgumentList 'plugin', 'install', $Action['repo'], '--yes' -Utf8 -Label 'herdr plugin install'
    }
}
