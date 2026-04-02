# RD cert issues
Get-WmiObject Win32_TerminalServiceSetting | Select-Object SSLCertificateSHA1Hash

# Event 1064 details
Get-WinEvent -FilterHashtable @{LogName='System'; ID=1064} -MaxEvents 1 | Select TimeCreated, Message
