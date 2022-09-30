
$logFile = "updEnv.log"

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
    $sysEnv = $Env:TNA_APP_ENVIRONMENT
    $sysTier = $Env:TNA_APP_TIER

    # check if environment is set correctly
    if (-not ($sysEnv -eq "dev" -or $sysEnv -eq "test" -or $sysEnv -eq "live")) {
        write-log -Message "environment variable not set" -Severity "Error"
        exit 1
    }

    if (-not ($sysTier -eq "api" -or $sysTier -eq "web")) {
        write-log -Message "tier variable not set" -Severity "Error"
        exit 1
    }

    net stop w3svc

    write-log -Message "read environment variables from system manager"
    $smData = aws ssm get-parameter --name /devops/deployment/discovery.environment.$Env:TNA_APP_TIER --region eu-west-2 | ConvertFrom-Json
    $smValues = $smData.Parameter.Value | ConvertFrom-Json
    # iterate over json content
    $smValues | Get-Member -MemberType NoteProperty | ForEach-Object {
        $smKey = $_.Name
        # setting environment variables
        $envValue = $smValues."$smKey"
        write-log -Message "set: $smKey - $envValue" -Severity "Information"
        [System.Environment]::SetEnvironmentVariable($smKey.trim(), $envValue.trim(), "Machine")
    }

    net start w3svc
} catch {
    write-log -Message "Caught an exception:" -Severity "Error"
    write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Error"
    write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Error"
    exit 1
}
