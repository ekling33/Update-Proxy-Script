# Update Chrome Enterprise on remote machines from machines.txt (proxy + auth)
# Prompts for proxy creds ONCE, caches for all VMs

# Get proxy credentials ONCE (no repeat prompts)
$proxyCred = Get-Credential -Message "Enter proxy credentials for proxy.jimmy.com:8080 (domain\user or user)"
if (-not $proxyCred) { Write-Error "No proxy credentials provided. Exiting."; exit 1 }

$proxyUri = "http://proxy.jimmy.com:8080"
$machines = Get-Content .\machines.txt | Where-Object { $_ -match '\S' }

$scriptBlock = {
    param($proxyUri, $proxyCred)
    
    # Close Chrome
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
        Write-Host "[$env:COMPUTERNAME] Downloading MSI via proxy..."
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -Proxy $proxyUri -ProxyCredential $proxyCred
        Write-Host "[$env:COMPUTERNAME] Downloaded."

        Write-Host "[$env:COMPUTERNAME] Installing..."
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -Wait -NoNewWindow
        Write-Host "[$env:COMPUTERNAME] Chrome updated successfully."
    } catch {
        Write-Error "[$env:COMPUTERNAME] Error: $($_.Exception.Message)"
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Run on all machines (creds cached, passed once per VM)
Write-Host "Starting updates on $($machines.Count) machines..."
Invoke-Command -ComputerName $machines -ScriptBlock $scriptBlock -ArgumentList $proxyUri, $proxyCred -AsJob | Wait-Job | Receive-Job

Write-Host "All updates complete."
