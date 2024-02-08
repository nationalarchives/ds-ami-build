# server setup
# os and environment setup

param(
	[string]$application = "",
	[string]$environment = "",
	[string]$tier = "",
    [string] $keyfile = ""
)

$logFile = "\debug.txt"

function write-log
{
   param(
        [string]$Message,
        [string]$Severity = 'Information'
   )

   $Time = (Get-Date -f g)
   Add-content $logFile -value "$Time - $Severity - $Message"
   echo $Message
}
# Set-ExecutionPolicy Bypass -Scope Process

$tmpDir = "c:\temp"

"[debug]" | Out-File -FilePath \debug.txt

# required packages
$installerPackageUrl =  "s3://ds-intersite-deployment/discovery/installation-packages"

$wacInstaller = "WindowsAdminCenter2306.msi"
$dotnetInstaller = "ndp48-web.exe"
$dotnetPackagename = ".NET Framework 4.8 Platform (web installer)"
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

write-log -Message "=================> start server setup script"

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

    write-log -Message "---- create required directories"
    New-Item -itemtype "directory" $webSiteRoot -Force
    New-Item -itemtype "directory" "$servicesPath" -Force
    New-Item -itemtype "directory" "$webSitePath" -Force

    write-log -Message "===> AWS CLI V2"
    write-log -Message "---- downloading AWS CLI"
    Invoke-WebRequest -UseBasicParsing -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile "$tmpDir\AWSCLIV2.msi"
    write-log -Message "---- installing AWS CLI"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i,"$tmpDir\AWSCLIV2.msi",/qn
    write-log -Message "---- set path to AWS CLI"
    $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
    $newpath = $oldpath;$pathAWScli
    Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH -Value $newPath
    $env:Path = "$env:Path;$pathAWScli"

    #write-log -Message "===> AWS for PowerShell"
    #Import-Module AWSPowerShell

    write-log -Message "===> install CodeDeploy Agent"
    Invoke-Expression -Command "aws s3 cp s3://aws-codedeploy-eu-west-2/latest/codedeploy-agent.msi $tmpDir\codedeploy-agent.msi"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i,"$tmpDir\codedeploy-agent.msi /l $tmpDir\codedeploy-log.txt",/qn

    write-log -Message "===> IIS Remote Management"
    netsh advfirewall firewall add rule name="IIS Remote Management" dir=in action=allow protocol=TCP localport=8172
    Install-WindowsFeature Web-Mgmt-Service
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1
    Set-Service -Name WMSVC -StartupType Automatic

    write-log -Message "===> download and install required packages and config files"
    Set-Location -Path $tmpDir

    write-log -Message "===> get credentials"
    $InstanceId = Get-EC2InstanceMetadata -Category InstanceId
    $InstancePassword = Get-EC2PasswordData -InstanceId $InstanceId -Decrypt -PemFile "C:\tna-startup\$keyfile"
    $PWord = ConvertTo-SecureString "$InstancePassword" -AsPlainText -Force
    $UserName = "Administrator"
    $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $PWord
    $Password = $Credentials.GetNetworkCredential().Password
    Remove-Item "C:\tna-startup\$keyfile" -Force

    write-log -Message "===> aquire AWS credentials for intersite"
    $sts = (Use-STSRole -RoleArn "arn:aws:iam::500447081210:role/discovery-s3-deployment-source-access" -RoleSessionName "MyRoleSessionName").Credentials
    $Env:AWS_ACCESS_KEY_ID = $sts.AccessKeyId
    $Env:AWS_SECRET_ACCESS_KEY = $sts.SecretAccessKey
    $Env:AWS_SESSION_TOKEN = $sts.SessionToken

    write-log -Message "===> URLRewrite2"
    write-log -Message "---- download from S3"
    Invoke-Expression -Command "aws s3 cp s3://ds-intersite-deployment/discovery/installation-packages/rewrite_amd64_en-US.msi $tmpDir\rewrite_amd64_en-US.msi"
    write-log -Message "---- run installer"
    Start-Process -Wait -NoNewWindow -PassThru -FilePath msiexec -ArgumentList /i,"$tmpDir\rewrite_amd64_en-US.msi /norestart",/qn

    write-log -Message "===> install CloudWatch Agent"
    write-log -Message "---- download agent"
    (new-object System.Net.WebClient).DownloadFile($cloudwatchAgentInstaller, "$tmpDir\amazon-cloudwatch-agent.msi")
    write-log -Message "---- download config json"
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$cloudwatchAgentJSON $tmpDir"
    write-log -Message "---- start installation"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i,"$tmpDir\amazon-cloudwatch-agent.msi",/qn
    write-log -Message "---- configure agent"
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:$tmpDir\$cloudwatchAgentJSON -s
    write-log -Message "---- end cloudwatch installation process"

    write-log -Message "===> $dotnetPackagename"
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$dotnetInstaller $tmpDir"
    write-log -Message "---- start installation process"
    Start-Process -Wait -NoNewWindow -PassThru -FilePath "$tmpDir\$dotnetInstaller" -ArgumentList /q,/norestart
    write-log -Message "---- end installation process"

    if ($tier -eq "api") {
        write-log -Message "===> $dotnetCorePackagename"
        Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$dotnetCoreInstaller $tmpDir"
        write-log -Message "---- start installation process"
        Start-Process -Wait -NoNewWindow -PassThru -FilePath "$tmpDir\$dotnetCoreInstaller" -ArgumentList /q,/norestart
        write-log -Message "---- end installation process"
    }

    write-log -Message "---- import ServerManager"
    Import-Module ServerManager
    write-log -Message "---- import WebAdministration"
    Import-Module WebAdministration

    write-log -Message "---- create website"
    Stop-Website -Name "Default Web Site"
    Set-ItemProperty "IIS:\Sites\Default Web Site" serverAutoStart False
    Remove-WebSite -Name "Default Web Site"
    $site = new-WebSite -name $webSiteName -PhysicalPath $webSitePath -ApplicationPool $appPool -force

    write-log -Message "---- create AppPool"
    New-WebAppPool -name $appPool  -force
    Set-ItemProperty -Path IIS:\AppPools\$appPool -Name managedRuntimeVersion -Value "v4.0"
    Set-ItemProperty -Path IIS:\AppPools\$appPool -Name processModel.loadUserProfile -Value "True"

    write-log -Message "---- give IIS_USRS permissions"
    $acl = Get-ACL $webSiteRoot
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($accessRule)
    Set-ACL -Path "$webSiteRoot" -ACLObject $acl

    # remove unwanted IIS headers
    Clear-WebConfiguration "/system.webServer/httpProtocol/customHeaders/add[@name='X-Powered-By']"

    write-log -Message "---- add X-Forwarded-For to IIS log file"
    Add-WebConfigurationProperty -filter "system.applicationHost/sites/siteDefaults/logFile/customFields" -name "." -value @{logFieldName='xff';sourceName='X-Forwarded-For';sourceType='RequestHeader'}

    write-log -Message "===> set up scheduled task and register"
    $action = New-ScheduledTaskAction -Execute "c:\tna-start-up\push-logfiles.ps1"
    $trigger = New-ScheduledTaskTrigger -Daily -At '8:15 AM'
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 5) -RestartCount 5 -StartWhenAvailable
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings
    $task | Register-ScheduledTask 'PushLogfiles' -User $UserName -Password $Password

    Start-WebSite -Name $webSiteName

    # set system variables for application
    write-log -Message "===> environment variables"
    foreach ($key in $envHash.keys) {
        $envKey = $($key)
        $envValue = $($envHash[$key])
        [System.Environment]::SetEnvironmentVariable($envKey, $envValue, "Machine")
    }

    write-log -Message "===> set network interface profile to private"
    $networks = Get-NetConnectionProfile
    Write-Output $networks
    $interfaceIndex = $networks.InterfaceIndex
    write-log -Message "change interface index $interfaceIndex"
    Set-NetConnectionProfile -InterfaceIndex $interfaceIndex -NetworkCategory private
    Write-Output $(Get-NetConnectionProfile -InterfaceIndex $interfaceIndex)

    write-log -Message "===> enable SMBv2 signing"
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

    write-log -Message "===> EC2Launch"
    write-log -Message "---> set instance to generate a new password for next start and run user script"
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
    write-log -Message "---- schedule EC2Launch for next start"
    C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1 -Schedule

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath \setup-status.txt
    "finished = true" | Out-File -FilePath \setup-status.txt -Append

    write-log -Message "===> Windows Admin Center"
    netsh advfirewall firewall add rule name="WAC" dir=in action=allow protocol=TCP localport=3390
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$wacInstaller $tmpDir"
    write-log -Message "---- start installation process"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i,"$tmpDir\$wacInstaller /norestart /L*v wac-log.txt SME_PORT=3390 SSL_CERTIFICATE_OPTION=generate RESTART_WINRM=0",/qn
#    Start-Process -FilePath $wacInstaller -ArgumentList "/qn /L*v log.txt SME_PORT=3390 SSL_CERTIFICATE_OPTION=generate RESTART_WINRM=0" -PassThru -Wait

    write-log -Message "=================> end of server setup script"
} catch {
    write-log -Message "Caught an exception:"
    write-log -Message "Exception Type: $($_.Exception.GetType().FullName)"
    write-log -Message "Exception Message: $($_.Exception.Message)"
    exit 1
}
