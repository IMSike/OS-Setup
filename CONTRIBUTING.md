# Contributing

**English** · [Français](CONTRIBUTING.fr.md)

## Getting started

Requirements: PowerShell 7.4+, Git, [Pester 5](https://pester.dev), and optionally [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

```powershell
git clone https://github.com/IMSike/OS-Setup.git
cd OS-Setup
git config core.hooksPath .githooks       # checks commit messages locally
Invoke-Pester -Path tests                 # unit tests, no effect on the system
./setup.ps1 -WhatIf                       # dry run of the setup
```

**Never run the setup for real on your own machine to test a change**: use the disposable Hyper-V VM described in [Testing](docs/en/testing.md).

Read [Architecture](docs/en/architecture.md) first, then [Adding an item](docs/en/adding-items.md) and [Known pitfalls](docs/en/pitfalls.md).

## Principles

- **Idempotent**: every action tests the state before changing it; re-running the setup changes nothing.
- **Data, not code**: software and settings are JSON in `catalog/` and `profiles/`; adding one must not require an engine change.
- **`-WhatIf` everywhere**: every action that changes the system supports `SupportsShouldProcess`.
- **No secrets, no personal data, no machine-specific paths** in the repository (`$env:USERPROFILE`, `[Environment]::GetFolderPath(...)`…).
- **Never overwrite** an existing configuration or data without a backup.

## Code conventions

- Engine: PowerShell 7.4+. `bootstrap.ps1` runs on Windows PowerShell 5.1 without any external module.
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at the top of scripts.
- `[CmdletBinding()]` everywhere, `Verb-Noun` names with approved verbs, typed parameters, no aliases, no ambiguous positional arguments.
- 4-space indentation, OTBS braces.
- PSScriptAnalyzer clean with `PSScriptAnalyzerSettings.psd1` (checked by a Pester test when the module is installed).
- Identifiers (functions, variables, data keys) in English; user messages in French for now.
- Encoding: `.ps1`, `.psm1`, `.psd1` in **UTF-8 with BOM** and CRLF (Windows PowerShell 5.1 reads BOM-less files as ANSI); other text files in UTF-8 without BOM. Enforced by `.gitattributes` and `.editorconfig`.

## Documentation

The documentation exists in **English** (`docs/en/`) and **French** (`docs/fr/`), with the same file names.

- Any change in behavior updates the documentation **in the same commit**, in **both languages**.
- Each catalog item is documented on the page of its category (effect, implications, changed value, how to revert). Tests check that every item is documented in both languages and that both trees have the same pages.

## Commit messages

Commit messages and pull request titles follow the [Angular convention](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md):

```
<type>(<scope>): <subject>
```

| Type | Use |
|---|---|
| `feat` | New feature (new item, new provider, new option) |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Tests only |
| `build` | Build, dependencies, tooling |
| `ci` | GitHub Actions workflows |
| `revert` | Reverts a previous commit |

Usual scopes: `catalog`, `engine`, `bootstrap`, `providers`, `profiles`, `dotfiles`, `vm`. The subject is in the imperative, lowercase, without a final period. One commit = one coherent change; avoid mixing catalog and engine changes.

Messages are checked by the `.githooks/commit-msg` hook and by the [Commit messages](.github/workflows/commit-lint.yml) workflow.

## Versions

Each push to `main` (direct or merged pull request) is tagged and released by the [Version](.github/workflows/release.yml) workflow, following [semantic versioning](https://semver.org):

| Commits since the last version | Bump |
|---|---|
| at least one `feat` | minor: `0.1.0` → `0.2.0` |
| anything else | patch: `0.1.0` → `0.1.1` |
| maintainer's decision only | major: run the workflow manually with `major` |

The first version is `v0.0.0`. There is no changelog for now.

## Pull requests

1. Branch from `main`.
2. Tests pass (`Invoke-Pester -Path tests`), the dry run shows the expected plan, and the change was tested in the VM when it touches the system.
3. Documentation updated in both languages.
4. Title following the commit convention (it becomes the commit message on squash merge).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
