# Comment le setup modifie Windows

Ce document explique les mécanismes communs à tous les éléments du catalogue. Le détail de chaque réglage (effet, implications, retour arrière) est dans [`windows/settings.md`](windows/settings.md).

## Données et moteur

Le catalogue (`catalog/`) décrit **ce qu'on veut obtenir**, en JSON : « telle valeur de registre doit valoir 0 », « tel paquet winget doit être installé ». Il ne contient aucun code.

Le moteur (`src/`) sait **comment** l'obtenir, grâce aux **providers** : un provider par type d'action. Ajouter un logiciel ou un réglage ne demande donc que du JSON ; un nouveau provider n'est nécessaire que pour un nouveau *type* d'action.

## Providers

Chaque provider fournit au moteur :

| Opération | Rôle |
|---|---|
| `Describe` | Phrase affichée dans le plan et le journal (« service DiagTrack : démarrage Disabled »). |
| `Test` | Le système est-il **déjà** dans l'état voulu ? Donne le statut `[ok]` / `[à faire]` du plan, rend le setup **idempotent** (une relance ne refait rien) et permet `-WhatIf`. Le moteur le rappelle **après** l'action pour vérifier qu'elle a réussi. |
| `Invoke` | Applique l'action. Peut signaler qu'un redémarrage est nécessaire. |
| (revérification) | Le plan teste tout **avant** d'agir. Quand une action d'un élément vient d'être appliquée, les actions suivantes du même élément, et celles des éléments qui en dépendent, jugées conformes sont **retestées** au moment de les exécuter (ex. l'installation d'un navigateur crée le raccourci que l'action suivante doit supprimer, ou l'entrée de démarrage qu'un autre élément doit désactiver). |
| `Read` (facultatif) | Lit l'état actuel, enregistré comme **valeur d'origine** avant toute modification (voir plus bas). |

