# Final PowerShell script: Reads machines.txt, sets WinHTTP proxy remotely as admin (no credential prompt)
# Usage: Create machines.txt (one VM per line), run .\Set-ProxyRemotely.ps1 as Administrator

$machinesPath = "machines.txt"
if (-not (Test-Path $machinesPath)) {
    Write-Error "machines.txt not found in current directory. Create it with one VM hostname/IP per line."
    exit 1
}

$ComputerNames = Get-Content $machinesPath | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }

Write-Host "Starting proxy update on $($ComputerNames.Count) machines from $machinesPath" -ForegroundColor Cyan

foreach ($Computer in $ComputerNames) {
    try {
        Invoke-Command -ComputerName $Computer -ScriptBlock {
            $ProxyServer = "proxy.jimmy.com:8080"
            netsh winhttp set proxy $ProxyServer
            $CurrentProxy = netsh winhttp show proxy
            "SUCCESS: Proxy set to $ProxyServer on $env:COMPUTERNAME"
            $CurrentProxy
        } -ErrorAction Stop | ForEach-Object { Write-Host $_ -ForegroundColor Green }
    }
    catch {
        Write-Warning "FAILED: $Computer - $($_.Exception.Message)"
    }
}

Write-Host "Proxy update process completed. Review output above." -ForegroundColor Yellow
