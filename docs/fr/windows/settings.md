# Réglages Windows

Référence de chaque réglage Windows du catalogue : ce qu'il fait, ses implications, la valeur modifiée et comment revenir en arrière. Les notions utilisées (HKLM / HKCU, préférence / stratégie, valeurs d'origine) sont expliquées dans [`../how-it-works.md`](../how-it-works.md).

Chaque réglage implémenté apparaît ici avec son identifiant de catalogue (`id`) : un test vérifie qu'aucun n'est oublié.

Légende : **✔** coché par défaut · **○** proposé, décoché par défaut · **✘** écarté · **admin** : nécessite les droits administrateur (obtenus par l'invite UAC unique) · **session** : effectif à la prochaine ouverture de session.

## Windows non activé

La plupart des machines cibles n'ont **pas de licence**. La page *Personnalisation* des Paramètres est alors verrouillée (fond d'écran, couleurs, thèmes, écran de verrouillage, Démarrer, barre des tâches) et un filigrane « Activer Windows » s'affiche.

Le verrou porte sur l'**interface** : les valeurs de registre restent modifiables par script. Conséquence pour le retour arrière : un réglage de *Personnalisation* se rétablit alors avec `regedit`, pas dans Paramètres.

---

## Confidentialité et télémétrie

Menu « Confidentialité et télémétrie » du profil `base` (`catalog/privacy/`).

### Données de diagnostic : minimum (Requis) — `telemetry-required`

✔ · admin · préférence (HKLM)

