# Update Google Chrome Enterprise via PowerShell (handles x86/x64)
# Closes Chrome processes, downloads latest MSI, installs silently, cleans up

# Close all Chrome processes
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "Closed Chrome processes."

# Determine system architecture
$is64Bit = [Environment]::Is64BitOperatingSystem

# MSI URLs for latest stable enterprise versions
$msiUrl64 = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
$msiUrl32 = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi"
$msiUrl = if ($is64Bit) { $msiUrl64 } else { $msiUrl32 }

$tempDir = "$env:TEMP\ChromeUpdate"
$msiPath = "$tempDir\ChromeEnterprise.msi"

# Create temp dir
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # Download MSI
    Write-Host "Downloading Chrome Enterprise MSI..."
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
    Write-Host "Downloaded."

    # Install silently (upgrades existing, no reboot)
    Write-Host "Installing/Updating Chrome..."
    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -NoNewWindow

    Write-Host "Chrome updated successfully."
} catch {
    Write-Error "Error: $($_.Exception.Message)"
} finally {
    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