| Provider | Ce qu'il fait | Pourquoi un provider dédié | Valeur d'origine |
|---|---|---|---|
| `winget` | Installe un logiciel avec winget (`--exact --id`, source `winget`). | Gestion des codes de retour (déjà installé, redémarrage, élévation), encodage de la sortie ; attente (60 s au plus) que le paquet soit détecté, certains installeurs finissant en arrière-plan. | — (logiciel absent avant) |
| `registry` | Écrit une valeur de registre. | Cas le plus courant des réglages. | type et valeur, ou absence |
| `directory` | Crée un dossier. | | — |
| `file` | Déploie un fichier de `dotfiles/` : copie, gabarit `{{Variable}}`, ou **fusion JSON** (`merge-json` : seules les clés du dépôt sont écrites, celles de la machine conservées ; conforme si ces clés ont déjà leur valeur ; commentaires et virgules finales acceptés en lecture, comme dans les réglages de VS Code, mais retirés à lécriture). `unlessSelected` : sans objet quand un autre élément retenu déploie une variante du fichier. | Sauvegarde préalable du fichier existant. | le fichier lui-même, dans les sauvegardes |
| `path` | Ajoute un dossier au PATH. | Préserve les `%VARIABLES%` et notifie Windows du changement. | — (ajout seul) |
| `windows-feature` | Active une fonctionnalité facultative de Windows (ex. WSL). | `dism`, détection du redémarrage nécessaire. | état (`Disabled`…) |
| `service` | Fixe le type de démarrage d'un service (et l'arrête s'il est désactivé). | Les **services** sont des programmes d'arrière-plan lancés par Windows (ex. DiagTrack, la télémétrie). Écrire la valeur `Start` du registre ne l'arrêterait qu'au redémarrage et contournerait le gestionnaire de services : le provider passe par `Set-Service`. | type de démarrage et état |
| `scheduled-task` | Active ou désactive une tâche planifiée. | Windows exécute périodiquement des **tâches planifiées** (ex. inventaire des logiciels envoyé à Microsoft). Elles ne se modifient pas de façon fiable par le registre : API du Planificateur de tâches. | état de la tâche |
| `power` | Règle un délai d'alimentation (veille, extinction de l'écran) du mode actif. | Les valeurs ne sont prises en compte que si le mode est réactivé : `powercfg`, l'outil officiel. Lecture indépendante de la langue de Windows. | délai en secondes |
| `appx` | Supprime une application du Store pour tous les comptes et la déprovisionne. | Module Appx (via Windows PowerShell 5.1 sous PowerShell 7). | paquets présents |
| `windows-capability` | Retire un composant Windows facultatif (« capacité »). | `Remove-WindowsCapability`, redémarrage éventuel. | capacités installées |
| `win32-uninstall` | Désinstalle un logiciel classique sans interaction. | Désinstalleur déclaré dans « Programmes et fonctionnalités » ; la disparition du logiciel fait foi plutôt que le code de retour. | entrée de désinstallation |
| `shortcut` | Crée (copie d'un raccourci existant) ou supprime un raccourci `.lnk`. | | présence |
| `desktop-layout` | Applique la disposition de la barre des tâches et du menu Démarrer. | Agrège les déclarations de **tous** les éléments retenus (`taskbarPin` : raccourci `.lnk` ou application du Store, `startLayout`) : Windows 10 n'applique la disposition qu'en bloc. Voir [`windows/desktop.md`](windows/desktop.md). | épingles et empreinte de la disposition |
| `startup-entry` | Désactive le lancement d'un logiciel à l'ouverture de session. | Comme le Gestionnaire des tâches (`StartupApproved`) : l'entrée reste et le logiciel peut la recréer, elle reste désactivée. | état de chaque entrée |
| `windows-update` | Installe les pilotes proposés par Windows Update. | API intégrée (objet COM `Microsoft.Update.Session`), sans module tiers ; recherche lente mémorisée pendant l'exécution ; redémarrage signalé. Voir [`windows/drivers.md`](windows/drivers.md). | titres des mises à jour proposées |
| `taskbar` | Masquage automatique de la barre des tâches. | API `SHAppBarMessage` (celle de Paramètres) : effet immédiat ; la valeur binaire du registre qui le contient est réécrite par l'Explorateur. Voir [`windows/desktop.md`](windows/desktop.md). | état d'avant |
| `manual` | Étape manuelle guidée (voir plus bas). | Vérification et aide écrites dans le moteur. | — |
| `git-config` | Une clé de la configuration Git globale (`git config --global`). | Clé par clé : les autres réglages de l'utilisateur restent. | valeur ou absence |
| `vscode-extension` | Installe une extension de VS Code ou de Cursor (`code` / `cursor --install-extension`, champ `editor`). | | — |
| `install-script` | Installe un logiciel par le script officiel de son éditeur (`irm <url> \| iex`, Windows PowerShell), quand c'est la méthode recommandée. Présence testée par la commande installée. | Seules des adresses `https` sont acceptées ; chaque script est relu avant son ajout au catalogue (il s'exécute avec les droits du setup). | — |
| `fnm-node` | Installe la dernière LTS de Node.js avec fnm et en fait la version par défaut. | | versions installées |
| `npm-global` | Installe un paquet npm global (version de Node.js par défaut). | | — |
| `gh-extension` | Installe une extension de GitHub CLI. | gh doit être connecté. | — |
| `rtk-init` | Branche rtk sur Claude Code (`rtk init --global`). | Refus des statistiques enregistré avant, sinon une question bloquerait le setup. | — |
| `herdr-plugin` | Installe un plugin herdr publié sur GitHub (`herdr plugin install`). | Présence lue dans `%APPDATA%\herdr\plugins.json`. | — |
| `claude-plugin` | Installe un plugin de Claude Code depuis une marketplace GitHub (`claude plugin install`, marketplace ajoutée au passage), et le réactive s'il a été désactivé. | Pour le compte ; présence lue avec `claude plugin list --json`. | — |
| `playwright-cli` | Configure Playwright CLI : skill d'un agent (`install --skills`) ou navigateur fourni par Playwright (`install-browser`). | Lancé depuis le profil de l'utilisateur (aucun dossier `.playwright` créé ailleurs) ; présence lue sur le disque. | — |
| `logon-task` | Crée une tâche planifiée qui lance un script PowerShell à l'ouverture de session (droits les plus élevés, sans invite UAC). | Script déployé hors du dépôt (qui peut être supprimé en fin de setup) ; Windows PowerShell 5.1, toujours présent. | — |
| `docker-build-cache` | Plafond du cache de build de Docker (`builder.gc` de `daemon.json`). | Fusion JSON ; plafond ramené à un pourcentage du disque système quand il est petit (sécurité matérielle). | contenu d'avant |
| `wsl-config` | Une clé de `%USERPROFILE%\.wslconfig` (réglages de la VM de WSL 2). | Clé par clé, reste du fichier conservé. `memoryPercent` calcule la valeur selon la RAM de la machine, avec des bornes (**sécurité matérielle** : un fichier de réponses reste valable sur une machine plus petite ; valeur ramenée dans les bornes signalée au journal). Voir [`windows/development.md`](windows/development.md). | valeur ou absence |

