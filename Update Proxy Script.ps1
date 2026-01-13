# Updated PowerShell script to read VM list from machines.txt and set WinHTTP proxy to proxy.jimmy.com:8080
# Usage: Save script as Set-ProxyRemotely.ps1, create machines.txt with one VM per line (hostnames/IPs),
# then run .\Set-ProxyRemotely.ps1 [-Credential (Get-Credential)]

param(
    [PSCredential]$Credential = (Get-Credential -Message "Enter admin credentials for VMs (optional)")
)

$machinesPath = "machines.txt"
if (-not (Test-Path $machinesPath)) {
    Write-Error "machines.txt not found in current directory."
    exit 1
}

$ComputerNames = Get-Content $machinesPath | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

foreach ($Computer in $ComputerNames) {
    try {
        Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock {
            $ProxyServer = "proxy.jimmy.com:8080"
            netsh winhttp set proxy $ProxyServer
            $CurrentProxy = netsh winhttp show proxy
            Write-Output "Proxy set to $ProxyServer on $env:COMPUTERNAME"
            Write-Output $CurrentProxy
        } -ErrorAction Stop
        Write-Host "Successfully updated proxy on $Computer" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to update $Computer : $($_.Exception.Message)"
    }
}

Write-Host "Script completed. Check output for results." -ForegroundColor Yellow
