# Provider playwright-cli : configuration de Playwright CLI (@playwright/cli) pour les agents.
# skills : installe la skill qui apprend la commande à un agent (claude : ~/.claude/skills, agents : ~/.agents/skills).
# browser : télécharge un navigateur fourni par Playwright (chromium, firefox) dans %LOCALAPPDATA%\ms-playwright.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'playwright-cli'

    Describe = {
        param($Action, $Context)
        if ($Action['skills']) { return "playwright-cli install --skills=$($Action['skills']) --global" }
        "playwright-cli install-browser $($Action['browser'])"
    }

    Test     = {
        param($Action, $Context)
        if ($Action['skills']) {
            $root = if ($Action['skills'] -eq 'claude') { '.claude' } else { '.agents' }
            return Test-Path -Path (Join-Path -Path $env:USERPROFILE -ChildPath "$root\skills\playwright-cli\SKILL.md") -PathType Leaf
        }
        $browsersPath = if ($env:PLAYWRIGHT_BROWSERS_PATH) { $env:PLAYWRIGHT_BROWSERS_PATH } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'ms-playwright' }
        if (-not (Test-Path -Path $browsersPath -PathType Container)) { return $false }
        # Dossier « <navigateur>-<révision> » (ex. chromium-1247), pas « chromium_headless_shell-1247 ».
        [bool](Get-ChildItem -Path $browsersPath -Directory | Where-Object { $_.Name -match "^$([regex]::Escape($Action['browser']))-\d+$" })
    }

    Invoke   = {
        param($Action, $Context)
        $arguments = if ($Action['skills']) { @('install', "--skills=$($Action['skills'])", '--global') } else { @('install-browser', $Action['browser']) }
        # Les skills globales ne dépendent pas du dossier courant ; le profil évite de créer .playwright ailleurs.
        # La CLI écrit en UTF-8 : sans ce réglage, PowerShell décode sa sortie avec la page de code OEM.
        $previousEncoding = [Console]::OutputEncoding
        Push-Location -Path $env:USERPROFILE
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $output = & playwright-cli @arguments 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            [Console]::OutputEncoding = $previousEncoding
            Pop-Location
        }
        # Barre de progression du téléchargement : seules les lignes de texte sont journalisées.
        foreach ($line in $output) { if ("$line".Trim() -and "$line" -notmatch '^\|') { Write-OSSetupLog -Level Detail -Message "  $line" } }
        if ($exitCode -ne 0) { throw "playwright-cli $($arguments[0]) a échoué (code $exitCode)." }
    }
}
