<#
Remove Windows 11 preinstalled Microsoft Store apps while keeping Microsoft Store.
- Removes installed apps for current user
- Removes provisioned apps so they won't install for new users
- Dry-run supported

Tested approach: Get-AppxPackage / Remove-AppxPackage and
Get-AppxProvisionedPackage / Remove-AppxProvisionedPackage
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    # If set, only prints what would be removed.
    [switch]$WhatIfOnly = $true,

    # If set, also attempts to remove for all existing users (best effort).
    # Note: Removing from other profiles is limited; provisioned removal is the real "stickiness".
    [switch]$AllUsers = $false
)

# --- Apps to KEEP (by Package Family Name / wildcard) ---
# Microsoft Store is the one you asked to keep.
# A few others are commonly required for Windows features / UI integrity.
$KeepPatterns = @(
  "Microsoft.WindowsStore*",
  "Microsoft.WindowsNotepad*",
  "Microsoft.PowerShell*",
  "Microsoft.StorePurchaseApp*",
  "Microsoft.DesktopAppInstaller*",
  "Microsoft.VCLibs*",
  "Microsoft.NET.Native.Framework*",
  "Microsoft.NET.Native.Runtime*",
  "Microsoft.UI.Xaml*",
  "Microsoft.WindowsAppRuntime*",
  "Microsoft.SecHealthUI*",
  "Microsoft.Windows.ShellExperienceHost*",
  "Microsoft.AAD.BrokerPlugin*",
  "Microsoft.AccountsControl*",
  "Microsoft.LockApp*",
  "Microsoft.Windows.StartMenuExperienceHost*"
)

function Test-IsKept {
    param([string]$Name)
    foreach ($p in $KeepPatterns) {
        if ($Name -like $p) { return $true }
    }
    return $false
}

function Remove-InstalledAppx {
    param([switch]$UseAllUsers)

    Write-Host "=== Removing installed Appx packages ($([string]::Join(', ', @('CurrentUser') + ($(if($UseAllUsers){'AllUsers'}else{@()})))) ) ==="

    $pkgs = if ($UseAllUsers) {
        Get-AppxPackage -AllUsers
    } else {
        Get-AppxPackage
    }

    $targets = $pkgs | Where-Object { -not (Test-IsKept $_.Name) } | Sort-Object Name -Unique

    foreach ($t in $targets) {
        $desc = "$($t.Name)  [$($t.PackageFullName)]"
        if ($WhatIfOnly) {
            Write-Host "[WhatIf] Would remove installed: $desc"
        } else {
            try {
                if ($PSCmdlet.ShouldProcess($t.PackageFullName, "Remove-AppxPackage")) {
                    # For all-users packages, Remove-AppxPackage still runs per-user context.
                    # This typically removes from the current user; other profiles vary.
                    Remove-AppxPackage -Package $t.PackageFullName -ErrorAction Stop
                    Write-Host "Removed installed: $desc"
                }
            } catch {
                Write-Warning "Failed to remove installed: $desc  -> $($_.Exception.Message)"
            }
        }
    }
}

function Remove-ProvisionedAppx {
    Write-Host "=== Removing provisioned Appx packages (for new users) ==="

    $prov = Get-AppxProvisionedPackage -Online
    $targets = $prov | Where-Object { -not (Test-IsKept $_.DisplayName) } | Sort-Object DisplayName -Unique

    foreach ($t in $targets) {
        $desc = "$($t.DisplayName)  [$($t.PackageName)]"
        if ($WhatIfOnly) {
            Write-Host "[WhatIf] Would remove provisioned: $desc"
        } else {
            try {
                if ($PSCmdlet.ShouldProcess($t.PackageName, "Remove-AppxProvisionedPackage")) {
                    Remove-AppxProvisionedPackage -Online -PackageName $t.PackageName -ErrorAction Stop | Out-Null
                    Write-Host "Removed provisioned: $desc"
                }
            } catch {
                Write-Warning "Failed to remove provisioned: $desc  -> $($_.Exception.Message)"
            }
        }
    }
}

# --- Main ---
Write-Host "KEEP list patterns:" -ForegroundColor Cyan
$KeepPatterns | ForEach-Object { Write-Host "  - $_" }

if ($WhatIfOnly) {
    Write-Host "`nRunning in DRY-RUN mode (WhatIfOnly = true). Set -WhatIfOnly:$false to actually remove." -ForegroundColor Yellow
}

# Remove from current user (and optionally try all users)
Remove-InstalledAppx -UseAllUsers:$AllUsers

# Remove from image so it doesn't come back for new profiles (needs Admin)
try {
    Remove-ProvisionedAppx
} catch {
    Write-Warning "Provisioned removal may require an elevated PowerShell session (Run as Administrator)."
    Write-Warning $_.Exception.Message
}

Write-Host "`nDone."
