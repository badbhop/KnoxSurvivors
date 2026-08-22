param(
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$localPropertiesPath = Join-Path $repositoryRoot 'local.properties'
$gradleWrapperPath = Join-Path $repositoryRoot 'gradlew.bat'

if (-not (Test-Path -LiteralPath $localPropertiesPath)) {
    throw "Missing local.properties. Copy gradle.properties.example and configure this machine first."
}

$configuration = @{}
foreach ($line in Get-Content -LiteralPath $localPropertiesPath) {
    $trimmedLine = $line.Trim()
    if ($trimmedLine.Length -eq 0 -or $trimmedLine.StartsWith('#')) {
        continue
    }

    $parts = $trimmedLine.Split('=', 2)
    if ($parts.Count -eq 2) {
        $configuration[$parts[0].Trim()] = $parts[1].Trim()
    }
}

foreach ($requiredKey in @('pzHome', 'workshopRoot', 'workshopModFolder', 'localModsRoot')) {
    if (-not $configuration.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($configuration[$requiredKey])) {
        throw "Missing '$requiredKey' in local.properties."
    }
}

Write-Host '[Knox Survivors] Building Java and deploying the development mod...'
& $gradleWrapperPath 'deployDev'
if ($LASTEXITCODE -ne 0) {
    throw "Development build failed with exit code $LASTEXITCODE."
}

$workshopProjectPath = Join-Path $configuration.workshopRoot $configuration.workshopModFolder
$agentJarPath = Join-Path $workshopProjectPath 'java\build\libs\knox-agent-0.0.1-dev.jar'
$localModPath = Join-Path $configuration.localModsRoot 'KnoxSurvivors'
$gameLauncherPath = Join-Path $configuration.pzHome 'ProjectZomboid64.bat'

if (-not (Test-Path -LiteralPath $agentJarPath)) {
    throw "Built Java agent was not found at '$agentJarPath'."
}
if (-not (Test-Path -LiteralPath (Join-Path $localModPath 'mod.info'))) {
    throw "Local development mod was not found at '$localModPath'."
}
if (-not (Test-Path -LiteralPath $gameLauncherPath)) {
    throw "Project Zomboid launcher was not found at '$gameLauncherPath'."
}

$expectedAgentArgument = '-javaagent:"' + $agentJarPath + '"'
$launcherText = Get-Content -LiteralPath $gameLauncherPath -Raw
if (-not $launcherText.Contains($expectedAgentArgument)) {
    throw "ProjectZomboid64.bat is not configured to load '$agentJarPath'. Steam may have replaced the patched launcher."
}

Write-Host "[Knox Survivors] Build ready: $agentJarPath"
Write-Host "[Knox Survivors] Local mod ready: $localModPath"

if ($BuildOnly) {
    Write-Host '[Knox Survivors] Build-only verification passed; game was not launched.'
    exit 0
}

$zomboidUserPath = Split-Path -Parent $configuration.localModsRoot
$consoleLogPath = Join-Path $zomboidUserPath 'console.txt'
$knoxLogPath = Join-Path $zomboidUserPath 'KnoxIsoPlayer.log'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$diagnosticsRoot = Join-Path $repositoryRoot 'dev-runs'
$runDirectory = Join-Path $diagnosticsRoot $runId
$sessionPath = Join-Path $runDirectory 'session.json'
$latestSessionPath = Join-Path $diagnosticsRoot 'latest-session.txt'

New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

function Get-LogLength([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).Length
    }
    return 0
}

$session = [ordered]@{
    runId = $runId
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    runDirectory = $runDirectory
    pzHome = $configuration.pzHome
    consoleLogPath = $consoleLogPath
    consoleStartOffset = Get-LogLength $consoleLogPath
    knoxLogPath = $knoxLogPath
    knoxStartOffset = Get-LogLength $knoxLogPath
}
$session | ConvertTo-Json | Set-Content -LiteralPath $sessionPath -Encoding UTF8
Set-Content -LiteralPath $latestSessionPath -Value $sessionPath -Encoding UTF8

Write-Host '[Knox Survivors] Starting Project Zomboid with the Java agent...'
Start-Process -FilePath $gameLauncherPath -WorkingDirectory $configuration.pzHome -WindowStyle Normal | Out-Null

$monitorScriptPath = Join-Path $PSScriptRoot 'monitor-dev-run.ps1'
$monitorArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$monitorScriptPath`" -SessionPath `"$sessionPath`""
Start-Process -FilePath 'powershell.exe' -ArgumentList $monitorArguments -WindowStyle Hidden | Out-Null

Write-Host "[Knox Survivors] Diagnostic session: $runDirectory"
Write-Host '[Knox Survivors] New logs and an issue summary will be collected automatically when the game closes.'
