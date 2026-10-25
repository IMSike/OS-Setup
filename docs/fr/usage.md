# Utilisation

## Sur une machine vierge

Dans **Windows PowerShell** (le setup demande une seule fois les droits administrateur) :

```powershell
cd $env:TEMP
irm https://raw.githubusercontent.com/IMSike/OS-Setup/main/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

Le setup se déroule en deux étapes :

1. **Préparation** : le bootstrap se relance en administrateur, installe winget si besoin, Git et PowerShell 7, puis clone le dépôt dans `%USERPROFILE%\OS-Setup`. Rien d'autre n'est installé à ce stade.
2. **Vos choix** : assistant par étapes (profils, logiciels, emplacements, informations personnelles), puis le plan, à appliquer, modifier ou annuler avant toute modification.

Le compte utilisé doit être administrateur : depuis un compte standard, le setup s'arrête (les réglages iraient dans le profil d'un autre compte).

### Dans les menus

| Touche | Effet |
|---|---|
| `↑` `↓` | Se déplacer |
| `Espace` ou `Entrée` | Cocher ou décocher |
| Ligne **[ Valider ]** | Passer à l'étape suivante |
| `Échap` ou ligne **← Retour** | Revenir à l'étape précédente |

## Depuis une copie du dépôt (PowerShell 7)

```powershell
./setup.ps1                                          # assistant interactif
./setup.ps1 -WhatIf                                  # simulation : plan et actions simulées, rien n'est modifié
./setup.ps1 -AnswerFile answers/dev.example.json     # rejoue un fichier de réponses, sans question
./setup.ps1 -Profiles base -AcceptDefaults -Yes      # profil base, valeurs par défaut, sans aucune question
```

| Paramètre | Effet |
|---|---|
| `-AnswerFile <fichier>` | Rejoue un fichier de réponses : aucune question. |
| `-Profiles <noms>` | Profils à appliquer (saute le menu des profils). |
| `-AcceptDefaults` | Valeurs par défaut des choix et des variables, au lieu des menus. |
| `-SaveAnswers <fichier>` | Enregistre les réponses de la session dans ce fichier. |
| `-Yes` | Sans surveillance : applique le plan sans confirmation, redémarre ou ferme la session sans compte à rebours, ferme la fenêtre à la fin. |
| `-NoPause` | Ne pas attendre `Entrée` avant de fermer la fenêtre. |
| `-WhatIf` | Simulation : aucune modification, pas d'élévation. |

## Fichiers de réponses

Un fichier de réponses contient les profils, les choix de chaque groupe et les variables. Il est validé par `schemas/answers.schema.json`.

```json
{
  "$schema": "../schemas/answers.schema.json",
  "profiles": ["dev"],
  "choices": {
    "browsers": ["firefox", "vivaldi"],
    "editor": ["vscode"]
  },
  "variables": {
    "DevRoot": "{{UserProfile}}\\Dev"
  }
}
```

Un groupe absent du fichier prend ses valeurs par défaut. Exemples : [`answers/dev.example.json`](../../answers/dev.example.json), [`answers/base-all.example.json`](../../answers/base-all.example.json) (tous les réglages du profil `base`).

Les réponses de chaque session sont enregistrées dans `state/answers-last.json` : pour rejouer la même installation sur une autre machine, copiez ce fichier **hors du dépôt public** (il peut contenir vos informations personnelles).

## Ce que le setup laisse sur la machine

| Emplacement | Contenu |
|---|---|
| `logs/` | Journal horodaté de chaque exécution |
| `state/answers-last.json` | Réponses de la dernière session |
| `state/backups/<date>/` | Sauvegardes des fichiers remplacés et `original-values.json` (valeurs d'origine de chaque réglage modifié, pour revenir en arrière à la main) |
| `state/run.json` | État d'une exécution en attente de redémarrage |
| `state/last-result.json` | Récapitulatif de la dernière exécution |

Ces dossiers sont dans la copie du dépôt et ignorés par Git. En fin de setup, si la copie a été créée par le bootstrap, un menu propose de la supprimer en gardant l'historique (journal, réponses, sauvegardes) dans `%LOCALAPPDATA%\OS-Setup\<date>` : voir [Nettoyage de fin](architecture.md#nettoyage-de-fin).

## Redémarrages et fermeture de session

Si un élément demande un redémarrage, le setup enregistre son état, crée une tâche planifiée de reprise et redémarre la machine (compte à rebours de 10 s qu'une touche reporte). Il reprend seul à l'ouverture de session suivante, sans nouvelle invite UAC.

Certains réglages ne prennent effet qu'à la prochaine ouverture de session : la session est alors fermée en fin de setup, de la même façon.

Après la fin du setup, le nettoyage continue quelques minutes en arrière-plan : ne pas redémarrer la machine tout de suite.

## Machine déjà utilisée

Le setup peut être lancé sur une machine en service : chaque action vérifie l'état avant d'agir, et le plan distingue ce qui est déjà en place (`[ok]`) de ce qui reste à faire. Commencez par une simulation (`-WhatIf`). Les fichiers de configuration existants sont sauvegardés avant d'être remplacés.

## Revenir en arrière

Il n'y a pas de retour arrière automatique. Chaque réglage est documenté avec sa manipulation inverse ([Réglages Windows](windows/settings.md)), et les valeurs d'origine sont dans `state/backups/<date>/original-values.json`. Voir [Comment le setup modifie Windows](how-it-works.md#retour-arrière-et-valeurs-dorigine).
