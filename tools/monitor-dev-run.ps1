param(
    [Parameter(Mandatory = $true)]
    [string]$SessionPath
)

$ErrorActionPreference = 'Stop'

$session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
$gameJavaPath = [System.IO.Path]::GetFullPath((Join-Path ([string]$session.pzHome) 'jre64\bin\java.exe'))
$sessionStart = [DateTimeOffset]::Parse([string]$session.startedAt).LocalDateTime
$startupDeadline = (Get-Date).AddMinutes(3)
$gameProcess = $null

while ((Get-Date) -lt $startupDeadline -and $null -eq $gameProcess) {
    $gameProcess = Get-Process -Name 'java' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                [System.IO.Path]::GetFullPath($_.Path) -eq $gameJavaPath -and $_.StartTime -ge $sessionStart
            }
            catch {
                $false
            }
        } |
        Sort-Object StartTime |
        Select-Object -First 1

    if ($null -eq $gameProcess) {
        Start-Sleep -Seconds 1
    }
}

$monitorStatusPath = Join-Path ([string]$session.runDirectory) 'monitor-status.txt'
if ($null -eq $gameProcess) {
    Set-Content -LiteralPath $monitorStatusPath -Value 'Project Zomboid Java process was not detected within three minutes.' -Encoding UTF8
}
else {
    Set-Content -LiteralPath $monitorStatusPath -Value "Monitoring Project Zomboid process $($gameProcess.Id)." -Encoding UTF8
    $liveTestStatusPath = Join-Path ([string]$session.runDirectory) 'live-test-status.txt'
    Set-Content -LiteralPath $liveTestStatusPath -Value 'Waiting for Knox Test Lab result.' -Encoding UTF8

    while ($null -ne (Get-Process -Id $gameProcess.Id -ErrorAction SilentlyContinue)) {
        $consolePath = [string]$session.consoleLogPath
        if (Test-Path -LiteralPath $consolePath) {
            $latestResult = Get-Content -LiteralPath $consolePath -Tail 500 -ErrorAction SilentlyContinue |
                ForEach-Object { $_ -replace "`0", '' } |
                Where-Object { $_ -match '(?i)\[KnoxSurvivors\]\[TestLab\].*RESULT scenario=' } |
                Select-Object -Last 1
            if (-not [string]::IsNullOrWhiteSpace($latestResult)) {
                Set-Content -LiteralPath $liveTestStatusPath -Value $latestResult -Encoding UTF8
            }
        }
        Start-Sleep -Seconds 2
    }
}

$collectorPath = Join-Path $PSScriptRoot 'collect-dev-logs.ps1'
& $collectorPath -SessionPath $SessionPath | Out-Null
