# Dev Machine Scratch / Temp Setup (Windows)

This folder contains a standard PowerShell setup script to move Windows temp files and common dev caches (NuGet, optionally npm/pip) to a dedicated `Scratch` folder on a non-OS drive.

**Repo/Org:** `imeritas-org/.github`  
**Script:** `scripts/Setup-DevScratch.ps1`

---

## What this does

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

## Requirements

- Windows 10/11
- PowerShell 5.1+ (PowerShell 7 also works)
- **Run as Administrator** (required to set System `TEMP/TMP` and create scheduled task)

---

## Quick start

1) Clone the repo (or copy the script to the machine)

2) Run PowerShell **as Administrator** and execute:

```powershell
# Example: use D: as scratch, configure npm + pip caches, overwrite existing task/script if present
.\scripts\Setup-DevScratch.ps1 -ScratchDrive D -ConfigureNpm -ConfigurePip -Force}

Assert-Admin

$driveRoot = "$ScratchDrive`:\"
if (-not (Test-Path $driveRoot)) {
  throw "Drive $ScratchDrive`: does not exist. Choose an existing drive letter."
}

# Base paths
$ScratchRoot  = Join-Path $driveRoot "Scratch"
$TempPath     = Join-Path $ScratchRoot "Temp"
$CacheRoot    = Join-Path $ScratchRoot "Cache"
$BuildPath    = Join-Path $ScratchRoot "Build"
$LogsPath     = Join-Path $ScratchRoot "Logs"
$ScriptsPath  = Join-Path $ScratchRoot "Scripts"

$NugetCache   = Join-Path $CacheRoot "nuget"
$NpmCache     = Join-Path $CacheRoot "npm"
$PipCache     = Join-Path $CacheRoot "pip"

# Create directories
Ensure-Dir $TempPath
Ensure-Dir $NugetCache
Ensure-Dir $BuildPath
Ensure-Dir $LogsPath
Ensure-Dir $ScriptsPath
Ensure-Dir $NpmCache
Ensure-Dir $PipCache

# Set TEMP/TMP (User + Machine)
Set-EnvVar "TEMP" $TempPath "User"
Set-EnvVar "TMP"  $TempPath "User"
Set-EnvVar "TEMP" $TempPath "Machine"
Set-EnvVar "TMP"  $TempPath "Machine"

# NuGet global packages folder (User)
Set-EnvVar "NUGET_PACKAGES" $NugetCache "User"

# pip cache (optional)
if ($ConfigurePip) {
  Set-EnvVar "PIP_CACHE_DIR" $PipCache "User"
}

# npm cache (optional, only if npm exists)
if ($ConfigureNpm) {
  if (Get-CommandExists "npm") {
    & npm config set cache $NpmCache --global | Out-Null
  } else {
    Write-Warning "npm not found. Skipping npm cache configuration."
  }
}

# Write cleanup script
$cleanupScriptPath = Join-Path $ScriptsPath "CleanScratchTemp.ps1"

$cleanupScript = @"
`$TempPath = '$TempPath'
`$Days = $TempRetentionDays

if (Test-Path `$TempPath) {
  Get-ChildItem -Path `$TempPath -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { `$_.LastWriteTime -lt (Get-Date).AddDays(-`$Days) } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
"@

if ((Test-Path $cleanupScriptPath) -and -not $Force) {
  Write-Warning "Cleanup script already exists: $cleanupScriptPath (use -Force to overwrite)"
} else {
  Set-Content -Path $cleanupScriptPath -Value $cleanupScript -Encoding UTF8
}

# Scheduled task (daily)
$taskName = "Clean Scratch Temp"
$timeParts = $TaskTime.Split(":")
$hour = [int]$timeParts[0]
$min  = [int]$timeParts[1]
$runAt = (Get-Date).Date.AddHours($hour).AddMinutes($min)

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cleanupScriptPath`""
$trigger = New-ScheduledTaskTrigger -Daily -At $runAt

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing -and -not $Force) {
  Write-Warning "Scheduled task already exists: $taskName (use -Force to replace)"
} else {
  if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null }
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Deletes scratch temp files older than $TempRetentionDays days" -Force | Out-Null
}

Write-Host ""
Write-Host "✅ Dev scratch setup complete"
Write-Host "Scratch root:      $ScratchRoot"
Write-Host "TEMP/TMP (User):   $([Environment]::GetEnvironmentVariable('TEMP','User'))"
Write-Host "TEMP/TMP (Machine):$([Environment]::GetEnvironmentVariable('TEMP','Machine'))"
Write-Host "NUGET_PACKAGES:    $([Environment]::GetEnvironmentVariable('NUGET_PACKAGES','User'))"
if ($ConfigurePip) { Write-Host "PIP_CACHE_DIR:     $([Environment]::GetEnvironmentVariable('PIP_CACHE_DIR','User'))" }
Write-Host "Cleanup script:    $cleanupScriptPath"
Write-Host "Cleanup task:      $taskName @ $TaskTime daily"
Write-Host ""
Write-Host "➡️  Restart Windows (or sign out/in) so all apps pick up the new TEMP/TMP paths."