- **Effet** : Windows n'envoie que les données de diagnostic « requises » (configuration de l'appareil, état des mises à jour, erreurs de base) et plus les « facultatives » (utilisation des applications et des fonctionnalités, navigation dans Edge, données d'écriture manuscrite et de saisie améliorées).
- **Implications** : aucune perte de fonctionnalité courante. Le programme Windows Insider exige le niveau facultatif. Le niveau 0 (« Sécurité ») n'existe pas sur Pro : il est réservé à Entreprise / Éducation.
- **Valeur** : `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` `AllowTelemetry` = 1. Malgré le mot « Policies » dans le chemin, c'est la clé où Paramètres range ce choix (pas une stratégie : la page reste utilisable).
- **Revenir en arrière** : Paramètres > Confidentialité > Diagnostics et commentaires > « Données de diagnostic facultatives ».

### Service de télémétrie DiagTrack : désactivé — `diagtrack-off`

✔ · admin · service

- **Effet** : désactive et arrête le service « Expériences des utilisateurs connectés et télémétrie » (`DiagTrack`), qui collecte et envoie les données de diagnostic en continu.
- **Implications** : Windows Update, le Store et l'activation ne sont pas concernés. La « Visionneuse des données de diagnostic » n'a plus rien à afficher.
- **Valeur** : service `DiagTrack`, démarrage *Désactivé*.
- **Revenir en arrière** : `services.msc` > « Expériences des utilisateurs connectés et télémétrie » > Type de démarrage *Automatique*, puis *Démarrer*.

### Tâches planifiées de télémétrie : désactivées — `telemetry-tasks-off`

✔ · admin · tâches planifiées

- **Effet** : désactive les tâches qui collectent des données en arrière-plan :

  | Tâche | Rôle |
  |---|---|
  | `Application Experience\Microsoft Compatibility Appraiser` | Inventorie logiciels et matériel et l'envoie à Microsoft (compatibilité des mises à niveau) |
  | `Application Experience\ProgramDataUpdater` | Collecte pour le programme d'amélioration de l'expérience utilisateur |
  | `Customer Experience Improvement Program\Consolidator`, `UsbCeip` | Programme d'amélioration de l'expérience utilisateur (général, USB) |
  | `Autochk\Proxy` | Collecte de données au démarrage |
  | `DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Envoie des informations sur les disques à Microsoft |
  | `Feedback\Siuf\DmClient`, `DmClientOnScenarioDownload` | Hub de commentaires |

- **Implications** : l'évaluation de compatibilité avant une mise à niveau majeure de Windows est moins fine ; les mises à jour fonctionnent normalement. Une tâche absente (selon la version de Windows) est considérée comme conforme.
- **Valeur** : tâches sous `\Microsoft\Windows\`, état *Désactivée*.
- **Revenir en arrière** : `taskschd.msc` > Bibliothèque > Microsoft > Windows > dossier de la tâche > clic droit *Activer*.

### Identifiant de publicité : désactivé — `advertising-id-off`

✔ · préférence (HKCU)

- **Effet** : les applications ne disposent plus d'un identifiant unique par utilisateur pour suivre l'activité et cibler la publicité.
- **Implications** : la publicité dans les applications n'est pas supprimée, seulement non personnalisée.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` `Enabled` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Général > « Permettre aux applications d'utiliser l'identifiant de publicité ».

### Expériences personnalisées : désactivées — `tailored-experiences-off`

✔ · préférence (HKCU)

- **Effet** : Microsoft n'utilise plus les données de diagnostic pour proposer astuces, publicités et recommandations personnalisées.
- **Implications** : aucune perte de fonctionnalité.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy` `TailoredExperiencesWithDiagnosticDataEnabled` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Diagnostics et commentaires > « Expériences personnalisées ».

### Historique d'activité : désactivé — `activity-history-off`

✔ · admin · stratégie (HKLM)

- **Effet** : Windows n'enregistre plus les applications, documents et sites ouverts, et ne les envoie plus à Microsoft.
- **Implications** : la Chronologie (`Win+Tab`) ne montre plus d'activités passées ; « reprendre sur un autre appareil » ne fonctionne plus. La page Paramètres correspondante est grisée.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` `PublishUserActivities` = 0 et `UploadUserActivities` = 0 (pas d'équivalent utilisateur fiable).
- **Revenir en arrière** : `regedit` : supprimer les deux valeurs.

### Suggestions et publicités de Windows : désactivées — `suggestions-off`

✔ · préférence (HKCU) · session

- **Effet** : supprime les contenus promotionnels de Windows :

  | Valeur (`ContentDeliveryManager`) | Ce qu'elle coupe |
  |---|---|
  | `SystemPaneSuggestionsEnabled`, `SubscribedContent-338388Enabled` | Applications « suggérées » dans le menu Démarrer |
  | `SubscribedContent-338389Enabled`, `SoftLandingEnabled` | Astuces et suggestions dans les notifications |
  | `SubscribedContent-338387Enabled`, `RotatingLockScreenOverlayEnabled` | Anecdotes et astuces sur l'écran de verrouillage |
  | `SubscribedContent-310093Enabled` | Écran « Bienvenue » après les mises à jour |
  | `SubscribedContent-353694Enabled`, `SubscribedContent-353696Enabled` | Contenu suggéré dans Paramètres |
  | `UserProfileEngagement\ScoobeSystemSettingEnabled` | « Terminer la configuration de votre appareil » |

- **Implications** : aucune perte de fonctionnalité ; l'image Windows à la une de l'écran de verrouillage reste possible.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` (et `UserProfileEngagement`), valeurs ci-dessus = 0.
- **Revenir en arrière** : Paramètres > Système > Notifications (astuces, bienvenue, terminer la configuration), Confidentialité > Général (contenu suggéré), Personnalisation > Démarrer et Écran de verrouillage (verrouillées si Windows n'est pas activé : `regedit`, valeurs à 1).

### Applications sponsorisées : installation bloquée — `sponsored-apps-off`

✔ · préférence (HKCU)

- **Effet** : Windows n'installe plus de lui-même des applications promues (Candy Crush, etc.), notamment après une mise à jour majeure.
- **Implications** : ne supprime pas celles déjà installées (voir [`removable-apps.md`](removable-apps.md)). La stratégie `DisableWindowsConsumerFeatures`, plus radicale, est ignorée sur Pro.
- **Valeur** : `ContentDeliveryManager` `SilentInstalledAppsEnabled`, `PreInstalledAppsEnabled`, `OemPreInstalledAppsEnabled` = 0.
- **Revenir en arrière** : `regedit` : valeurs à 1 (pas d'interface).

### Recherche web Bing dans Démarrer : retirée — `web-search-off`

✔ · préférence + stratégie (HKCU) · session

- **Effet** : la recherche du menu Démarrer ne montre plus que des résultats locaux (applications, fichiers, paramètres), sans suggestions Bing ; elle est plus rapide.
- **Implications** : plus de résultats web en tapant dans Démarrer. La stratégie utilisée coupe aussi l'affichage des **recherches récentes** dans la zone de recherche de l'Explorateur.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `BingSearchEnabled` = 0 et `CortanaConsent` = 0 ; stratégie `HKCU\Software\Policies\Microsoft\Windows\Explorer` `DisableSearchBoxSuggestions` = 1 (seule méthode encore efficace depuis Windows 10 2004).
- **Revenir en arrière** : `regedit` : supprimer `DisableSearchBoxSuggestions`, remettre les deux autres à 1.

### Cortana : désactivée — `cortana-off`

✔ · admin · stratégie (HKLM) · session

- **Effet** : Cortana ne peut plus être utilisée.
- **Implications** : aucune. Cortana est abandonnée par Microsoft et, sur un Windows en français, déjà inutilisable (« pas disponible en français (France) ») : le réglage sert surtout aux machines dans une autre langue. L'application elle-même est supprimée avec les applications préinstallées.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` `AllowCortana` = 0.
- **Revenir en arrière** : `regedit` : supprimer la valeur.

### Demandes de commentaires : jamais — `feedback-never`

✔ · préférence (HKCU)

- **Effet** : Windows ne sollicite plus d'avis (« Quelle est la probabilité que vous recommandiez… »).
- **Implications** : aucune ; le Hub de commentaires reste utilisable manuellement s'il est installé.
- **Valeur** : `HKCU\Software\Microsoft\Siuf\Rules` `NumberOfSIUFInPeriod` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Diagnostics et commentaires > « Fréquence des commentaires ».

### Personnalisation de l'écriture et de la saisie : désactivée — `inking-typing-off`

✔ · préférence (HKCU)

- **Effet** : Windows n'apprend plus de vos frappes, tracés et contacts pour personnaliser la reconnaissance, et n'envoie plus d'échantillons à Microsoft.
- **Implications** : suggestions de saisie et reconnaissance de l'écriture manuscrite moins personnalisées ; le dictionnaire personnel appris est effacé.
- **Valeur** : `HKCU\Software\Microsoft\InputPersonalization` `RestrictImplicitInkCollection` = 1, `RestrictImplicitTextCollection` = 1 ; `…\InputPersonalization\TrainedDataStore` `HarvestContacts` = 0 ; `HKCU\Software\Microsoft\Personalization\Settings` `AcceptedPrivacyPolicy` = 0 ; `HKCU\Software\Microsoft\Input\TIPC` `Enabled` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Personnalisation de l'écriture manuscrite et de la saisie ; Diagnostics et commentaires > « Améliorer l'écriture manuscrite et la saisie ».

### Reconnaissance vocale en ligne : désactivée — `online-speech-off`

✔ · préférence (HKCU)

- **Effet** : la voix n'est plus envoyée aux serveurs de Microsoft pour être reconnue.
- **Implications** : la dictée `Win+H` ne fonctionne plus (elle repose sur la reconnaissance en ligne sous Windows 10) ; la reconnaissance vocale hors ligne historique reste disponible.
- **Valeur** : `HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy` `HasAccepted` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Voix.

### Optimisation de la distribution : réseau local — `delivery-optimization-lan`

✔ · admin · stratégie (HKLM)

- **Effet** : les morceaux de mises à jour ne sont plus échangés avec des PC inconnus sur Internet ; seulement avec les PC du réseau local.
- **Implications** : votre connexion n'est plus utilisée pour servir des inconnus ; les téléchargements viennent de Microsoft ou du réseau local. La page Paramètres correspondante est grisée.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` `DODownloadMode` = 1 (le réglage de Paramètres est stocké dans le profil d'un compte de service, peu fiable à modifier).
- **Revenir en arrière** : `regedit` : supprimer la valeur.

### Liste des langues : non communiquée aux sites web — `language-list-optout`

✔ · préférence (HKCU)

- **Effet** : Windows ne transmet plus la liste de vos langues aux sites web.
- **Implications** : un site peut s'afficher dans sa langue par défaut. Firefox, Chrome et Vivaldi utilisent leurs propres réglages de langue et ne sont pas concernés.
- **Valeur** : `HKCU\Control Panel\International\User Profile` `HttpAcceptLanguageOptOut` = 1.
- **Revenir en arrière** : Paramètres > Confidentialité > Général > « Permettre aux sites web d'accéder à ma liste de langues ».

### Recherche sans contenu cloud ni historique — `search-cloud-off`

✔ · préférence (HKCU)

- **Effet** : la recherche Windows n'inclut plus de résultats issus du compte Microsoft ou professionnel (OneDrive, Outlook…) et ne conserve plus l'historique des recherches sur l'appareil.
- **Implications** : plus de résultats cloud ni de « recherches récentes » dans le volet de recherche.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings` `IsMSACloudSearchEnabled`, `IsAADCloudSearchEnabled`, `IsDeviceSearchHistoryEnabled` = 0.
- **Revenir en arrière** : Paramètres > Recherche > Autorisations et historique.

### Points forts de la recherche : désactivés — `search-highlights-off`

✔ · préférence (HKCU) · session

- **Effet** : retire les illustrations et contenus mis en avant par Bing (événements du jour, tendances) dans la zone et le volet de recherche.
- **Implications** : aucune perte de fonctionnalité.
- **Valeur** : `SearchSettings` `IsDynamicSearchBoxEnabled` = 0.
- **Revenir en arrière** : selon la version, Paramètres > Recherche > Autorisations et historique > « Afficher les points forts de la recherche » ; sur la 22H2 testée, l'interrupteur n'y figure pas : `regedit`, valeur à 1.

### Diagnostics des autres applications : accès refusé — `app-diagnostics-off`

✔ · préférence (HKCU)

- **Effet** : les applications du Store ne peuvent plus lire les informations de diagnostic des autres applications (lesquelles tournent, leur consommation…).
- **Implications** : seules de rares applications du Store (gestionnaires de tâches alternatifs) en ont besoin.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics` `Value` = `Deny`.
- **Revenir en arrière** : Paramètres > Confidentialité > Diagnostics d'application.

### Actualités et centres d'intérêt : retirés de la barre des tâches — `news-interests-off`

✔ · admin · stratégie (HKLM) · session

- **Effet** : supprime le widget météo / actualités MSN de la barre des tâches, qui charge en continu du contenu depuis MSN.
- **Implications** : plus de météo dans la barre des tâches ; l'option du clic droit sur la barre des tâches disparaît.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds` `EnableFeeds` = 0 (la préférence utilisateur est protégée par Windows sur 22H2).
- **Revenir en arrière** : `regedit` : supprimer la valeur.

### Messages push WAP (gestion à distance) : désactivés — `dmwappush-off`

✔ · admin · service

- **Effet** : désactive `dmwappushservice`, qui achemine des messages de gestion d'appareil et une partie de la télémétrie.
- **Implications** : empêche l'inscription de la machine à une gestion d'entreprise (Intune / MDM). Sans effet pour un usage personnel.
- **Valeur** : service `dmwappushservice`, démarrage *Désactivé*.
- **Revenir en arrière** : `services.msc` > « Service de routage de messages Push… » > *Manuel*.

### Suivi des applications lancées : désactivé (vide « Les plus utilisées ») — `app-launch-tracking-off`

○ · préférence (HKCU) · session

- **Effet** : Windows ne mémorise plus les programmes lancés.
- **Implications** : la liste « Les plus utilisées » du menu Démarrer est vide et son option grisée ; la recherche classe un peu moins bien vos applications.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` `Start_TrackProgs` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Général > « Autoriser Windows à suivre les lancements d'applications ».

### Localisation : désactivée — `location-off`

✔ · admin · préférence (HKLM)

- **Effet** : coupe le service de localisation pour **toute la machine**.
- **Implications** : plus de réglage automatique du fuseau horaire, ni de météo locale, Cartes, « Localiser mon appareil », ni de position pour les applications qui passent par Windows (dont certains navigateurs).
- **Valeur** : `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location` `Value` = `Deny`.
- **Revenir en arrière** : Paramètres > Confidentialité > Localisation > « Modifier » (accès à la localisation pour cet appareil).

### Rapport d'erreurs Windows : désactivé — `error-reporting-off`

✔ · admin · préférence (HKLM)

- **Effet** : les plantages ne sont plus signalés à Microsoft.
- **Implications** : plus de solutions proposées après un plantage ; les éditeurs ne reçoivent plus les rapports de leurs logiciels via Windows. Restent en local : l'événement 1000 du journal Application et les vidages d'écran bleu ; pour déboguer, voir `crash-dumps-local` (options avancées).
- **Valeur** : `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting` `Disabled` = 1.
- **Revenir en arrière** : `regedit` : valeur à 0.

### Applications du Store en arrière-plan : bloquées — `background-apps-off`

✔ · préférence (HKCU)

- **Effet** : les applications du Store (Courrier, Météo, Photos…) ne s'exécutent plus quand elles sont fermées.
- **Implications** : plus de notifications ni de vignettes dynamiques de ces applications. Les logiciels de bureau classiques (navigateurs, Discord…) ne sont pas concernés.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications` `GlobalUserDisabled` = 1 ; `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `BackgroundAppGlobalToggle` = 0.
- **Revenir en arrière** : Paramètres > Confidentialité > Applications en arrière-plan.

### Presse-papiers entre appareils : non synchronisé — `cross-device-clipboard-off`

✔ · admin · stratégie (HKLM)

- **Effet** : le presse-papiers n'est plus synchronisé entre appareils via le compte Microsoft.
- **Implications** : l'historique local (`Win+V`) reste disponible. Sans objet avec un compte local.
- **Valeur** : `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` `AllowCrossDeviceClipboard` = 0.
- **Revenir en arrière** : `regedit` : supprimer la valeur.

### Écartés

| Réglage | Raison |
|---|---|
| Blocage des serveurs Microsoft (fichier hosts, pare-feu) | ✘ Casse Windows Update, le Store et l'activation ; fragile |
| Defender : envoi d'échantillons et protection cloud | ✘ Compromis de sécurité ; la protection contre les falsifications de Defender bloque ou ignore ces valeurs |
| Télémétrie d'Edge et des logiciels installés (PowerShell 7, winget, VS Code, navigateurs, NVIDIA) | Traitée avec la configuration de chaque logiciel |

---

## Permissions des applications du Store

Menu « Permissions refusées aux applications du Store » du profil `base`, tout coché par défaut sauf la caméra et le micro.

Chaque élément coupe, pour le compte courant, le réglage « Autoriser les applications à accéder à … » de Paramètres > Confidentialité : **aucune application du Store** n'y a plus accès. Selon la documentation de Microsoft, les applications de bureau classiques (navigateurs, Zoom, Discord…) ne sont pas concernées : elles ont un réglage distinct sur la même page. **Constaté sous Windows 10 22H2 : c'est faux pour le micro** : avec `perm-microphone`, Discord n'avait plus accès au micro, jusqu'à ce que « Autoriser les applications à accéder à votre micro » soit réactivé. La caméra est réglée de la même façon : `perm-camera` et `perm-microphone` sont donc décochés par défaut, avec un avertissement quand ils sont cochés. Les autres capacités n'ont pas de réglage pour les applications de bureau.

- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\<capacité>` `Value` = `Deny` (préférence HKCU).
- **Revenir en arrière** : Paramètres > Confidentialité > page de la capacité > « Autoriser les applications à accéder… ».

| Élément | Capacité | Applications de Windows touchées (exemples) |
|---|---|---|
| `perm-camera` | `webcam` | Caméra, Skype / Teams version Store |
| `perm-microphone` | `microphone` | Enregistreur vocal, Teams version Store |
| `perm-account-info` | `userAccountInformation` | Applications qui affichent votre nom ou photo de compte |
| `perm-contacts` | `contacts` | Contacts, Courrier |
| `perm-calendar` | `appointments` | Calendrier, Courrier |
| `perm-call-history` | `phoneCallHistory` | Mobile connecté |
| `perm-email` | `email` | Courrier |
| `perm-messaging` | `chat` | Mobile connecté (SMS) |
| `perm-tasks` | `userDataTasks` | To Do, Courrier |
| `perm-radios` | `radios` | Applications qui activent le Bluetooth ou le Wi-Fi |
| `perm-notifications` | `userNotificationListener` | Applications qui lisent vos notifications (Mobile connecté) |

---

## Alimentation et verrouillage

Menu « Alimentation et verrouillage » du profil `base` (`catalog/power/`). Les délais portent sur le **mode d'alimentation actif** (« Utilisation normale » par défaut) : passer à un autre mode les fait perdre. Ces pages ne sont pas verrouillées sur Windows non activé.

### Mise en veille : jamais sur secteur, 20 min sur batterie — `sleep-policy`

✔ · alimentation

- **Effet** : sur secteur, la machine ne se met jamais en veille ni en veille prolongée ; sur batterie (portables), elle se met en veille après 20 min d'inactivité.
- **Implications** : un PC fixe reste allumé (consommation à vide, de l'ordre de quelques dizaines de watts) ; tâches longues, accès à distance et téléchargements ne sont jamais interrompus. Sans effet sur batterie pour un PC fixe.
- **Valeur** : `powercfg` : veille (`STANDBYIDLE`) secteur 0, veille prolongée (`HIBERNATEIDLE`) secteur 0, veille batterie 1 200 s.
- **Revenir en arrière** : Paramètres > Système > Alimentation et mise en veille.

### Écran : extinction après 4 min 30 (avant le verrouillage) — `display-off`

✔ · alimentation

- **Effet** : l'écran s'éteint après 4 min 30 d'inactivité, sur secteur comme sur batterie.
- **Implications** : 30 s avant le verrouillage (5 min) : bouger la souris pendant ce délai rallume l'écran sans mot de passe. La liste de Paramètres ne propose pas 4 min 30 : elle affiche « 4 minutes », mais c'est bien 270 s qui s'applique (y choisir une valeur la remplace).
- **Valeur** : `powercfg` : `VIDEOIDLE` secteur et batterie = 270 s.
- **Revenir en arrière** : Paramètres > Système > Alimentation et mise en veille.

### Verrouillage : après 5 min d'inactivité (écran de veille) — `lock-on-idle`

✔ · préférence (HKCU) · session

- **Effet** : après 5 min sans activité, un écran de veille vide démarre et la reprise demande le mot de passe (ou le code PIN) : la session est verrouillée.
- **Implications** : une vidéo en plein écran ou une présentation empêche normalement l'écran de veille, donc le verrouillage. Réglage par utilisateur.
- **Choix** : préféré à la stratégie machine `InactivityTimeoutSecs` (qui verrouille aussi, mais n'est plus modifiable dans l'interface).
- **Valeur** : `HKCU\Control Panel\Desktop` : `SCRNSAVE.EXE` = `C:\Windows\System32\scrnsave.scr` (écran vide), `ScreenSaveActive` = `1`, `ScreenSaverIsSecure` = `1`, `ScreenSaveTimeOut` = `300` (secondes).
- **Revenir en arrière** : `Win+R` > `control desk.cpl,,@screensaver` (accessible même sur Windows non activé).

### Démarrage rapide : désactivé (arrêts complets) — `fast-startup-off`

✔ · admin · préférence (HKLM) · avertissement si décoché

- **Fonctionnement du démarrage rapide** (activé par défaut dans Windows) : « Arrêter » ferme les sessions, puis **met en veille prolongée la partie système** (noyau et pilotes) dans `C:\hiberfil.sys` ; l'allumage suivant recharge cet état au lieu de tout réinitialiser. « Redémarrer », ou « Arrêter » avec `Maj` enfoncé, fait toujours un démarrage complet. À ne pas confondre avec le « Fast Boot » de l'UEFI (réglage du firmware).
- **Effet du réglage** : chaque « Arrêter » éteint complètement Windows.
- **Avantages du démarrage rapide (perdus)** : allumage plus rapide après un arrêt — des dizaines de secondes sur disque dur, quelques secondes sur SSD.
- **Inconvénients du démarrage rapide (évités)** :
  - **double démarrage** : la partition Windows reste « en veille prolongée » ; Linux refuse d'y écrire (ou la monte en lecture seule), et forcer l'écriture peut **corrompre des fichiers Windows**. Avec Linux sur un autre disque, le risque disparaît tant que Linux ne touche pas aux partitions Windows, mais reste pour un **disque de données NTFS partagé** ;
  - matériel utilisé par un autre système entre-temps (Bluetooth, réseau, USB) : Windows recharge un état qui ne correspond plus, des périphériques peuvent mal se comporter ;
  - un « arrêt » ne réinitialise ni pilotes ni noyau : un problème persiste après arrêt et rallumage, et la durée de fonctionnement affichée continue de courir ;
  - un logiciel ou pilote qui attend un vrai redémarrage peut sembler ne pas s'appliquer ; un matériel changé pendant l'arrêt est moins bien détecté ; le réveil réseau (Wake-on-LAN) peut ne pas fonctionner selon la carte.
- **Ce qui ne change pas** : la veille prolongée reste disponible et `hiberfil.sys` reste présent (ce réglage ne les supprime pas) ; « Redémarrer » est inchangé.
- **Choix** : coché par défaut, parce que le double démarrage est souvent installé *après* Windows (une détection au moment du setup ne le verrait pas), qu'un outil qui reconstruit des machines doit avoir des arrêts prévisibles, et que le coût est faible sur SSD. Décoché, le setup affiche : « En double démarrage (Linux, ou disque de données NTFS partagé), le démarrage rapide laisse les partitions Windows en veille prolongée : y écrire depuis l'autre système peut corrompre des fichiers Windows. » (champ `uncheckedWarning` du catalogue).
- **Valeur** : `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` `HiberbootEnabled` = 0.
- **Revenir en arrière** : Panneau de configuration > Options d'alimentation > « Choisir l'action des boutons d'alimentation » > « Activer le démarrage rapide ».

---

## Options avancées

Menu « Options avancées » du profil `base`, rien de coché par défaut.

### Vidages des plantages : conservés en local (débogage) — `crash-dumps-local`

○ · admin · préférence (HKLM)

- **Effet** : à chaque plantage d'un programme, Windows écrit un mini-vidage (`.dmp`) dans `%LOCALAPPDATA%\CrashDumps` du compte concerné : threads, pile d'appels, modules chargés, erreur. 10 fichiers au plus, le plus ancien est remplacé.
- **Utilité** : déboguer un plantage (WinDbg, Visual Studio) bien plus précisément qu'avec l'événement 1000 du journal. Sans débogage, aucune.
- **Implications** : **jamais envoyé** (fichiers locaux ; fonctionne même avec le rapport d'erreurs désactivé, vérifié en VM). Quelques centaines de Ko à quelques Mo par plantage. Un vidage contient un extrait de la mémoire du programme (texte ouvert, éventuellement un mot de passe) : ne pas le partager à la légère. Les programmes qui gèrent eux-mêmes leurs plantages (Firefox, Chrome) ne sont pas concernés.
- **Valeur** : `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps` : `DumpFolder` = `%LOCALAPPDATA%\CrashDumps`, `DumpCount` = 10, `DumpType` = 1 (mini-vidage).
- **Revenir en arrière** : `regedit` : supprimer la clé `LocalDumps`.

Traces conservées sans cette option, rapport d'erreurs désactivé : l'événement 1000 « Application Error » du journal Application (programme, module fautif, code d'exception) et les vidages d'écran bleu (`C:\Windows\MEMORY.DMP`, `C:\Windows\Minidump`), indépendants du rapport d'erreurs.

---

## Explorateur et apparence

Réglages toujours appliqués par le profil `base` (`catalog/system/`).

### Explorateur : extensions de fichiers affichées — `explorer-show-extensions`

✔ · préférence (HKCU) · session

- **Effet** : l'Explorateur affiche l'extension des fichiers (`facture.pdf.exe` au lieu de `facture.pdf`).
- **Implications** : repère les fichiers déguisés ; attention à ne pas modifier l'extension en renommant.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` `HideFileExt` = 0.
- **Revenir en arrière** : Explorateur > Affichage > « Extensions de noms de fichiers ».

### Explorateur : fichiers cachés affichés — `explorer-show-hidden`

✔ · préférence (HKCU) · session

- **Effet** : l'Explorateur affiche les fichiers et dossiers cachés (ex. `AppData`, `.git`), en grisé.
- **Implications** : les fichiers système protégés restent masqués.
- **Valeur** : `Explorer\Advanced` `Hidden` = 1.
- **Revenir en arrière** : Explorateur > Affichage > « Éléments masqués ».

### Thème : sombre (applications et système) — `dark-theme`

✔ · préférence (HKCU) · session

- **Effet** : mode sombre pour les applications et pour Windows (barre des tâches, menu Démarrer).
- **Implications** : la page *Couleurs* est verrouillée sur Windows non activé ; le réglage s'applique quand même.
- **Valeur** : `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` `AppsUseLightTheme` = 0, `SystemUsesLightTheme` = 0.
- **Revenir en arrière** : Paramètres > Personnalisation > Couleurs (ou `regedit`, valeurs à 1, si Windows n'est pas activé).
