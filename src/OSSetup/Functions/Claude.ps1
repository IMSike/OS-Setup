function Get-OSSetupClaudePlugin {
    <#
    .SYNOPSIS
        Plugins de Claude Code installés (`claude plugin list --json`) : identifiant, portée (user, project…) et état
        d'activation. Vide si Claude Code est absent ou si la liste est illisible.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    if (-not (Get-Command -Name claude -CommandType Application -ErrorAction SilentlyContinue)) { return }
    # Claude Code écrit en UTF-8. La liste (JSON) n'est pas journalisée ; la sortie d'erreur est écartée.
    $result = Invoke-OSSetupNativeCommand -FilePath claude -ArgumentList 'plugin', 'list', '--json' -Utf8 -NoThrow -PassThru -NoLog
    if ($result.ExitCode -ne 0) { return }
    try {
        foreach ($plugin in @(($result.StandardOutput -join "`n") | ConvertFrom-Json)) {
            # Champ absent de la sortie ou nul : $null (le provider le signale et compare strictement, donc non conforme).
            # Pas de conversion d'un null : [string] en ferait '' et [bool] $false, que le provider ne signalerait pas.
            $scopeProperty = $plugin.PSObject.Properties['scope']
            $enabledProperty = $plugin.PSObject.Properties['enabled']
            $scope = if ($scopeProperty -and $null -ne $scopeProperty.Value) { [string]$scopeProperty.Value } else { $null }
            $enabled = if ($enabledProperty -and $null -ne $enabledProperty.Value) { [bool]$enabledProperty.Value } else { $null }
            [pscustomobject]@{ Id = [string]$plugin.id; Scope = $scope; Enabled = $enabled }
        }
    }
    catch {
        Write-OSSetupLog -Level Detail -Message "  liste des plugins de Claude Code illisible : $($_.Exception.Message)"
    }
}
