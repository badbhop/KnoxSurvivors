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

Write-Host '[Knox Survivors] Starting Project Zomboid with the Java agent...'
Start-Process -FilePath $gameLauncherPath -WorkingDirectory $configuration.pzHome -WindowStyle Normal
