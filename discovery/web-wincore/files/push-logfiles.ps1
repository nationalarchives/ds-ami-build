# Get-EC2InstanceMetadata can take a long time to run
param([switch] $termination = $false)

function Set-FileName {
    param([string] $bucket, [string] $keyPrefix, [string] $baseName, [int] $count = 0)

    if ($count -eq 0) {
        $zName = $baseName + ".zip"
    } else {
        $zName = $baseName + "(" + $count + ").zip"
    }
    $x = (aws s3api head-object --bucket "$bucket" --key "$keyPrefix/$zName" 2> $null)
    if (-not ([string]::IsNullOrEmpty($x))) {
        $count += 1
        $zName = Set-FileName -bucket "$bucket" -keyPrefix "$keyPrefix" -baseName "$baseName" -count $count
    }
    Write-Output $zName
}

$InstanceId = Get-EC2InstanceMetadata -Category InstanceId
$Today = Get-Date -Format "yyMMdd"
$TodaysLog = "u_ex" + $Today + "*"
$Bucket = "ds-" + $Env:TNA_APP_ENVIRONMENT  + "-logfiles"
$KeyPrefix = "discovery/" + $Env:TNA_APP_TIER

$TempCopyDir = "C:/iis-copy-logfiles"
$SourceDir = "C:/inetpub/logs/LogFiles/W3SVC1"

if ($termination) {
    $files = Get-ChildItem -Path "$SourceDir/*.log" -Name
} else {
    $files = Get-ChildItem -Path "$SourceDir/*.log" -Exclude $TodaysLog -Name
}

if ([string]::IsNullOrEmpty($files)) {
    Write-Output 'No logfiles found'
} else {
    # compress the logfiles
    # Compress-Archive won't work on a log file which is currently in use from IIS
    # even when the webserver and app pool are stopped - copy works!
    [System.IO.Directory]::CreateDirectory("$TempCopyDir")
    foreach ($file in $files) {
        $zipName = (Get-Item ("$SourceDir/$file")).Basename + "_" + $InstanceId + ".zip"
        if (Test-Path -Path "$TempCopyDir/$zipName" -PathType Leaf) {
            Remove-Item "$TempCopyDir/$zipName"
        }
        Copy-Item -Path "$SourceDir/$file" -Destination "$TempCopyDir/$file"
        Compress-Archive -Path "$TempCopyDir/$file" -DestinationPath "$TempCopyDir/$zipName"
        if (Test-Path -Path "$TempCopyDir/$zipName" -PathType Leaf) {
            Remove-Item "$TempCopyDir/$file"
            Remove-Item "$SourceDir/$file"
        }
    }
    $files = Get-ChildItem -Path ($TempCopyDir + "/*.zip") -Name
    foreach ($file in $files) {
        $zipBase = (Get-Item ("$TempCopyDir/$file")).Basename
        $targetName = Set-FileName -bucket "$Bucket" -keyPrefix "$KeyPrefix" -baseName "$zipBase"
        aws s3 cp $TempCopyDir/$file s3://$bucket/$keyPrefix/$targetName
        Remove-Item -Path "$TempCopyDir/$file"
    }
}
