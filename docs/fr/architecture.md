# Architecture

## Objectif

Configurer entièrement un poste à partir d'une machine vierge, de façon **reproductible**, **modulaire** et **choisie** :

- plusieurs **profils** d'installation **cumulables** (choix multiple au lancement) : `base` et `dev` ;
- à l'intérieur d'un profil, des **choix** (unique ou multiple) : navigateurs, éditeurs, langages… ;
- installation des logiciels **et** de leur **configuration**, y compris dans des emplacements non standard ;
- exécution **interactive** (menus) ou **sans surveillance** (fichier de réponses rejouable) ;
- fonctionnement sur machine vierge **et** sur machine déjà utilisée.

| Plateforme | Statut |
|---|---|
| Windows 10 Pro 22H2 (19045) | prise en charge |
| Windows 11 | prévue |
| Fedora | prévue |
| Autres distributions Linux | plus tard |
| macOS | hors périmètre |

Le code isole ce qui est propre à une plateforme (providers, réglages système) de ce qui est commun (catalogue, profils, résolution des choix, menus, journalisation).

### Point de départ : une machine vierge

Un Windows fraîchement installé n'a que :

- Windows PowerShell **5.1** (pas de PowerShell 7) ;
- **pas de `winget` utilisable** : une image Windows 10 fraîche embarque un App Installer de 2019 sans winget. Le bootstrap l'installe depuis la publication officielle `microsoft/winget-cli` sur GitHub ;
- pas de Git, de Python, de Chocolatey ni de Scoop ;
- la stratégie d'exécution PowerShell par défaut (`Restricted`).

Tout le reste est installé par le setup lui-même : aucun outil n'est supposé présent sans avoir été vérifié ou installé.

## Principes

