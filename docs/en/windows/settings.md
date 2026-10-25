# Windows settings

Reference for every Windows setting in the catalog: what it does, its implications, the value it changes and how to roll it back. The concepts used (HKLM / HKCU, preference / group policy, original values) are explained in [`../how-it-works.md`](../how-it-works.md).

Every implemented setting appears here with its catalog identifier (`id`): a test checks that none is missing.

Legend: **✔** checked by default · **○** offered, unchecked by default · **✘** rejected · **admin**: requires administrator rights (obtained through the single UAC prompt) · **session**: takes effect at the next sign-in.

## Windows not activated

Most target machines have **no license**. The *Personalization* page of Settings is then locked (wallpaper, colors, themes, lock screen, Start, taskbar) and an "Activate Windows" watermark is displayed.

The lock applies to the **interface**: registry values can still be changed by script. Consequence for rollback: a *Personalization* setting is then restored with `regedit`, not in Settings.

---

## Privacy and telemetry

"Confidentialité et télémétrie" (Privacy and telemetry) menu of the `base` profile (`catalog/privacy/`).

### Diagnostic data: minimum (Required) — `telemetry-required`

✔ · admin · preference (HKLM)

- **Effect**: Windows only sends the "required" diagnostic data (device configuration, update status, basic errors) and no longer the "optional" data (app and feature usage, browsing in Edge, enhanced inking and typing data).
- **Implications**: no loss of everyday functionality. The Windows Insider program requires the optional level. Level 0 ("Security") does not exist on Pro: it is reserved for Enterprise / Education.
- **Value**: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` `AllowTelemetry` = 1. Despite the word "Policies" in the path, this is the key where Settings stores this choice (not a group policy: the page stays usable).
- **Rollback**: Settings > Privacy > Diagnostics & feedback > "Optional diagnostic data".

### DiagTrack telemetry service: disabled — `diagtrack-off`

✔ · admin · service

- **Effect**: disables and stops the "Connected User Experiences and Telemetry" service (`DiagTrack`), which continuously collects and sends diagnostic data.
- **Implications**: Windows Update, the Store and activation are not affected. The "Diagnostic Data Viewer" has nothing left to show.
- **Value**: service `DiagTrack`, startup type *Disabled*.
- **Rollback**: `services.msc` > "Connected User Experiences and Telemetry" > Startup type *Automatic*, then *Start*.

### Telemetry scheduled tasks: disabled — `telemetry-tasks-off`

✔ · admin · scheduled tasks

- **Effect**: disables the tasks that collect data in the background:

  | Task | Purpose |
  |---|---|
  | `Application Experience\Microsoft Compatibility Appraiser` | Inventories software and hardware and sends it to Microsoft (upgrade compatibility) |
  | `Application Experience\ProgramDataUpdater` | Collects data for the Customer Experience Improvement Program |
  | `Customer Experience Improvement Program\Consolidator`, `UsbCeip` | Customer Experience Improvement Program (general, USB) |
  | `Autochk\Proxy` | Data collection at startup |
  | `DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Sends disk information to Microsoft |
  | `Feedback\Siuf\DmClient`, `DmClientOnScenarioDownload` | Feedback Hub |

- **Implications**: the compatibility assessment before a major Windows upgrade is less precise; updates work normally. A missing task (depending on the Windows version) is considered compliant.
- **Value**: tasks under `\Microsoft\Windows\`, state *Disabled*.
- **Rollback**: `taskschd.msc` > Library > Microsoft > Windows > the task's folder > right-click *Enable*.

### Advertising ID: disabled — `advertising-id-off`

✔ · preference (HKCU)

- **Effect**: apps no longer have a unique per-user identifier to track activity and target advertising.
- **Implications**: advertising in apps is not removed, only made non-personalized.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` `Enabled` = 0.
- **Rollback**: Settings > Privacy > General > "Let apps use advertising ID".

### Tailored experiences: disabled — `tailored-experiences-off`

✔ · preference (HKCU)

