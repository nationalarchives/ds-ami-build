# server setup
# os and environment setup

param(
	[string]$application = "",
	[string]$environment = "",
	[string]$tier = ""
)

# Set-ExecutionPolicy Bypass -Scope Process

$tmpDir = "c:\temp"

"[debug]" | Out-File -FilePath /debug.txt

# required packages
$installerPackageUrl =  "s3://ds-intersite-deployment/discovery/installation-packages"

$wacInstaller = "WindowsAdminCenter2110.2.msi"
$dotnetInstaller = "ndp48-web.exe"
$dotnetPackagename = ".NET Framework 4.8 Platform (web installer)"
$dotnetCoreInstaller = "dotnet-hosting-6.0.11-win.exe"
$dotnetCorePackagename = ".NET Core 6.0.11"
$cloudwatchAgentJSON = "discovery-cloudwatch-agent.json"
$pathAWScli = "C:\Program Files\Amazon\AWSCLIV2"

$cloudwatchAgentInstaller = "https://s3.eu-west-1.amazonaws.com/amazoncloudwatch-agent-eu-west-1/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$ec2launchInstallerUrl = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/amd64/latest"
$ec2launchInstaller = "AmazonEC2Launch.msi"

# website parameters
$appPool = "DiscoveryAppPool"
$webSiteName = "Main"
$webSiteRoot = "C:\WebSites"

# discovery front-end server setup requires to be based in RDWeb service
$servicesPath = "$webSiteRoot\Services"
if ($tier -eq "web") {
    $webSitePath = "$servicesPath\RDWeb"
} else {
    $webSitePath = "$webSiteRoot\Main"
}

# environment variables for target system
$envHash = @{
    "TNA_APP_ENVIRONMENT" = "$environment"
    "TNA_APP_TIER" = "$tier"
}

