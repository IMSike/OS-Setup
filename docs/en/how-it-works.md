# How the setup changes Windows

This document explains the mechanisms shared by all catalog items. The detail of each setting (effect, implications, rollback) is in [`windows/settings.md`](windows/settings.md).

## Data and engine

The catalog (`catalog/`) describes **what we want to obtain**, in JSON: "this registry value must be 0", "this winget package must be installed". It contains no code.

The engine (`src/`) knows **how** to obtain it, thanks to **providers**: one provider per action type. Adding a piece of software or a setting therefore only requires JSON; a new provider is only needed for a new *type* of action.

## Providers

Each provider gives the engine:

| Operation | Role |
|---|---|
| `Describe` | Sentence displayed in the plan and the log ("service DiagTrack : démarrage Disabled", i.e. "service DiagTrack: startup Disabled"). |
| `Test` | Is the system **already** in the desired state? Gives the plan's `[ok]` / `[à faire]` ("to do") status, makes the setup **idempotent** (a rerun does nothing again) and enables `-WhatIf`. The engine calls it again **after** the action to check that it succeeded. |
| `Invoke` | Applies the action. Can signal that a reboot is required. |
| (recheck) | The plan tests everything **before** acting. When an action of an item has just been applied, the following actions of the same item, and those of the items that depend on it, that were judged compliant are **retested** when they are about to run (e.g. installing a browser creates the shortcut that the next action must remove, or the startup entry that another item must disable). |
| `Read` (optional) | Reads the current state, recorded as the **original value** before any modification (see below). |

