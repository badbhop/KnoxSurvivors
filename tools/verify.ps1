param(
    [string]$Lua = 'lua',
    [string]$Luac = 'luac',
    [string]$GameDirectory,
    [switch]$SkipJava
)

$ErrorActionPreference = 'Stop'
# Native failures are recorded per check so one failed test cannot hide others.
$PSNativeCommandUseErrorActionPreference = $false
$root = Split-Path -Parent $PSScriptRoot
$reportDirectory = Join-Path $root 'build/verification'
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-Check([string]$Name, [string]$Command, [string[]]$Arguments) {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = 1
    try {
        $output = @(& $Command @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @($_.ToString())
    }
    $timer.Stop()
    $logName = ($Name -replace '[^A-Za-z0-9._-]', '_') + '.txt'
    $output | Out-File -LiteralPath (Join-Path $reportDirectory $logName) -Encoding utf8
    $results.Add([pscustomobject]@{
        name = $Name
        passed = ($exitCode -eq 0)
        exitCode = $exitCode
        durationMs = $timer.ElapsedMilliseconds
        log = $logName
    })
    if ($exitCode -ne 0) { Write-Host "FAIL $Name (see $logName)" }
}

# Missing tools are a setup error, never a passing or silently skipped suite.
$luaCommand = (Get-Command $Lua -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$luacCommand = (Get-Command $Luac -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
Push-Location $root
try {
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'mod') -Recurse -Filter '*.lua' -File)
    $tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test-*.lua' -File | Sort-Object Name)
    if ($sourceFiles.Count -eq 0 -or $tests.Count -eq 0) {
        throw 'No mod Lua sources or regression tests were found.'
    }
    foreach ($source in $sourceFiles) {
        $relativePath = $source.FullName.Substring($root.Length + 1)
        Invoke-Check "syntax-$relativePath" $luacCommand @('-p', $source.FullName)
    }
    Write-Host "Checked syntax for $($sourceFiles.Count) Lua files."
    foreach ($test in $tests) {
        $testArguments = @($test.FullName, $root)
        if ($GameDirectory) { $testArguments += $GameDirectory }
        Invoke-Check $test.BaseName $luaCommand $testArguments
    }
    Write-Host "Ran $($tests.Count) Lua regression scripts."
    if (-not $SkipJava) {
        Invoke-Check 'java-check-build' (Join-Path $root 'gradlew.bat') @(':java:check', ':java:build', '--console=plain')
    }
    $failures = @($results | Where-Object { -not $_.passed })
    $report = [ordered]@{
        completedUtc = [DateTime]::UtcNow.ToString('o')
        luaSources = $sourceFiles.Count
        luaTests = $tests.Count
        javaSkipped = [bool]$SkipJava
        failedChecks = $failures.Count
        checks = @($results.ToArray())
        scope = 'Offline checks only; no deployment, game launch, or gameplay acceptance.'
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'summary.json') -Encoding utf8
    Write-Host "$($results.Count) checks; $($failures.Count) failed. Report: $reportDirectory/summary.json"
    if ($failures.Count -gt 0) { exit 1 }
}
finally {
    Pop-Location
}
