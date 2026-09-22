param(
    [string]$LogPath,
    [string]$OutputPath = "build/live-qa/latest.json"
)

$ErrorActionPreference = "Stop"
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
$suite = $null
foreach ($line in Get-Content -LiteralPath $LogPath) {
    # A single DebugLog can contain several disposable runs after a reload or
    # a second test attempt. Keep the report aligned with the newest suite
    # summary instead of mixing results from earlier attempts.
    if ($line -match "\[KnoxSurvivors\]\[AutomatedQA\] START save_is_disposable=true") {
        $entries = @()
        $suite = $null
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
    suite = $suite
    results = @($entries)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
$report | ConvertTo-Json -Depth 8
