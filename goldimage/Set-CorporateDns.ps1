# Step 3: pin the corporate resolvers FIRST on the LAN adapter. Run as admin.
# WSL inherits the host resolver order through DNS tunneling; a public
# resolver listed first makes internal names randomly fail inside WSL.

# ---- EDIT THESE -------------------------------------------------------------
$InterfaceAlias = 'Ethernet0'                  # Get-NetAdapter to list yours
$DnsServers     = @('10.0.0.53')               # corporate resolvers, in order
$ProbeFqdn      = 'intranet.example.internal'  # a name that must resolve
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers

$probe = Resolve-DnsName $ProbeFqdn -ErrorAction SilentlyContinue
if ($probe) {
    Write-Host "OK: $ProbeFqdn -> $($probe[0].IPAddress)"
} else {
    Write-Warning "$ProbeFqdn does not resolve - fix DNS before continuing"
    exit 1
}
