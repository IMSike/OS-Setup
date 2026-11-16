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
    $output = @($result.Output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    try {
        foreach ($plugin in @(($output -join "`n") | ConvertFrom-Json)) {
            $scope = if ($plugin.PSObject.Properties['scope']) { [string]$plugin.scope } else { '' }
            [pscustomobject]@{ Id = [string]$plugin.id; Scope = $scope; Enabled = [bool]$plugin.enabled }
        }
    }
    catch {
        Write-OSSetupLog -Level Detail -Message "  liste des plugins de Claude Code illisible : $($_.Exception.Message)"
    }
}
