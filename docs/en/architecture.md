# Architecture

## Goal

Fully configure a workstation starting from a blank machine, in a way that is **reproducible**, **modular** and **chosen**:

- several **cumulative installation profiles** (multiple choice at launch): `base` and `dev`;
- within a profile, **choices** (single or multiple): browsers, editors, languages…;
- installation of software **and** of its **configuration**, including in non-standard locations;
- **interactive** execution (menus) or **unattended** execution (replayable answer file);
- works on a blank machine **and** on a machine already in use.

| Platform | Status |
|---|---|
| Windows 10 Pro 22H2 (19045) | supported |
| Windows 11 | planned |
| Fedora | planned |
| Other Linux distributions | later |
| macOS | out of scope |

The code separates what is platform-specific (providers, system settings) from what is common (catalog, profiles, choice resolution, menus, logging).

### Starting point: a blank machine

A freshly installed Windows only has:

- Windows PowerShell **5.1** (no PowerShell 7);
- **no usable `winget`**: a fresh Windows 10 image ships a 2019 App Installer without winget. The bootstrap installs it from the official `microsoft/winget-cli` release on GitHub;
- no Git, Python, Chocolatey or Scoop;
- the default PowerShell execution policy (`Restricted`).

Everything else is installed by the setup itself: no tool is assumed to be present without having been checked or installed.

Prerequisite: the **Microsoft Store, present and reachable**. PowerShell 7 is installed only from the Store (winget `msstore` source, see [ADR 0004](adr/0004-store-updates-without-forced-close.md)): on an edition without the Store (LTSC, IoT), with the Store removed or blocked (policy, "debloat" tool), the `msstore` source disabled, or a network that filters the Store, the bootstrap stops with a message giving these causes and what to do.

## Principles

