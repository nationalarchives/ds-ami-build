# Get-EC2InstanceMetadata can take a long time to run
param([switch] $termination)

function Set-FileName {
    param([string] $bucket, [string] $keyPrefix, [string] $fileName, [int] $count)

    if ([int]::IsNullOrEmpty($count)) {
        $zName = $fileName + ".zip"
        $count = 0
    } else {
        $zName = "$fileName($count).zip"
    }

    $x = (aws s3api head-object --bucket $bucket --key $keyPrefix/$zName 2> $null)
    if (-not ([string]::IsNullOrEmpty($x))) {
        $count++
        $zName = Set-FileName -bucket $bucket -keyPrefix $keyPrefix -fileName $fileName -count $count
    }
    Write-Output $zName
}

$InstanceId = Get-EC2InstanceMetadata -Category InstanceId
$Today = Get-Date -Format "yyMMdd"
$TodaysLog = "u_ex" + $Today + "*"
$bucket = "ds-" + $Env:TNA_APP_ENVIRONMENT  + "-logfiles"
$keyPrefix = "discovery/" + $Env:TNA_APP_TIER

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
            $targetName = Set-FileName -bucket $bucket -keyPrefix $keyPrefix -fileName $fileName
            aws s3 cp $SourceDir$zipName s3://$bucket/$keyPrefix/$targetName
            if ($LASTEXITCODE -eq 0) {
                Remove-Item -Path "$SourceDir$fileName"
            }
            Remove-Item -Path "$SourceDir$zipName"
        }
    }
}
