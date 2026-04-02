# Generate GPO report (no restart needed)
gpresult /scope computer /h C:\GPReport.html

# Quick SSL policy check
gpresult /scope computer /v | findstr -i "cipher\|ssl\|schannel\|tls"
