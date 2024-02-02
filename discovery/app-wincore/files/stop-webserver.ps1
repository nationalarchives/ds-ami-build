param (
    $appPool = "DiscoveryAppPool"
)
Stop-WebAppPool -Name $appPool
net stop w3svc
