# Provider gh-extension : extension de GitHub CLI (ex. dlvhdr/gh-dash), installée pour le compte. GitHub CLI doit être
# connecté (étape gh-auth).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'gh-extension'

    Describe = {
        param($Action, $Context)
        "gh extension install $($Action['repo'])"
    }

    Test     = {
        param($Action, $Context)
        if (-not (Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
        $installed = @(& gh extension list 2>$null)
        [bool]($installed | Where-Object { $_ -match "(^|\s)$([regex]::Escape($Action['repo']))(\s|$)" })
    }

    Invoke   = {
        param($Action, $Context)
        $output = & gh extension install $Action['repo'] 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) { if ("$line".Trim()) { Write-OSSetupLog -Level Detail -Message "  $line" } }
        if ($exitCode -ne 0) { throw "gh extension install a échoué (code $exitCode)." }
    }
}
