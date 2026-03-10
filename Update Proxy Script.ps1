reagentc /disable
$WinREPath = (reagentc /info | Select-String "Windows RE location").Line.Split(':')[1].Trim() + ':\Recovery\WindowsRE\winre.wim'
mkdir C:\winremount -Force
dism /Mount-Image /ImageFile:$WinREPath /Index:1 /MountDir:C:\winremount
dism /Image:C:\winremount /Add-Package /PackagePath:"C:\Downloads\windows10.0-kb5034232-x64.cab"
dism /Unmount-Image /MountDir:C:\winremount /Commit
reagentc /enable
