$fwParams = @{
    DisplayName = "Nexus"
    Direction = "Inbound"
    LocalPort = "8081"
    Protocol = "TCP"
    Action = "Allow"
}

New-NetFirewallRule @fwParams
Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -enabled True