Les providers propres à un outil (`git-config`, `fnm-node`, `rtk-init`…) tiennent en quelques lignes : ils évitent le provider « commande » générique écarté ci-dessous.

### Provider « commande » générique : écarté

Une action qui contiendrait, en texte, une commande de test et une commande d'application permettrait de tout faire sans toucher au moteur. Écartée parce que :

- c'est du code dans les données, contraire au principe « données ≠ moteur » ;
- le schéma ne vérifie que la syntaxe, pas le sens ; le plan afficherait une commande brute au lieu d'une phrase ;
- l'idempotence et les pièges (langue des sorties, encodage) seraient à refaire par chaque auteur ;
- impossible à tester avec des simulations (mocks) ;
- n'importe quel fichier de données pourrait exécuter du code arbitraire avec les droits administrateur.

Elle reste un dernier recours, à valider, si un besoin ne rentre dans aucun provider.

## Étapes manuelles guidées

Certaines étapes ne peuvent pas être automatisées : choix protégé par Windows (navigateur par défaut), connexion à un compte (GitHub), mot de passe choisi par l'utilisateur (compte Linux de WSL). Le provider `manual` les rend aussi simples que possible :

1. le plan indique `[à faire]` tant que la vérification échoue (une relance du setup ne repropose donc que ce qui reste à faire) ;
2. au moment de l'étape, le setup affiche les instructions et lance l'aide : page de Paramètres, commande à compléter dans la console, ou nouvelle fenêtre ;
3. menu « C'est fait : vérifier » / « Relancer l'aide » / « Passer (à faire plus tard) » ; la vérification lit l'état réel (ex. `gh auth status`) ;
4. sans surveillance (`-Yes`), l'étape n'est pas lancée : elle est signalée en échec « à faire plus tard » dans le récapitulatif, comme une étape passée ; les éléments qui en dépendent sont ignorés.

Les vérifications et les aides sont écrites dans le moteur (`src/OSSetup/Functions/Manual.ps1`) ; un élément choisit seulement laquelle (`check`) et fournit les instructions.

## Informations personnelles

Une variable de profil déclarée `personal` (ex. nom et adresse pour Git) n'a **jamais** de valeur dans le dépôt. L'assistant la demande à l'étape « Informations personnelles » ; elle est conservée dans les réponses de la session (`state/answers-last.json`, hors dépôt) et peut figurer dans un fichier de réponses personnel. Non renseignée (choix « Continuer sans », fichier de réponses sans elle, `-AcceptDefaults`), les actions qui l'utilisent sont marquées `[ignoré]` dans le plan : rien n'est écrit à vide.

## Registre : HKLM et HKCU

Le **registre** est la base de configuration de Windows, organisée en « ruches » :

