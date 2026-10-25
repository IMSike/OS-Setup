# Réglages de PSScriptAnalyzer pour le code du dépôt (setup.ps1, bootstrap.ps1, src/, dotfiles/).
# Règles par défaut, sauf exclusions justifiées ci-dessous. Un cas isolé se traite au plus près du code avec
# [Diagnostics.CodeAnalysis.SuppressMessageAttribute('Règle', 'Cible', Justification = '…')].
# Les tests ont leurs propres réglages : tests/PSScriptAnalyzerSettings.psd1.
# Vérifié par tests/CodeQuality.Tests.ps1.
@{
    ExcludeRules = @(
        # L'interface est un assistant console interactif : menus redessinés sur place, états en couleur, messages
        # du bootstrap. Write-Host est voulu (affichage seulement, jamais une sortie à capturer) ; le journal est
        # écrit à part par Write-OSSetupLog.
        'PSAvoidUsingWriteHost'
    )
}