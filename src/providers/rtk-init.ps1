# Provider rtk-init : branche rtk sur Claude Code (rtk init --global) : crochet PreToolUse dans ~/.claude/settings.json,
# RTK.md et sa référence dans ~/.claude/CLAUDE.md. rtk demande d'abord s'il peut envoyer des statistiques d'usage :
# sans réponse enregistrée, la question bloquerait le setup, d'où le refus enregistré au préalable (modifiable ensuite
# avec « rtk telemetry enable »).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'rtk-init'

    Describe = {
        param($Action, $Context)
        'rtk init --global (crochet Claude Code)'
    }

    Test     = {
        param($Action, $Context)
        if (-not (Get-Command -Name rtk -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
        $show = @(& rtk init --show 2>$null)
        [bool]($show | Where-Object { $_ -match '^\[ok\] Hook:' }) -and [bool]($show | Where-Object { $_ -match '^\[ok\] settings\.json:' })
    }

    Invoke   = {
        param($Action, $Context)
        $status = @(& rtk telemetry status 2>$null)
        if ($status | Where-Object { $_ -match 'consent:\s+never asked' }) {
            & rtk telemetry disable *> $null
            Write-OSSetupLog -Level Detail -Message '  statistiques d''usage de rtk refusées (rtk telemetry enable pour les accepter)'
        }
        # Entrée vide : aucune question ne peut bloquer le setup.
        $output = $null | & rtk init --global --auto-patch 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
        if ($exitCode -ne 0) { throw "rtk init a échoué (code $exitCode)." }
    }
}
