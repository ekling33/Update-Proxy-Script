# Update Chrome Enterprise on remote machines from machines.txt
# Requires PSRemoting enabled on targets (Enable-PSRemoting -Force)

$machines = Get-Content .\machines.txt | Where-Object { $_ -match '\S' }

$scriptBlock = {
    # Embedded update logic (same as before)
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "[$env:COMPUTERNAME] Closed Chrome processes."

    $is64Bit = [Environment]::Is64BitOperatingSystem
    $msiUrl64 = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
    $msiUrl32 = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi"
    $msiUrl = if ($is64Bit) { $msiUrl64 } else { $msiUrl32 }
    $tempDir = "$env:TEMP\ChromeUpdate"
    $msiPath = "$tempDir\ChromeEnterprise.msi"

    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Write-Host "[$env:COMPUTERNAME] Downloading MSI..."
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath
        Write-Host "[$env:COMPUTERNAME] Downloaded."

        Write-Host "[$env:COMPUTERNAME] Installing..."
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -NoNewWindow
        Write-Host "[$env:COMPUTERNAME] Chrome updated."
    } catch {
        Write-Error "[$env:COMPUTERNAME] Error: $($_.Exception.Message)"
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Run on all machines (parallel by default, throttles to 32)
Invoke-Command -ComputerName $machines -ScriptBlock $scriptBlock -AsJob | Wait-Job | Receive-Job

Write-Host "All updates complete."