| Provider | What it does | Why a dedicated provider | Original value |
|---|---|---|---|
| `winget` | Installs software with winget (`--exact --id`, `winget` source). | Handling of return codes (already installed, reboot, elevation), output encoding; waits (60 s at most) for the package to be detected, as some installers finish in the background. | — (software absent before) |
| `registry` | Writes a registry value. | The most common case of settings. | type and value, or absence |
| `directory` | Creates a folder. | | — |
| `file` | Deploys a file from `dotfiles/`: copy, `{{Variable}}` template, or **JSON merge** (`merge-json`: only the repository's keys are written, the machine's keys are kept; compliant if those keys already have their value; comments and trailing commas are accepted when reading, as in VS Code settings, but removed on writing). `unlessSelected`: moot when another selected item deploys a variant of the file. | Prior backup of the existing file. | the file itself, in the backups |
| `path` | Adds a folder to the PATH. | Preserves `%VARIABLES%` and notifies Windows of the change. | — (addition only) |
| `windows-feature` | Enables an optional Windows feature (e.g. WSL). | `dism`, detection of the required reboot. | state (`Disabled`…) |
| `service` | Sets a service's startup type (and stops it if disabled). | **Services** are background programs started by Windows (e.g. DiagTrack, telemetry). Writing the registry's `Start` value would only stop it at the next reboot and would bypass the service manager: the provider goes through `Set-Service`. | startup type and state |
| `scheduled-task` | Enables or disables a scheduled task. | Windows periodically runs **scheduled tasks** (e.g. a software inventory sent to Microsoft). They cannot be reliably modified through the registry: Task Scheduler API. | task state |
| `power` | Sets a power timeout (sleep, screen off) of the active plan. | The values are only taken into account if the plan is reactivated: `powercfg`, the official tool. Reading is independent of Windows' language. | timeout in seconds |
| `appx` | Removes a Store app for all accounts and deprovisions it. | Appx module (via Windows PowerShell 5.1 under PowerShell 7). | packages present |
| `windows-capability` | Removes an optional Windows component ("capability"). | `Remove-WindowsCapability`, possible reboot. | installed capabilities |
| `win32-uninstall` | Uninstalls a classic piece of software without interaction. | Uninstaller declared in "Programs and Features"; the software's disappearance is authoritative rather than the return code. | uninstall entry |
| `shortcut` | Creates (copy of an existing shortcut) or deletes a `.lnk` shortcut. | | presence |
| `desktop-layout` | Applies the taskbar and Start menu layout. | Aggregates the declarations of **all** selected items (`taskbarPin`: `.lnk` shortcut or Store app, `startLayout`): Windows 10 only applies the layout as a whole. See [`windows/desktop.md`](windows/desktop.md). | pins and layout fingerprint |
| `startup-entry` | Disables a software's launch at logon. | Like Task Manager (`StartupApproved`): the entry stays and if the software recreates it, it stays disabled. | state of each entry |
| `windows-update` | Installs the drivers offered by Windows Update. | Built-in API (`Microsoft.Update.Session` COM object), no third-party module; slow search cached during the run; reboot signaled. See [`windows/drivers.md`](windows/drivers.md). | titles of the offered updates |
| `taskbar` | Taskbar auto-hide. | `SHAppBarMessage` API (the one Settings uses): immediate effect; the binary registry value that holds it is rewritten by Explorer. See [`windows/desktop.md`](windows/desktop.md). | previous state |
| `manual` | Guided manual step (see below). | Check and help written in the engine. | — |
| `git-config` | A key of the global Git configuration (`git config --global`). | Key by key: the user's other settings remain. | value or absence |
| `vscode-extension` | Installs a VS Code or Cursor extension (`code` / `cursor --install-extension`, `editor` field). | | — |
| `install-script` | Installs software with its publisher's official script (`irm <url> \| iex`, Windows PowerShell), when that is the recommended method. Presence tested through the installed command. | Only `https` addresses are accepted; each script is reviewed before being added to the catalog (it runs with the setup's rights). | — |
| `fnm-node` | Installs the latest Node.js LTS with fnm and makes it the default version. | | installed versions |
| `npm-global` | Installs a global npm package (default Node.js version). | | — |
| `gh-extension` | Installs a GitHub CLI extension. | gh must be signed in. | — |
| `rtk-init` | Hooks rtk into Claude Code (`rtk init --global`). | Statistics refusal recorded beforehand, otherwise a question would block the setup. | — |
| `herdr-plugin` | Installs a herdr plugin published on GitHub (`herdr plugin install`). | Presence read from `%APPDATA%\herdr\plugins.json`. | — |
| `playwright-cli` | Configures Playwright CLI: an agent's skill (`install --skills`) or the browser provided by Playwright (`install-browser`). | Launched from the user's profile (no `.playwright` folder created elsewhere); presence read from disk. | — |
| `logon-task` | Creates a scheduled task that runs a PowerShell script at logon (highest privileges, no UAC prompt). | Script deployed outside the repository (which may be deleted at the end of the setup); Windows PowerShell 5.1, always present. | — |
| `docker-build-cache` | Cap on Docker's build cache (`builder.gc` in `daemon.json`). | JSON merge; cap reduced to a percentage of the system disk when it is small (hardware safety). | previous content |
| `wsl-config` | A key of `%USERPROFILE%\.wslconfig` (WSL 2 VM settings). | Key by key, rest of the file kept. `memoryPercent` computes the value from the machine's RAM, with bounds (**hardware safety**: an answer file remains valid on a smaller machine; a value brought back within the bounds is reported in the log). See [`windows/development.md`](windows/development.md). | value or absence |

Tool-specific providers (`git-config`, `fnm-node`, `rtk-init`…) are only a few lines long: they avoid the generic "command" provider rejected below.

### Generic "command" provider: rejected

An action that would contain, as text, a test command and an apply command would make it possible to do everything without touching the engine. Rejected because:

- it is code in the data, contrary to the "data ≠ engine" principle;
- the schema only checks syntax, not meaning; the plan would display a raw command instead of a sentence;
- idempotence and the pitfalls (output language, encoding) would have to be redone by each author;
- impossible to test with mocks;
- any data file could run arbitrary code with administrator rights.

It remains a last resort, subject to validation, if a need fits no provider.

## Guided manual steps