- **Effect**: Microsoft no longer uses diagnostic data to offer personalized tips, ads and recommendations.
- **Implications**: no loss of functionality.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy` `TailoredExperiencesWithDiagnosticDataEnabled` = 0.
- **Rollback**: Settings > Privacy > Diagnostics & feedback > "Tailored experiences".

### Activity history: disabled — `activity-history-off`

✔ · admin · group policy (HKLM)

- **Effect**: Windows no longer records the apps, documents and sites you open, and no longer sends them to Microsoft.
- **Implications**: Timeline (`Win+Tab`) no longer shows past activities; "pick up where you left off on another device" stops working. The matching Settings page is grayed out.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` `PublishUserActivities` = 0 and `UploadUserActivities` = 0 (no reliable per-user equivalent).
- **Rollback**: `regedit`: delete both values.

### Windows suggestions and ads: disabled — `suggestions-off`

✔ · preference (HKCU) · session

- **Effect**: removes promotional content from Windows:

  | Value (`ContentDeliveryManager`) | What it turns off |
  |---|---|
  | `SystemPaneSuggestionsEnabled`, `SubscribedContent-338388Enabled` | "Suggested" apps in the Start menu |
  | `SubscribedContent-338389Enabled`, `SoftLandingEnabled` | Tips and suggestions in notifications |
  | `SubscribedContent-338387Enabled`, `RotatingLockScreenOverlayEnabled` | Fun facts and tips on the lock screen |
  | `SubscribedContent-310093Enabled` | "Welcome" screen after updates |
  | `SubscribedContent-353694Enabled`, `SubscribedContent-353696Enabled` | Suggested content in Settings |
  | `UserProfileEngagement\ScoobeSystemSettingEnabled` | "Finish setting up your device" |

- **Implications**: no loss of functionality; the Windows Spotlight picture on the lock screen remains possible.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` (and `UserProfileEngagement`), values above = 0.
- **Rollback**: Settings > System > Notifications (tips, welcome, finish setup), Privacy > General (suggested content), Personalization > Start and Lock screen (locked if Windows is not activated: `regedit`, values set to 1).

### Sponsored apps: installation blocked — `sponsored-apps-off`

✔ · preference (HKCU)

- **Effect**: Windows no longer installs promoted apps on its own (Candy Crush, etc.), notably after a major update.
- **Implications**: does not remove those already installed (see [`removable-apps.md`](removable-apps.md)). The more radical `DisableWindowsConsumerFeatures` policy is ignored on Pro.
- **Value**: `ContentDeliveryManager` `SilentInstalledAppsEnabled`, `PreInstalledAppsEnabled`, `OemPreInstalledAppsEnabled` = 0.
- **Rollback**: `regedit`: values set to 1 (no interface).

### Bing web search in Start: removed — `web-search-off`

✔ · preference + group policy (HKCU) · session

- **Effect**: the Start menu search only shows local results (apps, files, settings), without Bing suggestions; it is faster.
- **Implications**: no more web results when typing in Start. The policy used also turns off the display of **recent searches** in the File Explorer search box.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `BingSearchEnabled` = 0 and `CortanaConsent` = 0; policy `HKCU\Software\Policies\Microsoft\Windows\Explorer` `DisableSearchBoxSuggestions` = 1 (the only method still effective since Windows 10 2004).
- **Rollback**: `regedit`: delete `DisableSearchBoxSuggestions`, set the other two back to 1.

### Cortana: disabled — `cortana-off`

✔ · admin · group policy (HKLM) · session

- **Effect**: Cortana can no longer be used.
- **Implications**: none. Cortana has been abandoned by Microsoft and, on a French Windows, is already unusable ("not available in French (France)"): the setting mainly serves machines in another language. The app itself is removed with the preinstalled apps.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` `AllowCortana` = 0.
- **Rollback**: `regedit`: delete the value.

### Feedback requests: never — `feedback-never`

✔ · preference (HKCU)

- **Effect**: Windows no longer asks for feedback ("How likely are you to recommend…").
- **Implications**: none; the Feedback Hub remains usable manually if it is installed.
- **Value**: `HKCU\Software\Microsoft\Siuf\Rules` `NumberOfSIUFInPeriod` = 0.
- **Rollback**: Settings > Privacy > Diagnostics & feedback > "Feedback frequency".

