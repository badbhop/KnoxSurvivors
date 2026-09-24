[CmdletBinding()]
param(
    [string]$SteamRoot,
    [string]$AgentJar,
    [string]$ExistingOptions = ''
)

# Prints a proposed Steam Launch Options value only.
# It never writes Steam, Project Zomboid configuration, save data, or global environment settings.
$ErrorActionPreference = 'Stop'

if ($ExistingOptions -match '[\r\n\x00]') {
    throw 'Existing options contain unsupported control characters.'
}
if ($ExistingOptions -match '(?i)knox-agent(?:-[^\s"'']+)?\.jar|knox-steam-launch\.cmd') {
    throw 'Existing options already reference Knox. Remove the older Knox launch entry before generating a replacement.'
}

if (-not $AgentJar) {
    if (-not $SteamRoot) {
        $SteamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    }
    if (-not $SteamRoot) { $SteamRoot = Join-Path ${env:ProgramFiles(x86)} 'Steam' }

    $roots = @($SteamRoot)
    $libraries = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $libraries) {
        $roots += [regex]::Matches([IO.File]::ReadAllText($libraries), '"path"\s+"([^"\r\n]+)"') |
            ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') }
    }

    $candidates = @($roots | Sort-Object -Unique | ForEach-Object {
        $candidate = Join-Path $_ 'steamapps\workshop\content\108600\3749727604\mods\KnoxSurvivors\java\knox-agent.jar'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            (Get-Item -LiteralPath $candidate).FullName
        }
    } | Sort-Object -Unique)

    if ($candidates.Count -ne 1) {
        throw "Expected one installed Knox Workshop runtime, found $($candidates.Count). Wait for Workshop download or supply -AgentJar with the actual subscribed file."
    }
    $AgentJar = $candidates[0]
}

$AgentJar = (Get-Item -LiteralPath $AgentJar).FullName
if ($AgentJar -notmatch '(?i)[\\/]steamapps[\\/]workshop[\\/]content[\\/]108600[\\/]3749727604[\\/]mods[\\/]KnoxSurvivors[\\/]java[\\/]knox-agent\.jar$') {
    throw 'Use the stable knox-agent.jar from Workshop item 3749727604, not a build/staging or versioned JAR.'
}
if ($AgentJar -match '["\r\n]') {
    throw 'The runtime path cannot be represented safely in Steam launch options.'
}

$checksumPath = $AgentJar + '.sha256'
if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
    throw 'Runtime checksum sidecar is missing. Let Steam finish or repair the Workshop download.'
}
$checksum = ([IO.File]::ReadAllText($checksumPath)).Trim()
if ($checksum -notmatch '^([a-fA-F0-9]{64})\s+\*?knox-agent\.jar$') {
    throw 'Invalid runtime SHA-256 sidecar.'
}
$expectedHash = $Matches[1]
$sha = [Security.Cryptography.SHA256]::Create()
$stream = [IO.File]::OpenRead($AgentJar)
try { $actualHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
finally { $stream.Dispose(); $sha.Dispose() }
if ($actualHash -ne $expectedHash) {
    throw 'Runtime checksum mismatch. Let Steam complete or repair the Workshop download.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($AgentJar)
try {
    $entry = $archive.GetEntry('META-INF/MANIFEST.MF')
    if (-not $entry) { throw 'Runtime manifest missing.' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { $manifest = $reader.ReadToEnd() -replace '\r?\n ', '' }
    finally { $reader.Dispose() }
    if ($manifest -notmatch '(?m)^Premain-Class: com\.knoxsurvivors\.agent\.KnoxAgent\r?$') {
        throw 'Unexpected runtime entry point.'
    }
}
finally { $archive.Dispose() }

$commandMatches = [regex]::Matches($ExistingOptions, '(?i)%command%')
if ($commandMatches.Count -gt 0) {
    throw 'Existing Steam options use a %command% wrapper. The direct Knox agent option cannot merge that wrapper automatically.'
}

$existing = $ExistingOptions.Trim()
$separatorMatches = [regex]::Matches($existing, '(?<!\S)--(?!\S)')
if ($separatorMatches.Count -gt 1) {
    throw 'Existing Steam options contain more than one standalone -- separator. Merge those options manually.'
}

$agentOption = '-javaagent:"' + $AgentJar + '"=pz-game'
if ($separatorMatches.Count -eq 1) {
    $separator = $separatorMatches[0]
    $jvmOptions = $existing.Substring(0, $separator.Index).Trim()
    $gameOptions = $existing.Substring($separator.Index + $separator.Length).Trim()
    $parts = @($jvmOptions, $agentOption, '--', $gameOptions) |
        Where-Object { $_ }
    [string]::Join(' ', [string[]]$parts)
} elseif ($existing) {
    # Without an existing separator, preserve the supplied text as game arguments.
    # JVM options must be supplied with an explicit trailing `--`.
    "$agentOption -- $existing"
} else {
    "$agentOption --"
}
