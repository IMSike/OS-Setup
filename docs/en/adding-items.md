# Adding an item to the catalog

An item is a JSON file in `catalog/<category>/`, validated by [`schemas/item.schema.json`](../../schemas/item.schema.json). Adding a piece of software or a setting does not require changing the engine.

## Example

```json
{
  "$schema": "../../schemas/item.schema.json",
  "id": "explorer-show-extensions",
  "name": "Explorateur : extensions de fichiers affichées",
  "category": "system",
  "platforms": ["windows"],
  "notes": "Takes effect when Explorer restarts or at the next session.",
  "actions": [
    {
      "provider": "registry",
      "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
      "name": "HideFileExt",
      "type": "DWord",
      "value": 0
    }
  ]
}
```

The available providers and their parameters are described in [How the setup changes Windows](how-it-works.md#providers); the schema is authoritative.

## Steps

1. **winget package**: find the exact identifier with `winget search <name>`, then `winget show --id <Id> --exact`. The provider always uses `--exact --id`, `--source winget`, `--accept-package-agreements`, `--accept-source-agreements` and `--silent`. Specify the `scope` (`user` or `machine`). See the [winget pitfalls](pitfalls.md#winget-windows-10-winget-129).
2. **Create the file** in the right category:

   | Category | Contents | Documentation |
   |---|---|---|
   | `system/`, `privacy/`, `power/` | Windows settings | [Windows settings](windows/settings.md) |
   | `remove/` | Apps, components and preinstalled software to remove | [Removable apps](windows/removable-apps.md) |
   | `desktop/` | Pins, Start menu, shortcuts, taskbar | [Desktop integration](windows/desktop.md) |
   | `browsers/`, `browser-settings/` | Browsers and their policies | [Browsers](windows/browsers.md) |
   | `drivers/` | Drivers, manufacturer tools | [Drivers](windows/drivers.md) |
   | `dev/` | Development profile | [Development](windows/development.md) |
   | `apps/` | Common software | [Apps](windows/apps.md) |

3. **Name** (`name`) in the form "Subject : state" or "Software : detail" (the setup's UI is French, so names are in French; e.g. "Localisation : désactivée" ("Location: disabled"), "lazygit : interface Git dans le terminal" ("lazygit: Git interface in the terminal")); a piece of software on its own keeps its name ("Firefox"). The subject comes first; the menus display the part after ":" in color. Consequences worth knowing go in `uncheckedWarning` or `checkedWarning`, not in the name.
4. **PATH**: the engine reloads the session PATH after each installation. If the installer does not add the software to the PATH itself, add a `path` action.
5. **Dependencies** (`dependsOn`), **conditions** (`when`), **reboot** (`requiresReboot`) or **logoff** (`requiresLogoff`): see [Architecture](architecture.md#concepts).
6. **Offer it in a profile** (`profiles/`): everything that is installed or removed goes in a choice group, never in `items` (checked at load time).
7. **Document it** in its category's page, **in English and in French**, under its identifier in backticks: effect, implications, modified value (preference or policy, HKCU or HKLM), manual rollback. A test checks that no item is forgotten.
8. **Verify**: `Invoke-Pester -Path tests`, then `./setup.ps1 -WhatIf` shows the expected plan, then a test in a VM ([Testing](testing.md)). For a Windows setting, after a reboot check that the relevant Settings page (or the behavior) is in the expected state: reading a value back does not prove that Windows takes it into account.

## Unlicensed machines

Most target machines are not activated: the personalization pages of Settings are locked on them. A personalization setting must be applied through the registry or a command, and tested on a non-activated machine.
