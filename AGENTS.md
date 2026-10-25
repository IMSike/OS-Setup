# AGENTS.md

Instructions for coding agents (Claude Code, Codex, Copilot…) working on this repository. Humans: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Project

Reproducible Windows setup from a fresh install: PowerShell 7 engine, JSON catalog and profiles, console wizard, replayable answer files. Target: Windows 10 22H2 now, Windows 11 and Fedora later, macOS out of scope. The repository is **public** (MIT).

Read before changing anything:

- [Architecture](docs/en/architecture.md): principles, concepts, execution flow.
- [How it works](docs/en/how-it-works.md): providers, registry, preferences vs. policies, original values.
- [Adding an item](docs/en/adding-items.md) and [Known pitfalls](docs/en/pitfalls.md).
- [CONTRIBUTING.md](CONTRIBUTING.md): code conventions, commit messages, versions.

## Hard rules

1. **Never change the host machine** (install, uninstall, registry, system settings, running `setup.ps1` without `-WhatIf`) without the maintainer's explicit consent. Prefer `-WhatIf`, reading state, mocked tests, and the test VM ([Testing](docs/en/testing.md)).
2. **Never install global tools** (package managers, PowerShell modules…) "to test" without asking.
3. **No secrets, personal data or machine-specific paths** in the repository: it is public.
4. **Do not settle open design questions alone**: present the mechanism, the alternatives and a recommendation, then let the maintainer decide. Significant decisions go in an ADR (`docs/{en,fr}/adr/NNNN-title.md`: context, decision, consequences).
5. **Idempotence, `-WhatIf`, isolated failures, single UAC prompt**: see the principles in [Architecture](docs/en/architecture.md#principles). Any new engine dependency must be justified and installable by the bootstrap.
6. **Winget only** for Windows packages; another package manager or a direct-download provider needs the maintainer's approval.

## Documentation

- English (`docs/en/`) and French (`docs/fr/`) trees have the **same files**. Any page you change is changed **in both languages, in the same commit** as the code or data change. `README.md` / `README.fr.md` and `CONTRIBUTING.md` / `CONTRIBUTING.fr.md` likewise.
- Every catalog item is documented on its category page under its id in backticks (effect, implications, changed value, how to revert). Tests check both languages.
- Explain what each item does and its implications for the user, not only the value it changes.
- A new Windows setting must be checked as **recognized by Windows**, not only written: after a reboot in the VM, use `tests/vm/Get-TestVMScreenshot.ps1` to check the relevant Settings page or behavior.

## Maintainer notes

Work in progress, to-do lists, verification reports and notes about specific machines live in `.maintainer/` (ignored by Git), never in the documentation. Keep the documentation about what the setup does, not about what remains to do.

## Conventions

- Language: identifiers in English; user-facing messages (console, catalog names) in French for now; documentation in both languages. Talk to the maintainer in French.
- PowerShell: see [CONTRIBUTING.md](CONTRIBUTING.md#code-conventions). PSScriptAnalyzer must stay clean with `PSScriptAnalyzerSettings.psd1`.
- Encoding: `.ps1`, `.psm1`, `.psd1` are **UTF-8 with BOM, CRLF**; other text files UTF-8 without BOM, LF in the repository.
- Catalog item names: "Subject: state" in French (e.g. « Localisation : désactivée »); consequences go in `uncheckedWarning` / `checkedWarning`.

## Tests

- `Invoke-Pester -Path tests` before proposing a change; tests must have no side effect on the system.
- Integration tests only in the disposable Hyper-V VM (`tests/vm/`): targeted run (`Invoke-TestVM.ps1 -Reset -Only <groups>`) during development, full run from the `vierge` checkpoint (`-Baseline vierge`) for any bootstrap change and before closing a milestone.

## Git

- Maintainer's own work happens on the `dev` branch: never commit or push to `main` for them, they merge `dev` into `main`, which publishes a version. External contributions are pull requests to `main` (see [CONTRIBUTING.md](CONTRIBUTING.md)). Commit messages and PR titles follow the **Angular convention** (`feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`); there is no `chore`. Versions are computed from them on each push to `main` (see [CONTRIBUTING.md](CONTRIBUTING.md#versions)).
- One commit = one coherent change; avoid mixing catalog and engine changes.
- Keep this file up to date when a convention changes.
