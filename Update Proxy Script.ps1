taskkill /f /im OfficeC2RClient.exe
taskkill /f /im OfficeClickToRun.exe
reg delete "HKCU\Software\Microsoft\Office\ClickToRun" /f
reg delete "HKLM\Software\Microsoft\Office\ClickToRun\Configuration" /v UpdateChannel /f
reg delete "HKLM\Software\Microsoft\Office\ClickToRun\Configuration" /v CDNBaseUrl /f