"=================> start server setup script" | Out-File -FilePath /debug.txt -Append

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

    "---- create required directories" | Out-File -FilePath /debug.txt -Append
    New-Item -itemtype "directory" $webSiteRoot -Force
    New-Item -itemtype "directory" "$servicesPath" -Force
    New-Item -itemtype "directory" "$webSitePath" -Force

    "===> AWS CLI V2" | Out-File -FilePath /debug.txt -Append
    "---- downloading AWS CLI" | Out-File -FilePath /debug.txt -Append
    Invoke-WebRequest -UseBasicParsing -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile c:/temp/AWSCLIV2.msi
    "---- installing AWS CLI" | Out-File -FilePath /debug.txt -Append
    Start-Process msiexec.exe -Wait -ArgumentList '/i c:\temp\AWSCLIV2.msi /qn /norestart' -NoNewWindow
    "---- set path to AWS CLI" | Out-File -FilePath /debug.txt -Append
    $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
    $newpath = $oldpath;$pathAWScli
    Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH -Value $newPath
    $env:Path = "$env:Path;$pathAWScli"

    "===> AWS for PowerShell" | Out-File -FilePath /debug.txt -Append
    Import-Module AWSPowerShell

    "===> install CodeDeploy Agent" | Out-File -FilePath /debug.txt -Append
    Invoke-Expression -Command "aws s3 cp s3://aws-codedeploy-eu-west-2/latest/codedeploy-agent.msi $tmpDir/codedeploy-agent.msi"
    Start-Process msiexec.exe -Wait -ArgumentList "/I `"$tmpDir\codedeploy-agent.msi`" /quiet /l `"$tmpDir\codedeploy-log.txt`""

    "===> WebPlatformInstaller and URLRewrite2" | Out-File -FilePath /debug.txt -Append
    (new-object System.Net.WebClient).DownloadFile("https://go.microsoft.com/fwlink/?LinkId=287166", "$tmpDir/WebPlatformInstaller_amd64_en-US.msi")
    Start-Process -FilePath "$tmpDir/WebPlatformInstaller_amd64_en-US.msi" -ArgumentList "/qn" -PassThru -Wait
    $logFile = "$tmpDir/WebpiCmd.log"
    Start-Process -FilePath "C:/Program Files/Microsoft/Web Platform Installer\WebpiCmd.exe" -ArgumentList "/Install /Products:'UrlRewrite2' /AcceptEULA /Log:$logFile" -PassThru -Wait

    "===> IIS Remote Management" | Out-File -FilePath /debug.txt -Append
    netsh advfirewall firewall add rule name="IIS Remote Management" dir=in action=allow protocol=TCP localport=8172
    Install-WindowsFeature Web-Mgmt-Service
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1
    Set-Service -Name WMSVC -StartupType Automatic


    "===> aquire AWS credentials" | Out-File -FilePath /debug.txt -Append
    $sts = Invoke-Expression -Command "aws sts assume-role --role-arn arn:aws:iam::500447081210:role/discovery-s3-deployment-source-access --role-session-name s3-access" | ConvertFrom-Json
    $Env:AWS_ACCESS_KEY_ID = $sts.Credentials.AccessKeyId
    $Env:AWS_SECRET_ACCESS_KEY = $sts.Credentials.SecretAccessKey
    $Env:AWS_SESSION_TOKEN = $sts.Credentials.SessionToken

    "===> download and install required packages and config files" | Out-File -FilePath /debug.txt -Append
    Set-Location -Path $tmpDir

    "===> install CloudWatch Agent" | Out-File -FilePath /debug.txt -Append
    "---- download agent" | Out-File -FilePath /debug.txt -Append
    (new-object System.Net.WebClient).DownloadFile($cloudwatchAgentInstaller, "$tmpDir\amazon-cloudwatch-agent.msi")
    "---- download config json" | Out-File -FilePath /debug.txt -Append
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$cloudwatchAgentJSON $tmpDir"
    "---- start installation" | Out-File -FilePath /debug.txt -Append
    Start-Process msiexec.exe -Wait -ArgumentList "/I `"$tmpDir\amazon-cloudwatch-agent.msi`" /quiet"
    "---- configure agent" | Out-File -FilePath /debug.txt -Append
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:$tmpDir\$cloudwatchAgentJSON -s
    "---- end cloudwatch installation process" | Out-File -FilePath /debug.txt -Append

    "===> $dotnetPackagename" | Out-File -FilePath /debug.txt -Append
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$dotnetInstaller $tmpDir"
    "---- start installation process" | Out-File -FilePath /debug.txt -Append
    Start-Process -FilePath $dotnetInstaller -ArgumentList "/q /norestart" -PassThru -Wait
    "---- end installation process" | Out-File -FilePath /debug.txt -Append

    if ($tier -eq "api") {
        "===> $dotnetCorePackagename" | Out-File -FilePath /debug.txt -Append
        Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$dotnetCoreInstaller $tmpDir"
        "---- start installation process" | Out-File -FilePath /debug.txt -Append
        Start-Process -FilePath $dotnetCoreInstaller -ArgumentList "/q /norestart" -PassThru -Wait
        "---- end installation process" | Out-File -FilePath /debug.txt -Append
    }

    "---- create AppPool" | Out-File -FilePath /debug.txt -Append
    Import-Module WebAdministration
    New-WebAppPool -name $appPool  -force
    Set-ItemProperty -Path IIS:\AppPools\$appPool -Name managedRuntimeVersion -Value 'v4.0'
    Set-ItemProperty -Path IIS:\AppPools\$appPool -Name processModel.loadUserProfile -Value 'True'

    "---- create website" | Out-File -FilePath /debug.txt -Append
    Stop-Website -Name "Default Web Site"
    Set-ItemProperty "IIS:\Sites\Default Web Site" serverAutoStart False
    Remove-WebSite -Name "Default Web Site"
    $site = new-WebSite -name $webSiteName -PhysicalPath $webSitePath -ApplicationPool $appPool -force

    "---- create .NET v6.0 AppPool" | Out-File -FilePath /debug.txt -Append
    $net6_app_pool_name = 'dotNET v6.0 AppPool'
    New-WebAppPool -name "$net6_app_pool_name" -force
    New-WebApplication -name 'DigitalMetadataAPI' -Site $webSiteName -PhysicalPath $webSitePath/DigitalMetadataAPI -ApplicationPool "$net6_app_pool_name" -force
    New-WebApplication -name 'IAdataAPI' -Site $webSiteName -PhysicalPath $webSitePath/IAdataAPI -ApplicationPool "$net6_app_pool_name" -force

    "---- give IIS_USRS permissions" | Out-File -FilePath /debug.txt -Append
    $acl = Get-ACL $webSiteRoot
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($accessRule)
    Set-ACL -Path "$webSiteRoot" -ACLObject $acl

    # remove unwanted IIS headers
    Clear-WebConfiguration "/system.webServer/httpProtocol/customHeaders/add[@name='X-Powered-By']"

    Start-WebSite -Name $webSiteName

    # set system variables for application
    "===> environment variables" | Out-File -FilePath /debug.txt -Append
    foreach ($key in $envHash.keys) {
        $envKey = $($key)
        $envValue = $($envHash[$key])
        [System.Environment]::SetEnvironmentVariable($envKey, $envValue, "Machine")
    }

    "===> set network interface profile to private" | Out-File -FilePath /debug.txt -Append
    $networks = Get-NetConnectionProfile
    Write-Output $networks
    $interfaceIndex = $networks.InterfaceIndex
    "change interface index $interfaceIndex" | Out-File -FilePath /debug.txt -Append
    Set-NetConnectionProfile -InterfaceIndex $interfaceIndex -NetworkCategory private
    Write-Output $(Get-NetConnectionProfile -InterfaceIndex $interfaceIndex)

    "===> enable SMBv2 signing" | Out-File -FilePath /debug.txt -Append
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

    "===> EC2Launch" | Out-File -FilePath /debug.txt -Append
    "---> set instance to generate a new password for next start and run user script" | Out-File -FilePath /debug.txt -Append
    $destination = "C:\ProgramData\Amazon\EC2-Windows\Launch\Config"
    Set-Content -Path "$destination\LaunchConfig.json" -Value @"
{
    "SetComputerName":  false,
    "SetMonitorAlwaysOn":  false,
    "SetWallpaper":  true,
    "AddDnsSuffixList":  true,
    "ExtendBootVolumeSize":  true,
    "HandleUserData":  true,
    "AdminPasswordType":  "Random",
    "AdminPassword":  ""
}
"@
    "---- schedule EC2Launch for next start" | Out-File -FilePath /debug.txt -Append
    C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1 -Schedule

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath /setup-status.txt
    "finished = true" | Out-File -FilePath /setup-status.txt -Append

    "===> Windows Admin Center" | Out-File -FilePath /debug.txt -Append
    netsh advfirewall firewall add rule name="WAC" dir=in action=allow protocol=TCP localport=3390
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$wacInstaller $tmpDir"
    "---- start installation process" | Out-File -FilePath /debug.txt -Append
    Start-Process -FilePath $wacInstaller -ArgumentList "/qn /L*v log.txt SME_PORT=3390 SSL_CERTIFICATE_OPTION=generate RESTART_WINRM=0" -PassThru -Wait

    "=================> end of server setup script" | Out-File -FilePath /debug.txt -Append
} catch {
    "Caught an exception:" | Out-File -FilePath /debug.txt -Append
    "Exception Type: $($_.Exception.GetType().FullName)" | Out-File -FilePath /debug.txt -Append
    "Exception Message: $($_.Exception.Message)" | Out-File -FilePath /debug.txt -Append
    exit 1
}