| Ruche | Nom complet | Portée | Droits pour écrire | Fichier |
|---|---|---|---|---|
| **HKLM** | `HKEY_LOCAL_MACHINE` | toute la machine, tous les comptes | administrateur | `C:\Windows\System32\config\` |
| **HKCU** | `HKEY_CURRENT_USER` | uniquement le compte de la session | aucun | `C:\Users\<compte>\NTUSER.DAT` |

Conséquences :

- un réglage HKCU ne s'applique **qu'au compte courant** : un compte créé plus tard sur la machine ne l'a pas ;
- c'est pour HKCU que le setup vérifie que le compte élevé (après l'invite UAC) est bien celui de la session : sinon les réglages iraient dans le profil d'un autre compte.

## Préférence ou stratégie de groupe

Deux sortes de valeurs de registre peuvent piloter un même réglage :

| | **Préférence** | **Stratégie de groupe** (clé `…\Policies\…`) |
|---|---|---|
| Ce que c'est | L'endroit où Paramètres (ou l'application) range **le choix de l'utilisateur** | Le mécanisme d'**administration** prévu pour les entreprises (gpedit.msc, Active Directory) |
| Priorité | Remplacée par une stratégie si elle existe | Toujours prioritaire |
| Interface | Reste modifiable dans Paramètres | Réglage grisé, bandeau « Certains paramètres sont gérés par votre organisation » |
| Mises à jour de Windows | Une mise à jour majeure peut la réinitialiser | Conservée |
| Édition | Fonctionne partout | Certaines ne sont lues que sur Entreprise / Éducation (ignorées sur Pro) |
| Visibilité | Paramètres | **Invisible dans gpedit.msc** (qui lit son propre fichier) : visible seulement avec `regedit` |
| Machine dans un domaine | — | Une stratégie du domaine prévaut sur la nôtre |

**Règle du projet** : la préférence d'abord ; une stratégie seulement s'il n'existe pas d'équivalent fiable. Chaque réglage de [`windows/settings.md`](windows/settings.md) indique lequel des deux il utilise.

## Effet différé

Certains réglages (Explorateur, menu Démarrer, écran de veille…) ne prennent effet qu'à la **prochaine ouverture de session**. Ils sont marqués `requiresLogoff` dans le catalogue ; le récapitulatif de fin les liste, sauf si un redémarrage est déjà prévu. C'est aussi le cas d'un logiciel qui ajoute le compte à un groupe local (Docker Desktop : groupe `docker-users`, pris en compte à l'ouverture de session suivante).

Pour que l'environnement soit prêt à l'emploi à la fin du setup, la **session est alors fermée** (passe finale seulement, sans redémarrage prévu, au moins une action de ce type appliquée) : compte à rebours de 10 secondes qu'une touche reporte, immédiat avec `-Yes`. La fermeture est faite par le nettoyage de fin (`src/cleanup.ps1`, `shutdown /l`), après ses autres opérations : fermer la session plus tôt les interromprait. Les tâches lancées à l'ouverture de session (ex. entretien de Docker, qui démarre Docker Desktop) s'exécutent à la reconnexion. Enregistrer le travail ouvert dans les autres fenêtres avant la fin du setup.

## Retour arrière et valeurs d'origine

Le setup **n'annule rien de lui-même** : décocher un réglage lors d'une exécution suivante ne le rétablit pas. Tout reste réversible **à la main** ([`windows/settings.md`](windows/settings.md) indique où pour chaque réglage) :

| Type | Où revenir en arrière |
|---|---|
| Préférence | Paramètres (attention : sur Windows non activé, la page *Personnalisation* est verrouillée, il faut passer par `regedit`) |
| Stratégie | `regedit` : supprimer la valeur |
| Service | `services.msc` |
| Tâche planifiée | `taskschd.msc` |
| Alimentation | Paramètres > Système > Alimentation et mise en veille |

Pour savoir quelle valeur remettre, le moteur enregistre, **avant chaque modification**, l'état d'origine lu par le provider (`Read`) :

- fichier `state\backups\<date>\original-values.json` du dossier du setup : pour chaque action, l'élément, la description, l'action et l'état d'avant (`before`) — par exemple `{ "exists": false }` si la valeur n'existait pas, ce qui signifie qu'il suffit de la supprimer ;
- les exécutions reprises après redémarrage complètent le même fichier ;
- en fin de setup, avec l'option « garder l'historique », il est conservé dans `%LOCALAPPDATA%\OS-Setup\<date>\backups\` avec le journal et les réponses ; avec « tout supprimer », il disparaît.

Une commande d'annulation automatique pourra s'appuyer sur ce fichier plus tard.
