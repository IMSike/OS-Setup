# Navigateurs (Windows 10)

Installation (menu « Navigateurs à installer », `catalog/browsers/`) et réglages (menu « Navigateurs : réglages », `catalog/browser-settings/`, tout coché par défaut). Un réglage propre à un navigateur n'est proposé que si ce navigateur est choisi. Les notions communes (stratégie, HKLM, retour arrière) sont expliquées dans [`../how-it-works.md`](../how-it-works.md).

## Mécanisme : les stratégies des navigateurs

Edge, Chrome, Brave et Firefox lisent des **stratégies** dans `HKLM\SOFTWARE\Policies\…`, y compris sur un poste personnel. Méthode officielle et documentée par chaque éditeur.

- **Implication commune** : le navigateur affiche « Votre navigateur est géré par votre organisation » (Firefox : « Votre navigateur est géré par votre organisation » dans le menu), et les réglages concernés sont grisés dans ses paramètres. Les stratégies appliquées se consultent dans `edge://policy`, `chrome://policy`, `brave://policy` ou `about:policies`.
- **Revenir en arrière** : `regedit` : supprimer la valeur (ou la clé du navigateur sous `HKLM\SOFTWARE\Policies`), puis redémarrer le navigateur.
- Les mises à jour des navigateurs ne sont **jamais** désactivées : un navigateur doit rester à jour pour la sécurité.
- Hors dépôt (personnel) : page d'accueil, extensions, comptes et synchronisation.

## Edge (conservé et neutralisé)

Sur Windows 10, Edge ne se désinstalle pas (voir [`removable-apps.md`](removable-apps.md)) : il est neutralisé. Il est déjà retiré de la barre des tâches par la disposition (voir [Intégration au bureau](desktop.md)). Désinstallation complète prévue pour Windows 11.

### Pas d'exécution en arrière-plan — `edge-no-background`

✔ · admin · stratégies (HKLM) + entrée de démarrage

- **Effet** : Edge ne se lance plus à l'ouverture de session (« démarrage anticipé », qui le préchargeait sans fenêtre) et ne reste plus en arrière-plan après la fermeture de sa dernière fenêtre.
- **Implications** : premier lancement d'Edge un peu plus lent ; moins de mémoire utilisée et plus de processus Edge invisibles.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Edge` `StartupBoostEnabled` = 0, `BackgroundModeEnabled` = 0 ; entrée de démarrage `MicrosoftEdgeAutoLaunch_*` désactivée (provider `startup-entry`, voir plus bas).

### Pas de raccourci sur le bureau — `edge-no-desktop-shortcut`

✔ · admin · stratégie (HKLM) + raccourci

- **Effet** : supprime le raccourci d'Edge du bureau et empêche ses mises à jour d'en recréer un.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate` `CreateDesktopShortcutDefault` = 0 ; raccourci `Microsoft Edge.lnk` retiré du bureau du compte et du bureau public.
- **Revenir en arrière** : supprimer la valeur ; recréer le raccourci depuis le menu Démarrer.

### Personnalisation et commentaires désactivés — `edge-telemetry-off`

✔ · admin · stratégies (HKLM)

- **Effet** : Edge n'utilise plus l'historique de navigation pour personnaliser publicités, recherche et actualités, et ne propose plus d'envoyer des commentaires.
- **Implications** : sur Windows 10, le niveau de données de diagnostic d'Edge suit celui de Windows, déjà réglé au minimum (`telemetry-required`).
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Edge` `PersonalizationReportingEnabled` = 0, `UserFeedbackAllowed` = 0.

### Incitations désactivées — `edge-no-nags`

✔ · admin · stratégies (HKLM)

- **Effet** : plus d'écran de bienvenue au premier lancement, plus de demande à devenir navigateur par défaut, plus de recommandations ni de contenus « à la une », plus d'assistant d'achat (comparaison de prix), plus de Microsoft Rewards, plus de barre latérale (applications), plus de bouton « Conversation » (Copilot) dans la barre d'outils, plus d'onglets promotionnels.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Edge` : `HideFirstRunExperience` = 1, `DefaultBrowserSettingEnabled` = 0, `ShowRecommendationsEnabled` = 0, `SpotlightExperiencesAndRecommendationsEnabled` = 0, `EdgeShoppingAssistantEnabled` = 0, `ShowMicrosoftRewards` = 0, `HubsSidebarEnabled` = 0, `PromotionalTabsEnabled` = 0, `Microsoft365CopilotChatIconEnabled` = 0 (la stratégie de la barre latérale ne masque plus le bouton Copilot dans les versions récentes : vérifié en VM).

## Firefox — `firefox-privacy`

✔ si Firefox est choisi · admin · stratégies (HKLM)

