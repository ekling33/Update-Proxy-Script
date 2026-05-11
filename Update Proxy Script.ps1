@echo off
setlocal EnableExtensions EnableDelayedExpansion
color 1F

echo ==================================================
echo Microsoft Defender / Windows Update Repair Script
echo ==================================================
echo.
echo This script must be run as Administrator.
echo.

net session >nul 2>&1
if not %errorlevel%==0 (
  echo [ERROR] Please right-click this file and choose Run as administrator.
  echo.
  pause
  exit /b 1
)

echo [1/8] Stopping update-related services...
net stop wuauserv /y
net stop cryptSvc /y
net stop bits /y
net stop msiserver /y
net stop usosvc /y

echo.
echo [2/8] Clearing Windows Update cache...
if exist C:\Windows\SoftwareDistribution (
  ren C:\Windows\SoftwareDistribution SoftwareDistribution.old.%random%
)
if exist C:\Windows\System32\catroot2 (
  ren C:\Windows\System32\catroot2 catroot2.old.%random%
)

echo.
echo [3/8] Resetting network/update stack...
netsh winsock reset
netsh winhttp reset proxy
ipconfig /flushdns

echo.
echo [4/8] Starting services again...
net start cryptSvc
net start bits
net start msiserver
net start wuauserv
net start usosvc

echo.
echo [5/8] Running system file checks...
sfc /scannow
DISM /Online /Cleanup-Image /RestoreHealth

echo.
echo [6/8] Trying Defender signature update...
if exist "%ProgramFiles%\Windows Defender\MpCmdRun.exe" (
  "%ProgramFiles%\Windows Defender\MpCmdRun.exe" -SignatureUpdate
) else if exist "%ProgramData%\Microsoft\Windows Defender\Platform" (
  for /f "delims=" %%I in ('dir /b /ad /o-n "%ProgramData%\Microsoft\Windows Defender\Platform"') do (
    if exist "%ProgramData%\Microsoft\Windows Defender\Platform\%%I\MpCmdRun.exe" (
      "%ProgramData%\Microsoft\Windows Defender\Platform\%%I\MpCmdRun.exe" -SignatureUpdate
      goto :afterupdate
    )
  )
)
:afterupdate

echo.
echo [7/8] Opening Windows Security update page...
start windowsdefender:

echo.
echo [8/8] Cleanup note:
echo Old update cache folders were renamed, not deleted.
echo You can remove the old SoftwareDistribution.old.* and catroot2.old.* folders later after confirming updates work.
echo.
echo Script completed. A reboot is strongly recommended before testing again.
echo.
pause
endlocal
