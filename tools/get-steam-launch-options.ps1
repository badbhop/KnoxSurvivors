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

$modRoot = Split-Path (Split-Path $AgentJar -Parent) -Parent
$bootstrap = Join-Path $modRoot 'knox-steam-launch.cmd'
if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) {
    throw 'Knox Steam bootstrap is missing. Let Steam update or verify the Workshop item.'
}
$bootstrap = (Get-Item -LiteralPath $bootstrap).FullName
if ($bootstrap -match '["\r\n%]') {
    throw 'The Workshop path contains characters that cannot be represented safely by the Steam bootstrap.'
}

$commandMatches = [regex]::Matches($ExistingOptions, '(?i)%command%')
if ($commandMatches.Count -gt 1) {
    throw 'Existing Steam options contain more than one %command% placeholder. Merge that custom wrapper manually.'
}

$existing = $ExistingOptions.Trim()
$prefix = '"' + $bootstrap + '"'
if ($commandMatches.Count -eq 1) {
    # Preserve an existing wrapper exactly, but run it inside Knox's process-local
    # bundled-Java environment so its own options/mods are not discarded.
    $prefix + ' ' + $existing
}
# Some Java-mod installers copy runtime DLLs beside the EXE. That directory
# wins over PATH, so a stale copy cannot be repaired by this wrapper. Never
# replace another mod's files automatically.
foreach ($name in @('java.dll', 'jli.dll', 'instrument.dll', 'jvm.dll')) {
    $rootDll = Join-Path $GameDirectory $name
    if (Test-Path -LiteralPath $rootDll -PathType Leaf) {
        $relative = if ($name -eq 'jvm.dll') { 'jre64\bin\server\jvm.dll' } else { 'jre64\bin\' + $name }
        $bundledDll = Join-Path $GameDirectory $relative
        $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
        try {
            $rootHash = [BitConverter]::ToString($hashAlgorithm.ComputeHash([IO.File]::ReadAllBytes($rootDll)))
            $bundledHash = [BitConverter]::ToString($hashAlgorithm.ComputeHash([IO.File]::ReadAllBytes($bundledDll)))
        } finally { $hashAlgorithm.Dispose() }
        if ($rootHash -ne $bundledHash) {
            throw "Game-root $name differs from the bundled runtime and takes precedence over PATH. Review the installer that owns that copy; no files were changed."
        }
    }
}
# Shell metacharacters in existing arguments cannot safely be forwarded through
# cmd without reinterpreting their quoting. Decline those cases rather than edit them.
if (($GameDirectory + $options) -match '[&|<>^%!\r\n\x00]' -or $GameDirectory.Contains('"')) {
    throw 'Runtime-isolation options contain shell metacharacters requiring a manual setup. No settings were changed.'
}
$insideQuotes = $false
foreach ($character in $options.ToCharArray()) {
    if ($character -eq '"') { $insideQuotes = -not $insideQuotes }
    elseif (-not $insideQuotes -and ($character -eq '(' -or $character -eq ')')) {
        throw 'Quote argument paths containing parentheses before generating runtime-isolation options.'
    }
}
'cmd /d /v:off /s /c "set "PATH=' + $GameDirectory + '\jre64\bin;' +
    $GameDirectory + '\jre64\bin\server;%PATH%" && %command% ' + $options + '"'
