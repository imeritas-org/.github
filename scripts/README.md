# Dev Machine Scratch / Temp Setup (Windows)

This folder contains standard PowerShell setup scripts for Windows dev machines:

1) `Setup-DevScratch.ps1` — move Windows temp files and common dev caches (NuGet, optionally npm/pip) to a dedicated `Scratch` folder on a non-OS drive.

2) `Remove-PreinstalledApps.ps1` — remove most preinstalled Microsoft Store (Appx) apps while keeping key system components (and explicitly keeping Microsoft Store + new Notepad).

**Repo/Org:** `imeritas-org/.github`  
**Scripts:**
- `scripts/Setup-DevScratch.ps1`
- `scripts/Remove-PreinstalledApps.ps1`

---

## Setup-DevScratch.ps1

### What this does

When you run `Setup-DevScratch.ps1`, it will:

- Create a scratch layout on the selected drive (default: `D:`)
  - `D:\Scratch\Temp`
  - `D:\Scratch\Cache\nuget`
  - `D:\Scratch\Cache\npm` (optional)
  - `D:\Scratch\Cache\pip` (optional)
  - `D:\Scratch\Build`
  - `D:\Scratch\Logs`
  - `D:\Scratch\Scripts`
- Set **User + System** environment variables:
  - `TEMP` and `TMP` → `D:\Scratch\Temp`
- Set `NUGET_PACKAGES` (User) → `D:\Scratch\Cache\nuget`
- Optionally set:
  - `PIP_CACHE_DIR` → `D:\Scratch\Cache\pip`
  - npm cache → `D:\Scratch\Cache\npm` (only if `npm` is installed)
- Create a cleanup script:
  - `D:\Scratch\Scripts\CleanScratchTemp.ps1`
- Create a scheduled task:
  - **Clean Scratch Temp** (daily) to delete files in `Scratch\Temp` older than the retention window (default: 7 days)

> **Important:** You should restart Windows (or sign out/in) after running so all apps pick up the new temp paths.

---

### Requirements

- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 also works)
- **Run as Administrator** (required to set System `TEMP/TMP` and create scheduled task)

---

### Quick start

1) Clone the repo (or copy the script to the machine)

2) Run PowerShell **as Administrator** and execute:

```powershell
# Example: use D: as scratch, configure npm + pip caches, overwrite existing task/script if present
.\scripts\Setup-DevScratch.ps1 -ScratchDrive D -ConfigureNpm -ConfigurePip -Force
