# Get-EC2InstanceMetadata can take a long time to run
param([switch] $termination)

$InstanceId = Get-EC2InstanceMetadata -Category InstanceId
$Today = Get-Date -Format "yyMMdd"
$TodaysLog = "u_ex" + $Today + "*"

$SourceDir = "C:\inetpub\logs\LogFiles\W3SVC1\"

if ($termination) {
    & "c:/tna-startup/stop-webserver.ps1"
    $files = Get-ChildItem $SourceDir
} else {
    $files = Get-ChildItem $SourceDir -Exclude $Todayslog
}

if ([string]::IsNullOrEmpty($files)) {
    Write-Output 'No logfiles found'
} else {
    foreach ($file in $files) {
        $fileName = $file.name
        Write-Output $file_name
        $zipName = (Get-Item ($SourceDir + $fileName)).Basename + "_" + $InstanceId + ".zip"
        Write-Output $zipName
        Compress-Archive -Path "$SourceDir$fileName" -DestinationPath "$SourceDir$zipName"
    }
    # Compress-Archive returns before the process has finished and locks the file for some time afterwards.
    # This is the reason to split the compressing from the copy-delete to give the process to finish and unlock the file.
    Start-Sleep -Seconds 5
    foreach ($file in $files) {
        if (Test-Path -Path "$SourceDir$zipName" -PathType Leaf) {
            aws s3 cp $SourceDir$zipName s3://ds-dev-logfiles/discovery/$Env:TNA_APP_TIER/$zipName
            if ($LASTEXITCODE -eq 0) {
                Remove-Item -Path "$SourceDir$fileName"
            }
            Remove-Item -Path "$SourceDir$zipName"
        }
    }
}
