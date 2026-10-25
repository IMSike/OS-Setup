# Contribuer

[English](CONTRIBUTING.md) · **Français**

## Pour commencer

Prérequis : PowerShell 7.4+, Git, [Pester 5](https://pester.dev), et en option [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

```powershell
git clone https://github.com/IMSike/OS-Setup.git
cd OS-Setup
git config core.hooksPath .githooks       # vérifie les messages de commit en local
Invoke-Pester -Path tests                 # tests unitaires, sans effet sur le système
./setup.ps1 -WhatIf                       # simulation du setup
```

**Ne lancez jamais le setup pour de vrai sur votre propre machine pour tester un changement** : utilisez la VM Hyper-V jetable décrite dans [Tests](docs/fr/testing.md).

Lisez d'abord [Architecture](docs/fr/architecture.md), puis [Ajouter un élément](docs/fr/adding-items.md) et [Pièges connus](docs/fr/pitfalls.md).

## Principes

- **Idempotence** : chaque action vérifie l'état avant de le modifier ; relancer le setup ne change rien.
- **Données, pas code** : logiciels et réglages sont décrits en JSON dans `catalog/` et `profiles/` ; en ajouter un ne doit pas demander de modifier le moteur.
- **`-WhatIf` partout** : toute action qui modifie le système respecte `SupportsShouldProcess`.
- **Aucun secret, aucune donnée personnelle, aucun chemin propre à une machine** dans le dépôt (`$env:USERPROFILE`, `[Environment]::GetFolderPath(...)`…).
- **Jamais d'écrasement** d'une configuration ou d'une donnée existante sans sauvegarde.

## Conventions de code

- Moteur : PowerShell 7.4+. `bootstrap.ps1` tourne sous Windows PowerShell 5.1, sans module externe.
- `Set-StrictMode -Version Latest` et `$ErrorActionPreference = 'Stop'` en tête de script.
- `[CmdletBinding()]` partout, noms `Verbe-Nom` avec des verbes approuvés, paramètres typés, pas d'alias, pas d'arguments positionnels ambigus.
- Indentation de 4 espaces, accolades style OTBS.
- Aucun avertissement de PSScriptAnalyzer avec `PSScriptAnalyzerSettings.psd1` (vérifié par un test Pester quand le module est installé).
- Identifiants (fonctions, variables, clés de données) en anglais ; messages utilisateur en français pour l'instant.
- Encodage : `.ps1`, `.psm1`, `.psd1` en **UTF-8 avec BOM** et CRLF (Windows PowerShell 5.1 lit un fichier sans BOM comme ANSI) ; autres fichiers texte en UTF-8 sans BOM. Figé par `.gitattributes` et `.editorconfig`.

## Documentation

La documentation existe en **anglais** (`docs/en/`) et en **français** (`docs/fr/`), avec les mêmes noms de fichiers.

- Tout changement de comportement met la documentation à jour **dans le même commit**, **dans les deux langues**.
- Chaque élément du catalogue est documenté dans la page de sa catégorie (effet, implications, valeur modifiée, retour arrière). Des tests vérifient que chaque élément est documenté dans les deux langues et que les deux arborescences ont les mêmes pages.

## Messages de commit

Les messages de commit et les titres de pull request suivent la [convention Angular](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md) :

```
<type>(<portée>): <sujet>
```

| Type | Usage |
|---|---|
| `feat` | Fonctionnalité (nouvel élément, provider, option) |
| `fix` | Correction |
| `docs` | Documentation seule |
| `refactor` | Changement de code qui ne corrige rien et n'ajoute rien |
| `perf` | Performances |
| `test` | Tests seuls |
| `build` | Construction, dépendances, outillage |
| `ci` | Workflows GitHub Actions |
| `revert` | Annule un commit précédent |

Portées courantes : `catalog`, `engine`, `bootstrap`, `providers`, `profiles`, `dotfiles`, `vm`. Le sujet est à l'impératif (ou nominal), en minuscules, sans point final. Un commit = un changement cohérent ; éviter de mélanger catalogue et moteur.

Les messages sont vérifiés par le hook `.githooks/commit-msg` et par le workflow [Commit messages](.github/workflows/commit-lint.yml).

## Versions

Chaque envoi sur `main` (direct ou pull request fusionnée) reçoit une version, étiquetée et publiée par le workflow [Version](.github/workflows/release.yml), selon le [versionnage sémantique](https://semver.org/lang/fr/) :

| Commits depuis la dernière version | Montée |
|---|---|
| au moins un `feat` | mineure : `0.1.0` → `0.2.0` |
| tout le reste | correctif : `0.1.0` → `0.1.1` |
| décision du mainteneur uniquement | majeure : lancer le workflow à la main avec `major` |

La première version est `v0.0.0`. Pas de journal des modifications pour l'instant.

## Pull requests

1. Partir de `main`.
2. Les tests passent (`Invoke-Pester -Path tests`), la simulation affiche le plan attendu, et le changement a été testé en VM s'il touche au système.
3. Documentation à jour dans les deux langues.
4. Titre conforme à la convention de commit (il devient le message du commit lors d'une fusion « squash »).

## Licence

En contribuant, vous acceptez que vos contributions soient publiées sous [licence MIT](LICENSE).
