# Desktop integration (Windows 10)

Reference for the items in `catalog/desktop/`: taskbar, Start menu, desktop shortcuts. The common concepts (preference, policy, HKCU, rollback) are explained in [`../how-it-works.md`](../how-it-works.md).

Principle: **each piece of software declares what it can offer** (pin, shortcut) and the user chooses in the profile's menus. A menu only offers the options of the software actually selected (pinning Vivaldi only appears if Vivaldi is selected).

Legend: **✔** selected by default · **○** offered, unselected by default · **session**: effective at the next sign-in (or when Explorer restarts, which the layout does at the end of the setup).

## Taskbar and Start menu: the layout

### Taskbar and Start menu: layout — `desktop-layout`

Always present in the `base` profile, processed **last** (it restarts Explorer, which also makes the taskbar settings applied before it effective).

- **Why this mechanism**: Windows 10 no longer has an API to pin (removed by Microsoft in 2018; only "unpin" remains possible by script). The official method is a `LayoutModification.xml` file applied by the "Start layout" group policy.
- **Flow**: the engine gathers the pins (`taskbarPin`) and the Start menu layout (`startLayout`) of the selected items into a single file; it enables the **locked** policy (`HKCU\Software\Policies\Microsoft\Windows\Explorer` `StartLayoutFile`, `LockedStartLayout` = 1), restarts Explorer, then **unlocks and removes it** and deletes the file. Explorer is stopped and Windows relaunches it by itself; if it has not done so after 30 s (seen once while an installer was creating its shortcuts), the setup starts it through a temporary scheduled task, **without** its administrator rights (checked in a VM by disabling the automatic restart).
- **Effect**: the taskbar contains exactly the chosen pins, in the order of the menus — those of Windows (Edge, Store, Mail) and those that installers add on their own (Firefox, Brave and Vivaldi do) are removed.
- **Implications**: open Explorer windows close during the setup. The user then stays in control: their changes (pinning, unpinning) are kept, including after a restart (checked in a VM). Rerunning the setup only reapplies the layout if the choices changed: its fingerprint is stored in `HKCU\Software\OS-Setup` `DesktopLayout`.
- **Rollback**: pin or unpin by hand (right-click). Delete the `DesktopLayout` value for the setup to reapply its layout.

### Pins (menu "Épinglés à la barre des tâches", Pinned to the taskbar, everything selected)

| Item | Pin | Offered if |
|---|---|---|
| `pin-explorer` | File Explorer | always |
| `pin-firefox` | Firefox | Firefox is selected |
| `pin-chrome` | Google Chrome | Chrome is selected |
| `pin-brave` | Brave | Brave is selected |
| `pin-vivaldi` | Vivaldi | Vivaldi is selected |
| `pin-discord` | Discord | Discord is selected |
| `pin-windows-terminal` | Windows Terminal (Store app; menu "Épinglés à la barre des tâches (développement)", Pinned to the taskbar (development), of the `dev` profile) | Terminal is selected |

A pin refers to the Start menu shortcut created by the installer (e.g. `{{StartMenu}}\Vivaldi.lnk`), or, for a Store app that has none, its AppUserModelID (e.g. `Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`). Deselecting everything leaves the taskbar as it is.

### Start menu: no tiles — `start-no-tiles`

✔ · menu "Barre des tâches et menu Démarrer" (Taskbar and Start menu)

- **Effect**: the Start menu no longer has tiles (right-hand part): it is reduced to the list of apps.
- **Implications**: the **download tiles** of promoted apps (arrow) also disappear; they used to install an app on first click. You can then pin your own tiles.
- **Mechanism**: `DefaultLayoutOverride` part of the layout file (see `desktop-layout`).
- **Rollback**: right-click an app > "Pin to Start".

## Taskbar and Start menu settings (menu "Barre des tâches et menu Démarrer")

HKCU preferences: they apply even on a non-activated Windows, although the *Personalization* page is locked (rollback through `regedit` in that case).

