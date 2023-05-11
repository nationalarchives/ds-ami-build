
$logFile = "/updEnv.log"

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
    if (-not ($sysEnv -eq "dev" -or $sysEnv -eq "staging" -or $sysEnv -eq "live")) {
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

    if ($sysTier -eq "api")
    {
        write-log -Message "read secret arn"
        $arnData = aws ssm get-parameter --name /devops/deployment/discovery.environment.mongodb.secrets-arn --region eu-west-2 | ConvertFrom-Json
        $secrets_arn = $arnData.Parameter.Value

        write-log -Message "read environment variables from secrets manager"
        $mongoSecrets = aws secretsmanager get-secret-value --secret-id $secrets_arn | ConvertFrom-Json
        $userList = $mongoSecrets.SecretString | ConvertFrom-Json
        foreach ($line in $userList.PSObject.Properties)
        {
            if ($line.Name -Match "^DISC_MONGO_")
            {
                $envVarNameUser = $line.Name + "_USR"
                $envUsernameValue = $line.Value.username
                $envVarNamePassword = $line.Name + "_PWD"
                $envPasswordValue = $line.Value.password

                write-log -Message "set: $envVarNameUser - $envUsernameValue"
                [System.Environment]::SetEnvironmentVariable($envVarNameUser.trim(),$envUsernameValue.trim(), "Machine")

                write-log -Message "set: $envVarNamePassword - $envPasswordValue"
                [System.Environment]::SetEnvironmentVariable($envVarNamePassword.trim(),$envPasswordValue.trim(), "Machine")
            }
        }
    }

    net start w3svc
} catch {
    write-log -Message "Caught an exception:" -Severity "Error"
    write-log -Message "Exception Type: $($_.Exception.GetType().FullName)" -Severity "Error"
    write-log -Message "Exception Message: $($_.Exception.Message)" -Severity "Error"
    exit 1
}
