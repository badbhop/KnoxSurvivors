param(
    [string]$LogPath,
    [string]$OutputPath = "build/live-qa/latest.json"
)

$ErrorActionPreference = "Stop"
$supportedStatuses = @("PASS", "FAIL", "BLOCKED", "SKIPPED", "HARNESS_ERROR")
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$userProfile = [Environment]::GetFolderPath("UserProfile")

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $logRoot = Join-Path $userProfile "Zomboid\Logs"
    $candidate = Get-ChildItem -LiteralPath $logRoot -Filter "*DebugLog.txt" -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate -eq $null) { throw "No DebugLog.txt was found under $logRoot" }
    $LogPath = $candidate.FullName
}
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "QA log not found: $LogPath"
}

$entries = @()
$checkpoints = @()
$suite = $null
$metadata = $null
foreach ($line in Get-Content -LiteralPath $LogPath) {
    # A single DebugLog can contain several disposable runs after a reload or
    # a second test attempt. Keep the report aligned with the newest suite
    # summary instead of mixing results from earlier attempts.
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] START (?:runId=(\S+) )?save_is_disposable=true") {
        $entries = @()
        $checkpoints = @()
        $suite = $null
        $metadata = [pscustomobject]@{
            runId = $Matches[1]
            start = $line
        }
    }
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] CHECKPOINT runId=(\S+) scenario=(\S+) phase=(\S+) tick=(\d+) save=(\S+) evidenceType=(\S+)") {
        $checkpoints += [pscustomobject]@{
            runId = $Matches[1]
            scenario = $Matches[2]
            phase = $Matches[3]
            tick = [int]$Matches[4]
            save = $Matches[5]
            evidenceType = $Matches[6]
        }
    }
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] RESULT runId=(\S+) scenario=(\S+) status=(\S+) reason=(\S+) evidenceType=(\S+) humanConfirmation=(\S+) task=(\S+) evidence=(.*)$") {
        if ($supportedStatuses -notcontains $Matches[3]) {
            throw "Unsupported QA result status in ${LogPath}: $($Matches[3])"
        }
        $entries += [pscustomobject]@{
            runId = $Matches[1]
            scenario = $Matches[2]
            status = $Matches[3]
            reason = $Matches[4]
            evidenceType = $Matches[5]
            humanConfirmation = $Matches[6]
            task = $Matches[7]
            evidence = $Matches[8]
        }
    }
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] RESULT scenario=(\S+) status=(\S+) reason=(\S+)(?: brief=(.*?) )?evidence=(.*)$") {
        $entries += [pscustomobject]@{
            scenario = $Matches[1]
            status = $Matches[2]
            reason = $Matches[3]
            brief = $Matches[4]
            evidence = $Matches[5]
        }
    }
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] SUITE runId=(\S+) status=(\S+) pass=(\d+) fail=(\d+) blocked=(\d+) skipped=(\d+) harnessError=(\d+) ticks=(\d+) evidenceType=(\S+) humanRequired=(.*)$") {
        $suite = [pscustomobject]@{
            runId = $Matches[1]
            status = $Matches[2]
            pass = [int]$Matches[3]
            fail = [int]$Matches[4]
            blocked = [int]$Matches[5]
            skipped = [int]$Matches[6]
            harnessError = [int]$Matches[7]
            ticks = [int]$Matches[8]
            evidenceType = $Matches[9]
            humanRequired = $Matches[10]
        }
    }
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] SUITE status=(\S+) pass=(\d+) fail=(\d+) blocked=(\d+) skip=(\d+) passes=(\d+) ticks=(\d+)") {
        $suite = [pscustomobject]@{
            status = $Matches[1]
            pass = [int]$Matches[2]
            fail = [int]$Matches[3]
            blocked = [int]$Matches[4]
            skip = [int]$Matches[5]
            passes = [int]$Matches[6]
            ticks = [int]$Matches[7]
        }
    }
}

if ($suite -eq $null -and $entries.Count -eq 0) {
    throw "No Knox Automated QA results were found in $LogPath"
}

$resolvedOutput = Join-Path $workspaceRoot $OutputPath
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$report = [pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    logPath = [IO.Path]::GetFullPath($LogPath)
    metadata = $metadata
    suite = $suite
    results = @($entries)
    checkpoints = @($checkpoints)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
$report | ConvertTo-Json -Depth 8
