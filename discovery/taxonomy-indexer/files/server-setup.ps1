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

$cloudwatchAgentJSON = "discovery-cloudwatch-agent.json"
$pathAWScli = "C:\Program Files\Amazon\AWSCLIV2"
$dotnetSDK6 = "https://download.visualstudio.microsoft.com/download/pr/4a725ea4-cd2c-4383-9b63-263156d5f042/d973777b32563272b85617105a06d272/dotnet-sdk-6.0.406-win-x64.exe"
$cloudwatchAgentInstaller = "https://s3.eu-west-1.amazonaws.com/amazoncloudwatch-agent-eu-west-1/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$codeTarget = "c://Elastic-Taxonomy//batch-update"

"=================> start server setup script" | Out-File -FilePath /debug.txt -Append

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

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

    "===> download and install dotnet sdk 6" | Out-File -FilePath /debug.txt -Append
    "download" | Out-File -FilePath /debug.txt -Append
    (new-object System.Net.WebClient).DownloadFile($dotnetSDK6, "$tmpDir\dotnet-sdk-6.0.406-win-x64.exe")
    "install" | Out-File -FilePath /debug.txt -Append
    & "$tmpDir\dotnet-sdk-6.0.406-win-x64.exe" /install /passive /norestart

    "===> download and install updater code" | Out-File -FilePath /debug.txt -Append
    "---- download code" | Out-File -FilePath /debug.txt -Append
    Invoke-Expression -Command "aws s3 cp s3://ds-$environment-deployment-source/taxonomy/taxonomy-indexer.zip $tmpDir/taxonomy-indexer.zip"
    "---- install code" | Out-File -FilePath /debug.txt -Append
    New-Item -Path "$codeTarget" -ItemType "directory" -Force
    Expand-Archive -LiteralPath "$tmpDir/taxonomy-indexer.zip" -DestinationPath "$codeTarget"

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
    Restart-Service AmazonSSMAgent

    "===> install EC2Launch" | Out-File -FilePath /debug.txt -Append
    $Url = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/386/latest/AmazonEC2Launch.msi"
    $DownloadFile = "c:\temp\" + $(Split-Path -Path $Url -Leaf)
    "download package" | Out-File -FilePath /debug.txt -Append
    Invoke-WebRequest -Uri $Url -OutFile $DownloadFile
    "install EC2Launch v2" | Out-File -FilePath /debug.txt -Append
    Start-Process -Wait -FilePath msiexec -ArgumentList /i, "$DownloadFile", /qn
    "write agent-config.yml" | Out-File -FilePath /debug.txt -Append
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
'@
    "reset EC2Launch" | Out-File -FilePath /debug.txt -Append
    & "C:\Program Files\Amazon\EC2Launch\ec2launch" reset -c

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath /setup-status.txt
    "finished = true" | Out-File -FilePath /setup-status.txt -Append

    "=================> end of server setup script" | Out-File -FilePath /debug.txt -Append
} catch {
    "Caught an exception:" | Out-File -FilePath /debug.txt -Append
    "Exception Type: $($_.Exception.GetType().FullName)" | Out-File -FilePath /debug.txt -Append
    "Exception Message: $($_.Exception.Message)" | Out-File -FilePath /debug.txt -Append
    exit 1
}
