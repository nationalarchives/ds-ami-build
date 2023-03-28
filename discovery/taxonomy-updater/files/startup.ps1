# startup and deployment script for taxonomy .NET framework

$logFile = "\startup.log"
$runFlag = "\startupActive.txt"
$codeTarget = "c:\taxonomy-daily-index"

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

	write-log -Message "starting updater"
	Set-Location -Path "$codeTarget"

	write-log -Message "--- live - NationalArchives.Taxonomy.Batch.exe"
	Start-Process "$codeTarget\live\process\NationalArchives.Taxonomy.Batch.exe" -WindowStyle "Hidden"
	write-log -Message "--- live - NationalArchives.Taxonomy.Batch.Update.Elastic.exe"
	Start-Process "$codeTarget\live\update\NationalArchives.Taxonomy.Batch.Update.Elastic.exe" -WindowStyle "Hidden"
	write-log -Message "--- staging - NationalArchives.Taxonomy.Batch.exe"
	Start-Process "$codeTarget\staging\process\NationalArchives.Taxonomy.Batch.exe" -WindowStyle "Hidden"
	write-log -Message "--- staging - NationalArchives.Taxonomy.Batch.Update.Elastic.exe"
	Start-Process "$codeTarget\staging\update\NationalArchives.Taxonomy.Batch.Update.Elastic.exe" -WindowStyle "Hidden"
	write-log -Message "all processes started"
	del $runFlag
} catch {
	write-log -Message "Caught an exception:" -Severity "Error"
	write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Error"
	write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Error"
	del $runFlag
    exit 1
}
