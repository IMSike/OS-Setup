# Pièges connus

Comportements constatés pendant le développement, et leur traitement dans le moteur. À lire avant de modifier un provider ou d'ajouter un élément.

## winget (Windows 10, winget 1.29)

| Symptôme | Cause et traitement |
|---|---|
| `0x8A150019` « nécessite des privilèges d'administrateur » | Le paquet exige un winget **déjà élevé** (l'installeur ne s'élève pas seul). Le provider relance winget en mode élevé (`Start-Process -Verb RunAs`). |
| `0x8A150113` sur une installation `--scope machine` | Paquet **MSIX** : installation pour toute la machine non prise en charge sous Windows 10. Forcer un autre installeur (`installerType`, ex. `wix` pour PowerShell 7) ou passer en `scope: user`. |
| `0x8A15002B` | Déjà installé, aucune mise à jour applicable : traité comme un succès. |
| Paquet non détecté juste après une installation réussie | Installeur qui termine en arrière-plan (Squirrel : Discord). Le provider attend jusqu'à 60 s que `winget list` le trouve. |
| Outil introuvable juste après son installation | Le PATH de la session est figé : le moteur le recharge depuis le registre après chaque installation (`Update-SessionPath` dans le bootstrap). |
| Programme installé qui ne démarre pas, code `-1073741515` (`0xC0000135`) sans message | DLL absente, le plus souvent le runtime Visual C++ (absent d'un Windows neuf, rarement déclaré par les paquets portables, ex. rtk) : dépendance `vcredist`. |
| Paquet absent de winget (ex. NVIDIA App) | Nécessiterait un autre provider (téléchargement direct), à valider avant d'en ajouter un. |
| Accents corrompus dans la sortie capturée (`Trouv├®`) | winget écrit en UTF-8 : régler `[Console]::OutputEncoding` sur UTF-8 le temps de l'appel. |
| Paquet trouvé dans la source `msstore` au lieu de `winget` | Toujours préciser `--source winget`. |
| Version du Store (MSIX) d'un logiciel déjà présente : `winget list --id` la reconnaît, et son alias d'exécution (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`) répond à `Get-Command` (constaté : PowerShell 7, dont le Store ferme de force tous les processus à chaque mise à jour, sessions herdr comprises) | Ne pas se fier à la commande ni à winget : vérifier le fichier de l'installation voulue (`installedPath`, `-Path` du bootstrap), forcer l'installeur (`--force`), lancer le setup par ce chemin complet, puis supprimer la version du Store (provider `appx`). `setup.ps1` refuse de tourner dans le pwsh du Store. |
| Paquet installé que `winget list --id` ne trouve pas (`0x8A150014`), alors que `winget list --name` l'affiche avec son identifiant (constaté : PowerShell 7 mis à jour par Microsoft Update) | Le plan prévoyait de le réinstaller. `winget export` fait bien le rattachement : second avis dans `Test-OSSetupWingetInstalled`. |

Sous Windows PowerShell 5.1, ne pas capturer ni rediriger la sortie de winget (`| Out-Host`, affectation) : elle serait décodée avec la page de code OEM. La laisser écrire directement dans la console, ou régler `[Console]::OutputEncoding` sur UTF-8.

## Windows

- `New-Item -Force` sur une clé de registre **existante** la recrée vide : toutes ses valeurs sont perdues. Créer une clé seulement si elle n'existe pas (`if (-not (Test-Path …)) { New-Item … }`).
- Supprimer une application du Store pour tous les comptes (`Remove-AppxPackage -AllUsers`) échoue (`0x80073CFA`) tant qu'elle est provisionnée : la déprovisionner d'abord (`Remove-AppxProvisionedPackage`).
- Sous PowerShell 7 et Windows 10, le module Appx ne se charge pas (« Operation is not supported on this platform ») : `Import-Module Appx -UseWindowsPowerShell` le fait passer par Windows PowerShell 5.1 (`Import-OSSetupAppxModule`, objets désérialisés). Sous `-WhatIf`, ce chargement échoue (la copie des fichiers du module de compatibilité est simulée) : forcer `$global:WhatIfPreference = $false` le temps de l'import, puis le rétablir.
- Sur une machine vierge, `Install-PSResource` échoue tant que la configuration de PSResourceGet n'existe pas ; un premier `Get-PSResourceRepository` l'initialise.
- Les sorties d'outils système (`powercfg`, `dism`…) dépendent de la langue : ne lire que des valeurs stables (nombres hexadécimaux, `dism /English`).

## PowerShell

- Windows PowerShell 5.1 lit un `.ps1` **sans BOM** comme ANSI : les caractères accentués sont corrompus. Les fichiers `.ps1`, `.psm1` et `.psd1` sont en UTF-8 avec BOM (figé dans `.gitattributes` et `.editorconfig`).
- Les noms de variables ne tiennent pas compte de la casse : une variable locale `$answers` écrase le paramètre `$Answers`.
- Les apostrophes typographiques `‘ ’` valent `'` et les guillemets `“ ”` valent `"` : un texte contenant `’` (ex. sortie de `powercfg` en français) va entre guillemets droits `"…"`.
- `$x = if (...) { @() }` donne `$null`, et un tableau d'un seul élément devient l'élément : écrire `$x = @(if (...) { ... })`.
- Un script avancé (`[CmdletBinding()]`) qui relaie ses arguments restants (`ValueFromRemainingArguments`) doit déclarer `[CmdletBinding(PositionalBinding = $false)]` : sinon un argument comme `-WhatIf` destiné à `setup.ps1` est capté en position par un autre paramètre.

## VM de test

- winget est inutilisable dans une session PowerShell Direct : l'exécution passe par une tâche planifiée dans la session ouverte.
- `Start-ScheduledTask` y échoue silencieusement : utiliser `schtasks /run`.
