# server setup
# os and environment setup

param(
	[string]$application = "",
	[string]$environment = ""
)

$logFile = "\server-setup.log"

function write-log
{
   param(
        [string]$Message,
        [string]$Severity = 'Information'
   )

   $Time = (Get-Date -f g)
   Add-content $logFile -value "$Time - $Severity - $Message"
}
# Set-ExecutionPolicy Bypass -Scope Process

$tmpDir = "c:\temp"

"[debug]" | Out-File -FilePath \debug.txt

# required packages
$installerPackageUrl = "s3://ds-$environment-deployment-source/installation-packages/discovery"

$cloudwatchAgentJSON = "discovery-cloudwatch-agent.json"
$pathAWScli = "C:\Program Files\Amazon\AWSCLIV2"
$dotnetSDK6 = "https://download.visualstudio.microsoft.com/download/pr/38dca5f5-f10f-49fb-b07f-a42dd123ea30/335bb4811c9636b3a4687757f9234db9/dotnet-sdk-6.0.407-win-x64.exe"
$cloudwatchAgentInstaller = "https://s3.eu-west-2.amazonaws.com/amazoncloudwatch-agent-eu-west-2/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$codeTarget = "c:\taxonomy-daily-index"

write-log -Message "=================> start server setup script" -Severity "Info"

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

    write-log -Message "===> AWS CLI V2" -Severity "Info"
    write-log -Message "---- downloading AWS CLI" -Severity "Info"
    Invoke-WebRequest -UseBasicParsing -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile "$tmpDir\AWSCLIV2.msi"
    write-log -Message "---- installing AWS CLI" -Severity "Info"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$tmpDir\AWSCLIV2.msi", /qn
    write-log -Message "---- set path to AWS CLI" -Severity "Info"
    $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
    $newpath = $oldpath;$pathAWScli
    Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH -Value $newPath
    $env:Path = "$env:Path;$pathAWScli"

    write-log -Message "===> AWS for PowerShell" -Severity "Info"
    Import-Module AWSPowerShell

    write-log -Message "===> download and install required packages and config files" -Severity "Info"
    Set-Location -Path $tmpDir

    write-log -Message "===> install CloudWatch Agent" -Severity "Info"
    write-log -Message "---- download agent" -Severity "Info"
    (new-object System.Net.WebClient).DownloadFile($cloudwatchAgentInstaller, "$tmpDir\amazon-cloudwatch-agent.msi")
    write-log -Message "---- download config json" -Severity "Info"
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$cloudwatchAgentJSON $tmpDir"
    write-log -Message "---- start installation" -Severity "Info"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$tmpDir\amazon-cloudwatch-agent.msi", /qn
    write-log -Message "---- configure agent" -Severity "Info"
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:$tmpDir\$cloudwatchAgentJSON -s

    write-log -Message "===> download and install dotnet sdk 6" -Severity "Info"
    write-log -Message "---- download" -Severity "Info"
    (new-object System.Net.WebClient).DownloadFile($dotnetSDK6, "$tmpDir\dotnet-sdk-6.0.407-win-x64.exe")
    write-log -Message "---- install" -Severity "Info"
    & "$tmpDir\dotnet-sdk-6.0.407-win-x64.exe" /install /passive /norestart

    write-log -Message "===> download and install updater code" -Severity "Info"
    write-log -Message "---- download code" -Severity "Info"
    Invoke-Expression -Command "aws s3 cp s3://ds-$environment-deployment-source/taxonomy/taxonomy-daily-index.zip $tmpDir\taxonomy-daily-index.zip"
    write-log -Message "---- install code" -Severity "Info"
    New-Item -Path "$codeTarget" -ItemType "directory" -Force
    Expand-Archive -LiteralPath "$tmpDir\taxonomy-daily-index.zip" -DestinationPath \

##    write-log -Message "===> set network interface profile to private" -Severity "Info"
##    $networks = Get-NetConnectionProfile
##    Write-Output $networks
##    $interfaceIndex = $networks.InterfaceIndex
##    write-log -Message "---- change interface index $interfaceIndex" -Severity "Info"
##    Set-NetConnectionProfile -InterfaceIndex $interfaceIndex -NetworkCategory private
##    Write-Output $(Get-NetConnectionProfile -InterfaceIndex $interfaceIndex)

    write-log -Message "===> enable SMBv2 signing" -Severity "Info"
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

##    write-log -Message "===> install SSM" -Severity "Info"
###    $progressPreference = 'silentlyContinue'
##    write-log -Message "---- download installer" -Severity "Info"
##    Invoke-WebRequest `
##        https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe `
##        -OutFile $tmpDir\SSMAgent_latest.exe
##
##    write-log -Message "---- run installer" -Severity "Info"
##    cd $tmpDir
##    Start-Process `
##        -FilePath .\SSMAgent_latest.exe `
##        -ArgumentList "/S"
##    Restart-Service AmazonSSMAgent

    write-log -Message "===> install EC2Launch" -Severity "Info"
    $Url = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/386/latest/AmazonEC2Launch.msi"
    $DownloadFile = "$tmpDir\" + $(Split-Path -Path $Url -Leaf)
    write-log -Message "---- download package" -Severity "Info"
    Invoke-WebRequest -Uri $Url -OutFile $DownloadFile
    write-log -Message "---- install EC2Launch v2" -Severity "Info"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$DownloadFile", /qn
    write-log -Message "---- copy agent-config.yml" -Severity "Info"
    copy "$tmpDir\agent-config.yml" "C:\ProgramData\Amazon\EC2Launch\agent-config.yml"
    write-log -Message "---- reset EC2Launch" -Severity "Info"
    & "C:\Program Files\Amazon\EC2Launch\ec2launch" reset -c

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath \setup-status.txt
    "finished = true" | Out-File -FilePath \setup-status.txt -Append

    write-log -Message "=================> end of server setup script" -Severity "Info"
} catch {
    write-log -Message "Caught an exception:" -Severity "Info"
    write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Info"
    write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Info"
    exit 1
}
