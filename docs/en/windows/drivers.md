# Drivers

Goal: install and update drivers **according to the detected hardware**. "Pilotes" (Drivers) menu of the `base` profile (`catalog/drivers/`): an option is only offered if it matches the machine (facts `Manufacturer`, `CpuVendor`, `GpuVendor`, `when` condition).

## Chosen approach

1. **Windows Update "drivers" pass** on all machines, through the built-in Windows Update API.
2. **Manufacturer tools** when the hardware matches: those of brand-name PCs (drivers **and BIOS**) selected by default, Intel's unselected.
3. **NVIDIA and AMD graphics cards**: through Windows Update for now (their tools are not in winget). A guided manual step (official page, verification) may be added.
4. **Report** at the end of the setup: devices with no driver or in error, added to the summary.

## Items

### Windows Update: drivers offered — `windows-update-drivers`

✔ · admin · `windows-update` provider

- **Effect**: asks Windows Update for missing or newer drivers **for the hardware present**, downloads and installs them. If Windows asks for a restart, the setup restarts and resumes automatically.
- **Mechanism**: `Microsoft.Update.Session` COM object (criteria `IsInstalled=0 and Type='Driver' and IsHidden=0`), no third-party module; works on a non-activated Windows. Compliant when Windows Update no longer offers any driver.
- **Implications**: the search queries Microsoft's servers (one to a few minutes, result cached during the run). The versions offered are often behind, especially for graphics cards. A driver that fails to install makes the item fail (title shown); it is retried on the next run.
- **Rollback**: Device Manager > device > Driver > "Roll Back Driver".

### Manufacturer tools (installed with winget)

| Item | Default | Offered if | Tool (winget id) | What it provides |
|---|---|---|---|---|
| `dell-command-update` | ✔ | Dell PC (`Manufacturer` = dell) | Dell Command \| Update (`Dell.CommandUpdate`) | All drivers and BIOS of Dell PCs |
| `lenovo-system-update` | ✔ | Lenovo PC | Lenovo System Update (`Lenovo.SystemUpdate`) | All drivers and BIOS of Lenovo PCs |
| `hp-support-assistant` | ✔ | HP PC | HP Support Assistant (`HP.SupportAssistant`) | Drivers and BIOS of HP PCs (HP Image Assistant, an enterprise tool, is not offered) |
| `intel-driver-assistant` | ○ | Intel processor (`CpuVendor` = intel) | Intel Driver & Support Assistant (`Intel.IntelDriverAndSupportAssistant`) | Intel drivers (graphics, Wi-Fi, Bluetooth) newer than those from Windows Update |

- **Implications**: these tools stay installed (service and, often, an icon near the clock) and then offer updates themselves. BIOS updates are done from the tool, at the user's request.
- **Rollback**: uninstall the tool (Settings > Apps).
- The Intel condition is on the processor: a PC with an Intel processor almost always has Intel graphics, Wi-Fi or Bluetooth components (the `when` condition cannot combine two facts with "or").

## Device report

At the end of the setup (outside simulation), the summary lists the devices flagged by Device Manager: no driver (code 28), in error, or disabled (code 22). This is what remains to be done by hand; "none" is shown when everything is fine.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **Windows Update, built-in API** (chosen) | Native, covers all hardware, works without a license | Versions often behind (especially GPU) |
| PSWindowsUpdate module | Convenient | Third-party dependency to install: rejected, the native approach is enough |
| `pnputil` | Native | Only uses drivers already present on the machine |
| **Component manufacturer tools** via winget (chosen for Intel) | Recent drivers, updates followed afterwards | NVIDIA App and AMD Adrenalin absent from winget |
| **PC manufacturer tools** (chosen: Dell, Lenovo, HP) | Handle BIOS + all drivers | Only on brand-name PCs |
| Direct download (NVIDIA, AMD) | Automatic | Changing addresses and versions, downloads blocked by AMD: fragile to maintain |
| Third-party driver packs (Snappy Driver Installer…) | Offline, exhaustive | Third-party source, risk of unsuitable drivers: **rejected** |
