# Common apps (Windows 10)

"Logiciels courants" (Common apps) menu of the `base` profile (`catalog/apps/`): software useful on every machine, installed with winget. Their settings are in the next menu, "Logiciels courants : réglages" (Common apps: settings), which only offers a setting if its software is selected. Taskbar pin and desktop shortcut: see [Desktop integration](desktop.md).

Deliberately absent: an archive tool (Windows already opens `.zip` files), a media player and other utilities, to be added as needed.

## Discord — `discord`

✔ · installed for the user account (no admin) · winget `Discord.Discord`

- **Effect**: installs Discord in `%LOCALAPPDATA%\Discord`. Discord then updates itself on every launch.
- **Implications**:
  - the installer (Squirrel) finishes the installation in the background and then **opens Discord** (sign-in window): the setup waits for the installation to finish before continuing;
  - on this first launch, Discord tries to install **Discord System Helper** (`DiscordSystemHelper.exe`, a service running as administrator): a **UAC prompt** "Discord System Helper", verified publisher Discord Inc., appears during the setup. This component, still experimental and offered to only some accounts, is only used to make Discord's shortcuts (push-to-talk, overlay) work in games launched as administrator. Answering **No** blocks nothing else; with no answer, the prompt closes by itself after 2 minutes, like a refusal. Discord does not offer it again on later launches. To install it later: User Settings > Windows Settings > System Helper (same place to uninstall it);
  - Discord then starts **at every sign-in** (minimized near the clock), unless `discord-no-autostart` is selected;
  - the desktop shortcut created by the installer is removed, unless "Raccourci sur le bureau : Discord" (Desktop shortcut: Discord) is selected.
- **Rollback**: Settings > Apps > Discord > Uninstall.

## No launch at sign-in — `discord-no-autostart`

○ · offered if Discord is selected · startup entry

- **Effect**: Discord no longer starts at sign-in; you open it when you need it. Its notifications (messages, calls) therefore only arrive while it is open.
- **Value**: the `Discord` entry of `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, disabled the way Task Manager does it (Startup tab): `HKCU\…\Explorer\StartupApproved\Run`, value `Discord`, first byte odd. Discord can recreate its entry (the "Open Discord" setting in its own settings); it stays disabled.
- **Rollback**: Task Manager > Startup > Discord > Enable.
