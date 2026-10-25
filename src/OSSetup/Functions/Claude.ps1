function Get-OSSetupClaudePlugin {
    <#
    .SYNOPSIS
        Plugins de Claude Code installés pour le compte (`claude plugin list --json`) : identifiant et état d'activation.
        Vide si Claude Code est absent ou si la liste est illisible.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    if (-not (Get-Command -Name claude -CommandType Application -ErrorAction SilentlyContinue)) { return }
    # Claude Code écrit en UTF-8 ; sans ce réglage, PowerShell décode sa sortie avec la page de code OEM.
    $previousEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $output = & claude plugin list --json 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousEncoding
    }
    if ($exitCode -ne 0) { return }
    try {
        foreach ($plugin in @(($output -join "`n") | ConvertFrom-Json)) {
            [pscustomobject]@{ Id = [string]$plugin.id; Enabled = [bool]$plugin.enabled }
        }
    }
    catch {
        Write-OSSetupLog -Level Detail -Message "  liste des plugins de Claude Code illisible : $($_.Exception.Message)"
    }
}