- **Effet** : plus de télémétrie ni d'études (expériences à distance de Mozilla), plus d'« agent de navigateur par défaut » (tâche planifiée qui envoie à Mozilla des informations sur le navigateur par défaut), plus de Pocket, plus de raccourcis ni d'articles sponsorisés sur la page Nouvel onglet, plus de recommandations d'extensions ou de fonctionnalités.
- **Valeur** : `HKLM\SOFTWARE\Policies\Mozilla\Firefox` : `DisableTelemetry` = 1, `DisableFirefoxStudies` = 1, `DisableDefaultBrowserAgent` = 1, `DisablePocket` = 1 ; `…\FirefoxHome` `SponsoredTopSites` = 0, `SponsoredPocket` = 0 ; `…\UserMessaging` `ExtensionRecommendations` = 0, `FeatureRecommendations` = 0.

## Chrome — `chrome-privacy`

✔ si Chrome est choisi · admin · stratégies (HKLM)

- **Effet** : plus de statistiques d'utilisation ni de rapports de plantage envoyés à Google, plus de collecte des adresses visitées « anonymisées », plus de commentaires, plus de contenus promotionnels.
- **Implications** : la navigation sécurisée de Google reste active (protection contre les sites malveillants).
- **Valeur** : `HKLM\SOFTWARE\Policies\Google\Chrome` : `MetricsReportingEnabled` = 0, `UrlKeyedAnonymizedDataCollectionEnabled` = 0, `UserFeedbackAllowed` = 0, `PromotionsEnabled` = 0.

## Brave

### Statistiques et services intégrés désactivés — `brave-privacy`

✔ si Brave est choisi · admin · stratégies (HKLM)

- **Effet** : plus de statistiques d'utilisation (P3A, ping quotidien, rapports de plantage), et désactivation de Brave Rewards (publicités rémunérées), Brave Wallet (portefeuille de cryptomonnaies), Brave VPN et de l'assistant IA (Leo).
- **Valeur** : `HKLM\SOFTWARE\Policies\BraveSoftware\Brave` : `MetricsReportingEnabled` = 0, `BraveP3AEnabled` = 0, `BraveStatsPingEnabled` = 0, `BraveRewardsDisabled` = 1, `BraveWalletDisabled` = 1, `BraveVPNDisabled` = 1, `BraveAIChatEnabled` = 0.

### Mise à jour non lancée à l'ouverture de session — `brave-no-autostart`

✔ si Brave est choisi · entrée de démarrage

- **Effet** : le programme de mise à jour de Brave (`BraveSoftware Update`) ne se lance plus à chaque ouverture de session.
- **Implications** : aucune pour la sécurité : les mises à jour continuent par les tâches planifiées de Brave.
- **Valeur** : provider `startup-entry` (voir ci-dessous).

## Lancement au démarrage : provider `startup-entry`

Désactive une entrée comme le **Gestionnaire des tâches** (onglet Démarrage) : l'entrée de la clé `Run` reste, une valeur binaire de `…\Explorer\StartupApproved\Run` la marque « désactivée » (premier octet impair, suivi de la date). Un logiciel qui recrée son entrée à chaque mise à jour reste ainsi désactivé. **Revenir en arrière** : Gestionnaire des tâches > Démarrage > Activer.

## Navigateur par défaut — étape manuelle guidée

Menu « Navigateur par défaut (étape manuelle guidée) », choix unique parmi les navigateurs choisis ; Vivaldi par défaut.

| Élément | Navigateur | Programme attendu pour `https` (ProgId) |
|---|---|---|
| `default-browser-vivaldi` | Vivaldi | `VivaldiHTM*` |
| `default-browser-firefox` | Firefox | `FirefoxURL-*` |
| `default-browser-chrome` | Google Chrome | `ChromeHTML` |
| `default-browser-brave` | Brave | `BraveHTML` |

- **Pourquoi manuel** : Windows 10 protège ce choix par une empreinte (`UserChoice\Hash`) que seul Windows calcule : une valeur écrite par un script est ignorée et Windows revient à Edge. Les outils tiers qui recalculent l'empreinte sont écartés ; la stratégie « fichier d'associations par défaut » et le fichier d'associations DISM ne valent que pour une machine d'un domaine ou les nouveaux comptes.
- **Déroulement** (provider `manual`, voir [`../how-it-works.md`](../how-it-works.md)) : le setup affiche les instructions, ouvre Paramètres > Applications > Applications par défaut, puis attend « C'est fait : vérifier » ; il lit alors le choix de l'utilisateur (`HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice` `ProgId`). « Passer » laisse l'étape à faire plus tard (signalée dans le récapitulatif) ; une relance du setup la repropose. Sans surveillance (`-Yes`), l'étape est seulement signalée.
- **Implications** : la page Applications par défaut fonctionne aussi sur Windows non activé.
- **Revenir en arrière** : Paramètres > Applications > Applications par défaut.
