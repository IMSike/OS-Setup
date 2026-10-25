# OS-Setup

[English](README.md) · **Français**

Configurer un poste Windows à partir d'une installation fraîche, de façon reproductible : choisir profils et options dans un assistant en console, relire le plan, l'appliquer avec une seule invite UAC. Logiciels, réglages et fichiers de configuration sont décrits en JSON ; le moteur PowerShell vérifie chacun avant d'agir.

> **Statut : début du projet.** Pris en charge : Windows 10 22H2. Prévus : Windows 11, puis Fedora.

## Fonctionnalités

- **Profils cumulables** : `base` (navigateurs, confidentialité, alimentation, bureau, suppression des applications préinstallées, pilotes) et `dev` (Git, terminal, éditeurs, Node.js, agents de code, WSL, Docker).
- **Choix dans chaque profil** : menus à choix unique ou multiple, valeurs par défaut, avertissements pour les choix qui ont des conséquences.
- **Relançable sans risque** : chaque action vérifie l'état avant d'agir ; rien de ce qui est en place n'est refait.
- **Simulation** (`-WhatIf`), **exécution sans surveillance** à partir d'un fichier de réponses, **reprise automatique** après redémarrage.
- **Traçable** : journal horodaté, récapitulatif final, valeur d'origine de chaque réglage modifié conservée pour un retour arrière manuel.
- **Ne laisse rien derrière lui** : les outils installés pour le seul besoin du setup (Git, PowerShell 7) sont retirés à la fin, sauf s'ils ont été choisis.
- **Documenté** : chaque réglage est expliqué (effet, implications, retour arrière).

## Démarrage rapide

Sur un Windows fraîchement installé, dans **Windows PowerShell** :

```powershell
cd $env:TEMP
irm https://raw.githubusercontent.com/IMSike/OS-Setup/main/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

Le bootstrap installe winget, Git et PowerShell 7, clone ce dépôt dans `%USERPROFILE%\OS-Setup` et lance l'assistant. Rien d'autre n'est modifié avant la validation du plan.

Depuis une copie du dépôt, avec PowerShell 7 :

```powershell
./setup.ps1 -WhatIf                                   # simulation
./setup.ps1 -AnswerFile answers/dev.example.json      # rejoue un fichier de réponses
./setup.ps1 -Profiles base -AcceptDefaults -Yes       # sans aucune question
```

Voir [Utilisation](docs/fr/usage.md) pour tous les paramètres, les fichiers de réponses, les journaux et les redémarrages.

## Documentation

| | |
|---|---|
| [Utilisation](docs/fr/usage.md) | Lancement, paramètres, fichiers de réponses, retour arrière |
| [Comment le setup modifie Windows](docs/fr/how-it-works.md) | Providers, registre, préférences et stratégies, valeurs d'origine |
| [Réglages Windows](docs/fr/windows/settings.md) | Chaque réglage : effet, implications, retour arrière |
| [Applications supprimables](docs/fr/windows/removable-apps.md) · [Bureau](docs/fr/windows/desktop.md) · [Navigateurs](docs/fr/windows/browsers.md) · [Logiciels](docs/fr/windows/apps.md) · [Développement](docs/fr/windows/development.md) · [Pilotes](docs/fr/windows/drivers.md) | Ce que chaque profil installe et configure |
| [Architecture](docs/fr/architecture.md) | Principes, concepts, déroulement |

Index complet : [docs/fr](docs/fr/README.md).

## Contribuer

Voir [CONTRIBUTING.fr.md](CONTRIBUTING.fr.md) : conventions, messages de commit, tests, et [ajouter un élément](docs/fr/adding-items.md).

## Licence

[MIT](LICENSE)
