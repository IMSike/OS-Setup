# ADR 0004 — PowerShell 7 installé depuis le Microsoft Store, repli sur le MSI

- **Statut** : accepté
- **Date** : 2026-11-21

## Contexte

Le setup s'exécute sous PowerShell 7 ([ADR 0001](0001-engine-language.md)), que le bootstrap installe avant de le lancer, et que le profil de développement garde comme shell de travail (élément `pwsh`). Jusqu'ici, c'était le MSI (`winget install Microsoft.PowerShell --installer-type wix`), installé pour toute la machine.

- PowerShell abandonne le MSI à partir de la 7.7 : la 7.6 (LTS) est la dernière branche publiée sous cette forme. Les versions suivantes ne sont distribuées que comme paquet MSIX.
- Le MSIX de la source `winget` (publication GitHub) n'est pas sous licence du Store et ne s'installe pas pour toute la machine sous Windows 10. Celui de la source `msstore` (produit `9MZ1SNWT0N5D`) est le paquet du Microsoft Store : il s'installe pour le compte courant et le Store le met à jour.
- Un paquet du Store ne se comporte pas comme un MSI :
  - il est installé **par compte**, sous `%ProgramFiles%\WindowsApps\Microsoft.PowerShell_<version>_…` (chemin qui change à chaque mise à jour), et se lance par un alias d'exécution du compte (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`) ;
  - `winget list --id 9MZ1SNWT0N5D` répond « installé » quand seul le MSI est présent : winget rattache le MSI au produit du Store ;
  - sous ce PowerShell, le module `Dism` ne se charge pas directement (constaté en VM : échec des providers `appx` et `windows-capability`) ;
  - le Store peut fermer une application ouverte pour la mettre à jour (constaté : mise à jour reportée sur au moins 3 dates UTC et session verrouillée).
- Le Store n'existe pas partout : éditions LTSC et IoT, Store retiré ou bloqué par une stratégie, source `msstore` désactivée, réseau filtré.

Options envisagées :

1. **Rester sur le MSI.** Rien à changer, mais bloqué à la 7.6 (support jusqu'en novembre 2028).
2. **Paquet du Store, obligatoire.** Une seule variante à maintenir, mais le bootstrap s'arrête sur un poste sans Store alors qu'un MSI utilisable existe encore.
3. **Paquet du Store, repli sur le MSI quand le Store est indisponible** (retenue).

## Décision

Option 3.

- **Variante visée.** PowerShell 7 vient du Microsoft Store (`winget install --id 9MZ1SNWT0N5D --source msstore`, sans `--scope`), pour le compte courant, par le bootstrap et par l'élément `pwsh`. La présence est jugée sur le paquet appx `Microsoft.PowerShell` du compte, pas sur `winget list`.
- **Bootstrap.** Il installe le paquet du Store et lance `setup.ps1` par l'alias d'exécution du compte, même si un MSI passe avant dans le `PATH`. Si l'installation depuis le Store échoue (ou si l'alias n'apparaît pas), il affiche un avertissement avec le code de winget et les causes probables, puis installe le MSI de PowerShell 7 (ou garde celui qui est déjà là) et lance le setup avec lui. Il ne s'arrête que si les deux échouent.
- **Élément `pwsh`.** Deux actions :
  - installer le paquet du Store. Si winget échoue alors que le MSI (« PowerShell 7-x64 ») est installé, l'action n'est pas en échec : elle est « ignorée », avec le code de winget et la mention de la variante de repli dans le récapitulatif. Elle ne bloque ni les éléments qui dépendent de `pwsh` ni le code de sortie, et elle est retentée à chaque exécution (`fallbackDisplayName`) ;
  - désinstaller le MSI, pour qu'un poste déjà utilisé finisse comme un poste neuf. Elle ne s'applique qu'une fois le paquet du Store installé pour le compte (`replacedByPackage`) : un poste sans Store garde son MSI. Si le setup tourne sous ce MSI, la désinstallation est faite par le nettoyage de fin, après la fermeture du setup.
- **Moteur.**
  - Le provider `winget` accepte la source `msstore` et un nom de paquet appx.
  - Le module `Dism` est chargé par Windows PowerShell 5.1 quand le setup tourne sous le PowerShell du Store.
  - La relance élevée utilise l'alias du Store quand il existe, sinon le PowerShell en cours.
  - La reprise après redémarrage ([ADR 0005](0005-resume-from-administrators-only-copy.md)) retrouve le `pwsh.exe` du paquet du Store par l'API des paquets de Windows (dossier que seuls les administrateurs modifient), jamais par l'alias du compte ; à défaut, elle utilise le MSI.
  - Le nettoyage de fin considère `Microsoft.PowerShell` (MSI noté par le bootstrap) et `9MZ1SNWT0N5D` comme le même outil.
- **Windows Terminal** reste installé depuis la source `winget`.
- **Mises à jour.** Le Store met PowerShell à jour seul ; le setup n'encadre pas ces mises à jour.

## Conséquences

- PowerShell 7 suit le Store, y compris au-delà de la 7.6 (versions non LTS comprises).
- L'installation est **par compte** : un autre compte du poste doit lancer le bootstrap pour avoir PowerShell 7. Le MSI installé par un autre moyen pour un autre compte n'est pas concerné, sauf s'il est retiré par l'élément `pwsh` (il est installé pour toute la machine).
- Le Store peut fermer les sessions PowerShell ouvertes pour appliquer une mise à jour reportée. Accepté : le profil de développement restaure les sessions de travail (herdr) après une fermeture.
- **Limite du repli.** Le repli dépend de l'existence d'un MSI dans winget : il s'arrête à la 7.6. Quand le setup exigera une version plus récente, un poste sans Store ne pourra plus l'exécuter, et le repli devra être retiré ou remplacé.
- Un poste resté sur le MSI n'est pas dans la variante visée : le plan et le récapitulatif le signalent à chaque exécution tant que le Store est indisponible. Une fois le Store rétabli, une exécution du setup installe le paquet du Store et retire le MSI.
- Une tâche planifiée du compte SYSTEM ne peut pas utiliser ce PowerShell (paquet par compte) : la reprise reste une tâche de l'utilisateur, lancée par Windows PowerShell 5.1.
- Deux variantes sont à tester (Store, repli) tant que le repli existe.