### Inking and typing personalization: disabled — `inking-typing-off`

✔ · preference (HKCU)

- **Effect**: Windows no longer learns from your keystrokes, ink strokes and contacts to personalize recognition, and no longer sends samples to Microsoft.
- **Implications**: typing suggestions and handwriting recognition are less personalized; the learned personal dictionary is erased.
- **Value**: `HKCU\Software\Microsoft\InputPersonalization` `RestrictImplicitInkCollection` = 1, `RestrictImplicitTextCollection` = 1; `…\InputPersonalization\TrainedDataStore` `HarvestContacts` = 0; `HKCU\Software\Microsoft\Personalization\Settings` `AcceptedPrivacyPolicy` = 0; `HKCU\Software\Microsoft\Input\TIPC` `Enabled` = 0.
- **Rollback**: Settings > Privacy > Inking & typing personalization; Diagnostics & feedback > "Improve inking and typing".

### Online speech recognition: disabled — `online-speech-off`

✔ · preference (HKCU)

- **Effect**: speech is no longer sent to Microsoft servers for recognition.
- **Implications**: `Win+H` dictation no longer works (it relies on online recognition under Windows 10); the legacy offline speech recognition remains available.
- **Value**: `HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy` `HasAccepted` = 0.
- **Rollback**: Settings > Privacy > Speech.

### Delivery Optimization: local network — `delivery-optimization-lan`

✔ · admin · group policy (HKLM)

- **Effect**: update chunks are no longer exchanged with unknown PCs on the Internet; only with PCs on the local network.
- **Implications**: your connection is no longer used to serve strangers; downloads come from Microsoft or the local network. The matching Settings page is grayed out.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` `DODownloadMode` = 1 (the Settings option is stored in a service account's profile, which is unreliable to modify).
- **Rollback**: `regedit`: delete the value.

### Language list: not shared with websites — `language-list-optout`

✔ · preference (HKCU)

- **Effect**: Windows no longer sends your language list to websites.
- **Implications**: a site may be displayed in its default language. Firefox, Chrome and Vivaldi use their own language settings and are not affected.
- **Value**: `HKCU\Control Panel\International\User Profile` `HttpAcceptLanguageOptOut` = 1.
- **Rollback**: Settings > Privacy > General > "Let websites provide locally relevant content by accessing my language list".

### Search without cloud content or history — `search-cloud-off`

✔ · preference (HKCU)

- **Effect**: Windows search no longer includes results from the Microsoft or work account (OneDrive, Outlook…) and no longer keeps the search history on the device.
- **Implications**: no more cloud results or "recent searches" in the search pane.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings` `IsMSACloudSearchEnabled`, `IsAADCloudSearchEnabled`, `IsDeviceSearchHistoryEnabled` = 0.
- **Rollback**: Settings > Search > Permissions & History.

### Search highlights: disabled — `search-highlights-off`

✔ · preference (HKCU) · session

- **Effect**: removes the illustrations and content highlighted by Bing (events of the day, trends) in the search box and pane.
- **Implications**: no loss of functionality.
- **Value**: `SearchSettings` `IsDynamicSearchBoxEnabled` = 0.
- **Rollback**: depending on the version, Settings > Search > Permissions & History > "Show search highlights"; on the tested 22H2, the toggle is not there: `regedit`, value set to 1.

### Other apps' diagnostics: access denied — `app-diagnostics-off`

✔ · preference (HKCU)

- **Effect**: Store apps can no longer read diagnostic information about other apps (which ones are running, their resource usage…).
- **Implications**: only a few Store apps (alternative task managers) need it.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics` `Value` = `Deny`.
- **Rollback**: Settings > Privacy > App diagnostics.

### News and interests: removed from the taskbar — `news-interests-off`

✔ · admin · group policy (HKLM) · session

- **Effect**: removes the MSN weather / news widget from the taskbar, which continuously loads content from MSN.
- **Implications**: no more weather on the taskbar; the right-click taskbar option disappears.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds` `EnableFeeds` = 0 (the user preference is protected by Windows on 22H2).
- **Rollback**: `regedit`: delete the value.

