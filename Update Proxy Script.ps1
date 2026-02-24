<# 
.SYNOPSIS
    Remotely uninstalls Notepad++ from a list of machines.

.DESCRIPTION
    - Reads machine names from .\machines.txt
    - For each machine, queries both 32-bit and 64-bit uninstall registry keys
      for DisplayName matching "Notepad++".
    - Executes the UninstallString silently (/S or /quiet /norestart when appropriate).
    - Writes basic status output to the console.

.NOTES
    Run this script from an elevated PowerShell session with rights to the remote PCs.
#>

$ComputerListPath = ".\machines.txt"
$ProgramName      = "Notepad++"

if (-not (Test-Path $ComputerListPath)) {
    Write-Error "machines.txt not found at path: $ComputerListPath"
    exit 1
}

$Computers = Get-Content -Path $ComputerListPath | Where-Object { $_ -and $_.Trim() -ne "" }

if (-not $Computers) {
    Write-Error "No computer names found in machines.txt"
    exit 1
}

foreach ($Computer in $Computers) {
    Write-Host "==== $Computer ===="

    try {
        # Build script block that runs ON the remote machine
        $scriptBlock = {
            param($ProgramName)

            $uninstallKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            $programs = foreach ($key in $uninstallKeys) {
                if (Test-Path $key) {
                    Get-ItemProperty $key |
                        Where-Object { $_.DisplayName -like "*$ProgramName*" -and $_.UninstallString } |
                        Select-Object DisplayName, UninstallString
                }
            }

            if (-not $programs) {
                Write-Output "Notepad++ not found."
                return
            }

            foreach ($program in $programs) {
                Write-Output "Found: $($program.DisplayName)"
                $uninst = $program.UninstallString.Trim('"')

                # If it's an MSI-based uninstall, normalize /I to /X and add quiet flags
                if ($uninst -match "^MsiExec\.exe\s*/I\s*[{[]?([A-F0-9]{8}-([A-F0-9]{4}-){3}[A-F0-9]{12})[}\]]?") {
                    $productCode = $matches[1]
                    $arguments = "/X `"$productCode`" /quiet /qn /norestart"
                    Write-Output "Running MSI uninstall for product code $productCode"
                    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                    Write-Output "Exit code: $($proc.ExitCode)"
                }
                else {
                    # Assume EXE uninstall; try to add silent switch if not present
                    if ($uninst -notmatch "\s/S(\s|$)" -and $uninst -notmatch "/silent" -and $uninst -notmatch "/quiet") {
                        $uninst += " /S"
                    }

                    Write-Output "Running EXE uninstall: $uninst"
                    $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninst`"" -Wait -PassThru -NoNewWindow
                    Write-Output "Exit code: $($proc.ExitCode)"
                }
            }
        }

        Invoke-Command -ComputerName $Computer -ScriptBlock $scriptBlock -ArgumentList $ProgramName -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed on $Computer`: $($_.Exception.Message)"
    }

    Write-Host ""
}
