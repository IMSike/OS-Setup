# ADR 0004 — Applications du Store mises à jour sans fermeture forcée (PowerShell 7, Windows Terminal)

- **Statut** : accepté
- **Date** : 2026-11-01

## Contexte

Le profil de développement fait tourner des sessions longues dans PowerShell 7 (volets herdr, agents de code). Le 26/10/2026, Windows les a fermées de force pour mettre à jour PowerShell depuis le Microsoft Store.

Observé dans la VM de test (Windows 10 22H2 et Windows 11) :

- Windows ferme de force une application du Store ouverte quand sa mise à jour a été reportée sur **au moins 3 dates UTC distinctes** et que la session est **verrouillée**. Windows Terminal y est exposé de la même façon.
- La version MSI de PowerShell n'est pas concernée : Microsoft Update remplace ses fichiers sans fermer les sessions. Mais PowerShell abandonne le MSI à partir de la 7.7 ; la 7.6 LTS est la dernière branche à en avoir un.
- Le correctif amont (`UpdateWhileInUse=defer` dans le paquet du Store) est ignoré par Windows tant que le paquet garde un ancien `MaxVersionTested`. Il est en outre sans effet sous Windows 10.
- Le réglage `DoNotUpdate` du fournisseur MDM (`EnterpriseModernAppManagement`, accessible par son pont WMI `MDM_EnterpriseModernAppManagement_AppManagement01_02`) empêche le Store de mettre à jour une application de lui-même. Avec lui, aucune fermeture forcée sur 3 dates UTC et une session verrouillée.
- Une mise à jour demandée par l'API du Store avec `AllowForcedAppRestart = false` s'installe en quelques secondes quand l'application est fermée. Avec `AutomaticallyDownloadAndInstallUpdateIfFound = false`, le Store indique seulement qu'une mise à jour existe, sans la télécharger. Il ne répond que blocage levé, et la demande ne provoque ni report ni fermeture.

## Options étudiées

1. **MSI + Microsoft Update.**
   - Aucun code à écrire.
   - Délai inconnu après une sortie (jusqu'à deux semaines selon la documentation) ; jamais installé de lui-même sous Windows 11 pendant les essais.
   - S'arrête avec la 7.6 (support jusqu'en novembre 2028).
2. **MSI + tâche SYSTEM qui installe la mise à jour de PowerShell depuis Windows Update.** Délai d'installation maîtrisé, mais s'arrête aussi avec la 7.6, et dépend de la publication par Microsoft Update.
3. **Attendre le correctif amont.** Trois conditions hors de notre contrôle : relèvement de `MaxVersionTested`, publication, rétroportage en 7.6. Sans effet sous Windows 10.
4. **Version du Store, mises à jour automatiques bloquées et faites par des tâches planifiées quand l'application est fermée** (retenue).

## Décision

PowerShell 7 est installé depuis le Store (`winget --source msstore`, produit `9MZ1SNWT0N5D`), sous Windows 10 et Windows 11, par le bootstrap et par l'élément `pwsh`. Windows Terminal est aussi installé depuis le Store (produit `9N0DX20HK701`) par l'élément `windows-terminal` ; une copie de la source `winget` (publication GitHub) est le même paquet (même identité, signature du Store) et elle est gardée. Tous deux déclarent une action `store-update-guard` :