### WAP push messages (remote management): disabled — `dmwappush-off`

✔ · admin · service

- **Effect**: disables `dmwappushservice`, which routes device management messages and part of the telemetry.
- **Implications**: prevents the machine from being enrolled in corporate management (Intune / MDM). No effect for personal use.
- **Value**: service `dmwappushservice`, startup type *Disabled*.
- **Rollback**: `services.msc` > "Device Management Wireless Application Protocol (WAP) Push message Routing Service" > *Manual*.

### Launched-app tracking: disabled (empties "Most used") — `app-launch-tracking-off`

○ · preference (HKCU) · session

- **Effect**: Windows no longer remembers the programs you launch.
- **Implications**: the "Most used" list of the Start menu is empty and its option grayed out; search ranks your apps slightly less well.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` `Start_TrackProgs` = 0.
- **Rollback**: Settings > Privacy > General > "Let Windows track app launches to improve Start and search results".

### Location: disabled — `location-off`

✔ · admin · preference (HKLM)

- **Effect**: turns off the location service for the **whole machine**.
- **Implications**: no more automatic time zone setting, local weather, Maps, "Find my device", or position for apps that go through Windows (including some browsers).
- **Value**: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location` `Value` = `Deny`.
- **Rollback**: Settings > Privacy > Location > "Change" (location access for this device).

### Windows Error Reporting: disabled — `error-reporting-off`

✔ · admin · preference (HKLM)

- **Effect**: crashes are no longer reported to Microsoft.
- **Implications**: no more solutions offered after a crash; vendors no longer receive reports for their software through Windows. Kept locally: event 1000 in the Application log and blue screen dumps; for debugging, see `crash-dumps-local` (advanced options).
- **Value**: `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting` `Disabled` = 1.
- **Rollback**: `regedit`: value set to 0.

### Store apps in the background: blocked — `background-apps-off`

✔ · preference (HKCU)

- **Effect**: Store apps (Mail, Weather, Photos…) no longer run when they are closed.
- **Implications**: no more notifications or live tiles from these apps. Classic desktop software (browsers, Discord…) is not affected.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications` `GlobalUserDisabled` = 1; `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` `BackgroundAppGlobalToggle` = 0.
- **Rollback**: Settings > Privacy > Background apps.

### Clipboard across devices: not synchronized — `cross-device-clipboard-off`

✔ · admin · group policy (HKLM)

- **Effect**: the clipboard is no longer synchronized between devices through the Microsoft account.
- **Implications**: the local history (`Win+V`) remains available. Irrelevant with a local account.
- **Value**: `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` `AllowCrossDeviceClipboard` = 0.
- **Rollback**: `regedit`: delete the value.

### Rejected

| Setting | Reason |
|---|---|
| Blocking Microsoft servers (hosts file, firewall) | ✘ Breaks Windows Update, the Store and activation; fragile |
| Defender: sample submission and cloud protection | ✘ Security trade-off; Defender's tamper protection blocks or ignores these values |
| Telemetry of Edge and of installed software (PowerShell 7, winget, VS Code, browsers, NVIDIA) | Handled with each software's configuration |

---

## Store app permissions

"Permissions refusées aux applications du Store" (Permissions denied to Store apps) menu of the `base` profile, everything checked by default except the camera and microphone.

Each item turns off, for the current account, the "Allow apps to access your …" setting in Settings > Privacy: **no Store app** has access to it any more. According to Microsoft's documentation, classic desktop apps (browsers, Zoom, Discord…) are not affected: they have a separate setting on the same page. **Observed on Windows 10 22H2: this is false for the microphone**: with `perm-microphone`, Discord lost access to the microphone until "Allow apps to access your microphone" was turned back on. The camera is set the same way: `perm-camera` and `perm-microphone` are therefore unchecked by default, with a warning when they are checked. The other capabilities have no setting for desktop apps.

- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\<capability>` `Value` = `Deny` (HKCU preference).
- **Rollback**: Settings > Privacy > the capability's page > "Allow apps to access…".

