# OS-Setup

**English** · [Français](README.fr.md)

Set up a Windows machine from a fresh install, reproducibly: pick profiles and options in a console wizard, review the plan, apply it with a single UAC prompt. Software, settings and configuration files are described as JSON data; the PowerShell engine checks each one before acting.

> **Status: early stage.** Supported: Windows 10 22H2. Planned: Windows 11, then Fedora. The wizard and catalog names are in French for now.

## Features

- **Cumulative profiles**: `base` (browsers, privacy, power, desktop, removal of preinstalled apps, drivers) and `dev` (Git, terminal, editors, Node.js, coding agents, WSL, Docker).
- **Choices within each profile**: single or multiple choice menus, sensible defaults, warnings for choices with consequences.
- **Safe to re-run**: every action tests the current state first; nothing already in place is redone.
- **Dry run** (`-WhatIf`), **unattended runs** from a replayable answer file, **resumes after reboots** on its own.
- **Traceable**: timestamped log, final summary, original value of every changed setting saved for manual rollback.
- **Leaves nothing behind**: the tools installed only for the setup (Git, PowerShell 7) are removed at the end unless chosen.
- **Documented**: each setting explained — effect, implications, how to revert.

## Quick start

On a fresh Windows, in **Windows PowerShell**:

```powershell
cd $env:TEMP
irm https://raw.githubusercontent.com/IMSike/OS-Setup/main/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

The bootstrap installs winget, Git and PowerShell 7, clones this repository into `%USERPROFILE%\OS-Setup` and starts the wizard. Nothing else is changed before you approve the plan.

From a clone, with PowerShell 7:

```powershell
./setup.ps1 -WhatIf                                   # dry run
./setup.ps1 -AnswerFile answers/dev.example.json      # replay an answer file
./setup.ps1 -Profiles base -AcceptDefaults -Yes       # no questions at all
```

See [Usage](docs/en/usage.md) for all parameters, answer files, logs and reboots.

## Documentation

| | |
|---|---|
| [Usage](docs/en/usage.md) | Running the setup, parameters, answer files, rollback |
| [How it works](docs/en/how-it-works.md) | Providers, registry, preferences vs. policies, original values |
| [Windows settings](docs/en/windows/settings.md) | Every setting: effect, implications, how to revert |
| [Removable apps](docs/en/windows/removable-apps.md) · [Desktop](docs/en/windows/desktop.md) · [Browsers](docs/en/windows/browsers.md) · [Apps](docs/en/windows/apps.md) · [Development](docs/en/windows/development.md) · [Drivers](docs/en/windows/drivers.md) | What each profile installs and configures |
| [Architecture](docs/en/architecture.md) | Principles, concepts, execution flow |

Full index: [docs/en](docs/en/README.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): conventions, commit messages, tests, and [how to add an item](docs/en/adding-items.md).

## License

[MIT](LICENSE)
