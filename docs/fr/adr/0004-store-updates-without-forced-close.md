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

PowerShell 7 est installé depuis le Store (`winget --source msstore`, produit `9MZ1SNWT0N5D`), sous Windows 10 et Windows 11, par le bootstrap et par l'élément `pwsh`. Windows Terminal reste une application du Store. Tous deux déclarent une action `store-update-guard` :

- `DoNotUpdate = 1` pour leur famille de paquets ;
- trois tâches planifiées, communes à toutes les applications encadrées (liste dans `apps.json`). Les scripts sont dans `%ProgramFiles%\OS-Setup\store-update`, modifiables par les seuls administrateurs :
  - **`OS-Setup - Store (système)`** (SYSTEM, chaque jour et à l'ouverture de session ; les utilisateurs authentifiés peuvent la lancer, pas la modifier) :
    - rétablit le blocage s'il a été levé ;
    - application fermée : lève le blocage, fait installer la mise à jour sans fermeture forcée, remet le blocage ;
    - application ouverte : ne lève le blocage que le temps de demander au Store si une mise à jour existe ;
  - **`OS-Setup - Store (recherche)`** (utilisateur, sans déclencheur) : interroge le Store pour le compte de l'utilisateur. L'API du Store n'agit que pour le compte qui l'appelle ;
  - **`OS-Setup - Store (fenêtre)`** (utilisateur, à l'ouverture de session puis toutes les 15 minutes) :
    - fait vérifier le Store au plus toutes les 4 heures ;
    - mise à jour en attente pour une application fermée : la fait installer sans rien demander ;
    - mise à jour en attente pour une application ouverte : propose **Mettre à jour maintenant** ou un report (10 min, 1 h, 5 h, demain) ;
    - **Maintenant** revérifie d'abord auprès du Store et ne ferme rien si la mise à jour n'est plus proposée. Sinon, ferme l'application (et d'abord herdr, qui relancerait le shell), puis la met à jour.

Un MSI de PowerShell 7 existant est désinstallé (`win32-uninstall`), pour qu'un poste déjà utilisé finisse comme un poste neuf. Le nettoyage considère l'identifiant `Microsoft.PowerShell` noté par un ancien bootstrap et le produit du Store comme le même outil.

## Conséquences

- Aucune session n'est fermée sans l'accord de l'utilisateur. Les mises à jour suivent le Store, y compris le passage à la 7.7 (non LTS), accepté.
- Une mise à jour proposée pendant que l'application reste ouverte toute la journée attend le choix de l'utilisateur ou la prochaine ouverture de session. La fenêtre repose la question après le report choisi.
- Pendant la vérification d'une application ouverte, le blocage est levé quelques secondes. Si le Store lançait sa propre mise à jour à cet instant précis, elle suivrait ses règles habituelles : report, et fermeture forcée seulement après 3 dates et une session verrouillée.
- Les tâches de l'utilisateur sont enregistrées pour le compte qui lance le setup.
- Sous le PowerShell du Store, quelques chemins du moteur ont été adaptés :
  - le chemin du paquet contient sa version : la tâche de reprise et l'élévation passent par l'alias d'exécution `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` ;
  - le module DISM passe par Windows PowerShell 5.1.
- La tenue de `DoNotUpdate` sur des mois, sur un poste non géré par un MDM, n'est pas vérifiée. La tâche SYSTEM le rétablit à chaque passage.
- Retour arrière : supprimer les trois tâches et `%ProgramFiles%\OS-Setup\store-update`, puis remettre `DoNotUpdate` à 0 (voir [`windows/development.md`](../windows/development.md#powershell-7--pwsh)).
