param(
    [Parameter(Mandatory = $true)]
    [string]$SessionPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SessionPath)) {
    throw "Diagnostic session file not found: $SessionPath"
}

$session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
$runDirectory = [string]$session.runDirectory
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

function Read-NewLogText([string]$Path, [long]$StartOffset) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite
    )
    try {
        if ($StartOffset -lt 0 -or $StartOffset -gt $stream.Length) {
            $StartOffset = 0
        }
        [void]$stream.Seek($StartOffset, [System.IO.SeekOrigin]::Begin)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

$consoleText = Read-NewLogText ([string]$session.consoleLogPath) ([long]$session.consoleStartOffset)
$knoxText = Read-NewLogText ([string]$session.knoxLogPath) ([long]$session.knoxStartOffset)

$consoleOutputPath = Join-Path $runDirectory 'console-since-launch.txt'
$knoxOutputPath = Join-Path $runDirectory 'knox-since-launch.log'
$eventsOutputPath = Join-Path $runDirectory 'knox-events.txt'
$issuesOutputPath = Join-Path $runDirectory 'possible-issues.txt'
$testResultsOutputPath = Join-Path $runDirectory 'test-results.txt'
$summaryOutputPath = Join-Path $runDirectory 'summary.txt'

Set-Content -LiteralPath $consoleOutputPath -Value $consoleText -Encoding UTF8
Set-Content -LiteralPath $knoxOutputPath -Value $knoxText -Encoding UTF8

$combinedLines = @($consoleText -split "`r?`n") + @($knoxText -split "`r?`n")
$knoxEvents = @($combinedLines | Where-Object { $_ -match '(?i)\[(KnoxSurvivors|KnoxIsoPlayer)\]' })
$possibleIssues = @($combinedLines | Where-Object {
    $_ -match '(?i)(error|exception|object tried to call nil|reflection init failed|stack traceback|stack trace|java\.lang\.|\[TestLab\].*status=FAIL)'
})
$testResults = @($combinedLines | Where-Object {
    $_ -match '(?i)\[KnoxSurvivors\]\[TestLab\].*RESULT scenario='
})
$testPassCount = @($testResults | Where-Object { $_ -match '(?i)status=PASS' }).Count
$testFailCount = @($testResults | Where-Object { $_ -match '(?i)status=FAIL' }).Count
$testBlockedCount = @($testResults | Where-Object { $_ -match '(?i)status=BLOCKED' }).Count

Set-Content -LiteralPath $eventsOutputPath -Value $knoxEvents -Encoding UTF8
Set-Content -LiteralPath $issuesOutputPath -Value $possibleIssues -Encoding UTF8
Set-Content -LiteralPath $testResultsOutputPath -Value $testResults -Encoding UTF8

$summary = @(
    "Knox Survivors diagnostic run: $($session.runId)"
    "Started UTC: $($session.startedAt)"
    "Collected UTC: $((Get-Date).ToUniversalTime().ToString('o'))"
    "New console characters: $($consoleText.Length)"
    "New Knox log characters: $($knoxText.Length)"
    "Knox event lines: $($knoxEvents.Count)"
    "Possible issue lines: $($possibleIssues.Count)"
    "Test results: $($testResults.Count)"
    "Test passes: $testPassCount"
    "Test failures: $testFailCount"
    "Test blocked: $testBlockedCount"
    "Console extract: $consoleOutputPath"
    "Knox extract: $knoxOutputPath"
    "Issue extract: $issuesOutputPath"
    "Test result extract: $testResultsOutputPath"
)
Set-Content -LiteralPath $summaryOutputPath -Value $summary -Encoding UTF8

Write-Output $summaryOutputPath
