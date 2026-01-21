# QID-92030 Remover - WinRM No Prompts (After TrustedHosts)
# FIRST: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force  (or your machines)
# Run as DOMAIN Admin

$machines = Get-Content .\machines.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logFile = "RemovalResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$scriptBlock = {
    $apps = @('*RawImageExtension*', '*VP9VideoExtensions*')
    foreach ($pattern in $apps) {
        1..3 | % {
            $pkgs = Get-AppxPackage -AllUsers $pattern -ea SilentlyContinue
            if ($pkgs) { $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop }
            Start-Sleep 3
        }
    }
    Get-AppXProvisionedPackage -Online | ? DisplayName -match 'RawImageExtension|VP9VideoExtensions' | Remove-AppxProvisionedPackage -Online -ea SilentlyContinue
    gps Microsoft.Photos*,Movies*,*Store* | sp -Force -ea SilentlyContinue
    $p = 'C:\Program Files\WindowsApps'
    if (Test-Path $p) { ri "$p\*Raw*" -Recurse -Force -ea SilentlyContinue; ri "$p\*VP9*" -Recurse -Force -ea SilentlyContinue }
    $rem = Get-AppxPackage -AllUsers '*Raw*|*VP9*' -ea SilentlyContinue
    if (-not $rem) { "SUCCESS on $env:COMPUTERNAME" } else { "REMNANTS: $($rem.Name)" }
}

foreach ($m in $machines) {
    $ts = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
    if (Test-WSMan $m -ea SilentlyContinue) {
        $out = Invoke-Command -ComputerName $m -ScriptBlock $scriptBlock -ea Stop 2>&1
        "[$ts] SUCCESS $m`n$out`n" | Tee -FilePath $logFile -Append
    } else {
        "[$ts] FAILED $m - No WinRM`n" | Tee -FilePath $logFile -Append
    }
}
"Done. Log: $logFile"
