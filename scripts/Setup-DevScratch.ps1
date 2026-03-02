<#
.SYNOPSIS
  Standardizes dev machine scratch/temp/caches on a chosen drive.

.DESCRIPTION
  - Creates <Drive>:\Scratch\Temp, Cache, Build, Logs, Scripts
  - Sets User + System TEMP/TMP -> <Drive>:\Scratch\Temp
  - Sets NUGET_PACKAGES -> <Drive>:\Scratch\Cache\nuget
  - Optionally sets PIP_CACHE_DIR and npm cache (if tools exist)
  - Creates a cleanup script and a scheduled task to clean old temp files

.PARAMETER ScratchDrive
  Drive letter to host Scratch (e.g., D). Default: D

.PARAMETER TempRetentionDays
  Delete scratch temp files older than N days. Default: 7

.PARAMETER TaskTime
  Daily cleanup task time (HH:mm, 24-hour). Default: 03:15

.PARAMETER ConfigureNpm
  If set, configure npm cache to Scratch (only if npm is installed)

.PARAMETER ConfigurePip
  If set, configure pip cache dir env var to Scratch

.PARAMETER Force
  If set, overwrites existing cleanup script and scheduled task if present.

.EXAMPLE
  .\Setup-DevScratch.ps1 -ScratchDrive D -ConfigureNpm -ConfigurePip -Force
#>

[CmdletBinding()]
param(
  [ValidatePattern("^[A-Za-z]$")]
  [string]$ScratchDrive = "D",

  [ValidateRange(1,365)]
  [int]$TempRetentionDays = 7,

  [ValidatePattern("^\d{2}:\d{2}$")]
  [string]$TaskTime = "03:15",

  [switch]$ConfigureNpm,
  [switch]$ConfigurePip,
  [switch]$Force
)

function Assert-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script in an elevated PowerShell (Run as Administrator)."
  }
}

function Ensure-Dir([string]$Path) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Set-EnvVar([string]$Name, [string]$Value, [string]$Scope) {
  [Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
}

function Get-CommandExists([string]$Cmd) {
  return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue)
}

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