1. **Idempotence**: rerunning the setup breaks nothing and does not reinstall what is in place. Each action checks the state before acting (`Test` → `Set`).
2. **Data ≠ engine**: the *what* (packages, profiles, choices, settings) is described in JSON; the *how* is in the PowerShell engine. Adding a piece of software does not require changing the engine.
3. **Simulation**: every action that modifies the system respects `-WhatIf`.
4. **Traceability**: each run produces a timestamped log (file and console) and a final summary (applied / skipped / failed).
5. **Isolated failure**: the failure of one item does not interrupt the setup (except for dependencies); it is reported in the summary.
6. **No secrets in the repository**: secrets are requested at run time or read from outside the repository.
7. **No machine-specific paths**: `$env:USERPROFILE`, `$env:LOCALAPPDATA`, `[Environment]::GetFolderPath(...)`…
8. **Single elevation**: the bootstrap (or `setup.ps1` launched alone, outside `-WhatIf`) relaunches itself once as administrator; everything else inherits the rights, hence **a single UAC prompt**. The setup checks that the elevated account is the one of the logged-on session, otherwise the account's settings would go into another profile; it stops in that case.
9. **Third-party code without administrator rights**: the publishers' install scripts (`install-script` provider: Claude Code, Cursor CLI, herdr) install into the user's profile and do not need the setup's rights. They run with a limited token, through a one-off scheduled task in the user's session (no new UAC prompt), deleted afterwards. A script still running after 30 min is not stopped: its item is reported as not finished and the script completes in the background (see [How the setup changes Windows](how-it-works.md#providers)). Their content remains whatever their URL serves at installation time: the setup neither pins nor verifies it.

## Repository layout

```
OS-Setup/
├─ bootstrap.ps1          Entry point on a blank machine (PowerShell 5.1): prerequisites, clone, launch
├─ setup.ps1              Main entry point (menus, -AnswerFile, -Profiles)
├─ src/
│  ├─ OSSetup/            Engine module: loading, resolution, plan, execution, log, menus
│  ├─ providers/          One file per action type: { Name; Test; Invoke; Describe; Read }
│  └─ cleanup.ps1         End-of-setup cleanup, run detached after the setup closes
├─ catalog/               Installable or configurable items, one JSON file per item
├─ profiles/              Profiles: items and choice groups; a profile can extend another
├─ dotfiles/              Deployed configuration files (Git, terminal, editors, agents…)
├─ schemas/               JSON schemas of the catalog, profiles and answer files
├─ answers/               Example answer files
├─ tests/                 Pester tests, and test VM tooling (tests/vm/)
└─ docs/                  Documentation (en/, fr/)
```

Catalog categories: `browsers/`, `browser-settings/`, `apps/`, `dev/`, `system/`, `privacy/`, `power/`, `remove/`, `desktop/`, `drivers/`.

## Concepts

| Concept | Role |
|---|---|
| **Item** (`catalog/`) | Atomic unit: a piece of software or a setting. Declares: identifier, name, category, actions, dependencies, need for administrator rights, conditions. |
| **Action** | Elementary step of an item (install a package, write a registry value, deploy a file…), run by a provider. |
| **Provider** | Knows how to test (`Test`) then apply (`Invoke`) one type of action; `Read` (optional) reads the original state before modification. See [How the setup changes Windows](how-it-works.md). Windows packages: **winget only**. |
| **Choice group** | List of items to choose from, in `single` or `multi` mode, with default values, minimum and maximum. |
| **Profile** (`profiles/`) | Mandatory items and choice groups. Can extend another profile (`dev` extends `base`); several profiles combine. Everything that is installed or removed is offered in a choice group, never imposed (checked at load time): `items` only contains settings. |
| **Dependency** (`dependsOn`) | A technical dependency, offered in no menu, is added automatically. A dependency offered in a menu but not checked is never silently added: the item that depends on it is skipped. |
| **Aggregated declarations** | An item can declare what an "aggregator" item applies for all: `taskbarPin` (pin) and `startLayout` (Start menu), applied in bulk by `desktop-layout`, processed last (`runLast`). `unlessSelected` makes an action moot when another selected item takes over. |
| **Answer file** | Profiles, choices and variables of a session, replayable without interaction. |
| **Variables** | `{{Name}}` values resolved at run time: built-in (`UserProfile`, `Documents`…) or declared by a profile with a default value, overridable by the answer file (e.g. `{{DevRoot}}`). |

### Data: JSON and schemas

The catalog, profiles and answer files are JSON, each validated by a schema from `schemas/` (the `$schema` key, for editor autocompletion). Since JSON has no comments, the `description` and `notes` fields carry the explanations. **Invalid data makes the setup fail before any action on the system.**

### Conditions

An item can be conditioned on the machine's context (`when` field), evaluated on **facts** that are detected automatically and never asked: platform, OS version and edition, activation, rights, manufacturer, processor, graphics card, virtualization… The list is authoritative in `src/OSSetup/Functions/Facts.ps1` and `schemas/item.schema.json` (a test checks that they are identical).

```json
"when": { "GpuVendor": "nvidia", "OSName": ["windows-10", "windows-11"] }
```

All keys must match; a list means "one of these values".

To be distinguished:

- **Preferences**: what cannot be deduced (e.g. `DevRoot`). They have a default value; the wizard only asks for them if the user chooses to customize locations.
- **Personal information** (`personal` variables, e.g. name and email for Git): never a value in the repository, requested by the wizard; when left blank, the actions that use them are skipped.

### Application configuration

In addition to installation, an item can deploy configuration files from `dotfiles/`: copy, `{{Variable}}` template or JSON merge, with a prior backup (see [ADR 0003](adr/0003-in-house-dotfiles.md)). An existing configuration or piece of data is **never overwritten without a backup**. Personal data (memories, histories) is never versioned.

## Interface

- **Step-by-step console wizard**: profiles, one choice group per step, locations, personal information. Keyboard navigation, going back with `Échap` (Esc). A validated menu is replaced by a single summary line: the console and the log stay readable. Text variant (typing numbers) when the console is redirected. The menu logic is tested separately from the display.
- **"Subject : state" labels** (e.g. "Localisation : désactivée", "Location: disabled"): the state is displayed in color.
- **Warnings**: an item whose absence has a consequence declares `uncheckedWarning`; an item whose selection has one (e.g. a removal that erases data) declares `checkedWarning`. The text is displayed under the menu summary, and in the log in unattended execution.
- **Validation screen** after the plan: apply, modify a step or cancel.

## Execution flow

1. `bootstrap.ps1`: checks the OS, sets the execution policy (`Process` scope), installs winget if needed, Git and PowerShell 7 (Store version, see [ADR 0004](adr/0004-store-updates-without-forced-close.md)), clones the repository, launches `setup.ps1`.
2. `setup.ps1`: loads and **validates** the catalog and profiles, asks for or reads the choices.
3. Resolution: profile merge, application of choices, conditions, dependency sorting.
4. Plan → validation → execution → summary and log.

### Reboots

The setup is **resumable**. A reboot is signaled by the provider (code 3010, Windows feature, winget code `0x8A150109`) or declared by the item (`requiresReboot`): the item finishes its actions, its dependents are postponed. At the end of a pass, the setup copies itself to `%ProgramFiles%\OS-Setup\resume` (read only for users), saves its state in `state\run.json` of that copy, creates a scheduled task "OS-Setup - reprise" ("OS-Setup - resume") (at logon, highest privileges: no new UAC prompt), then the machine restarts (immediately with `-Yes`, otherwise after a 10 s countdown that a key press postpones). On resume: same answers, same log, at most 5 passes. This task runs Windows PowerShell from the system folder with the copy's launcher `resume.ps1`, which starts the copy's `setup.ps1 -Resume` with the Store `pwsh.exe` found in its package folder, and the resume pass loads modules only from administrators-only folders: nothing that the elevated task runs can be modified without administrator rights ([ADR 0005](adr/0005-resume-from-administrators-only-copy.md)). Logs, backups and answers stay in the repository. The task and the copy are deleted when the setup finishes.

A setting that only takes effect at the next logon declares `requiresLogoff`: the session is closed at the end of the setup (see [Deferred effect](how-it-works.md#deferred-effect)).

### Manual steps

Some steps cannot be automated: choosing the default browser, signing in to GitHub CLI, WSL's Linux account. The `manual` provider displays instructions, launches the useful helper and checks the result; "Passer" ("Skip") or an unattended run leaves them to be done later. See [Guided manual steps](how-it-works.md#guided-manual-steps).

### End-of-setup cleanup

The setup leaves only what was chosen. The bootstrap records what it installed in `state/bootstrap.json`. At the end of the run (never in simulation or while waiting for a reboot):

- an uninstall that would stop the running setup is done here, after the setup closes: the PowerShell 7 MSI of an older machine, when the setup runs under that MSI (summary status "reportées à la fermeture du setup", "postponed until the setup closes"). If a reboot is pending, the cleanup does not run: the resume pass runs under the Store PowerShell and uninstalls the MSI directly;
- Git and PowerShell 7 installed by the bootstrap are uninstalled if no chosen item installs them;
- if the repository copy was created by the bootstrap, a menu offers: delete everything, keep the history (log, answers, backups in `%LOCALAPPDATA%\OS-Setup\<date>`), or keep everything. With `-Yes`: the history. A development clone is never deleted. The downloaded bootstrap script is deleted with the copy only if it is a `.ps1` file directly in the user's `%TEMP%` or Downloads folder: `state/bootstrap.json` can be modified without elevation and the cleanup runs as administrator, so any other recorded path is kept (warning in the log).

The work is done by `src/cleanup.ps1`, copied with its configuration into `%ProgramFiles%\OS-Setup\cleanup` (administrators only, since it runs elevated) and launched detached under Windows PowerShell 5.1: it waits for the setup to close, runs the postponed uninstalls (skipped if the software is already gone), uninstalls, deletes, then deletes itself. Deletions never follow junctions or symbolic links: a link placed in the repository copy is removed itself, never the content of the folder it points to (`Remove-Item -Recurse` in Windows PowerShell 5.1 can enter a junction). A path one of whose parent folders is a link is not deleted, and the log is not written through a link: these paths are in the user's repository, where a program running under the account could place one ([ADR 0005](adr/0005-resume-from-administrators-only-copy.md)). Its results go to the setup log (or the kept history), lines `[CLEANUP]`. It takes a few minutes: do not restart right after the setup ends.

## Windows specifics

- **Non-activated Windows**: most target machines have no license, and the personalization pages of Settings are then locked. Every personalization setting is applied through the registry or a command, and tested on a non-activated machine.
- **Drivers**: installed according to the detected hardware. See [Drivers](windows/drivers.md).
- **No Windows restore point**: the setup itself is what rebuilds a system.

## Machine already in use

The engine can **audit** what exists and produce a **plan** (`[ok]` / `[à faire]`, "to do"). An agent will optionally be able to propose resolutions for ambiguous cases, always validated by the user and executed by the engine; the setup remains fully usable without an agent. See [ADR 0002](adr/0002-agent-assistance.md).

## Architecture decisions

| ADR | Subject |
|---|---|
| [0001](adr/0001-engine-language.md) | Engine language: PowerShell 7 |
| [0002](adr/0002-agent-assistance.md) | Agent assistance on a machine already in use |
| [0003](adr/0003-in-house-dotfiles.md) | Deployment of configuration files by the engine |
| [0004](adr/0004-store-updates-without-forced-close.md) | Store apps (PowerShell 7, Windows Terminal) updated without forced close |
| [0005](adr/0005-resume-from-administrators-only-copy.md) | Resume after reboot from an administrators-only copy |
