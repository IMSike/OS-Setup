# Pièges connus

Comportements constatés pendant le développement, et leur traitement dans le moteur. À lire avant de modifier un provider ou d'ajouter un élément.

## winget (Windows 10, winget 1.29)

| Symptôme | Cause et traitement |
|---|---|
| `0x8A150019` « nécessite des privilèges d'administrateur » | Le paquet exige un winget **déjà élevé** (l'installeur ne s'élève pas seul). Le provider relance winget en mode élevé (`Start-Process -Verb RunAs`). |
| `0x8A150113` sur une installation `--scope machine` | Paquet **MSIX** : installation pour toute la machine non prise en charge sous Windows 10. Forcer un autre installeur (`installerType`, ex. `msi` ou `wix` quand le paquet en propose un) ou passer en `scope: user`. |
| `0x8A15002B` | Déjà installé, aucune mise à jour applicable : traité comme un succès. |
| Paquet non détecté juste après une installation réussie | Installeur qui termine en arrière-plan (Squirrel : Discord). Le provider attend jusqu'à 60 s que `winget list` le trouve. |
| Outil introuvable juste après son installation | Le PATH de la session est figé : le moteur le recharge depuis le registre après chaque installation (`Update-SessionPath` dans le bootstrap). |
| Programme installé qui ne démarre pas, code `-1073741515` (`0xC0000135`) sans message | DLL absente, le plus souvent le runtime Visual C++ (absent d'un Windows neuf, rarement déclaré par les paquets portables, ex. rtk) : dépendance `vcredist`. |
| Paquet absent de winget (ex. NVIDIA App) | Nécessiterait un autre provider (téléchargement direct), à valider avant d'en ajouter un. |
| Accents corrompus dans la sortie capturée (`Trouv├®`) | winget et les autres outils en ligne de commande lancés par les providers (gh, npm, herdr, code, fnm, rtk, claude, playwright-cli) écrivent en UTF-8 : régler `[Console]::OutputEncoding` sur UTF-8 le temps de l'appel (`Invoke-OSSetupNativeCommand -Utf8`). |
| Paquet trouvé dans la source `msstore` au lieu de `winget` | Préciser `--source winget`, sauf si l'élément vise volontairement une application du Store sous licence (`source: msstore`). |
| Paquet installé que `winget list --id` ne trouve pas (`0x8A150014`), alors que `winget list --name` l'affiche avec son identifiant (constaté : PowerShell 7 mis à jour par Microsoft Update) | Le plan prévoyait de le réinstaller. `winget export` fait bien le rattachement : second avis dans `Test-OSSetupWingetInstalled`. |
| `winget list --id 9MZ1SNWT0N5D` (PowerShell du Store) répond « installé » sur un poste qui n'a que le MSI « PowerShell 7-x64 », même avec `--source msstore` | winget rattache le MSI au produit du Store. L'installation du Store était jugée faite, puis le MSI était désinstallé : plus aucun PowerShell 7. Une action `msstore` donne `packageName` (nom du paquet appx) : la présence est jugée sur ce paquet pour le compte courant (`Test-OSSetupAppxInstalled`), pas par `winget list`. |

Sous Windows PowerShell 5.1, ne pas capturer ni rediriger la sortie de winget (`| Out-Host`, affectation) : elle serait décodée avec la page de code OEM. La laisser écrire directement dans la console, ou régler `[Console]::OutputEncoding` sur UTF-8.

## Windows

- `New-Item -Force` sur une clé de registre **existante** la recrée vide : toutes ses valeurs sont perdues. Créer une clé seulement si elle n'existe pas (`if (-not (Test-Path …)) { New-Item … }`).
- Supprimer une application du Store pour tous les comptes (`Remove-AppxPackage -AllUsers`) échoue (`0x80073CFA`) tant qu'elle est provisionnée : la déprovisionner d'abord (`Remove-AppxProvisionedPackage`).
- Une application du Store supprimée qui revient après un redémarrage, de nouveau provisionnée : une mise à jour du Store était en file ou en cours pendant la suppression et s'est achevée ensuite. Le provider `appx` annule d'abord les mises à jour du Store en attente de l'application (`Stop-OSSetupStoreUpdate`, WinRT `AppInstallManager`, via Windows PowerShell 5.1 car PowerShell 7 ne charge pas les types WinRT). Si cette annulation échoue, la suppression a quand même lieu et un avertissement du journal signale que l'application peut revenir après un redémarrage.
- Sous PowerShell 7 et Windows 10, le module Appx ne se charge pas (« Operation is not supported on this platform ») : `Import-Module Appx -UseWindowsPowerShell` le fait passer par Windows PowerShell 5.1 (`Import-OSSetupAppxModule`, objets désérialisés). Le module Dism prend le même chemin dans le PowerShell 7 du Store (`Import-OSSetupDismModule`). Sous `-WhatIf`, ce chargement échoue (la copie des fichiers du module de compatibilité est simulée) : `Import-OSSetupCompatibilityModule`, commun aux deux, force `$global:WhatIfPreference = $false` le temps de l'import, puis le rétablit.
- Sur une machine vierge, `Install-PSResource` échoue tant que la configuration de PSResourceGet n'existe pas ; un premier `Get-PSResourceRepository` l'initialise.
- Les sorties d'outils système (`powercfg`, `dism`…) dépendent de la langue : ne lire que des valeurs stables (nombres hexadécimaux, `dism /English`).

## PowerShell

- Windows PowerShell 5.1 lit un `.ps1` **sans BOM** comme ANSI : les caractères accentués sont corrompus. Les fichiers `.ps1`, `.psm1` et `.psd1` sont en UTF-8 avec BOM (figé dans `.gitattributes` et `.editorconfig`).
- Les noms de variables ne tiennent pas compte de la casse : une variable locale `$answers` écrase le paramètre `$Answers`.
- Les apostrophes typographiques `‘ ’` valent `'` et les guillemets `“ ”` valent `"` : un texte contenant `’` (ex. sortie de `powercfg` en français) va entre guillemets droits `"…"`.
- `$x = if (...) { @() }` donne `$null`, et un tableau d'un seul élément devient l'élément : écrire `$x = @(if (...) { ... })`.
- Un script avancé (`[CmdletBinding()]`) qui relaie ses arguments restants (`ValueFromRemainingArguments`) doit déclarer `[CmdletBinding(PositionalBinding = $false)]` : sinon un argument comme `-WhatIf` destiné à `setup.ps1` est capté en position par un autre paramètre.
- Sous le PowerShell 7 du Store (processus empaqueté) :
  - le chemin de l'exécutable contient la version du paquet et change à chaque mise à jour : la relance élevée passe par l'alias d'exécution `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` (`Get-OSSetupPwshPath`, dès que l'alias existe, quel que soit le PowerShell en cours). Le dossier de l'alias est modifiable par l'utilisateur : la tâche de reprise élevée ne l'utilise pas, son lanceur retrouve le dossier du paquet par l'API WinRT des paquets à chaque reprise ([ADR 0005](adr/0005-resume-from-administrators-only-copy.md)) ;
  - le module DISM ne peut pas ouvrir sa session (« Classe non enregistrée », après deux minutes) : `Import-OSSetupDismModule` le fait passer par Windows PowerShell 5.1 ;
  - Windows PowerShell 5.1 lancé par un programme intermédiaire (`cmd`, herdr) hérite du `PSModulePath` de PowerShell 7 et perd des commandes intégrées comme `Get-FileHash`. Lancé directement par `pwsh`, non.
- Sur un ancien poste, le setup peut tourner sous le MSI de PowerShell 7 que l'élément `pwsh` désinstalle : `msiexec /x` sur ce MSI arrêtait le setup net (pas de récapitulatif, pas de tâche de reprise, pas de `state/last-result.json`). `win32-uninstall` confie donc au nettoyage de fin une entrée dont le dossier d'installation contient `$PSHOME`. Le MSI de PowerShell laisse `InstallLocation` vide dans « Programmes et fonctionnalités » : son dossier est lu dans `HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions`, par code produit. La relance élevée (alias du Store) et la tâche de reprise (dossier du paquet du Store) passent par le PowerShell du Store dès qu'il existe, jamais par le MSI.
- Le PowerShell du Store installé depuis la source `winget` (MSIX de GitHub) n'a pas de licence du Store et ne démarre pas : l'installer depuis la source `msstore`.

## VM de test

- winget est inutilisable dans une session PowerShell Direct : l'exécution passe par une tâche planifiée dans la session ouverte.
- `Start-ScheduledTask` y échoue silencieusement : utiliser `schtasks /run`.
