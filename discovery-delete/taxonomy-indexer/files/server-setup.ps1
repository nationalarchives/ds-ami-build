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

write-log -Message "[debug]" | Out-File -FilePath \debug.txt

# required packages
$installerPackageUrl = "s3://ds-$environment-deployment-source/installation-packages/discovery"

$cloudwatchAgentJSON = "discovery-cloudwatch-agent.json"
$pathAWScli = "C:\Program Files\Amazon\AWSCLIV2"
$dotnetSDK6 = "https://download.visualstudio.microsoft.com/download/pr/38dca5f5-f10f-49fb-b07f-a42dd123ea30/335bb4811c9636b3a4687757f9234db9/dotnet-sdk-6.0.407-win-x64.exe"
$cloudwatchAgentInstaller = "https://s3.eu-west-1.amazonaws.com/amazoncloudwatch-agent-eu-west-1/windows/amd64/latest/amazon-cloudwatch-agent.msi"
$codeTarget = "c:\taxonomy-full-index"

write-log -Message "=================> start server setup script"

try {
    # Catch non-terminateing errors
    $ErrorActionPreference = "Stop"

    write-log -Message "===> AWS CLI V2"
    write-log -Message "---- downloading AWS CLI"
    Invoke-WebRequest -UseBasicParsing -Uri https://awscli.amazonaws.com/AWSCLIV2.msi -OutFile "$tmpDir\AWSCLIV2.msi"
    write-log -Message "---- installing AWS CLI"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$tmpDir\AWSCLIV2.msi", /qn
    write-log -Message "---- set path to AWS CLI"
    $oldpath = (Get-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH).path
    $newpath = $oldpath;$pathAWScli
    Set-ItemProperty -Path "Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment" -Name PATH -Value $newPath
    $env:Path = "$env:Path;$pathAWScli"

    write-log -Message "===> AWS for PowerShell"
    Import-Module AWSPowerShell

    write-log -Message "===> download and install required packages and config files"
    Set-Location -Path $tmpDir

    write-log -Message "===> install CloudWatch Agent"
    write-log -Message "---- download agent"
    (new-object System.Net.WebClient).DownloadFile($cloudwatchAgentInstaller, "$tmpDir\amazon-cloudwatch-agent.msi")
    write-log -Message "---- download config json"
    Invoke-Expression -Command "aws s3 cp $installerPackageUrl/$cloudwatchAgentJSON $tmpDir"
    write-log -Message "---- start installation"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$tmpDir\amazon-cloudwatch-agent.msi", /qn
    write-log -Message "---- configure agent"
    & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -c file:$tmpDir\$cloudwatchAgentJSON -s

    write-log -Message "===> download and install dotnet sdk 6"
    write-log -Message "---- download"
    (new-object System.Net.WebClient).DownloadFile($dotnetSDK6, "$tmpDir\dotnet-sdk-6.0.407-win-x64.exe")
    write-log -Message "---- install"
    & "$tmpDir\dotnet-sdk-6.0.407-win-x64.exe" /install /passive /norestart

    write-log -Message "===> download and install indexer code"
    write-log -Message "---- download code"
    Invoke-Expression -Command "aws s3 cp s3://ds-$environment-deployment-source/taxonomy/taxonomy-full-index.zip $tmpDir\taxonomy-full-index.zip"
    write-log -Message "---- install code"
    New-Item -Path "$codeTarget" -ItemType "directory" -Force
    Expand-Archive -LiteralPath "$tmpDir\taxonomy-full-index.zip" -DestinationPath \

    write-log -Message "===> enable SMBv2 signing"
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

    write-log -Message "===> install EC2Launch"
    $Url = "https://s3.amazonaws.com/amazon-ec2launch-v2/windows/386/latest/AmazonEC2Launch.msi"
    $DownloadFile = "$tmpDir\" + $(Split-Path -Path $Url -Leaf)
    write-log -Message "---- download package"
    Invoke-WebRequest -Uri $Url -OutFile $DownloadFile
    write-log -Message "---- install EC2Launch v2"
    Start-Process -Wait -NoNewWindow -FilePath msiexec -ArgumentList /i, "$DownloadFile", /qn
    write-log -Message "---- copy agent-config.yml"
    copy "$tmpDir\agent-config.yml" "C:\ProgramData\Amazon\EC2Launch\agent-config.yml"
    write-log -Message "---- reset EC2Launch"
    & "C:\Program Files\Amazon\EC2Launch\ec2launch" reset -c

    # this need to be before WAC installation. The installation will restart winrm and the script won't finish
    "[status]" | Out-File -FilePath \setup-status.txt
    "finished = true" | Out-File -FilePath \setup-status.txt -Append

    write-log -Message "=================> end of server setup script"
} catch {
    "Caught an exception:"
    "Exception Type: $($_.Exception.GetType().FullName)"
    "Exception Message: $($_.Exception.Message)"
    exit 1
}
