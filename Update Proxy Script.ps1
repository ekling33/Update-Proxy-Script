# QID-92030 Remover - PsExec Only (ZERO Prompts, SYSTEM Context)
# https://docs.microsoft.com/sysinternals/downloads/psexec
# Save as RemoveVulns.ps1, put PsExec.exe beside it, run as Admin

$machines = Get-Content .\machines.txt | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logFile = "RemovalResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$scriptBlock = {
    $apps = @('*RawImageExtension*', '*VP9VideoExtensions*')
    foreach ($pattern in $apps) {
        1..3 | ForEach-Object {
            $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
            if ($pkgs) { $pkgs | Remove-AppxPackage -AllUsers -ErrorAction Stop }
            Start-Sleep 3
        }
    }
    Get-AppXProvisionedPackage -Online | ? DisplayName -match 'RawImageExtension|VP9VideoExtensions' | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

    gps Microsoft.Photos*, Movies*, *Store* | sp -Force -ea SilentlyContinue
    $p = 'C:\Program Files\WindowsApps'
    if (Test-Path $p) {
        ri "$p\*Raw*" -Recurse -Force -ea SilentlyContinue
        ri "$p\*VP9*" -Recurse -Force -ea SilentlyContinue
    }

    $rem = gapx -AllUsers '*Raw*|*VP9*' -ea SilentlyContinue
    if (-not $rem) { "SUCCESS: Clean on $env:COMPUTERNAME" } else { "WARNING: $($rem.Name)" }
}

foreach ($m in $machines) {
    $ts = Get-Date -f 'yyyy-MM-dd HH:mm:ss'
    $out = .\PsExec.exe \\$m -s -nobanner powershell -ep Bypass -c "& {$scriptBlock}" 2>&1
    $status = if ($LASTEXITCODE -eq 0) { 'SUCCESS' } else { "FAILED (Code $LASTEXITCODE)" }
    "[$ts] $status $m`n$out`n" | Tee -FilePath $logFile -Append
}
"Done. Log: $logFile"
