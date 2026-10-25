# ADR 0001 — Engine language: PowerShell 7

- **Status**: accepted for Windows; Fedora to be reassessed when the question arises
- **Date**: 2026-10-20

## Context

The setup must target Windows 10/11, then Fedora (and other Linux distributions later; no macOS).
The engine has two types of responsibilities:

- **common**: read and validate JSON, merge profiles, display menus, resolve dependencies, log, produce a plan;
- **OS-specific**: winget, registry, services, Windows features / dnf, gsettings, systemd…
  These actions essentially boil down to calling system commands, whatever the language.

Options studied:

| Option | Pros | Cons |
|---|---|---|
| PowerShell 7 everywhere | A single engine; excellent on Windows (registry, services, Appx); native `Test-Json -Schema` | Absent from Fedora by default (installable from the Microsoft repository); not very idiomatic on Linux |
| Python 3 | Native on Fedora; good libraries (menus, jsonschema) | Absent from Windows; Windows settings often delegated to PowerShell; venv/dependency management |
| Go / Rust (binary) | No runtime required | Build chain and releases; heavier to evolve |
| Native per OS (PowerShell + Bash) | Idiomatic, zero dependencies | Two engines: profile/choice/menu logic duplicated |
| Ansible / WinGet Configuration (DSC) | Proven tools | Ansible: Linux controller + WinRM; DSC: Windows only; interactive choices are painful |

## Decision

- A single engine in **PowerShell 7** (`pwsh`), shared across platforms.
- Two minimal **bootstraps**, the only OS-specific files outside the providers:
  - `bootstrap.ps1` (Windows PowerShell 5.1): installs Git and PowerShell 7 via winget, clones, launches `setup.ps1`;
  - `bootstrap.sh` (Bash): installs Git and PowerShell 7 via dnf, clones, launches `setup.ps1`.
- OS-specific code is confined to the **providers** and to catalog items.

## Consequences

- PowerShell 7 becomes a dependency of the setup on all platforms (it is useful for the `dev` profile anyway).
- Fedora is not in PowerShell's official list of supported distributions: installation via the RHEL package from the Microsoft repository must be **validated in a VM** before considering the decision accepted.
- Possible fallback: Python 3, if PowerShell on Fedora causes problems.
