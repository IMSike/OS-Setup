# ADR 0005 — Reprise après redémarrage depuis une copie réservée aux administrateurs

- **Statut** : accepté
- **Date** : 2026-11-03

## Contexte

Quand un élément demande un redémarrage, le setup crée la tâche planifiée « OS-Setup - reprise » (ouverture de session, droits les plus élevés, sans invite UAC) et reprend à l'ouverture de session suivante. Jusqu'ici, cette tâche lançait, par l'alias d'exécution du Store `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, le `setup.ps1` du dépôt, avec son état dans le `state\run.json` du dépôt. Un audit de sécurité a relevé que tout ce que cette tâche élevée exécutait ou lisait pouvait être modifié par un programme lancé sous le compte de l'utilisateur, sans élévation :

- le dépôt (code, catalogue, `state\run.json`, `state\bootstrap.json`) : un programme pouvait remplacer le code exécuté à l'ouverture de session suivante, ou les chemins que le nettoyage de fin supprime ;
- l'alias d'exécution, dans un dossier où l'utilisateur a le contrôle total ;
- les dossiers de modules de l'utilisateur (`Documents\PowerShell\Modules` vient en premier dans `PSModulePath`) : un module déposé là était chargé à la place d'un module de Windows ;
- le script du nettoyage de fin et sa configuration, écrits dans le `%TEMP%` de l'utilisateur puis exécutés avec les droits administrateur.

Chacun de ces points était un pont vers les droits administrateur sans invite UAC, du redémarrage jusqu'à la fin du setup (donc jusqu'à l'ouverture de session suivante si l'utilisateur reportait le redémarrage).

Options envisagées :

- **A. Garder la tâche et documenter le risque.** Aucun changement, mais le pont reste.
- **B. Reprendre sans élévation et redemander l'UAC.** Ferme le trou mais casse la reprise sans surveillance (`-Yes`), qui est la raison d'être de la tâche.
- **C. Reprendre depuis une copie figée sous `%ProgramFiles%`.** Les utilisateurs n'y ont que la lecture ; la tâche n'exécute que des fichiers de ce dossier, avec des exécutables trouvés par un chemin que seuls les administrateurs contrôlent.

Les essais dans la VM Windows 10 (PowerShell 7.6 du Store) ont montré que le `pwsh.exe` du Store lancé par le chemin de son paquet (`C:\Program Files\WindowsApps\Microsoft.PowerShell_<version>_x64__8wekyb3d8bbwe\pwsh.exe`, propriété de TrustedInstaller, lecture et exécution seules pour les utilisateurs) depuis une tâche d'ouverture de session aux droits les plus élevés s'exécute élevé, avec `Get-ScheduledTask` et les autres modules disponibles. Ce chemin contient la version : il ne peut pas être inscrit dans la tâche.

## Décision

Option C.

- **Copie figée.** Avant de créer la tâche, le setup élevé se copie dans `%ProgramFiles%\OS-Setup\resume` (`Copy-OSSetupResumeCode`) : code, catalogue, profils, schémas, dotfiles, sans `.git`, documentation, tests, journaux ni état, et sans les jonctions et liens de la racine du dépôt. Le lanceur `src\resume.ps1` va à la racine de la copie. La trace du bootstrap (`state\bootstrap.json`) est copiée dans `resume\state`, où se trouve aussi `run.json`. Le dossier hérite des droits de Program Files : lecture seule pour les utilisateurs.
- **Tâche.** La tâche lance le Windows PowerShell 5.1 du dossier système (`[Environment]::SystemDirectory`, pas une variable d'environnement) avec `-File "%ProgramFiles%\OS-Setup\resume\resume.ps1"`. Le lanceur retrouve le `pwsh.exe` du Store dans le dossier de son paquet par l'API WinRT des paquets (dernière version installée), à défaut celui du MSI de PowerShell 7 sous Program Files. Il n'utilise jamais l'alias et ne charge aucun module. Il lance ensuite le `setup.ps1 -Resume` de la copie.
- **Modules.** Avec `-Resume`, `setup.ps1` remplace `PSModulePath`, avant tout chargement de module, par une liste fixe de dossiers réservés aux administrateurs : `$PSHOME\Modules`, `%ProgramFiles%\PowerShell\Modules`, `%ProgramFiles%\WindowsPowerShell\Modules`, `System32\WindowsPowerShell\v1.0\Modules`.
- **Données de l'utilisateur.** Journaux, sauvegardes, réponses et dernier résultat restent dans le dépôt : `run.json` note son dossier (`dataRoot`). La reprise y écrit et n'y lit rien qui décide de ce qui s'exécute. Le nettoyage de fin prend son script et la trace du bootstrap dans la copie.
- **Nettoyage de fin.** Son script et sa configuration vont dans `%ProgramFiles%\OS-Setup\cleanup` (réservé aux administrateurs) au lieu de `%TEMP%`.
- **Versions précédentes.** Une tâche de reprise créée par une version précédente (`setup.ps1` du dépôt, `run.json` dans le dépôt) fonctionne encore une fois : l'état est déplacé dans la copie, et la tâche suivante éventuelle passe par la copie. Un état illisible, ou un dépôt disparu, abandonne la reprise : tâche et copie sont retirées, et la raison est affichée.
- **Fin.** La copie est supprimée à la fin du setup, après que le script du nettoyage y a été pris. `run.json` est écrit dans un fichier temporaire puis renommé : une interruption ne laisse jamais un état tronqué.

La règle des tâches orphelines du Store (ADR 0004 : le fichier de `-File` a `state\run.json` à côté de lui, et le programme existe) reconnaît la nouvelle tâche sans changement.

## Conséquences

- Pendant une reprise, rien de ce qui est exécuté, ni l'état qui décide de ce qui est exécuté, ne peut être modifié sans droits administrateur.
- Un dossier de plus, `%ProgramFiles%\OS-Setup\resume`, existe entre le redémarrage et la fin du setup ; `%ProgramFiles%\OS-Setup\cleanup` reste (vide) après le nettoyage.
- Une modification faite dans le dépôt après la demande de redémarrage n'est pas prise en compte par la reprise : elle exécute le code tel qu'il était au moment de la demande.
- Risque restant : la reprise élevée écrit toujours dans les dossiers de l'utilisateur (journaux et sauvegardes dans le dépôt, historique dans `%LOCALAPPDATA%\OS-Setup`). Un programme lancé sous le compte de l'utilisateur pourrait rediriger ces écritures par une jonction. Traité ensuite : pendant la reprise, chaque écriture dans le dossier des données et dans l'historique (journal, réponses, sauvegardes, résultat) contrôle d'abord tout le chemin jusqu'à la racine du disque (`Assert-OSSetupDataPath`, activé par `Enable-OSSetupDataGuard`). Un dossier qui est une jonction ou un lien symbolique, ou un fichier qui est un lien (liens physiques compris), arrête l'écriture par une erreur : la reprise est abandonnée si le dépôt lui-même est touché, sinon l'action échoue et l'exécution se termine en erreur. Les autres points d'analyse (fichiers OneDrive à la demande) sont acceptés. La copie de l'historique refuse aussi un lien parmi les sauvegardes, qui ferait copier un fichier protégé vers un dossier lisible par l'utilisateur. Le nettoyage de fin (`src/cleanup.ps1`) applique la même règle à son journal et à ses suppressions. Limites : reste l'intervalle entre le contrôle et l'écriture ; un dépôt placé volontairement derrière une jonction ne peut pas être repris ; les fichiers que les éléments eux-mêmes écrivent dans le profil (dotfiles, disposition du menu Démarrer) ne sont pas couverts, puisque c'est leur rôle d'y écrire.
- Hors reprise, une exécution élevée lancée par l'utilisateur (invite UAC) exécute toujours le code du dépôt et les modules de l'utilisateur. C'est attendu : l'utilisateur a choisi d'exécuter ce code avec les droits administrateur.
