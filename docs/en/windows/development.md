# Development (Windows 10)

The `dev` profile (`profiles/dev.json`, items in `catalog/dev/`) extends the `base` profile. Its software is offered in the menus, in this order: "Outils de développement" (development tools), "Avec WSL" (with WSL), "Éditeur de code" (code editor), "Extensions VS Code" (VS Code extensions), "JavaScript / TypeScript", "Agents et terminal" (agents and terminal), "Logiciels de développement" (development software), "Comptes (étapes manuelles guidées)" (accounts, guided manual steps), "Extensions GitHub CLI" (GitHub CLI extensions) and "Épinglés à la barre des tâches (développement)" (pinned to the taskbar, development). A menu only offers what depends on items checked earlier (e.g. VS Code extensions are not offered without VS Code). The profile's settings (its `items`) are applied automatically when the related software is chosen, and ignored otherwise. Concepts shared across pages (JSON merge, backup, rollback, manual steps) are explained in [`../how-it-works.md`](../how-it-works.md).

Legend: **✔** checked by default · **○** offered, unchecked by default · **auto**: applied when its dependencies are chosen · **technical**: added automatically as a dependency, never offered.

"Portable" winget packages (fnm, pnpm, lazygit, rtk): winget unpacks them into `%LOCALAPPDATA%\Microsoft\WinGet\Packages` and creates the command in `%LOCALAPPDATA%\Microsoft\WinGet\Links`, which is added to the account's PATH; they are uninstalled with `winget uninstall --id <Id>`.

## Projects folder — `dev-root`

auto · folder

- **Effect**: creates the root folder for projects, `{{DevRoot}}` (by default `Documents\repo`, which can be changed with "Personaliser les emplacements ?" (customize locations?) or in the answer file).
- **Rollback**: delete the folder if it is empty.

## Git — `git`

✔ · admin · winget `Git.Git` (machine-wide)

- **Effect**: installs Git for Windows, with Git Bash and Git Credential Manager (HTTPS sign-in to code forges, token stored in the Windows credential manager).
- **Rollback**: Settings > Apps > Git > Uninstall.

### Git configuration — `git-config`, `git-identity`, `git-vscode`

auto (with `git`) · `git-config` provider: `git config --global <key> <value>`, in `%USERPROFILE%\.gitconfig`

Key by key: the user's other settings are kept, and a key changed on the machine is reset to the repository's value when the setup is run again. The previous value of each key is recorded in the original values.

| Item | Key | Value | Effect (Git default in parentheses) |
|---|---|---|---|
| `git-config` | `init.defaultBranch` | `main` | Initial branch of a new repository (`master`) |
| | `core.autocrlf` | `input` | Line endings: CRLF converted to LF on commit, nothing converted on checkout (`true` set by the Git for Windows installer: LF → CRLF on checkout). Files that must stay CRLF are declared in the project's `.gitattributes` |
| | `core.longpaths` | `true` | Paths longer than 260 characters accepted (deep `node_modules` folders) |
| | `pull.rebase` | `true` | `git pull` replays local commits on top of the remote branch instead of creating a merge commit |
| | `rebase.autoStash` | `true` | Uncommitted changes are stashed and restored around a rebase (including `pull`) |
| | `push.autoSetupRemote` | `true` | First `git push` of a new branch: remote branch created and tracked, no `--set-upstream` needed |
| | `fetch.prune` | `true` | Remote branches that were deleted also disappear locally on every `fetch`/`pull` |
| | `merge.conflictStyle` | `zdiff3` | Conflict shown with the common original version in addition to the two sides (`merge`) |
| `git-identity` | `user.name`, `user.email` | asked at run time | Commit author. **Personal information**: never in the repository, asked by the wizard's "Informations personnelles" (personal information) step; if not provided, the item is skipped (reported in the plan) |
| `git-vscode` (with `vscode`) | `core.editor` | `code --wait` | Commit messages and interactive rebase: edited in VS Code |
| | `diff.tool`, `difftool.vscode.cmd` | `vscode`, `code --wait --diff "$LOCAL" "$REMOTE"` | `git difftool` opens the comparison in VS Code |
| | `merge.tool`, `mergetool.vscode.cmd` | `vscode`, `code --wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED"` | `git mergetool` opens VS Code's three-way merge editor |

- **Rollback**: `git config --global --unset <key>` (or edit `%USERPROFILE%\.gitconfig`).

## GitHub CLI — `gh`, `gh-auth`, `gh-dash`

`gh`: ✔ · admin · winget `GitHub.cli` (MSI, machine-wide)

- **Effect**: the `gh` command: repositories, pull requests, issues and GitHub Actions from the terminal.
- **Rollback**: Settings > Apps > GitHub CLI > Uninstall.

`gh-auth`: ✔ · "Comptes (étapes manuelles guidées)" menu · `manual` provider

- **Effect**: signs `gh` in to github.com over **HTTPS** (`gh auth login --web --git-protocol https`), in the setup console: gh displays a one-time code and opens the sign-in page (through Explorer, so in the browser without administrator rights). If gh offers to connect Git with this account, answer yes: `git push` to GitHub then no longer needs credentials.
- **Check**: `gh auth status --hostname github.com`. "Passer" (skip) leaves the step for later; unattended, it is reported without running anything.
- **Implications**: token stored in the Windows credential manager. No SSH key (HTTPS chosen: nothing to generate or register on GitHub, and it works behind firewalls that block port 22).
- **Rollback**: `gh auth logout`.

`gh-dash`: ✔ (if `gh-auth` is checked) · "Extensions GitHub CLI" menu · `gh-extension` provider