Some steps cannot be automated: a choice protected by Windows (default browser), signing in to an account (GitHub), a password chosen by the user (WSL's Linux account). The `manual` provider makes them as simple as possible:

1. the plan shows `[à faire]` ("to do") as long as the check fails (a rerun of the setup therefore only offers again what remains to be done);
2. at the time of the step, the setup displays the instructions and launches the helper: a Settings page, a command to complete in the console, or a new window;
3. menu "C'est fait : vérifier" ("Done: check") / "Relancer l'aide" ("Relaunch the help") / "Passer (à faire plus tard)" ("Skip (to do later)"); the check reads the real state (e.g. `gh auth status`);
4. unattended (`-Yes`), the step is not launched: it is reported as a "to do later" failure in the summary, like a skipped step; the items that depend on it are skipped.

The checks and helpers are written in the engine (`src/OSSetup/Functions/Manual.ps1`); an item only chooses which one (`check`) and provides the instructions.

## Personal information

A profile variable declared `personal` (e.g. name and email for Git) **never** has a value in the repository. The wizard asks for it at the "Informations personnelles" ("Personal information") step; it is kept in the session's answers (`state/answers-last.json`, outside the repository) and can appear in a personal answer file. When left blank ("Continuer sans" ("Continue without") choice, answer file without it, `-AcceptDefaults`), the actions that use it are marked `[ignoré]` ("skipped") in the plan: nothing is written empty.

## Registry: HKLM and HKCU

The **registry** is Windows' configuration database, organized in "hives":

| Hive | Full name | Scope | Rights to write | File |
|---|---|---|---|---|
| **HKLM** | `HKEY_LOCAL_MACHINE` | the whole machine, all accounts | administrator | `C:\Windows\System32\config\` |
| **HKCU** | `HKEY_CURRENT_USER` | only the session's account | none | `C:\Users\<account>\NTUSER.DAT` |

Consequences:

- an HKCU setting **only applies to the current account**: an account created later on the machine does not have it;
- it is for HKCU that the setup checks that the elevated account (after the UAC prompt) is indeed the session's: otherwise the settings would go into another account's profile.

## Preference or group policy

Two kinds of registry values can drive the same setting:

| | **Preference** | **Group policy** (`…\Policies\…` key) |
|---|---|---|
| What it is | The place where Settings (or the application) stores **the user's choice** | The **administration** mechanism designed for enterprises (gpedit.msc, Active Directory) |
| Priority | Overridden by a policy if one exists | Always takes precedence |
| Interface | Remains editable in Settings | Setting grayed out, banner "Some settings are managed by your organization" |
| Windows updates | A major update may reset it | Kept |
| Edition | Works everywhere | Some are only read on Enterprise / Education (ignored on Pro) |
| Visibility | Settings | **Invisible in gpedit.msc** (which reads its own file): visible only with `regedit` |
| Machine in a domain | — | A domain policy overrides ours |

**Project rule**: preference first; a policy only if there is no reliable equivalent. Each setting in [`windows/settings.md`](windows/settings.md) states which of the two it uses.

## Deferred effect

Some settings (Explorer, Start menu, screen saver…) only take effect at the **next logon**. They are marked `requiresLogoff` in the catalog; the final summary lists them, unless a reboot is already planned. This is also the case for software that adds the account to a local group (Docker Desktop: `docker-users` group, taken into account at the next logon).

So that the environment is ready to use at the end of the setup, the **session is then closed** (final pass only, no reboot planned, at least one action of this kind applied): 10-second countdown that a key press postpones, immediate with `-Yes`. The logoff is done by the end-of-setup cleanup (`src/cleanup.ps1`, `shutdown /l`), after its other operations: closing the session earlier would interrupt them. Tasks launched at logon (e.g. Docker maintenance, which starts Docker Desktop) run when signing back in. Save any work open in other windows before the end of the setup.

## Rollback and original values

The setup **undoes nothing by itself**: unchecking a setting in a later run does not restore it. Everything remains reversible **by hand** ([`windows/settings.md`](windows/settings.md) says where for each setting):

| Type | Where to roll back |
|---|---|
| Preference | Settings (note: on non-activated Windows, the *Personalization* page is locked, you have to go through `regedit`) |
| Policy | `regedit`: delete the value |
| Service | `services.msc` |
| Scheduled task | `taskschd.msc` |
| Power | Settings > System > Power & sleep |

To know which value to put back, the engine records, **before each modification**, the original state read by the provider (`Read`):

- file `state\backups\<date>\original-values.json` in the setup folder: for each action, the item, the description, the action and the previous state (`before`) — for example `{ "exists": false }` if the value did not exist, which means it is enough to delete it;
- runs resumed after a reboot complete the same file;
- at the end of the setup, with the "keep the history" option, it is kept in `%LOCALAPPDATA%\OS-Setup\<date>\backups\` with the log and the answers; with "delete everything", it disappears.

An automatic undo command may rely on this file later.
