param (
    $appPool = "DiscoveryAppPool"
)
net start w3svc
Start-WebAppPool -Name $appPool
