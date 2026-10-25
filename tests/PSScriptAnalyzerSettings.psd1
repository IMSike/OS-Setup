# Réglages de PSScriptAnalyzer pour les tests (Pester et outillage des VM de test).
# Mêmes règles que le code du dépôt (../PSScriptAnalyzerSettings.psd1), plus les exclusions propres aux tests.
@{
    ExcludeRules = @(
        # Comme pour le code du dépôt : affichage console voulu.
        'PSAvoidUsingWriteHost'

        # Les mocks et providers factices s'exécutent dans la portée du module OSSetup : une variable globale est le
        # seul canal commun avec le test (toujours retirée dans AfterAll / AfterEach).
        'PSAvoidGlobalVars'

        # Les fonctions New-Test… des tests fabriquent des objets en mémoire : -WhatIf n'aurait aucun sens.
        'PSUseShouldProcessForStateChangingFunctions'

        # Faux positifs avec Pester : une variable affectée dans BeforeAll / BeforeEach est lue dans les It, ce que
        # l'analyse (bloc par bloc) ne voit pas.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}