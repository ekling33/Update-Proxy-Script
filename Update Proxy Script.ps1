# Test TLS 1.2 to port 18900
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
$tcp = New-Object System.Net.Sockets.TcpClient
try { 
  $tcp.Connect("localhost", 18900)
  Write-Host "TLS 1.2 ✓ Port 18900 accepts connection"
} catch {
  Write-Host "TLS 1.2 ✗ Port 18900 rejects: $($_.Exception.Message)"
} finally { $tcp.Close() }
