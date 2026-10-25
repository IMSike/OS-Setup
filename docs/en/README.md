# Documentation

**English** · [Français](../fr/README.md)

## Using the setup

| Page | Contents |
|---|---|
| [Usage](usage.md) | Launching, parameters, answer files, logs, reboots, rollback |
| [How the setup changes Windows](how-it-works.md) | Providers, registry (HKLM / HKCU), preferences and policies, manual steps, original values |

## What the setup does

| Page | Contents |
|---|---|
| [Windows settings](windows/settings.md) | Privacy, system, power: effect, implications and rollback of each setting |
| [Removable apps](windows/removable-apps.md) | Store apps, Windows components and preinstalled software |
| [Desktop integration](windows/desktop.md) | Taskbar, Start menu, shortcuts |
| [Browsers](windows/browsers.md) | Neutralized Edge, browser telemetry, default browser |
| [Apps](windows/apps.md) | Common software of the `base` profile |
| [Development](windows/development.md) | `dev` profile: Git, terminal, editors, Node.js, agents, WSL, Docker |
| [Drivers](windows/drivers.md) | Windows Update and manufacturer tools depending on the hardware |

## Contributing

| Page | Contents |
|---|---|
| [Architecture](architecture.md) | Principles, concepts (items, profiles, choices, providers), execution flow |
| [Adding an item](adding-items.md) | Create a piece of software or a setting in the catalog |
| [Testing](testing.md) | Unit tests, code quality, Hyper-V test VM |
| [Known pitfalls](pitfalls.md) | winget, Windows and PowerShell: observed behaviors |
| [Architecture decisions](adr/) | [0001](adr/0001-engine-language.md) engine language · [0002](adr/0002-agent-assistance.md) agent assistance · [0003](adr/0003-in-house-dotfiles.md) configuration files |

See also the [contribution guide](../../CONTRIBUTING.md).
