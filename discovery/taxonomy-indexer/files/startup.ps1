# startup and deployment script for taxonomy .NET framework

$logFile = "startup.log"
$runFlag = "startupActive.txt"

function write-log
{
   param(
        [string]$Message,
        [string]$Severity = 'Information'
   )

   $Time = (Get-Date -f g)
   Add-content $logFile -value "$Time - $Severity - $Message"
}

try {
	if (Test-Path -Path "$runFlag" -PathType leaf) {
		write-log -Message "script is already active" -Severity "Warning"
		exit
	} else {
		$Time = (Get-Date -f g)
		Add-content $runFlag -value "$Time - startup script is activated"
	}

	Restart-Service AmazonSSMAgent

	$sysEnv = $Env:TNA_APP_ENVIRONMENT

	# check if environment is set correctly
	if (-not ($sysEnv -eq "dev" -or $sysEnv -eq "staging" -or $sysEnv -eq "live")) {
		write-log -Message "environment variable not set" -Severity "Error"
		exit 1
	}

} catch {
	write-log -Message "Caught an exception:" -Severity "Error"
	write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Error"
	write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Error"
    exit 1
}