- **Effect**: `gh dash`, a pull request and issue dashboard in the terminal ([dlvhdr/gh-dash](https://github.com/dlvhdr/gh-dash)).
- **Implications**: `gh extension install` requires gh to be signed in: skipped if the `gh-auth` step was skipped.
- **Rollback**: `gh extension remove dlvhdr/gh-dash`.

`gh-dash-config`: auto (with `gh-dash`) · `file` provider (copy of `dotfiles/gh-dash/config.yml` to `%USERPROFILE%\.config\gh-dash\config.yml`)

- **Effect**: dashboard sections — PRs ("My Pull Requests", "Needs My Review", "Involved", "All"), issues (created, assigned, involved) and notifications by reason; preview opened on the right (45%), 20 items per section, columns and widths, refresh every 30 min, no confirmation on quit.
- **Implications**: the file is replaced entirely (copy, the existing one is backed up): a manual customization is overwritten when the setup is run again; carry it over into the repository. "All" (`is:open`, added to gh-dash's default sections) lists all open PRs of the repository when `gh dash` is run inside a repository: smart filtering (`smartFilteringAtLaunch`) then adds `repo:<repository>` to each section (`t` key to remove it). Run outside a repository, this section covers all of GitHub and is not useful.
- **Rollback**: delete `%USERPROFILE%\.config\gh-dash\config.yml` (gh-dash goes back to its defaults).

## lazygit — `lazygit`

✔ · winget `JesseDuffield.lazygit` (portable)

- **Effect**: the `lazygit` command, a full-screen Git interface in the terminal (line-by-line staging, interactive rebase, conflict resolution). Icons with the Nerd Font.
- **Rollback**: `winget uninstall --id JesseDuffield.lazygit`.

## PowerShell 7 — `pwsh`

✔ · admin · winget `Microsoft.PowerShell` (MSI, machine-wide)

- **Effect**: installs PowerShell 7 alongside Windows PowerShell 5.1 (which stays: it is a Windows component). Not pinned to the taskbar: it is used from Windows Terminal.
- **Implications**: the default package is an MSIX, which cannot be installed machine-wide on Windows 10: the MSI is forced.
- **Rollback**: Settings > Apps > PowerShell 7 > Uninstall.

### PowerShell 7 profile — `pwsh-profile`

auto (with `pwsh`) · template file

- **Effect**: deploys `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` from `dotfiles/powershell/`: the `DEV_ROOT` variable, the `dev` command (go to the projects folder), fnm integration if fnm is installed (the project's Node.js version, see `node-lts`), and a Playwright CLI session specific to each terminal (`PLAYWRIGHT_CLI_SESSION` = `term-<process number>`, see `playwright-cli`).
- **Implications**: the existing file is backed up and then replaced; a change made on the machine is overwritten when the setup is run again (edit the repository instead).
- **Rollback**: restore the backup (`state\backups\…`) or delete the file.

## Windows Terminal — `windows-terminal`

✔ · per account · winget `Microsoft.WindowsTerminal`

- **Effect**: installs Windows Terminal (tabs, panes, modern rendering), then updated by winget.
- **Implications**: Store application (MSIX), installed for the account: machine-wide installation is not supported on Windows 10. On Windows 10, Terminal cannot become the default terminal of Windows (Windows 11 only): a script launched by double-click still opens in the classic console.
- **Rollback**: Settings > Apps > Windows Terminal > Uninstall.

### Windows Terminal settings

File `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`, **merged** (`merge-json`): only the keys managed by the repository are written, Terminal fills in the rest itself (detected profiles, etc.) and other settings made on the machine are kept. Works before Terminal's first launch (the file is then created with only the managed keys). The existing file is backed up before modification.

| Item | Applied if | Effect | Value (`dotfiles/windows-terminal/`) |
|---|---|---|---|
| `terminal-settings` | Terminal chosen | Appearance and behavior, detailed below | `settings.json` |
| `terminal-pwsh-default` | Terminal and PowerShell 7 chosen | A new tab or window opens PowerShell 7 | `pwsh-default.json`: `defaultProfile` = `{574e775e-4f2a-5b96-ac1e-a2962a402336}` (fixed identifier of the PowerShell 7 profile detected by Terminal) |
| `terminal-font` | Terminal and the font chosen | JetBrainsMono Nerd Font in all profiles | `font.json`: `profiles.defaults.font.face` |

Details of `terminal-settings` (Terminal default in parentheses):

| Key | Value | Effect |
|---|---|---|
| `theme` | `dark` (the Windows one) | Window and tabs in dark theme |
| `launchMode` | `maximized` (120 × 30 characters) | Window maximized on opening |
| `firstWindowPreference` | `persistedLayoutAndContent` (new tab) | On reopening, tabs, panes and their displayed content are restored (the programs that were running in them are not relaunched). Former name `persistedWindowLayout`, which Terminal renames itself: the repository uses the new one to stay compliant when the setup is run again |
| `copyOnSelect` | `true` (`false`) | Selecting text copies it, without `Ctrl+C` |
| `keybindings` | `Ctrl+C` copy, `Ctrl+V` paste, `Alt+Shift+D` duplicate pane (same list) | Shortcuts that Terminal writes into its file at its first launch (they have not been part of its defaults since version 1.21). The setup creates the file before that first launch: without this list, `Ctrl+V` was not a Terminal shortcut and was passed as is to the program (Claude Code did not paste the text; `Ctrl+Shift+V` worked). The list replaces that of an existing file (backed up beforehand) |
| `disabledProfileSources` | `Windows.Terminal.Azure` (none) | Azure Cloud Shell profile removed from the list; Windows PowerShell 5.1 and the Command Prompt remain |
| `profiles.defaults.font.size` | `8` (12) | Font size, for all profiles |
| `profiles.defaults.useAcrylic`, `opacity` | `true`, `80` (no transparency) | Transparent, blurred background (acrylic effect): 80 lets you see what is behind the window well. The blur cannot be adjusted, only the opacity. On Windows 10, transparency is only possible with the acrylic effect; transparency without blur (`useAcrylic` = `false`) only exists on Windows 11 (to be offered with Windows 11 support). Live test: Ctrl+Shift+mouse wheel in the terminal |
| `compatibility.enableUnfocusedAcrylic` | `true` (`false`) | The acrylic effect stays when the window is not active (otherwise the background becomes opaque again) |
| `profiles.defaults.colorScheme` | `One Half Dark` (Campbell) | Color scheme shipped with Terminal |
| `profiles.defaults.padding` | `1` (8) | 1-pixel inner margin around the text |
| `profiles.defaults.bellStyle` | `taskbar` (sound) | The "bell" character no longer makes a sound: the icon flashes in the taskbar (useful to see that a program, e.g. an agent, is waiting for an answer) |
| `profiles.defaults.historySize` | `20000` (9,001) | Lines kept in the scrollback history |

- **Rollback**: Terminal > Settings (or `Ctrl+,`), or remove the key from `settings.json`. A setting changed on the machine is reset to the repository's value when the setup is run again (only the keys above are concerned).

## JetBrainsMono Nerd Font — `nerd-font`

✔ · admin · winget `DEVCOM.JetBrainsMonoNerdFont`

- **Effect**: installs, machine-wide, the JetBrains Mono font completed with the [Nerd Fonts](https://www.nerdfonts.com/) icons (Git, folders, languages, prompt arrows), displayed by lazygit, herdr or an enriched command prompt. The only Nerd Font available in winget; usable in Terminal, VS Code and any monospaced-font software.
- **Implications**: 96 font files in `C:\Windows\Fonts`. Three families: "JetBrainsMono Nerd Font" (double-width icons, for terminals), "… Nerd Font Mono" (single-width icons), "… Nerd Font Propo" (proportional); Windows shows them under the short names "JetBrainsMono NF", "NFM", "NFP".
- **Rollback**: Settings > Apps > JetBrainsMono Nerd Font > Uninstall.

## Code editors — `vscode`, `cursor`

"Éditeurs de code" (code editors) menu, both checked: you can keep one, the other or both. Cursor is derived from VS Code: it receives the **same settings** (same files from `dotfiles/vscode/`), plus a few settings of its own.

`vscode`: ✔ · per account · winget `Microsoft.VisualStudioCode`

- **Effect**: installs the VS Code editor in the user's profile, updated by itself.
- **Rollback**: Settings > Apps > Microsoft Visual Studio Code > Uninstall.

`cursor`: ✔ · per account · winget `Anysphere.Cursor`

- **Effect**: installs the Cursor editor (VS Code with a built-in agent and completion) in the user's profile, updated by itself; `cursor` command. Distinct from Cursor CLI (`cursor-agent`, "Agents et terminal" menu).
- **Implications**: a Cursor account is requested at first launch. Its extensions come from [Open VSX](https://open-vsx.org/) and not from the Microsoft Marketplace.
- **Rollback**: Settings > Apps > Cursor > Uninstall.

### Editor settings

JSON merge (`file` provider, `merge-json` mode) into `%APPDATA%\Code\User\settings.json` (VS Code) and `%APPDATA%\Cursor\User\settings.json` (Cursor): only the listed keys are enforced, the user's other settings are kept; the existing file is backed up. These files accept comments, but a merge removes them (the file is rewritten).

| Item (VS Code / Cursor) | Condition | Settings (file in `dotfiles/vscode/`) | Effect (default value) |
|---|---|---|---|
| `vscode-settings` / `cursor-settings` | editor chosen | `editor.formatOnSave`: `true` (`false`); `editor.codeActionsOnSave`: `source.organizeImports` and `source.fixAll` set to `always` | On every save: formatting, imports sorted and unused ones removed, automatic fixes (ESLint included) |
| | | `editor.detectIndentation`: `false` (`true`); `editor.insertSpaces`: `false` (`true`) | Tab indentation everywhere, without guessing from the file (a project can enforce otherwise in its `.vscode/settings.json` or `.editorconfig` with the EditorConfig extension) |
| | | `editor.minimap.enabled`: `false` (`true`); `workbench.tree.indent`: `20` (8) | No minimap on the right; explorer tree more indented |
| | | `argv.json`: `enable-crash-reporter`: `false` (`true`), in `%USERPROFILE%\.vscode\` / `%USERPROFILE%\.cursor\` | No crash report sent (applied when the editor restarts) |
| `vscode-prettier` / `cursor-prettier` | Prettier extension chosen | `editor.defaultFormatter`: `esbenp.prettier-vscode`; `prettier.*` (`prettier.json`) | Prettier formats by default. Style applied **only to projects without a Prettier configuration** (`.prettierrc`…): tabs of width 4, no semicolons, single quotes (JSX included), 120-character lines, consistent quoting of object keys, indentation of `<script>`/`<style>` in Vue; TS, JS, TSX, JSX and JSON files |
| `vscode-terminal-pwsh` / `cursor-terminal-pwsh` | PowerShell 7 chosen | `terminal.integrated.defaultProfile.windows`: `PowerShell` (`PowerShell`, already) | The integrated terminal opens the "PowerShell" profile, which the editor points to PowerShell 7 when it is installed (Windows PowerShell 5.1 otherwise): enforced so that the choice stays explicit, as in Windows Terminal |
| `vscode-terminal-font` / `cursor-terminal-font` | Nerd Font chosen | `terminal.integrated.fontFamily`: `JetBrainsMono Nerd Font` (editor font) | Icons of lazygit, herdr and an enriched prompt displayed in the integrated terminal |
| `vscode-wsl` / `cursor-wsl` | WSL chosen | `security.allowedUNCHosts`: `["wsl.localhost"]` (empty) | Open a file from a WSL distribution (`\\wsl.localhost\…`) without a security warning. Replaces the existing list |

Cursor-specific settings (`cursor-settings`, file `dotfiles/cursor/settings.json`):

| Setting | Value (default in parentheses if known) | Effect |
|---|---|---|
| `workbench.colorTheme` | `Cursor Dark High Contrast` | High-contrast dark theme |
| `window.autoDetectColorScheme` | `false` | The theme does not follow the Windows light/dark mode |
| `window.commandCenter` | `true` | Search and command bar in the center of the title bar |
| `crashReporting.enabled` | `off` | No crash report sent |
| `cursor.cpp.enablePartialAccepts` | `true` (`false`) | A completion suggestion (Tab) can be accepted word by word (`Ctrl+→`) |
| `cursor.composer.usageSummaryDisplay` | `always` | Usage (requests, tokens) displayed after each agent response |

Deliberately absent: `css.validate`/`scss.validate` set to `false` (they would disable CSS checking in all projects: a Tailwind project disables them in its own `.vscode/settings.json`, or uses the Tailwind CSS IntelliSense extension), `javascript.format.*` (no effect when Prettier formats), empty `json.schemas`, `cursor.general.disableHttp2` (workaround for a proxy that breaks HTTP/2, useless on a normal network).

- **Rollback**: remove the keys from `settings.json` (editor Settings > "Open Settings (JSON)" icon), or restore the setup's backup.

### Extensions — `vscode-eslint`, `vscode-prettier`, `cursor-*`

✔ · "Extensions VS Code" and "Extensions Cursor" menus · `vscode-extension` provider (`code --install-extension <id>` or `cursor --install-extension <id>`, per account, in `%USERPROFILE%\.vscode\extensions` or `%USERPROFILE%\.cursor\extensions`)

| Item | Extension | Effect |
|---|---|---|
| `vscode-eslint`, `cursor-eslint` | `dbaeumer.vscode-eslint` | The project's ESLint errors displayed in the editor (uses the ESLint installed in the project) |
| `vscode-prettier`, `cursor-prettier` | `esbenp.prettier-vscode` | Formatting by Prettier (uses the project's Prettier and configuration); with its settings (above) |
| `cursor-remote-wsl` (with WSL) | `anysphere.remote-wsl` | Open a folder of a WSL distribution: the editor works inside Linux (terminal, tools, extensions) |
| `cursor-remote-ssh` | `anysphere.remote-ssh` | Work on a remote machine over SSH |
| `cursor-remote-containers` (with Docker Desktop) | `anysphere.remote-containers` | Open a project in a development container (`.devcontainer`) |

- **Implications**: the editor then updates them itself. Cursor's "remote" extensions are those of its publisher (Anysphere), equivalent to Microsoft's for VS Code (not installed here).
- **Rollback**: Extensions > Uninstall, or `code --uninstall-extension <id>` (`cursor --uninstall-extension <id>`).

## Node.js and TypeScript — `fnm`, `node-lts`, `pnpm`, `typescript-global`

`fnm`: technical (with `node-lts`) · winget `Schniz.fnm` (portable)

- **Effect**: [fnm](https://github.com/Schniz/fnm), a Node.js version manager: several versions installed side by side (in `%APPDATA%\fnm`), each project using the one it asks for. Chosen over nvm-windows: faster, cross-platform (same tool on Fedora), reads `.nvmrc` and `.node-version`, switches version automatically when entering a folder.

`node-lts`: ✔ · "JavaScript / TypeScript" menu · `fnm-node` provider

- **Effect**: installs the latest LTS version of Node.js (with npm) and makes it the default version (`fnm install --lts`, `fnm default lts-latest`). The folder of this default version (`%APPDATA%\fnm\aliases\default`) is added to the account's PATH: `node` and `npm` work everywhere (Git Bash, hence Claude Code; command prompt; applications). In PowerShell 7, the profile (`pwsh-profile`) enables the fnm integration: when entering a project, the version from its `.nvmrc` or `.node-version` is used (fnm offers to install it if it is missing).
- **Implications**: a new LTS is not installed automatically: `fnm install --lts` then `fnm default lts-latest`. Global npm packages are specific to each Node.js version.
- **Rollback**: `fnm uninstall <version>`, remove the folder from the account's PATH, `winget uninstall --id Schniz.fnm`.

`pnpm`: ✔ · winget `pnpm.pnpm` (portable)

- **Effect**: the pnpm package manager (dependencies shared between projects, faster installs), as a standalone executable: independent of the Node.js version. npm remains available with Node.js.
- **Rollback**: `winget uninstall --id pnpm.pnpm`.

`typescript-global`: ○ · `npm-global` provider (`npm install --global typescript`)

- **Effect**: the `tsc` command available outside any project (quick experiments, scripts).
- **Implications**: unchecked by default because each project declares its own TypeScript version (`devDependencies`) and uses it through `npx tsc` or its scripts: a global `tsc` may differ from the project's and hide an omission. Installed for the default Node.js version only.
- **Rollback**: `npm uninstall --global typescript`.

## Agents and terminal — `claude-code`, `rtk`, `rtk-claude`, `cursor-cli`, `herdr`

"Agents et terminal" menu, everything checked. Claude Code, Cursor CLI and herdr are installed with their publisher's **official script** (`install-script` provider, `irm <url> | iex` in Windows PowerShell): this is the recommended method, with automatic updates. The scripts were reviewed before being added to the catalog; they install into the account's profile, without administrator rights.

| Item | Installation | Command | Rollback |
|---|---|---|---|
| `claude-code` (depends on Git: Claude Code uses Git Bash) | script `https://claude.ai/install.ps1`: `%USERPROFILE%\.local\bin\claude.exe`. The script does not add this folder to the PATH: the setup does it (account PATH) | `claude` | `claude uninstall` or delete `%USERPROFILE%\.local\bin\claude.exe` and `%USERPROFILE%\.claude` |
| `rtk` | winget `rtk-ai.rtk` (portable), with `vcredist` | `rtk` | `winget uninstall --id rtk-ai.rtk` |
| `cursor-cli` (depends on Git) | script `https://cursor.com/install?win32=true`: `%LOCALAPPDATA%\cursor-agent`, added to the account PATH | `cursor-agent` or `agent` | delete `%LOCALAPPDATA%\cursor-agent` and the PATH entry |
| `herdr` | script `https://herdr.dev/install.ps1` (stable version): `%USERPROFILE%\.herdr`, version folder added to the account PATH | `herdr` | delete `%USERPROFILE%\.herdr` and the PATH entry |

- **Claude Code**: installation and basic settings (below). The full configuration (skills, plugins, MCP, memory location, carrying over the data of an existing installation) is not covered yet.
- **rtk** ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)): rewrites the commands run by agents to summarize their output (fewer tokens consumed).
- **`rtk-claude`** (auto, with `rtk` and `claude-code`, `rtk-init` provider): `rtk init --global --auto-patch` adds the `PreToolUse` hook (`rtk hook claude`, on the Bash tool) to `%USERPROFILE%\.claude\settings.json`, creates `RTK.md` and its `@RTK.md` reference in `%USERPROFILE%\.claude\CLAUDE.md`. Check: `rtk init --show`. rtk first asks whether it may send anonymous usage statistics; with no recorded answer, the question would block the setup: the refusal is recorded (`rtk telemetry disable`), and can be changed with `rtk telemetry enable`. Rollback: `rtk init --global --uninstall`.
- **herdr** ([herdrdev/herdr](https://github.com/herdrdev/herdr)): settings and plugin below.

### Playwright CLI — `playwright-cli`, `playwright-skill-claude`, `playwright-skill-agents`, `playwright-chrome`, `playwright-msedge`, `playwright-chromium`, `playwright-firefox`

`playwright-cli`: ✔ · "Agents et terminal" menu (if Node.js chosen) · `npm-global` provider (`@playwright/cli`)

- **Effect**: the `playwright-cli` command ([microsoft/playwright-cli](https://github.com/microsoft/playwright-cli)) with which **all agents** drive a browser (open a page, click, fill in, screenshot, network requests…). Replaces the Playwright MCP server: nothing to configure in each agent, and fewer tokens consumed (no tool schemas or page tree injected into the conversation).
- **Isolation between agents** (verified in a VM): each **named session** (`playwright-cli -s=<name> …`, or the `PLAYWRIGHT_CLI_SESSION` variable for a whole agent) has its own browser, with an **in-memory** profile (own cookies, storage and tabs, lost on close); two different folders, including two worktrees of the same repository, each have their own browser. Two agents launched in the same folder without a session name would share the `default` session (same tabs), and the skill does not tell them to pick one: the PowerShell profile (`pwsh-profile`) therefore gives **each terminal** (window, tab, herdr pane, editor terminal) its own session, inherited by the agents launched in it. What remains is the case of sub-agents of the same agent working in parallel (same terminal): not covered yet. The MCP, for its part, used a persistent profile by default that only one instance can open at a time.
- **Implications**: headless by default (`open --headed` to see the browser); a headless session closes after 1 h without a command. `playwright-cli list` lists the sessions, `close-all` closes them.
- **Rollback**: `npm uninstall --global @playwright/cli`.

`playwright-skill-claude` (auto, with Claude Code) and `playwright-skill-agents` (auto, with Cursor CLI) · `playwright-cli` provider

- **Effect**: `playwright-cli install --skills --global` installs the skill that teaches the command to Claude Code (`%USERPROFILE%\.claude\skills\playwright-cli`); `--skills=agents` installs it for the other agents (`%USERPROFILE%\.agents\skills\playwright-cli`, a folder shared by agents that follow the "Agent Skills" convention).
- **Implications**: Cursor CLI's support for `~/.agents/skills` is not confirmed (without the skill, an agent can read `playwright-cli --help`).
- **Rollback**: delete the skill's `playwright-cli` folder.

"Navigateur de Playwright CLI" (Playwright CLI browser) menu (single choice) · file `%USERPROFILE%\.playwright\cli.config.json` (the CLI's global settings, copy of `dotfiles/playwright/<browser>.json`; a project can have its own in `.playwright/cli.config.json`)

| Item | Browser | Disk space | Condition |
|---|---|---|---|
| `playwright-chrome` (default) | Google Chrome installed on the machine (`channel` `chrome`) | none extra | Chrome chosen among the browsers. Without Chrome, the CLI fails ("Chromium distribution 'chrome' is not found"): choose another browser |
| `playwright-msedge` | Microsoft Edge from Windows (`channel` `msedge`) | none extra | Windows 10 (Edge stays installed there, neutralized) |
| `playwright-chromium` | Chromium provided by Playwright, downloaded by `playwright-cli install-browser chromium` | ~720 MB (Chromium and its headless version) | — |
| `playwright-firefox` | Firefox provided by Playwright (`install-browser firefox`) | ~350 MB | — |

- **Implications**: the browsers provided by Playwright go into `%LOCALAPPDATA%\ms-playwright`; a CLI update may download a new revision (Playwright deletes revisions that are no longer used). Using the machine's Chrome or Edge avoids this disk space. Any browser can still be used occasionally: `playwright-cli open --browser=firefox`.
- **Rollback**: delete `%USERPROFILE%\.playwright\cli.config.json` (Chrome by default); downloaded browsers: delete their folder in `%LOCALAPPDATA%\ms-playwright`.

### Claude Code settings — `claude-settings`, `claude-bypass-permissions`, `claude-statusline`

JSON merge (`file` provider, `merge-json` mode) into `%USERPROFILE%\.claude\settings.json` (account settings, valid in all projects): only the listed keys are enforced; the rtk hook and other settings are kept. Claude Code rereads the file on the fly.

`claude-settings`: auto (with `claude-code`) · `dotfiles/claude/settings.json`

| Setting | Value | Effect |
|---|---|---|
| `model`, `advisorModel` | `opus` | Default model (and advisor): Opus |
| `effortLevel` | `xhigh` | Very high reasoning effort: more thoughtful answers, slower and more costly in quota |
| `language` | `French` | Claude answers in French |
| `theme`, `editorMode`, `verbose` | `dark`, `normal`, `true` | Dark theme, input without vim mode, detailed tool output |
| `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `autoCompactEnabled` | `30`, `1000000`, `true` | Automatic compaction of the conversation, triggered at 30% of a context window counted as 1 million tokens |
| `env.CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`, `env.CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | `30`, `30` | Up to 30 tools and 30 sub-agents in parallel |
| `env.DISABLE_TELEMETRY`, `env.DISABLE_ERROR_REPORTING`, `env.DISABLE_FEEDBACK_COMMAND` | `1` | No usage statistics or error reports sent; `/feedback` command removed |
| `attribution` | empty, `sessionUrl`: `false` | No "Co-Authored-By: Claude" mention in commits, and no session link in PRs |
| `dialogExpiry`, `preferredNotifChannel` | `60s`, `auto` | Dialog box timeout; notification channel chosen according to the terminal |
| `autoUpdatesChannel` | `latest` | Updates as soon as they are published |
| `autoContinueAtUsageLimit` | `true` | Resumes by itself when the usage limit is lifted |

Deliberately absent: `SHELL` (Claude Code finds Git Bash on its own), hooks (rtk writes its own; herdr's is installed and rewritten by herdr), plugins and skills (not covered yet).

`claude-bypass-permissions`: ✔ · "Claude Code : options" (Claude Code: options) menu · `dotfiles/claude/bypass-permissions.json`

- **Effect**: `permissions.defaultMode` = `bypassPermissions`, `skipDangerousModePermissionPrompt` and `skipAutoPermissionPrompt` = `true`: Claude runs commands and makes changes **without asking for permission**, and without the launch warning of this mode.
- **Implications**: the agent can do anything with the account's rights (delete files, run any command, access the network). Maintainer's choice, checked by default; unchecking it keeps the permission prompts.
- **Rollback**: remove these three keys (or `/config` > default permission mode).

`claude-statusline`: ✔ · "Claude Code : options" menu · with `jq`

- **Effect**: status bar below the input: model, context used (percentage and gauge), 5-hour and 7-day usage limits… The `statusline-command.sh` script (bash, run by Git Bash) reads the JSON passed by Claude Code with `jq` and follows the `statusline-config.json` description (lines, segments, icons, colors); both are copied into `%USERPROFILE%\.claude\`, and `statusLine` = `bash ~/.claude/statusline-command.sh`.
- **Implications**: requires `jq` in the PATH (installed automatically); icons readable with the Nerd Font. winget puts `jq` in a folder already in the PATH: no machine-specific path is needed.
- **Rollback**: remove `statusLine` from `settings.json`, delete the two files.

`jq`: technical (with `claude-statusline`) · per account · winget `jqlang.jq` (portable)

- **Effect**: the `jq` command, reading and transforming JSON on the command line.
- **Rollback**: `winget uninstall --id jqlang.jq`.

### herdr settings — `herdr-config`, `herdr-explorer`

`herdr-config`: auto (with `herdr` and PowerShell 7) · copy of `dotfiles/herdr/config.toml` to `%APPDATA%\herdr\config.toml`

| Setting | Value (default) | Effect |
|---|---|---|
| `onboarding` | `false` | No first-launch screen (notification choice) |
| `theme.name` | `gruvbox` (`catppuccin`) | Color theme |
| `terminal.default_shell` | `pwsh.exe` | New panes open PowerShell 7 |
| `ui.sidebar_width` | `26` | Sidebar width |
| `ui.mouse_scroll_lines` | `5` | Lines scrolled per mouse wheel notch |
| `ui.prompt_new_tab_name` | `false` | New tab created without asking for its name |
| `ui.pane_gaps` | `false` | Panes separated by a shared border |
| `ui.toast.delivery` | `system` (`off`) | Windows notifications when an agent has finished or is waiting for an answer in a background workspace |
| `experimental.pane_history` | `false` | Pane history not kept after a herdr server restart |

- **Implications**: only the differences from the defaults are deployed. The file is replaced entirely (TOML, no merge; the existing one is backed up): a setting changed in herdr (`prefix+s`) is overwritten when the setup is run again; carry it over into the repository.
- **Rollback**: delete `%APPDATA%\herdr\config.toml` (defaults).

`herdr-explorer`: ✔ · "Plugins herdr" (herdr plugins) menu (if Node.js chosen) · `herdr-plugin` provider

- **Effect**: third-party plugin [gcaudan/herdr-explorer](https://github.com/gcaudan/herdr-explorer): file explorer, preview, search and Git tracking (source control) in each tab. Installed by `herdr plugin install gcaudan/herdr-explorer` (clone managed by herdr, updated by `herdr plugin update`); presence checked in `%APPDATA%\herdr\plugins.json`. The settings file deployed is then `config-explorer.toml` (same settings, plus the plugin's shortcuts, which this installation method does not add): `prefix+f` explorer, `prefix+a` go to a file, `prefix+d` Git tracking. Plugin settings merged into `%LOCALAPPDATA%\herdr\plugins\gcaudan.explorer\settings.json` (`explorer-settings.json`, other settings are kept): `autoOpen` = `false` (the explorer no longer opens by itself in each new tab, only with `prefix+f`) and `side` = `right` (anchored on the right).
- **Implications**: requires Node.js 20 or later (`node-lts`), Git and a Nerd Font. Third-party code run by herdr.
- **Rollback**: `herdr plugin uninstall gcaudan.explorer`, then remove the three shortcuts from `config.toml`. Settings: `,` key in the explorer, or edit `settings.json`.

### Microsoft Visual C++ Redistributable — `vcredist`

technical (with `rtk`) · admin · winget `Microsoft.VCRedist.2015+.x64`

- **Effect**: Visual C++ runtime libraries (`vcruntime140.dll`…), absent from a fresh Windows. Without them, rtk does not start (code `0xC0000135`, "DLL not found", with no message): observed in a VM, rtk's winget package does not declare them.
- **Rollback**: Settings > Apps > Microsoft Visual C++ 2015-2022 Redistributable (x64) — other software may need it.

## Development software — `postman`, `pgadmin`

✔ · "Logiciels de développement" menu

| Item | Package | Effect | Rollback |
|---|---|---|---|
| `postman` | winget `Postman.Postman` (per account) | API client (HTTP requests, collections). Postman account optional | Settings > Apps > Postman |
| `pgadmin` | winget `PostgreSQL.pgAdmin` | PostgreSQL database administration (e.g. a project's database run by Docker, below) | Settings > Apps > pgAdmin 4 |

## WSL — `wsl`, `wsl-platform`

✔ · admin · Windows features + winget `Microsoft.WSL`

- **Effect**: `wsl-platform` (added automatically) enables the "Windows Subsystem for Linux" and "Virtual Machine Platform" features; after the restart (done and resumed automatically), `wsl` installs WSL 2 (the version distributed outside Windows). It also writes `OOBEComplete` = 1 (DWORD, HKCU preference, `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`): without this value, WSL opens a "Welcome to WSL" window (feature presentation) when a distribution first starts, then writes it itself. Without it, the window opens at the first sign-in, when Docker Desktop starts its distribution.
- **Implications**: requires virtualization enabled in the BIOS/UEFI; one restart. Docker Desktop runs its engine in WSL 2: WSL starts with it (`docker-desktop` distribution, which it stops after a few minutes without containers).
- **Rollback**: Settings > Apps > Windows Subsystem for Linux > Uninstall, then "Turn Windows features on or off". To see the welcome window again: Start menu > WSL Settings.

### WSL memory — `wsl-config`

auto (with `wsl`) · `wsl-config` provider (`memory` key of the `[wsl2]` section of `%USERPROFILE%\.wslconfig`)

- **Effect**: caps the WSL 2 VM's memory at **40% of RAM** (WSL otherwise takes up to half). Docker Desktop runs in this VM: the cap applies to it too. Linux keeps files it has read in cache as long as it is not short of memory; a lower cap forces it to release this cache before Windows runs out of memory (without a cap, more than 18 GB of cache held by the VM were observed).
- **Hardware safety**: the value is computed on the machine, not hard-coded: an answer file replayed on a smaller machine remains valid. Bounds: at least 2 GB for WSL, at least 4 GB left to Windows; a value brought back within these bounds is reported in the log. Below 6 GB of RAM, no cap is written (WSL default). Examples: 16 GB → 6 GB; 32 GB → 12 GB; 64 GB → 25 GB.
- **Implications**: only this key is written, the rest of the file is kept (backed up before modification). Applied at the next WSL start (`wsl --shutdown` to apply it right away). `autoMemoryReclaim` (returning the cache to Windows) is not written: `dropCache` is already WSL's default value.
- **Rollback**: remove the `memory=` line from `%USERPROFILE%\.wslconfig`.

### Linux distributions — `wsl-ubuntu`, `wsl-fedora`

○ · "Avec WSL" menu · `manual` provider (guided manual step)

Optional: only useful for working in a Linux terminal (Linux-specific tools, projects to build under Linux). **Docker Desktop does not need them**: it installs its own internal distribution (`docker-desktop`), with no user account, and `docker` works from Windows.

| Item | WSL distribution | Rollback |
|---|---|---|
| `wsl-ubuntu` | `Ubuntu` (latest LTS) | `wsl --unregister Ubuntu` |
| `wsl-fedora` | `FedoraLinux-44` (Fedora's WSL name includes its version: to be updated with each new Fedora version) | `wsl --unregister FedoraLinux-44` |

- **Effect**: installs the distribution in WSL (`wsl --install --distribution <name>`, in a new window); at its first launch, it asks for the name and password of the **Linux account**: the only manual part. The setup then checks that the distribution is registered with a non-root account (registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Lxss`, `DefaultUid`).
- **Implications**: processed after the WSL restart. The password is used for `sudo`; it is known only to the user. `wsl --unregister` deletes the distribution and its files.

### Docker Desktop — `docker-desktop`

✔ · "Avec WSL" menu · admin · winget `Docker.DockerDesktop`

- **Effect**: Docker (containers) with WSL 2 as the engine: `docker` and `docker compose` in all terminals.
- **Implications**: the installer adds the account to the local `docker-users` group, applied at the next sign-in (without it: `failed to connect to the docker API at npipe:////./pipe/docker_engine`); the item is therefore marked `requiresLogoff` and the setup signs the session out at the end of the run. Started at sign-in (by the maintenance task, see below), it asks to accept its terms at first launch (free for personal use or small businesses). Its memory is WSL's (`wsl-config`); its disk space is covered below.
- **Rollback**: Settings > Apps > Docker Desktop > Uninstall.

### Docker disk space

Docker stores images, containers, volumes (database data) and the build cache in **a single virtual disk**, `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`. This file **grows when Docker needs more room, but never shrinks on its own**: deleting images frees space inside the virtual disk (Docker reuses it), not on the Windows disk. If content piles up without being cleaned, the file keeps setting new records. With WSL 2, Docker Desktop offers **no adjustable maximum size** (theoretical size: 1 TB). The setup therefore does the following:

- **Build cache cap** (`docker-build-cache`, below): the biggest consumer is cleaned automatically by Docker.
- **Disk space warning**: in the plan, if the system disk has less than 40 GB free, a warning reports it (nothing is blocked).
- **Weekly maintenance** (`docker-maintenance`, below): compaction of the virtual disk (the freed space is returned to Windows) and removal of orphaned images.
- **Not done**: removal of unused images (complete, but used by no container): a project that needs one again would have to download or rebuild it (`docker image prune --all` by hand if needed).
- **Ruled out**: WSL's "sparse" mode (a disk that returns space by itself) was blocked by Microsoft in 2025 after data corruption, and is only allowed again as an experimental preview.

`docker-build-cache`: auto (with `docker-desktop`) · `docker-build-cache` provider (`builder.gc` keys of `%USERPROFILE%\.docker\daemon.json`, merged: the engine's other settings are kept)

- **Effect**: `builder.gc.enabled` = `true`, `defaultKeepStorage` = **30 GB** (20 GB by default): beyond that, Docker itself deletes the oldest build cache. A build that needed it only redoes the affected steps (slower the first time).
- **Hardware safety**: brought down to **10% of the system disk size** when that is less (e.g. 128 GB disk: 12 GB), reported in the log.
- **Implications**: applied at the next Docker Desktop start (file backed up before modification). Docker Desktop also displays this file in Settings > Docker Engine.
- **Rollback**: remove the `builder` section from `daemon.json` (Settings > Docker Engine).

`docker-maintenance`: auto (with `docker-desktop`) · script `dotfiles/docker/docker-maintenance.ps1` copied to `%LOCALAPPDATA%\OS-Setup\` (outside the repository, which may be deleted at the end of the setup) · `logon-task` provider (scheduled task "OS-Setup - Docker (entretien)" (Docker maintenance), at sign-in, highest privileges, Windows PowerShell 5.1)

- **Effect**, at each sign-in:
  1. **At most once a week**, **compaction** of Docker's virtual disk (`diskpart`: `attach vdisk readonly`, `compact vdisk`) while Docker and WSL are stopped: the file is brought back to what it really contains, the freed space returns to Windows. If Docker or a WSL distribution is already running, postponed to the next session.
  2. **Docker Desktop start** (without administrator rights, through Explorer), in place of its own automatic launch, which is disabled the way Task Manager does so that it does not start during compaction. Docker Desktop's "start with Windows" setting is still respected: unchecked, Docker is not started.
  3. **At most once a week**, removal of **orphaned images** (`docker image prune`: leftovers of rebuilt images, nameless, never reused), once the engine is ready (5 minutes' wait at most).
- **Implications**: only Docker is ready a little later on compaction day (from a few seconds to a few minutes depending on the virtual disk size); Windows and the session start normally. Volumes (database data) and images that are in use or merely unused are never deleted. Log: `%LOCALAPPDATA%\OS-Setup\docker-maintenance.log` (sizes before and after); dates of the last maintenance runs: `docker-maintenance.json` (deleting it forces maintenance at the next session).
- **Rollback**: delete the "OS-Setup - Docker (entretien)" task (Task Scheduler), re-enable Docker Desktop in Task Manager > Startup, delete `%LOCALAPPDATA%\OS-Setup\docker-maintenance.*`.

### PostgreSQL: one database per project, in Docker

There is no PostgreSQL item in the catalog (decision: one server per project rather than a service installed on the machine). Each project declares its database in a `docker-compose.yml`, with the version it needs:

```yaml
services:
  db:
    image: postgres:17
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app   # mot de passe de développement local, jamais de production
      POSTGRES_DB: app
    ports:
      - "5432:5432"            # un autre port (ex. "5433:5432") pour un 2e projet lancé en même temps
    volumes:
      - db-data:/var/lib/postgresql/data
volumes:
  db-data:
```

`docker compose up -d` starts the database, `docker compose down` stops it (the data stays in the volume; `down -v` deletes it). In pgAdmin: server `localhost`, port `5432`, user and password as above.
