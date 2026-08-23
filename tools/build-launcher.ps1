$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$launcherProject = Join-Path $repositoryRoot 'launcher\KnoxSurvivors.Launcher\KnoxSurvivors.Launcher.csproj'
$verifierProject = Join-Path $repositoryRoot 'launcher\KnoxSurvivors.Launcher.Verifier\KnoxSurvivors.Launcher.Verifier.csproj'
$launcherOutput = Join-Path $repositoryRoot 'launcher\KnoxSurvivors.Launcher\bin\Release\net48\KnoxSurvivorsLauncher.exe'
$verifierOutput = Join-Path $repositoryRoot 'launcher\KnoxSurvivors.Launcher.Verifier\bin\Release\net48\KnoxSurvivors.Launcher.Verifier.exe'
$artifactsDirectory = Join-Path $repositoryRoot 'launcher\artifacts'
$releaseExecutable = Join-Path $artifactsDirectory 'KnoxSurvivorsLauncher.exe'
$releaseArchive = Join-Path $artifactsDirectory 'KnoxSurvivorsLauncher-win-x64.zip'
$checksumFile = Join-Path $artifactsDirectory 'KnoxSurvivorsLauncher-win-x64.sha256'

& dotnet build $verifierProject -c Release --nologo
if ($LASTEXITCODE -ne 0) {
    throw "Launcher build failed with exit code $LASTEXITCODE."
}

& $verifierOutput
if ($LASTEXITCODE -ne 0) {
    throw "Launcher verification failed with exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Path $artifactsDirectory -Force | Out-Null
Copy-Item -LiteralPath $launcherOutput -Destination $releaseExecutable -Force
Compress-Archive -LiteralPath $releaseExecutable -DestinationPath $releaseArchive -Force
$hash = (Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksumFile -Value "$hash  $(Split-Path -Leaf $releaseArchive)" -Encoding ASCII

Write-Host "Launcher ready: $releaseArchive"
Write-Host "Checksum: $checksumFile"
