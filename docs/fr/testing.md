# Tests

## Tests unitaires et qualité du code

```powershell
Invoke-Pester -Path tests
```

Les tests [Pester 5](https://pester.dev) n'ont aucun effet sur le système (providers simulés). Ils vérifient aussi les données : chaque élément et profil est conforme à son schéma, chaque élément est documenté, et la documentation existe dans les deux langues.

[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) vérifie le style et les erreurs courantes du code PowerShell, avec les règles de `PSScriptAnalyzerSettings.psd1` (et `tests/PSScriptAnalyzerSettings.psd1` pour les tests ; exclusions justifiées dans les fichiers). Le test `tests/CodeQuality.Tests.ps1` le lance s'il est installé, et vérifie aussi que le manifeste du module exporte toutes ses fonctions :

```powershell
Install-PSResource PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path tests/CodeQuality.Tests.ps1 -Output Detailed
```

## VM de test Hyper-V

Tests d'intégration dans une VM Windows jetable, recréable à l'identique, sans ISO ni clic. Les scripts sont dans [`tests/vm/`](../../tests/vm/).

Prérequis sur l'hôte : virtualisation activée dans le BIOS, fonctionnalité Hyper-V, PowerShell 7, Git, une image Windows : `install.esd` ou `install.wim` (par exemple sur une clé créée avec l'outil de création de média Microsoft), ou l'ISO d'installation téléchargée sur le site de Microsoft. L'image est copiée dans un cache propre à chaque VM (`%ProgramData%\OSSetup-Tests\images\<VM>`). Les VM ont un TPM virtuel et le démarrage sécurisé, comme une machine Windows 11.

Droits : `New-TestVM.ps1` se lance **en administrateur** (disques virtuels, DISM). `Invoke-TestVM.ps1` et `Reset-TestVM.ps1` se lancent sans invite UAC si le compte est membre du groupe local **« Administrateurs Hyper-V »** (SID `S-1-5-32-578`, effectif après reconnexion à Windows).

| Script | Rôle |
|---|---|
| `New-TestVM.ps1` | Crée la VM à partir de l'image : disque virtuel, application de l'édition (DISM), `unattend.xml`, première ouverture de session, puis point de contrôle **« vierge »**. |
| `Invoke-TestVM.ps1` | Copie l'état courant du dépôt (y compris le travail non commité) dans la VM et y lance `bootstrap.ps1` dans la session de l'utilisateur, à droits élevés. Rapatrie dans `logs/vm/` les journaux et les sauvegardes (dont `original-values.json`, les valeurs d'origine). |
| `New-TestVMPrerequisite.ps1` | Crée le point de contrôle **« prerequis »** : bootstrap réel depuis « vierge » (winget, Git, PowerShell 7), simple simulation du setup, puis point de contrôle VM allumée. La trace du bootstrap (outils installés) est gardée hors du dépôt, dans `C:\OSSetup-Tests`, et réinjectée à chaque test pour que le nettoyage de fin se comporte comme sur une vraie machine. À relancer quand `bootstrap.ps1` change (`Invoke-TestVM.ps1` le signale). |
| `Reset-TestVM.ps1` | Revient au point de contrôle « vierge » (par défaut) ou « prerequis » (`-Checkpoint prerequis`). |
| `Get-TestVMScreenshot.ps1` | Capture l'écran de la VM en PNG, après avoir éventuellement ouvert une page dans la session (`-Open 'ms-settings:privacy-webcam'`) : vérifie qu'un réglage est **reconnu par Windows**, pas seulement écrit. |

```powershell
./tests/vm/New-TestVM.ps1 -ImagePath D:\sources\install.esd   # une fois (10 à 20 min)
./tests/vm/New-TestVM.ps1 -Name OSSetup-Win11 -ImagePath C:\ISO\Win11.iso  # VM Windows 11 ; -Name pour tous les scripts
./tests/vm/New-TestVMPrerequisite.ps1                         # une fois, puis quand bootstrap.ps1 change (6 min)
./tests/vm/Invoke-TestVM.ps1 -Reset -Only privacy, power         # test ciblé : ces menus du profil base, tout coché, le reste vide
./tests/vm/Invoke-TestVM.ps1 -Reset                            # depuis « prerequis », rejoue answers/dev.example.json
./tests/vm/Invoke-TestVM.ps1 -Reset -SetupArguments '-AnswerFile','answers\base-all.example.json','-Yes'  # tous les réglages du profil base cochés
./tests/vm/Invoke-TestVM.ps1 -Reset -Baseline vierge           # parcours complet depuis Windows fraîchement installé (bootstrap compris)
./tests/vm/Invoke-TestVM.ps1 -SetupArguments '-AnswerFile','answers\dev.example.json','-WhatIf'
./tests/vm/Invoke-TestVM.ps1 -Reset -AnswerFile $env:TEMP\t.json # test ciblé sur quelques éléments : fichier de réponses local injecté
./tests/vm/Invoke-TestVM.ps1 -Reset -PrepareOnly                # test manuel (menus, UAC) du travail non commité
./tests/vm/Invoke-TestVM.ps1 -Reset -PrepareOnly -AsBootstrapClone  # idem, copie traitée comme créée par le bootstrap (nettoyage de fin)
```

**Quel point de départ ?** Par défaut, `-Reset` repart de « prerequis » (3 à 4 min de moins par test). Le parcours complet depuis « vierge » (`-Baseline vierge`) reste nécessaire pour tout changement du bootstrap, et avant de valider une étape importante. `-Only` génère `answers/vm-only.json` (dans la copie de la VM seulement) : pour un changement limité à quelques menus, le test passe de plusieurs minutes à peu de chose. Chaque test affiche sa durée totale.

Les redémarrages demandés par le setup sont gérés : le harnais attend la reprise automatique et considère le test terminé quand `state\last-result.json` existe dans la VM.

Les tests automatiques passent par une tâche planifiée déjà élevée : ils n'exercent **ni l'invite UAC ni les menus**. Pour ces deux points, test manuel : `-PrepareOnly`, puis dans la console de la VM (Gestionnaire Hyper-V) lancer `powershell -NoProfile -ExecutionPolicy Bypass -File C:\OS-Setup\bootstrap.ps1`.

Depuis une autre console que celle-ci, passer les tableaux avec `-Command` : `pwsh -File` transmettrait `'-AnswerFile','…'` comme une seule chaîne.

Les images et disques virtuels sont stockés hors dépôt, dans `%ProgramData%\OSSetup-Tests`.

Compte de la VM : `tester` / `OSSetup-Test`. Ce mot de passe est **volontairement public** : il ne protège qu'une VM jetable et locale, et PowerShell Direct refuse les comptes sans mot de passe.

**WSL 2 et Docker Desktop ne sont pas testables dans la VM** sur l'hôte actuel (processeur AMD, Windows 10) : Hyper-V n'y prend pas en charge la virtualisation imbriquée (« cette plateforme ne prend pas en charge la virtualisation imbriquée » au démarrage de la VM). Ils sont vérifiés sur une machine physique ; leurs étapes de setup qui ne dépendent pas de la virtualisation (activation des fonctionnalités, redémarrage, reprise) restent testables.
