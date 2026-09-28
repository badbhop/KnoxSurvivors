[CmdletBinding()]
param(
    [ValidateSet('free', 'go')]
    [string] $Profile = 'free',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $OpenCodeArgument
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
    throw 'OpenCode is not on PATH. Install OpenCode, then run this script again.'
}

Set-Location $RepositoryRoot
if ($Profile -eq 'go') {
    $ProfilePath = Join-Path $RepositoryRoot 'opencode.go.json'
    Write-Host 'KnoxSurvivors OpenCode profile: OpenCode Go subscription' -ForegroundColor Yellow
    Write-Host 'Go is opt-in. Models use the opencode-go provider and the stored Go credential.' -ForegroundColor DarkYellow
} else {
    $ProfilePath = Join-Path $RepositoryRoot 'opencode.free.json'
    Write-Host 'KnoxSurvivors OpenCode profile: free-only' -ForegroundColor Cyan
    Write-Host 'Default: opencode/big-pickle; support: Muse Spark, MiMo, LongCat, Nemotron free models' -ForegroundColor DarkCyan
}
if (-not (Test-Path -LiteralPath $ProfilePath)) { throw "OpenCode profile not found: $ProfilePath" }

# Inline config is the highest normal runtime profile layer, so it overrides the
# repository default without rewriting opencode.json or changing the user's account.
$env:OPENCODE_CONFIG_CONTENT = Get-Content -Raw -LiteralPath $ProfilePath
Write-Host 'No --auto flag is added; OpenCode keeps its normal permission prompts.' -ForegroundColor DarkCyan

try {
    & opencode @OpenCodeArgument
    exit $LASTEXITCODE
} finally {
    Remove-Item Env:OPENCODE_CONFIG_CONTENT -ErrorAction SilentlyContinue
}