| Item | Capability | Windows apps affected (examples) |
|---|---|---|
| `perm-camera` | `webcam` | Camera, Skype / Teams Store version |
| `perm-microphone` | `microphone` | Voice Recorder, Teams Store version |
| `perm-account-info` | `userAccountInformation` | Apps that display your account name or picture |
| `perm-contacts` | `contacts` | People, Mail |
| `perm-calendar` | `appointments` | Calendar, Mail |
| `perm-call-history` | `phoneCallHistory` | Phone Link |
| `perm-email` | `email` | Mail |
| `perm-messaging` | `chat` | Phone Link (SMS) |
| `perm-tasks` | `userDataTasks` | To Do, Mail |
| `perm-radios` | `radios` | Apps that turn Bluetooth or Wi-Fi on or off |
| `perm-notifications` | `userNotificationListener` | Apps that read your notifications (Phone Link) |

---

## Power and lock

"Alimentation et verrouillage" (Power and lock) menu of the `base` profile (`catalog/power/`). The timeouts apply to the **active power mode** ("Normal use" by default): switching to another mode loses them. These pages are not locked on a Windows that is not activated.

### Sleep: never on AC power, 20 min on battery — `sleep-policy`

✔ · power

- **Effect**: on AC power, the machine never goes to sleep or hibernates; on battery (laptops), it sleeps after 20 min of inactivity.
- **Implications**: a desktop PC stays on (idle consumption of the order of a few tens of watts); long tasks, remote access and downloads are never interrupted. No effect on battery for a desktop PC.
- **Value**: `powercfg`: sleep (`STANDBYIDLE`) on AC 0, hibernate (`HIBERNATEIDLE`) on AC 0, sleep on battery 1,200 s.
- **Rollback**: Settings > System > Power & sleep.

### Display: off after 4 min 30 (before the lock) — `display-off`

✔ · power

- **Effect**: the display turns off after 4 min 30 of inactivity, on AC power and on battery alike.
- **Implications**: 30 s before the lock (5 min): moving the mouse during that interval turns the display back on without a password. The Settings list does not offer 4 min 30: it shows "4 minutes", but 270 s is what applies (choosing a value there replaces it).
- **Value**: `powercfg`: `VIDEOIDLE` on AC and battery = 270 s.
- **Rollback**: Settings > System > Power & sleep.

### Lock: after 5 min of inactivity (screen saver) — `lock-on-idle`

✔ · preference (HKCU) · session

- **Effect**: after 5 min without activity, a blank screen saver starts and resuming asks for the password (or PIN): the session is locked.
- **Implications**: a full-screen video or a presentation normally prevents the screen saver, and therefore the lock. Per-user setting.
- **Choice**: preferred over the machine policy `InactivityTimeoutSecs` (which also locks, but can no longer be changed in the interface).
- **Value**: `HKCU\Control Panel\Desktop`: `SCRNSAVE.EXE` = `C:\Windows\System32\scrnsave.scr` (blank screen), `ScreenSaveActive` = `1`, `ScreenSaverIsSecure` = `1`, `ScreenSaveTimeOut` = `300` (seconds).
- **Rollback**: `Win+R` > `control desk.cpl,,@screensaver` (reachable even on a Windows that is not activated).

### Fast startup: disabled (full shutdowns) — `fast-startup-off`

✔ · admin · preference (HKLM) · warning when unchecked

- **How fast startup works** (enabled by default in Windows): "Shut down" closes the sessions, then **hibernates the system part** (kernel and drivers) into `C:\hiberfil.sys`; the next power-on reloads that state instead of resetting everything. "Restart", or "Shut down" with `Shift` held, always does a full boot. Not to be confused with the UEFI "Fast Boot" (a firmware setting).
- **Effect of the setting**: every "Shut down" fully powers Windows off.
- **Advantages of fast startup (lost)**: faster power-on after a shutdown — tens of seconds on a hard disk, a few seconds on an SSD.
- **Drawbacks of fast startup (avoided)**:
  - **dual boot**: the Windows partition stays "hibernated"; Linux refuses to write to it (or mounts it read-only), and forcing write access can **corrupt Windows files**. With Linux on another disk, the risk disappears as long as Linux does not touch the Windows partitions, but it remains for a **shared NTFS data disk**;
  - hardware used by another system in the meantime (Bluetooth, network, USB): Windows reloads a state that no longer matches, and devices may misbehave;
  - a "shutdown" resets neither drivers nor kernel: a problem persists after shutting down and powering on again, and the displayed uptime keeps running;
  - software or a driver waiting for a real restart may appear not to apply; hardware changed during shutdown is less well detected; Wake-on-LAN may not work depending on the network card.