- `DoNotUpdate = 1` pour leur famille de paquets ;
- trois tâches planifiées, communes à toutes les applications encadrées (liste dans `apps.json`). Les scripts sont dans `%ProgramFiles%\OS-Setup\store-update` : un par tâche, plus `StoreUpdate.Common.ps1`, les fonctions que les trois chargent (journal, version installée, processus ouverts, tâche de reprise orpheline). Seuls les administrateurs peuvent les modifier, et le setup les compare au dépôt par leur empreinte, fichier commun compris puisque la tâche SYSTEM l'exécute aussi :
  - **`OS-Setup - Store (système)`** (SYSTEM, chaque jour et à l'ouverture de session ; les utilisateurs authentifiés peuvent la lancer, pas la modifier) :
    - rétablit le blocage s'il a été levé ;
    - application fermée : lève le blocage, fait installer la mise à jour sans fermeture forcée, remet le blocage ;
    - application ouverte : ne lève le blocage que le temps de demander au Store si une mise à jour existe ;
    - reprise du setup en attente (tâche `OS-Setup - reprise`, qui lance PowerShell 7 à l'ouverture de session) : vérification seule, même pour une application fermée. Une tâche de reprise qui ne reprendra plus rien est ignorée (ligne dans le journal) : son `setup.ps1`, son exécutable ou `state\run.json` n'existe plus (dépôt déplacé ou supprimé, PowerShell retiré), ou aucune passe n'a eu lieu depuis 48 heures (`run.json` est réécrit à chaque passe). Sans cela, un setup abandonné laisserait les applications encadrées sans mises à jour ;
    - à chaque passage, note dans `open.json` les processus de chaque application qu'elle voit ouverts, dans toutes les sessions (consoles administrateur et autres comptes compris, que la fenêtre de l'utilisateur ne voit pas) ;
  - **`OS-Setup - Store (recherche)`** (utilisateur, sans déclencheur) : interroge le Store pour le compte de l'utilisateur. L'API du Store n'agit que pour le compte qui l'appelle ;
  - **`OS-Setup - Store (fenêtre)`** (utilisateur, à l'ouverture de session puis toutes les 15 minutes) :
    - fait vérifier le Store au plus toutes les 4 heures ;
    - quand aucune vérification d'une application n'a abouti depuis plus de 14 jours, affiche au plus une fois par jour (même pendant un report ou une reprise du setup) : « Les mises à jour de <application> n'ont pas pu être vérifiées depuis N jours : voir le journal C:\Program Files\OS-Setup\store-update\store-update.log ». Le blocage reste en place ;
    - mise à jour en attente pour une application fermée : la fait installer sans rien demander. Une application que la fenêtre voit fermée mais que la tâche SYSTEM voit ouverte (processus toujours en cours dans `open.json`) est laissée à la vérification normale toutes les 4 heures, sans relance de la tâche SYSTEM chaque heure ;
    - mise à jour en attente pour une application ouverte : propose **Mettre à jour maintenant** ou un report (10 min, 1 h, 5 h, demain) ;
    - **Maintenant** revérifie d'abord auprès du Store et ne ferme rien si la mise à jour n'est plus proposée. Sinon, ferme l'application (et d'abord herdr, qui relancerait le shell), puis la met à jour ;
    - pendant cette revérification (jusqu'à 30 minutes si une exécution SYSTEM est déjà en cours), une petite fenêtre « Vérification auprès du Store… » reste affichée avec un bouton **Annuler**. Annuler (ou Échap) arrête l'attente, ne ferme rien et repose la question dans 10 minutes (ligne dans le journal) ;
    - la tâche SYSTEM fait foi : si, dans l'`open.json` écrit pendant cette revérification, elle voit un processus de l'application toujours en cours que la fenêtre ne voit pas, rien n'est fermé (herdr compris) et la fenêtre affiche « Une fenêtre administrateur ou la session d'un autre utilisateur utilise <application> : fermez-la, la mise à jour se fera ensuite. », puis repose la question dans 10 minutes. Un `open.json` absent ou antérieur à la revérification est ignoré (ligne dans le journal).

Fichiers à côté des scripts, en lecture seule pour les utilisateurs : `apps.json` (applications encadrées, écrit par le setup), `run.json` (demande de la tâche SYSTEM à la tâche de recherche) et `open.json` (processus vus par la tâche SYSTEM), écrits par SYSTEM. Modifiables par les utilisateurs : `check.json` (résultats des vérifications) et `store-update.log` (journal commun). Supprimer le dossier les retire tous.

Un MSI de PowerShell 7 existant est désinstallé (`win32-uninstall`), pour qu'un poste déjà utilisé finisse comme un poste neuf. Le nettoyage considère l'identifiant `Microsoft.PowerShell` noté par un ancien bootstrap et le produit du Store comme le même outil.

## Conséquences

- Aucune session n'est fermée sans l'accord de l'utilisateur. Les mises à jour suivent le Store, y compris le passage à la 7.7 (non LTS), accepté.
- Une mise à jour proposée pendant que l'application reste ouverte toute la journée attend le choix de l'utilisateur ou la prochaine ouverture de session. La fenêtre repose la question après le report choisi.
- Pendant la vérification d'une application ouverte, le blocage est levé le temps de la question au Store (quelques secondes d'habitude, 3 min au plus). Le Store peut lancer sa propre mise à jour à ce moment : la vérification la voit et l'annule tant que l'application est ouverte, et la fenêtre la propose ensuite. Seule une mise à jour lancée par le Store après la vérification et avant la remise du blocage suivrait ses règles habituelles : report, et fermeture forcée seulement après 3 dates et une session verrouillée. Pour une application fermée, le blocage reste levé pendant sa mise à jour (15 min au plus).
- Prérequis : le Microsoft Store présent et joignable. Le bootstrap n'a pas d'autre source pour PowerShell 7 : sur une édition sans Store (LTSC, IoT), un Store retiré ou bloqué, une source `msstore` désactivée ou un réseau qui filtre le Store, il s'arrête avec le code d'erreur, les causes probables et quoi faire.
- **Un seul compte par poste.** Les tâches de l'utilisateur sont enregistrées pour le compte qui lance le setup, et la garde vérifie ce compte par son SID : quand le setup est lancé depuis un autre compte, les tâches sont réenregistrées pour ce compte (le dernier compte gagne). Le blocage (`DoNotUpdate`) vaut pour tout le poste : **les autres comptes n'ont plus de mises à jour du Store pour PowerShell 7 et Windows Terminal**. Le Store ne met plus ces applications à jour de lui-même, et les tâches n'interrogent le Store et ne les mettent à jour que pour le compte auquel elles appartiennent.
- Sous le PowerShell du Store, quelques chemins du moteur ont été adaptés :
  - le chemin du paquet contient sa version : la tâche de reprise et l'élévation passent par l'alias d'exécution `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, dès qu'il existe, même quand le setup a été lancé depuis un MSI de PowerShell 7 ;
  - le module DISM passe par Windows PowerShell 5.1.
- Sur un ancien poste, le setup peut tourner sous le MSI de PowerShell 7 qu'il doit désinstaller : `msiexec` l'arrêterait net. Cette désinstallation est reportée à la fermeture du setup et faite par le nettoyage de fin ; si un redémarrage intervient avant, la passe de reprise, sous le PowerShell du Store, désinstalle le MSI directement.
- La tenue de `DoNotUpdate` sur des mois, sur un poste non géré par un MDM, n'est pas vérifiée. La tâche SYSTEM le rétablit à chaque passage.
- Si les vérifications échouent durablement (erreur de l'API du Store, tâche de recherche qui ne démarre jamais, tâches d'un autre compte), le blocage laisse les applications sans mises à jour. Plutôt que de lever le blocage, la fenêtre avertit l'utilisateur : `check.json` note pour chaque application la date de la dernière vérification aboutie (`lastSuccess` : « à jour », « proposée », ou installation terminée ; ni une erreur, ni un état `Error` ou `Canceled`, ni un délai dépassé), gardée tant que les passages suivants échouent. Au-delà de 14 jours depuis cette date, ou, sans aucune réussite, depuis la création de `check.json` (posé avec la garde), l'avertissement paraît au plus une fois par jour. Une entrée écrite par une version précédente, sans `lastSuccess`, est ignorée jusqu'à ce que la recherche suivante écrive le champ.
- Retour arrière sur un poste : arrêter et supprimer les trois tâches, remettre `DoNotUpdate` à 0, puis supprimer `%ProgramFiles%\OS-Setup\store-update` et le `%LOCALAPPDATA%\OS-Setup\store-update.json` de chaque compte (voir [`windows/development.md`](../windows/development.md#powershell-7--pwsh)).

## Retrait

La garde est un contournement : elle a vocation à être retirée d'OS-Setup quand Windows ne fermera plus ces applications de force.

**Condition**, toutes à la fois :

- Windows 10 n'est plus pris en charge par OS-Setup (le correctif amont n'y a pas d'effet) ;
- le PowerShell du Store déclare le report dans un manifeste que Windows respecte : `UpdateWhileInUse=defer` dans `(Get-AppxPackageManifest Microsoft.PowerShell).Package.Properties`, et `MaxVersionTested` au moins égal à `10.0.26100.0` dans `(Get-AppxPackageManifest Microsoft.PowerShell).Package.Dependencies.TargetDeviceFamily` ;
- l'essai en VM du contexte, refait sans la garde sous Windows 11 : blocage levé (`DoNotUpdate = 0`), application ouverte, mise à jour reportée sur au moins 3 dates UTC distinctes, session verrouillée ; rien n'est fermé, et l'événement 638 indique « Force update deferred by package: true » ;
- le même essai pour Windows Terminal, qui déclare déjà le report.

**Périmètre à retirer** :

- `src/store-update/` (les quatre scripts), `src/OSSetup/Functions/StoreUpdate.ps1`, `src/providers/store-update-guard.ps1` ;
- les exports de `StoreUpdate.ps1` dans `src/OSSetup/OSSetup.psd1` (de `ConvertTo-OSSetupStoreUpdateApp` à `Test-OSSetupStoreUpdateGuard`, `Get-OSSetupAccountSid` compris : rien d'autre ne s'en sert) ;
- la définition `storeUpdateGuardAction` de `schemas/item.schema.json` et sa référence dans la liste des actions ;
- les actions `store-update-guard` de `catalog/dev/pwsh.json` et `catalog/dev/windows-terminal.json` ;
- `tests/StoreUpdate.Tests.ps1` et les entrées `src\store-update\…` de `tests/CodeQuality.Tests.ps1` ;
- dans les deux langues : la ligne `store-update-guard` de `how-it-works.md`, les paragraphes « Mises à jour », les implications et retours arrière de la garde de `pwsh` et `windows-terminal` dans `windows/development.md`, les tâches du Store dans `testing.md` ; cet ADR passe à « remplacé », avec la date et la raison ;
- le commentaire de `Get-OSSetupStoreCancelScript` (`src/OSSetup/Functions/System.ps1`) qui renvoie à `StoreUpdate.User.ps1`.

**À garder** : PowerShell 7 et Windows Terminal installés depuis le Store (bootstrap, éléments `pwsh` et `windows-terminal`, `source: msstore`) ; `packageName` et `Test-OSSetupAppxInstalled` ; l'alias d'exécution (`Get-OSSetupPwshPath`) pour la tâche de reprise et l'élévation ; `Import-OSSetupDismModule` ; la désinstallation du MSI de PowerShell et son report à la fermeture du setup ; `Stop-OSSetupStoreUpdate` et le provider `appx` ; `Invoke-OSSetupUnelevatedCommand` ; les entrées de `pitfalls.md`.

**Commits** sur `dev`, comme point de départ. Des commits plus récents ont pu toucher les mêmes fichiers : retirer le périmètre ci-dessus en un seul commit est en général plus simple que de les annuler un à un, en s'aidant de cette liste. Les commits plus récents de la garde se retrouvent avec `git log --oneline -- src/store-update src/OSSetup/Functions/StoreUpdate.ps1 src/providers/store-update-guard.ps1 tests/StoreUpdate.Tests.ps1`.

- Garde seule, à annuler : `4a6806b`, `e07f7cd`, `61bcb2e`, `374ca07`, `922507c`, `843562c`, `9313766`, `f199320`, `2f4f388`, `3a232e0`, `8932fd7`, `7c57694`, `feff7da`, `a742345`, `ba52c18`, `0089583`, `5d23a37`, `55006a6`, `f30e20b`, `d01f38c`, `20eb245`, `729ed34`, `0b9fa03`, `41e3afe`, `ae1028a`, `b531e5a`.
- Mixtes, à défaire à la main pour la seule partie garde : `b0a27a8` (introduit la garde, mais aussi l'installation par le Store dans le bootstrap, l'alias d'exécution, `Import-OSSetupDismModule`, la `source` de winget et le nettoyage qui considère le MSI et le produit du Store comme un seul outil), `85b5236` (PowerShell 7 depuis le Store et les actions de garde des deux éléments), `afb524e` (Windows Terminal depuis le Store).
- À ne pas annuler, ils restent : `33b40f5`, `f63ddd8`, `598fafc`, `fde17a1`, `6043126`, `00cf8e7`, `c37c514`, `a75e8a2`, `107fda0`, `e1ffc5b`, `d9fd440`.

**Restes sur les postes installés** : les trois tâches, le dossier `%ProgramFiles%\OS-Setup\store-update`, `DoNotUpdate = 1` sur les deux familles de paquets, et `%LOCALAPPDATA%\OS-Setup\store-update.json` dans chaque compte qui a lancé le setup. Sans nettoyage, le Store ne mettrait plus jamais ces applications à jour. Une étape de nettoyage est livrée avant le retrait ou avec lui, et reste jusqu'à ce que tous les postes l'aient passée :

1. arrêter puis supprimer les trois tâches : la tâche SYSTEM ne doit plus tourner, sinon elle remettrait le blocage ;
2. remettre `DoNotUpdate` à 0 pour `Microsoft.PowerShell_8wekyb3d8bbwe` et `Microsoft.WindowsTerminal_8wekyb3d8bbwe` ;
3. supprimer `%ProgramFiles%\OS-Setup\store-update` seulement, jamais `%ProgramFiles%\OS-Setup`, qui contient aussi les fichiers d'autres éléments (`docker\`) ;
4. supprimer le `%LOCALAPPDATA%\OS-Setup\store-update.json` du compte qui lance le setup (les copies des autres comptes sont sans effet : plus rien ne les lit).
