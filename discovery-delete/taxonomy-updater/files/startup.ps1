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

	write-log -Message "starting updater"

	write-log -Message "--- live-process - NationalArchives.Taxonomy.Batch.exe"
	Set-Location "$codeTarget\live\process"
	start powershell .\NationalArchives.Taxonomy.Batch.exe

	write-log -Message "--- live-update - NationalArchives.Taxonomy.Batch.Update.Elastic.exe"
	Set-Location "$codeTarget\live\update"
	start powershell .\NationalArchives.Taxonomy.Batch.Update.Elastic.exe

	write-log -Message "--- staging-process - NationalArchives.Taxonomy.Batch.exe"
	Set-Location "$codeTarget\staging\process"
	start powershell .\NationalArchives.Taxonomy.Batch.exe

	write-log -Message "--- staging-update - NationalArchives.Taxonomy.Batch.Update.Elastic.exe"
	Set-Location "$codeTarget\staging\update"
	start powershell .\NationalArchives.Taxonomy.Batch.Update.Elastic.exe

	write-log -Message "all processes started"
	Remove-Item $runFlag
} catch {
	write-log -Message "Caught an exception:" -Severity "Error"
	write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Error"
	write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Error"
	Remove-Item $runFlag
    exit 1
}
