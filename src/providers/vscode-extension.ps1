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

    # Liste des extensions lue une fois par passe et par éditeur (une lecture par action serait lente).
    Test     = {
        param($Action, $Context)
        [bool](Get-OSSetupEditorExtension -Command ($Action['editor'] ?? 'code') | Where-Object { $_ -eq $Action['id'] })
    }

    Invoke   = {
        param($Action, $Context)
        $command = $Action['editor'] ?? 'code'
        Invoke-OSSetupNativeCommand -FilePath $command -ArgumentList '--install-extension', $Action['id'], '--force' -Utf8 -Label "$command --install-extension"
    }
}
