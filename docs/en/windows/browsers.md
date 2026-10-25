# Browsers (Windows 10)

Installation (menu "Navigateurs à installer", Browsers to install, `catalog/browsers/`) and settings (menu "Navigateurs : réglages", Browsers: settings, `catalog/browser-settings/`, everything selected by default). A setting specific to a browser is only offered if that browser is selected. The common concepts (policy, HKLM, rollback) are explained in [`../how-it-works.md`](../how-it-works.md).

## Mechanism: browser policies

Edge, Chrome, Brave and Firefox read **policies** from `HKLM\SOFTWARE\Policies\…`, including on a personal machine. This is the official method, documented by each vendor.

- **Common implication**: the browser shows "Your browser is managed by your organization" (Firefox: "Your browser is being managed by your organization" in the menu), and the settings concerned are grayed out in its settings. The applied policies can be viewed in `edge://policy`, `chrome://policy`, `brave://policy` or `about:policies`.
- **Rollback**: `regedit`: delete the value (or the browser's key under `HKLM\SOFTWARE\Policies`), then restart the browser.
- Browser updates are **never** disabled: a browser must stay up to date for security.
- Outside the repository (personal): home page, extensions, accounts and sync.

## Edge (kept and neutralized)

On Windows 10, Edge cannot be uninstalled (see [`removable-apps.md`](removable-apps.md)): it is neutralized. It is already removed from the taskbar by the layout (see [Desktop integration](desktop.md)). Full uninstallation is planned for Windows 11.

### No background execution — `edge-no-background`

✔ · admin · policies (HKLM) + startup entry

- **Effect**: Edge no longer starts at sign-in ("startup boost", which preloaded it without a window) and no longer stays in the background after its last window is closed.
- **Implications**: Edge's first launch is a little slower; less memory used and no more invisible Edge processes.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Edge` `StartupBoostEnabled` = 0, `BackgroundModeEnabled` = 0; startup entry `MicrosoftEdgeAutoLaunch_*` disabled (`startup-entry` provider, see below).

### No desktop shortcut — `edge-no-desktop-shortcut`

✔ · admin · policy (HKLM) + shortcut

- **Effect**: removes Edge's shortcut from the desktop and prevents its updates from creating a new one.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate` `CreateDesktopShortcutDefault` = 0; `Microsoft Edge.lnk` shortcut removed from the account's desktop and the public desktop.
- **Rollback**: delete the value; recreate the shortcut from the Start menu.

### Personalization and feedback disabled — `edge-telemetry-off`

✔ · admin · policies (HKLM)

- **Effect**: Edge no longer uses browsing history to personalize ads, search and news, and no longer offers to send feedback.
- **Implications**: on Windows 10, Edge's diagnostic data level follows Windows's, which is already set to the minimum (`telemetry-required`).
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Edge` `PersonalizationReportingEnabled` = 0, `UserFeedbackAllowed` = 0.

### Nags disabled — `edge-no-nags`

✔ · admin · policies (HKLM)

- **Effect**: no welcome screen on first launch, no prompt to become the default browser, no recommendations or "spotlight" content, no shopping assistant (price comparison), no Microsoft Rewards, no sidebar (apps), no "Chat" (Copilot) button in the toolbar, no promotional tabs.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Edge`: `HideFirstRunExperience` = 1, `DefaultBrowserSettingEnabled` = 0, `ShowRecommendationsEnabled` = 0, `SpotlightExperiencesAndRecommendationsEnabled` = 0, `EdgeShoppingAssistantEnabled` = 0, `ShowMicrosoftRewards` = 0, `HubsSidebarEnabled` = 0, `PromotionalTabsEnabled` = 0, `Microsoft365CopilotChatIconEnabled` = 0 (the sidebar policy no longer hides the Copilot button in recent versions: checked in a VM).

## Firefox — `firefox-privacy`

✔ if Firefox is selected · admin · policies (HKLM)

- **Effect**: no telemetry or studies (Mozilla's remote experiments), no "default browser agent" (a scheduled task that sends Mozilla information about the default browser), no Pocket, no sponsored shortcuts or articles on the New Tab page, no extension or feature recommendations.
- **Value**: `HKLM\SOFTWARE\Policies\Mozilla\Firefox`: `DisableTelemetry` = 1, `DisableFirefoxStudies` = 1, `DisableDefaultBrowserAgent` = 1, `DisablePocket` = 1; `…\FirefoxHome` `SponsoredTopSites` = 0, `SponsoredPocket` = 0; `…\UserMessaging` `ExtensionRecommendations` = 0, `FeatureRecommendations` = 0.

## Chrome — `chrome-privacy`

✔ if Chrome is selected · admin · policies (HKLM)

- **Effect**: no usage statistics or crash reports sent to Google, no collection of "anonymized" visited addresses, no feedback, no promotional content.
- **Implications**: Google Safe Browsing stays active (protection against malicious sites).
- **Value**: `HKLM\SOFTWARE\Policies\Google\Chrome`: `MetricsReportingEnabled` = 0, `UrlKeyedAnonymizedDataCollectionEnabled` = 0, `UserFeedbackAllowed` = 0, `PromotionsEnabled` = 0.

## Brave

### Statistics and built-in services disabled — `brave-privacy`

✔ if Brave is selected · admin · policies (HKLM)

- **Effect**: no usage statistics (P3A, daily ping, crash reports), and Brave Rewards (paid ads), Brave Wallet (cryptocurrency wallet), Brave VPN and the AI assistant (Leo) are disabled.
- **Value**: `HKLM\SOFTWARE\Policies\BraveSoftware\Brave`: `MetricsReportingEnabled` = 0, `BraveP3AEnabled` = 0, `BraveStatsPingEnabled` = 0, `BraveRewardsDisabled` = 1, `BraveWalletDisabled` = 1, `BraveVPNDisabled` = 1, `BraveAIChatEnabled` = 0.

### Updater not launched at sign-in — `brave-no-autostart`

✔ if Brave is selected · startup entry

- **Effect**: Brave's update program (`BraveSoftware Update`) no longer starts at every sign-in.
- **Implications**: none for security: updates continue through Brave's scheduled tasks.
- **Value**: `startup-entry` provider (see below).

## Launch at startup: `startup-entry` provider

Disables an entry the way **Task Manager** does (Startup tab): the entry in the `Run` key stays, and a binary value in `…\Explorer\StartupApproved\Run` marks it "disabled" (first byte odd, followed by the date). Software that recreates its entry on every update therefore stays disabled. **Rollback**: Task Manager > Startup > Enable.

## Default browser — guided manual step

"Navigateur par défaut (étape manuelle guidée)" (Default browser, guided manual step) menu, single choice among the selected browsers; Vivaldi by default.

| Item | Browser | Program expected for `https` (ProgId) |
|---|---|---|
| `default-browser-vivaldi` | Vivaldi | `VivaldiHTM*` |
| `default-browser-firefox` | Firefox | `FirefoxURL-*` |
| `default-browser-chrome` | Google Chrome | `ChromeHTML` |
| `default-browser-brave` | Brave | `BraveHTML` |

- **Why manual**: Windows 10 protects this choice with a hash (`UserChoice\Hash`) that only Windows computes: a value written by a script is ignored and Windows reverts to Edge. Third-party tools that recompute the hash are rejected; the "default associations file" policy and the DISM association file only work for a domain machine or for new accounts.
- **Flow** (`manual` provider, see [`../how-it-works.md`](../how-it-works.md#guided-manual-steps)): the setup shows the instructions, opens Settings > Apps > Default apps, then waits for "C'est fait : vérifier" (Done: verify); it then reads the user's choice (`HKCU\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice` `ProgId`). "Passer" (Skip) leaves the step for later (reported in the summary); rerunning the setup offers it again. Unattended (`-Yes`), the step is only reported.
- **Implications**: the Default apps page also works on a non-activated Windows.
- **Rollback**: Settings > Apps > Default apps.