- **What does not change**: hibernation remains available and `hiberfil.sys` remains present (this setting does not remove them); "Restart" is unchanged.
- **Choice**: checked by default, because dual boot is often installed *after* Windows (a detection at setup time would not see it), because a tool that rebuilds machines should have predictable shutdowns, and because the cost is low on an SSD. When unchecked, the setup displays: "En double démarrage (Linux, ou disque de données NTFS partagé), le démarrage rapide laisse les partitions Windows en veille prolongée : y écrire depuis l'autre système peut corrompre des fichiers Windows." (In dual boot (Linux, or a shared NTFS data disk), fast startup leaves the Windows partitions hibernated: writing to them from the other system can corrupt Windows files.) (`uncheckedWarning` field of the catalog).
- **Value**: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power` `HiberbootEnabled` = 0.
- **Rollback**: Control Panel > Power Options > "Choose what the power buttons do" > "Turn on fast startup".

---

## Advanced options

"Options avancées" (Advanced options) menu of the `base` profile, nothing checked by default.

### Crash dumps: kept locally (debugging) — `crash-dumps-local`

○ · admin · preference (HKLM)

- **Effect**: each time a program crashes, Windows writes a mini dump (`.dmp`) to `%LOCALAPPDATA%\CrashDumps` of the account concerned: threads, call stack, loaded modules, error. At most 10 files; the oldest is replaced.
- **Usefulness**: debugging a crash (WinDbg, Visual Studio) much more precisely than with event 1000 in the log. None without debugging.
- **Implications**: **never sent** (local files; works even with error reporting disabled, verified in a VM). A few hundred KB to a few MB per crash. A dump contains an excerpt of the program's memory (open text, possibly a password): do not share it lightly. Programs that handle their own crashes (Firefox, Chrome) are not affected.
- **Value**: `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps`: `DumpFolder` = `%LOCALAPPDATA%\CrashDumps`, `DumpCount` = 10, `DumpType` = 1 (mini dump).
- **Rollback**: `regedit`: delete the `LocalDumps` key.

Traces kept without this option, with error reporting disabled: event 1000 "Application Error" in the Application log (program, faulting module, exception code) and blue screen dumps (`C:\Windows\MEMORY.DMP`, `C:\Windows\Minidump`), independent of error reporting.

---

## Explorer and appearance

Settings always applied by the `base` profile (`catalog/system/`).

### Explorer: file extensions shown — `explorer-show-extensions`

✔ · preference (HKCU) · session

- **Effect**: File Explorer shows file extensions (`invoice.pdf.exe` instead of `invoice.pdf`).
- **Implications**: spots disguised files; take care not to change the extension when renaming.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` `HideFileExt` = 0.
- **Rollback**: Explorer > View > "File name extensions".

### Explorer: hidden files shown — `explorer-show-hidden`

✔ · preference (HKCU) · session

- **Effect**: File Explorer shows hidden files and folders (e.g. `AppData`, `.git`), grayed out.
- **Implications**: protected system files remain hidden.
- **Value**: `Explorer\Advanced` `Hidden` = 1.
- **Rollback**: Explorer > View > "Hidden items".

### Theme: dark (apps and system) — `dark-theme`

✔ · preference (HKCU) · session

- **Effect**: dark mode for apps and for Windows (taskbar, Start menu).
- **Implications**: the *Colors* page is locked on a Windows that is not activated; the setting still applies.
- **Value**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` `AppsUseLightTheme` = 0, `SystemUsesLightTheme` = 0.
- **Rollback**: Settings > Personalization > Colors (or `regedit`, values set to 1, if Windows is not activated).
