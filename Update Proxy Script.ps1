##Step 1:

# Create self-signed certificate
# Create self-signed certificate (corrected syntax)
$cert = New-SelfSignedCertificate `
  -DnsName $env:COMPUTERNAME, "localhost" `
  -CertStoreLocation "cert:\LocalMachine\My" `
  -KeyUsage DigitalSignature, KeyEncipherment `
  -Type SSLServerAuthentication `
  -NotAfter (Get-Date).AddYears(2)

  ##Step 2:
  # Add certificate to Trusted Root Certification Authorities
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store `
  -ArgumentList Root, LocalMachine
$rootStore.Open("MaxAllowed")
$rootStore.Add($cert)
$rootStore.Close()

##Step 3:

# Get the thumbprint (needed for Blue Prism configuration)
$cert.Thumbprint