| Item | Default | Effect | Value | Rollback |
|---|---|---|---|---|
| `taskbar-search-icon` | ✔ | Search box reduced to a magnifier: frees space in the taskbar | `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `SearchboxTaskbarMode` = 1 (0: hidden, 2: full box) | Right-click the taskbar > Search |
| `taskbar-hide-taskview` | ○ | "Task View" button hidden (`Win+Tab` remains available) | `…\Explorer\Advanced` `ShowTaskViewButton` = 0 | Right-click the taskbar |
| `taskbar-hide-people` | ✔ | "People" button hidden (app removed elsewhere) | `…\Explorer\Advanced\People` `PeopleBand` = 0 | Right-click the taskbar |
| `taskbar-hide-meetnow` | ✔ | "Meet Now" button (Skype) hidden in the notification area | user policy `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer` `HideSCAMeetNow` = 1 | `regedit`: delete the value |
| `taskbar-hide-ink` | ✔ | "Windows Ink Workspace" button hidden (only useful with a pen) | `HKCU\Software\Microsoft\Windows\CurrentVersion\PenWorkspace` `PenWorkspaceButtonDesiredVisibility` = 0 | Right-click the taskbar |
| `tray-show-all` | ○ | All notification area icons visible (no more "show hidden icons" arrow) | `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer` `EnableAutoTray` = 0 | Settings > Personalization > Taskbar |
| `start-hide-recent` | ○ | No more "Recently added" section at the top of the Start menu | user policy `HKCU\Software\Policies\Microsoft\Windows\Explorer` `HideRecentlyAddedApps` = 1 | `regedit`: delete the value |
| `desktop-this-pc` | ○ | "This PC" icon on the desktop | `…\Explorer\HideDesktopIcons\NewStartPanel` `{20D04FE0-3AEA-1069-A2D8-08002B30309D}` = 0 | Settings > Personalization > Themes > Desktop icon settings |

### Taskbar: automatically hidden — `taskbar-autohide`

✔ · menu "Barre des tâches et menu Démarrer"

- **Effect**: the taskbar hides and reappears when the mouse touches the screen edge (or with the Windows key). Immediate effect.
- **Implications**: more room for windows; taskbar notifications (a flashing icon, e.g. the Windows Terminal bell) are only visible if the bar reappears — Windows briefly brings it out when an app requests attention.
- **Mechanism**: `taskbar` provider, `SHAppBarMessage` API (the one used by the Settings checkbox), current account. Explorer stores the setting in the binary value `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3` `Settings` (9th byte: `03` hidden, `02` visible), which also holds the bar's position and size; it only writes it when closing normally (sign-out, restart). Writing it directly would only take effect when Explorer restarts, and Explorer would rewrite it when closing. Force-stopped by `desktop-layout`, Explorer would lose the setting applied just before: the setup restores it after that restart (seen in a VM, then fixed).
- **Rollback**: Settings > Personalization > Taskbar > "Automatically hide the taskbar in desktop mode". Page locked on a non-activated Windows: in PowerShell 7, from the setup folder, `Import-Module ./src/OSSetup/OSSetup.psd1; Set-OSSetupTaskbarAutoHide -Enabled $false`.

The other settings above are marked "session": effective when Explorer restarts, which `desktop-layout` does, otherwise at the next sign-in.

## Desktop shortcuts (menu "Raccourcis sur le bureau", Desktop shortcuts, nothing selected)

**Empty desktop by default**: each browser removes the shortcut its installer drops on the desktop (Firefox and Chrome on the public desktop, Brave and Vivaldi on the account's) — unless its shortcut is requested in this menu. Chrome also creates a shortcut on the desktop **of each account**, the first time that account's Explorer starts (the "Active Setup" mechanism, replayed after each Chrome update): the setup merges the options `do_not_create_desktop_shortcut`, `do_not_create_quick_launch_shortcut` and `do_not_create_taskbar_shortcut` into its installation preferences (`initial_preferences`, `merge-json` mode) (checked in a VM: Active Setup replayed without recreating the shortcut), then removes any shortcut already created. An update that recreates the shortcut is fixed when the setup is rerun. Edge's shortcut is handled with Edge's neutralization (browsers).

| Item | Shortcut | Offered if |
|---|---|---|
| `desktop-firefox` | `Firefox.lnk` (public desktop, copy of the Start menu shortcut) | Firefox is selected |
| `desktop-chrome` | `Google Chrome.lnk` (public desktop) | Chrome is selected |
| `desktop-brave` | `Brave.lnk` (account's desktop) | Brave is selected |
| `desktop-vivaldi` | `Vivaldi.lnk` (account's desktop) | Vivaldi is selected |
| `desktop-discord` | `Discord.lnk` (account's desktop) | Discord is selected |

- **Mechanism**: `shortcut` provider — copy of the Start menu shortcut created by the installer (same target, same icon), or deletion.
- **Rollback**: create or delete the shortcut by hand.
