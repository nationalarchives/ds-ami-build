# server setup
# os and environment setup

param(
	[string]$application = "",
	[string]$environment = ""
)

# Set-ExecutionPolicy Bypass -Scope Process

$tmpDir = "c:\temp"

"[debug]" | Out-File -FilePath /debug.txt

# required packages
$installerPackageUrl =  "s3://ds-intersite-deployment/discovery/installation-packages"

$wacInstaller = "WindowsAdminCenter2110.2.msi"
$dotnetInstaller = "ndp48-web.exe"
$dotnetPackagename = ".NET Framework 4.8 Platform (web installer)"
$cloudwatchAgentJSON = "discovery-cloudwatch-agent.json"
$pathAWScli = "C:\Program Files\Amazon\AWSCLIV2"

$cloudwatchAgentInstaller = "https://s3.eu-west-1.amazonaws.com/amazoncloudwatch-agent-eu-west-1/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$ec2launchInstallerUrl = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/amd64/latest"
$ec2launchInstaller = "AmazonEC2Launch.msi"

## # website parameters
## $appPool = "TaxonomyAppPool"
## $webSiteName = "Main"
## $webSiteRoot = "C:\WebSites"
##
## # discovery front-end server setup requires to be based in RDWeb service
## $servicesPath = "$webSiteRoot\Services"
## if ($tier -eq "web") {
##     $webSitePath = "$servicesPath\RDWeb"
## } else {
##     $webSitePath = "$webSiteRoot\Main"
## }
##
## # environment variables for target system
## $envHash = @{
##     "TNA_APP_ENVIRONMENT" = "$environment"
##     "TNA_APP_TIER" = "$tier"
## }

"=================> start server setup script" | Out-File -FilePath /debug.txt -Append

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

##     "---- create required directories" | Out-File -FilePath /debug.txt -Append
##     New-Item -itemtype "directory" $webSiteRoot -Force
##     New-Item -itemtype "directory" "$servicesPath" -Force
##     New-Item -itemtype "directory" "$webSitePath" -Force

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

    "===> URLRewrite2" | Out-File -FilePath /debug.txt -Append
    "---- download from S3" | Out-File -FilePath /debug.txt -Append
    Invoke-Expression -Command "aws s3 cp s3://ds-intersite-deployment/discovery/installation-packages/rewrite_amd64_en-US.msi $tmpDir/rewrite_amd64_en-US.msi"
    "---- run installer" | Out-File -FilePath /debug.txt -Append
    Start-Process -FilePath "$tmpDir/rewrite_amd64_en-US.msi" -ArgumentList "/quiet /norestart" -PassThru -Wait

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

##     if ($tier -eq "api") {
##         "===> $dotnetCorePackagename" | Out-File -FilePath /debug.txt -Append
##         Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$dotnetCoreInstaller $tmpDir"
##         "---- start installation process" | Out-File -FilePath /debug.txt -Append
##         Start-Process -FilePath $dotnetCoreInstaller -ArgumentList "/q /norestart" -PassThru -Wait
##         "---- end installation process" | Out-File -FilePath /debug.txt -Append
##     }
##
##     "---- create AppPool" | Out-File -FilePath /debug.txt -Append
##     Import-Module WebAdministration
##     New-WebAppPool -name $appPool  -force
##     Set-ItemProperty -Path IIS:\AppPools\$appPool -Name managedRuntimeVersion -Value 'v4.0'
##     Set-ItemProperty -Path IIS:\AppPools\$appPool -Name processModel.loadUserProfile -Value 'True'
##
##     "---- create website" | Out-File -FilePath /debug.txt -Append
##     Stop-Website -Name "Default Web Site"
##     Set-ItemProperty "IIS:\Sites\Default Web Site" serverAutoStart False
##     Remove-WebSite -Name "Default Web Site"
##     $site = new-WebSite -name $webSiteName -PhysicalPath $webSitePath -ApplicationPool $appPool -force
##
##     "---- give IIS_USRS permissions" | Out-File -FilePath /debug.txt -Append
##     $acl = Get-ACL $webSiteRoot
##     $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
##     $acl.AddAccessRule($accessRule)
##     Set-ACL -Path "$webSiteRoot" -ACLObject $acl
##
##     # remove unwanted IIS headers
##     Clear-WebConfiguration "/system.webServer/httpProtocol/customHeaders/add[@name='X-Powered-By']"
##
##     Start-WebSite -Name $webSiteName

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

    "===> install SSM" | Out-File -FilePath /debug.txt -Append
#    $progressPreference = 'silentlyContinue'
    "download installer" | Out-File -FilePath /debug.txt -Append
    Invoke-WebRequest `
        https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe `
        -OutFile $tmpDir\SSMAgent_latest.exe
    "run installer" | Out-File -FilePath /debug.txt -Append
    cd $tmpDir
    Start-Process `
        -FilePath .\SSMAgent_latest.exe `
        -ArgumentList "/S"
    "remove installer" | Out-File -FilePath /debug.txt -Append
    rm -Force .\SSMAgent_latest.exe

    Set-Content -Path "C:\ProgramData\Amazon\EC2Launch\config\agent-config.yml" -Value @'
version: 1.0
config:
  - stage: boot
    tasks:
      - task: extendRootPartition
  - stage: preReady
    tasks:
      - task: activateWindows
        inputs:
          activation:
            type: amazon
      - task: setDnsSuffix
        inputs:
          suffixes:
            - $REGION.ec2-utilities.amazonaws.com
      - task: setAdminAccount
        inputs:
          password:
            type: random
      - task: setWallpaper
        inputs:
          path: C:\ProgramData\Amazon\EC2Launch\wallpaper\Ec2Wallpaper.jpg
          attributes:
            - hostName
            - instanceId
            - privateIpAddress
            - publicIpAddress
            - instanceSize
            - availabilityZone
            - architecture
            - memory
            - network
  - stage: postReady
    tasks:
      - task: startSsm
      - task: executeScript
         inputs:
           frequency: once
           type: powershell
           runAs: localSystem
           detach: true
           content: |-
           cd 'C:\Program Files\Amazon\EC2Launch'
           & .\EC2Launch.exe reset --clean --block

'@

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath /setup-status.txt
    "finished = true" | Out-File -FilePath /setup-status.txt -Append

#    "===> Windows Admin Center" | Out-File -FilePath /debug.txt -Append
#    netsh advfirewall firewall add rule name="WAC" dir=in action=allow protocol=TCP localport=3390
#    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$wacInstaller $tmpDir"
#    "---- start installation process" | Out-File -FilePath /debug.txt -Append
#    Start-Process -FilePath $wacInstaller -ArgumentList "/qn /L*v log.txt SME_PORT=3390 SSL_CERTIFICATE_OPTION=generate RESTART_WINRM=0" -PassThru -Wait

    "=================> end of server setup script" | Out-File -FilePath /debug.txt -Append
} catch {
    "Caught an exception:" | Out-File -FilePath /debug.txt -Append
    "Exception Type: $($_.Exception.GetType().FullName)" | Out-File -FilePath /debug.txt -Append
    "Exception Message: $($_.Exception.Message)" | Out-File -FilePath /debug.txt -Append
    exit 1
}
