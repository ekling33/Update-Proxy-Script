# Find Blue Prism services and their accounts
Get-WmiObject Win32_Service | Where-Object Name -like "*Blue Prism*" | 
  Select-Object Name, DisplayName, State, StartMode, StartName, PathName |
  Format-Table -AutoSize

# Detailed service config
sc qc "Blue Prism Server"
sc qc "BPService Default"  # or whatever the exact service name is
