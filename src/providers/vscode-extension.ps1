# Provider vscode-extension : extension d'éditeur, installée pour le compte avec la commande de l'éditeur
# (« code » pour VS Code, « cursor » pour Cursor).

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'vscode-extension'

    Describe = {
        param($Action, $Context)
        $editorName = if ($Action['editor'] -eq 'cursor') { 'Cursor' } else { 'VS Code' }
        "extension $editorName $($Action['id'])"
    }

    Test     = {
        param($Action, $Context)
        $command = if ($Action['editor']) { $Action['editor'] } else { 'code' }
        if (-not (Get-Command -Name $command -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
        $installed = @(& $command --list-extensions 2>$null)
        [bool]($installed | Where-Object { $_ -eq $Action['id'] })
    }

    Invoke   = {
        param($Action, $Context)
        $command = if ($Action['editor']) { $Action['editor'] } else { 'code' }
        Invoke-OSSetupNativeCommand -FilePath $command -ArgumentList '--install-extension', $Action['id'], '--force' -Label "$command --install-extension"
    }
}
