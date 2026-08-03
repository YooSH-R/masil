[CmdletBinding()]
param(
    [string]$BrokerHost = "127.0.0.1",
    [int]$BrokerPort = 11883,
    [string]$DeviceId = "device-001",
    [string]$DevicePassword,
    [string]$BackendUsername,
    [string]$BackendPassword,
    [string]$MosquittoBin = "C:\Program Files (x86)\Mosquitto",
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function ConvertTo-PlainText {
    param([Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
        $SecureValue
    )
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Import-MqttEnvironment {
    $repositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..\..\..")
    )
    $envFile = Join-Path $repositoryRoot "02_Backend\.env"
    if (-not (Test-Path -LiteralPath $envFile)) {
        return
    }

    foreach ($line in Get-Content -LiteralPath $envFile) {
        if ($line -notmatch "^\s*(MQTT_USERNAME|MQTT_PASSWORD)=(.*)$") {
            continue
        }

        $name = $Matches[1]
        $value = $Matches[2].Trim()
        if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable(
                $name,
                $value,
                "Process"
            )
        }
    }
}

function Start-MqttSubscriber {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )

    $configuration = @{
        Executable = $Executable
        Arguments = $Arguments
    }
    return Start-Job -ScriptBlock {
        param($Configuration)

        $lines = & $Configuration.Executable `
            @($Configuration.Arguments) 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = ($lines -join [Environment]::NewLine)
        }
    } -ArgumentList $configuration
}

function Wait-MqttSubscriber {
    param(
        [Management.Automation.Job]$Job,
        [string]$ExpectedText,
        [string]$Direction
    )

    $completedJob = Wait-Job -Job $Job -Timeout $TimeoutSeconds
    if (-not $completedJob) {
        Stop-Job -Job $Job
        Remove-Job -Job $Job -Force
        throw "$Direction 구독이 ${TimeoutSeconds}초 안에 메시지를 받지 못했습니다."
    }

    $result = Receive-Job -Job $Job
    Remove-Job -Job $Job
    if ($result.ExitCode -ne 0) {
        throw "$Direction 구독 실패(exit=$($result.ExitCode)): $($result.Output)"
    }
    if (-not $result.Output.Contains($ExpectedText)) {
        throw "$Direction 메시지 검증 실패: $($result.Output)"
    }
}

Import-MqttEnvironment

if (-not $BackendUsername) {
    $BackendUsername = $env:MQTT_USERNAME
}
if (-not $BackendPassword) {
    $BackendPassword = $env:MQTT_PASSWORD
}
if (-not $BackendUsername) {
    $BackendUsername = "backend"
}
if (-not $BackendPassword) {
    $BackendPassword = ConvertTo-PlainText (
        Read-Host "Backend MQTT password" -AsSecureString
    )
}
if (-not $DevicePassword) {
    $DevicePassword = ConvertTo-PlainText (
        Read-Host "$DeviceId MQTT password" -AsSecureString
    )
}

$publisher = Join-Path $MosquittoBin "mosquitto_pub.exe"
$subscriber = Join-Path $MosquittoBin "mosquitto_sub.exe"
if (-not (Test-Path -LiteralPath $publisher)) {
    throw "mosquitto_pub.exe를 찾을 수 없습니다: $publisher"
}
if (-not (Test-Path -LiteralPath $subscriber)) {
    throw "mosquitto_sub.exe를 찾을 수 없습니다: $subscriber"
}

$portCheck = Test-NetConnection `
    -ComputerName $BrokerHost `
    -Port $BrokerPort `
    -WarningAction SilentlyContinue
if (-not $portCheck.TcpTestSucceeded) {
    throw "$BrokerHost`:$BrokerPort MQTT 터널에 연결할 수 없습니다."
}

$tempRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("mqtt-pubsub-" + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $tempRoot

try {
    $runId = [guid]::NewGuid().ToString()
    $eventTopic = "robot-pet/v1/devices/$DeviceId/events"
    $affectionTopic = "robot-pet/v1/devices/$DeviceId/affection"

    $backendSubscriber = Start-MqttSubscriber `
        -Executable $subscriber `
        -Arguments @(
            "-h", $BrokerHost,
            "-p", "$BrokerPort",
            "-u", $BackendUsername,
            "-P", $BackendPassword,
            "-t", $eventTopic,
            "-q", "1",
            "-C", "1"
        )

    Start-Sleep -Seconds 2
    $eventPayload = @{
        messageId = [guid]::NewGuid().ToString()
        messageVersion = "1.0"
        deviceId = $DeviceId
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
        eventType = "CALL_AND_RESPONSE"
        data = @{
            pubSubTestRunId = $runId
        }
    } | ConvertTo-Json -Compress -Depth 4
    $eventPath = Join-Path $tempRoot "event.json"
    [IO.File]::WriteAllText(
        $eventPath,
        $eventPayload,
        [Text.UTF8Encoding]::new($false)
    )

    & $publisher `
        -h $BrokerHost `
        -p $BrokerPort `
        -u $DeviceId `
        -P $DevicePassword `
        -t $eventTopic `
        -q 1 `
        -f $eventPath
    if ($LASTEXITCODE -ne 0) {
        throw "디바이스 계정의 events 발행에 실패했습니다."
    }

    Wait-MqttSubscriber `
        -Job $backendSubscriber `
        -ExpectedText $runId `
        -Direction "device -> backend"
    Write-Host "[PASS] device -> broker -> backend subscriber"

    $deviceSubscriber = Start-MqttSubscriber `
        -Executable $subscriber `
        -Arguments @(
            "-h", $BrokerHost,
            "-p", "$BrokerPort",
            "-u", $DeviceId,
            "-P", $DevicePassword,
            "-t", $affectionTopic,
            "-q", "1",
            "-C", "1"
        )

    Start-Sleep -Seconds 2
    $affectionPayload = @{
        messageId = [guid]::NewGuid().ToString()
        messageVersion = "1.0"
        deviceId = $DeviceId
        diagnostic = "pubsub-test"
        pubSubTestRunId = $runId
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress
    $affectionPath = Join-Path $tempRoot "affection.json"
    [IO.File]::WriteAllText(
        $affectionPath,
        $affectionPayload,
        [Text.UTF8Encoding]::new($false)
    )

    & $publisher `
        -h $BrokerHost `
        -p $BrokerPort `
        -u $BackendUsername `
        -P $BackendPassword `
        -t $affectionTopic `
        -q 1 `
        -f $affectionPath
    if ($LASTEXITCODE -ne 0) {
        throw "백엔드 계정의 affection 발행에 실패했습니다."
    }

    Wait-MqttSubscriber `
        -Job $deviceSubscriber `
        -ExpectedText $runId `
        -Direction "backend -> device"
    Write-Host "[PASS] backend -> broker -> device subscriber"
    Write-Host "[PASS] MQTT local pub/sub test completed"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith(
            $systemTemp,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}
