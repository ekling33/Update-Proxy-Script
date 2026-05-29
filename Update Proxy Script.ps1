Get-MpComputerStatus | Select-Object 
  AMProductVersion,        # platform version (what you showed)
  AntivirusSignatureVersion, 
  AntivirusSignatureLastUpdated, 
  RealTimeProtectionEnabled, 
  AMServiceEnabled | Format-List