1. **Idempotence** : relancer le setup ne casse rien et ne réinstalle pas ce qui est en place. Chaque action vérifie l'état avant d'agir (`Test` → `Set`).
2. **Données ≠ moteur** : le *quoi* (paquets, profils, choix, réglages) est décrit en JSON ; le *comment* est dans le moteur PowerShell. Ajouter un logiciel ne demande pas de modifier le moteur.
3. **Simulation** : toute action qui modifie le système respecte `-WhatIf`.
4. **Traçabilité** : chaque exécution produit un journal horodaté (fichier et console) et un récapitulatif final (appliqué / ignoré / échoué).
5. **Échec isolé** : l'échec d'un élément n'interrompt pas le setup (sauf dépendance) ; il est signalé dans le récapitulatif.
6. **Aucun secret dans le dépôt** : les secrets sont demandés à l'exécution ou lus hors du dépôt.
7. **Aucun chemin propre à une machine** : `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `[Environment]::GetFolderPath(...)`…
8. **Élévation unique** : le bootstrap (ou `setup.ps1` lancé seul, hors `-WhatIf`) se relance une fois en administrateur ; tout le reste hérite des droits, donc **une seule invite UAC**. Le setup vérifie que le compte élevé est celui de la session ouverte, sinon les réglages du compte iraient dans le profil d'un autre ; il s'arrête dans ce cas.

## Organisation du dépôt

```
OS-Setup/
├─ bootstrap.ps1          Point d'entrée sur machine vierge (PowerShell 5.1) : prérequis, clone, lancement
├─ setup.ps1              Point d'entrée principal (menus, -AnswerFile, -Profiles)
├─ src/
│  ├─ OSSetup/            Module du moteur : chargement, résolution, plan, exécution, journal, menus
│  ├─ providers/          Un fichier par type d'action : { Name; Test; Invoke; Describe; Read }
│  └─ cleanup.ps1         Nettoyage de fin, exécuté détaché après la fermeture du setup
├─ catalog/               Éléments installables ou configurables, un fichier JSON par élément
├─ profiles/              Profils : éléments et groupes de choix ; un profil peut en étendre un autre
├─ dotfiles/              Fichiers de configuration déployés (Git, terminal, éditeurs, agents…)
├─ schemas/               Schémas JSON du catalogue, des profils et des fichiers de réponses
├─ answers/               Exemples de fichiers de réponses
├─ tests/                 Tests Pester, et outillage de VM de test (tests/vm/)
└─ docs/                  Documentation (en/, fr/)
```

Catégories du catalogue : `browsers/`, `browser-settings/`, `apps/`, `dev/`, `system/`, `privacy/`, `power/`, `remove/`, `desktop/`, `drivers/`.

## Concepts

| Concept | Rôle |
|---|---|
| **Élément** (`catalog/`) | Unité atomique : un logiciel ou un réglage. Déclare : identifiant, nom, catégorie, actions, dépendances, besoin des droits administrateur, conditions. |
| **Action** | Étape élémentaire d'un élément (installer un paquet, écrire une valeur de registre, déployer un fichier…), exécutée par un provider. |
| **Provider** | Sait tester (`Test`) puis appliquer (`Invoke`) un type d'action ; `Read` (facultatif) lit l'état d'origine avant modification. Voir [Comment le setup modifie Windows](how-it-works.md). Paquets Windows : **winget uniquement**. |
| **Groupe de choix** | Liste d'éléments parmi lesquels choisir, en mode `single` ou `multi`, avec valeurs par défaut, minimum et maximum. |
| **Profil** (`profiles/`) | Éléments obligatoires et groupes de choix. Peut étendre un autre profil (`dev` étend `base`) ; plusieurs profils se combinent. Tout ce qui s'installe ou se supprime est proposé dans un groupe de choix, jamais imposé (vérifié au chargement) : `items` ne contient que des réglages. |
| **Dépendance** (`dependsOn`) | Une dépendance technique, proposée dans aucun menu, est ajoutée automatiquement. Une dépendance proposée dans un menu mais non cochée n'est jamais ajoutée en silence : l'élément qui en dépend est ignoré. |
| **Déclarations agrégées** | Un élément peut déclarer ce qu'un élément « agrégateur » applique pour tous : `taskbarPin` (épingle) et `startLayout` (menu Démarrer), appliqués en bloc par `desktop-layout`, traité en dernier (`runLast`). `unlessSelected` rend une action sans objet quand un autre élément retenu prend le relais. |
| **Fichier de réponses** | Profils, choix et variables d'une session, rejouables sans interaction. |
| **Variables** | Valeurs `{{Nom}}` résolues à l'exécution : intégrées (`UserProfile`, `Documents`…) ou déclarées par un profil avec une valeur par défaut, surchargeables par le fichier de réponses (ex. `{{DevRoot}}`). |

### Données : JSON et schémas

Catalogue, profils et fichiers de réponses sont en JSON, chacun validé par un schéma de `schemas/` (clé `$schema`, pour l'autocomplétion dans l'éditeur). Le JSON n'ayant pas de commentaires, les champs `description` et `notes` portent les explications. **Une donnée invalide fait échouer le setup avant toute action sur le système.**

### Conditions

Un élément peut être conditionné par le contexte de la machine (champ `when`), évalué sur des **faits** détectés automatiquement, jamais demandés : plateforme, version et édition de l'OS, activation, droits, fabricant, processeur, carte graphique, virtualisation… La liste fait foi dans `src/OSSetup/Functions/Facts.ps1` et `schemas/item.schema.json` (un test vérifie qu'elles sont identiques).

```json
"when": { "GpuVendor": "nvidia", "OSName": ["windows-10", "windows-11"] }
```

Toutes les clés doivent correspondre ; une liste signifie « une de ces valeurs ».

À distinguer :

- **Préférences** : ce qui ne peut pas être déduit (ex. `DevRoot`). Elles ont une valeur par défaut ; l'assistant ne les demande que si l'utilisateur choisit de personnaliser les emplacements.
- **Informations personnelles** (variables `personal`, ex. nom et adresse pour Git) : jamais de valeur dans le dépôt, demandées par l'assistant ; non renseignées, les actions qui les utilisent sont ignorées.

### Configuration des applications

En plus de l'installation, un élément peut déployer des fichiers de configuration depuis `dotfiles/` : copie, gabarit `{{Variable}}` ou fusion JSON, avec sauvegarde préalable (voir [ADR 0003](adr/0003-in-house-dotfiles.md)). Une configuration ou une donnée existante n'est **jamais écrasée sans sauvegarde**. Les données personnelles (mémoires, historiques) ne sont jamais versionnées.

## Interface

- **Assistant console par étapes** : profils, un groupe de choix par étape, emplacements, informations personnelles. Navigation au clavier, retour arrière avec `Échap`. Un menu validé est remplacé par une seule ligne de résumé : la console et le journal restent lisibles. Variante texte (saisie de numéros) quand la console est redirigée. La logique des menus est testée séparément de l'affichage.
- **Libellés « Sujet : état »** (ex. « Localisation : désactivée ») : l'état est affiché en couleur.
- **Avertissements** : un élément dont l'absence a une conséquence déclare `uncheckedWarning` ; un élément dont le choix en a une (ex. suppression qui efface des données) déclare `checkedWarning`. Le texte s'affiche sous le résumé du menu, et dans le journal en exécution sans surveillance.
- **Écran de validation** après le plan : appliquer, modifier une étape ou annuler.

## Déroulement

1. `bootstrap.ps1` : vérifie l'OS, règle la stratégie d'exécution (portée `Process`), installe winget si besoin, Git et PowerShell 7, clone le dépôt, lance `setup.ps1`.
2. `setup.ps1` : charge et **valide** le catalogue et les profils, demande ou lit les choix.
3. Résolution : fusion des profils, application des choix, conditions, tri par dépendances.
4. Plan → validation → exécution → récapitulatif et journal.

### Redémarrages

Le setup est **reprenable**. Un redémarrage est signalé par le provider (code 3010, fonctionnalité Windows, code winget `0x8A150109`) ou déclaré par l'élément (`requiresReboot`) : l'élément termine ses actions, ses dépendants sont reportés. En fin de passe, l'état est enregistré dans `state/run.json`, une tâche planifiée « OS-Setup - reprise » est créée (ouverture de session, droits les plus élevés : pas de nouvelle invite UAC), puis la machine redémarre (immédiatement avec `-Yes`, sinon après un compte à rebours de 10 s qu'une touche reporte). À la reprise : mêmes réponses, même journal, au plus 5 passes.

Un réglage qui ne prend effet qu'à la prochaine ouverture de session déclare `requiresLogoff` : la session est fermée en fin de setup (voir [Effet différé](how-it-works.md#effet-différé)).

### Étapes manuelles

Certaines étapes ne sont pas automatisables : choix du navigateur par défaut, connexion de GitHub CLI, compte Linux de WSL. Le provider `manual` affiche des instructions, lance l'aide utile et vérifie le résultat ; « Passer » ou une exécution sans surveillance les laisse à faire plus tard. Voir [Étapes manuelles guidées](how-it-works.md#étapes-manuelles-guidées).

### Nettoyage de fin

Le setup ne laisse que ce qui a été choisi. Le bootstrap consigne ce qu'il a installé dans `state/bootstrap.json`. En fin d'exécution (jamais en simulation ni en attente de redémarrage) :

- Git et PowerShell 7 installés par le bootstrap sont désinstallés si aucun élément choisi ne les installe ;
- si la copie du dépôt a été créée par le bootstrap, un menu propose : tout supprimer, garder l'historique (journal, réponses, sauvegardes dans `%LOCALAPPDATA%\OS-Setup\<date>`), ou tout garder. Avec `-Yes` : l'historique. Un clone de développement n'est jamais supprimé.

Le travail est fait par `src/cleanup.ps1`, copié dans `%TEMP%` et lancé détaché sous Windows PowerShell 5.1 : il attend la fermeture du setup, désinstalle, supprime, puis s'efface. Il faut quelques minutes : ne pas redémarrer juste après la fin du setup.

## Particularités de Windows

- **Windows non activé** : la plupart des machines cibles n'ont pas de licence, et les pages de personnalisation des Paramètres sont alors verrouillées. Tout réglage de personnalisation est appliqué par registre ou par commande, et testé sur une machine non activée.
- **Pilotes** : installés selon le matériel détecté. Voir [Pilotes](windows/drivers.md).
- **Pas de point de restauration Windows** : le setup lui-même sert à reconstruire un système.

## Machine déjà utilisée

Le moteur sait **auditer** l'existant et produire un **plan** (`[ok]` / `[à faire]`). Un agent pourra, en option, proposer des résolutions pour les cas ambigus, toujours validées par l'utilisateur et exécutées par le moteur ; le setup reste entièrement utilisable sans agent. Voir [ADR 0002](adr/0002-agent-assistance.md).

## Décisions d'architecture

| ADR | Sujet |
|---|---|
| [0001](adr/0001-engine-language.md) | Langage du moteur : PowerShell 7 |
| [0002](adr/0002-agent-assistance.md) | Assistance d'un agent sur une machine déjà utilisée |
| [0003](adr/0003-in-house-dotfiles.md) | Déploiement des fichiers de configuration par le moteur |
