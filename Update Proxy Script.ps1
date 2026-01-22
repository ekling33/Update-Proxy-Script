# Remote Web Media Extensions user profile scanner
# Run as Administrator. Scans machines.txt for per-user package details
# Requires WinRM enabled on targets

$machines = Get-Content -Path "machines.txt" | Where-Object { $_ -match '\S' }

foreach ($machine in $machines) {
    Write-Host "`n=== SCANNING $machine ===" -ForegroundColor Yellow
    
    try {
        Invoke-Command -ComputerName $machine -ScriptBlock {
            $webMediaPkgs = Get-AppxPackage -AllUsers *WebMediaExtensions* -ErrorAction SilentlyContinue
            
            if (-not $webMediaPkgs) {
                Write-Host "✓ No Web Media Extensions packages found. CLEAN!" -ForegroundColor Green
                return
            }
            
            Write-Host "Found $($webMediaPkgs.Count) package(s):" -ForegroundColor Red
            
            foreach ($pkg in $webMediaPkgs | Sort-Object Name) {
                Write-Host "`n  Package: $($pkg.Name) v$($pkg.Version)" -ForegroundColor Yellow
                Write-Host "  FullName: $($pkg.PackageFullName)" -ForegroundColor Gray
                
                if ($pkg.PackageUserInformation) {
                    foreach ($userInfo in $pkg.PackageUserInformation) {
                        $sid = $userInfo.UserSecurityId
                        $profile = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue
                        $profilePath = $profile.ProfileImagePath
                        $username = if ($profilePath) { Split-Path $profilePath -Leaf } else { "DELETED" }
                        $state = if ($userInfo.IsCurrentUser) { 
                            "ACTIVE (Current User: $env:USERNAME)" 
                        } elseif ($profilePath -and (Test-Path $profilePath)) { 
                            "INACTIVE LOCAL PROFILE" 
                        } elseif ($profile) { 
                            "ORPHANED SID (Profile Deleted)" 
                        } else { 
                            "UNKNOWN SID" 
                        }
                        
                        Write-Host "    SID: $sid | User: $username | State: $state" -ForegroundColor White
                    }
                } else {
                    Write-Host "    No user info (rare system package)" -ForegroundColor Cyan
                }
            }
        } -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed $machine`: $($_.Exception.Message)"
    }
}

Write-Host "`nNext: Use logon scripts for ACTIVE/INACTIVE users. ORPHANED safe to ignore." -ForegroundColor Cyan
