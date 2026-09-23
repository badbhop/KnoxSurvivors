[CmdletBinding()]
param(
    [string]$SteamRoot,
    [string]$AgentJar,
    [string]$ExistingOptions = '',
    [switch]$IsolateBundledRuntime,
    [string]$GameDirectory
)

# Prints a proposed value only. Never writes Steam, game configuration, or environment settings.
$ErrorActionPreference = 'Stop'
if ($ExistingOptions -match '(?i)knox-agent(?:-[^\s"'']+)?\.jar') {
    throw 'Existing options already reference Knox. Remove that agent option before generating a replacement.'
}
if ($ExistingOptions -match '[\r\n\x00]' -or $ExistingOptions.Contains('%command%')) {
    throw 'Wrapped commands/control characters require a manual merge; this helper accepts normal PZ launch options.'
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
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { (Get-Item -LiteralPath $candidate).FullName }
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
if ($AgentJar -match '["\r\n]') { throw 'The runtime path cannot be represented safely in Steam launch options.' }
$checksum = ([IO.File]::ReadAllText($AgentJar + '.sha256')).Trim()
if ($checksum -notmatch '^([a-fA-F0-9]{64})\s+\*?knox-agent\.jar$') { throw 'Invalid runtime SHA-256 sidecar.' }
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
    try { $manifest = $reader.ReadToEnd() -replace '\r?\n ', '' } finally { $reader.Dispose() }
    if ($manifest -notmatch '(?m)^Premain-Class: com\.knoxsurvivors\.agent\.KnoxAgent\r?$') {
        throw 'Unexpected runtime entry point.'
    }
} finally { $archive.Dispose() }

# PZ's native launcher separates VM arguments and game arguments at an unquoted --.
$quoted = $false
$separator = -1
for ($i = 0; $i -lt $ExistingOptions.Length; $i++) {
    if ($ExistingOptions[$i] -eq '"') { $quoted = -not $quoted; continue }
    if (-not $quoted -and $i + 1 -lt $ExistingOptions.Length -and
        $ExistingOptions.Substring($i, 2) -eq '--' -and
        ($i -eq 0 -or [char]::IsWhiteSpace($ExistingOptions[$i - 1])) -and
        ($i + 2 -eq $ExistingOptions.Length -or [char]::IsWhiteSpace($ExistingOptions[$i + 2]))) {
        if ($separator -ge 0) { throw 'Multiple -- separators require a manual merge.' }
        $separator = $i
    }
}
if ($quoted) { throw 'Existing options contain an unmatched double quote.' }
$agentOption = '-javaagent:"' + $AgentJar + '"=pz-game'
if ($separator -ge 0) {
    $vmOptions = $ExistingOptions.Substring(0, $separator).Trim()
    $gameOptions = $ExistingOptions.Substring($separator + 2).Trim()
} else {
    if ($ExistingOptions -match '(?i)(^|\s)-(?:javaagent:|agentlib:|agentpath:|Xmx|Xms|XX:|D\S+=|cp\b|classpath\b)') {
        throw 'Existing JVM options need a -- separator before game arguments. Add it and rerun.'
    }
    $vmOptions = ''
    $gameOptions = $ExistingOptions.Trim()
}
$options = (@($vmOptions, $agentOption, '--', $gameOptions) | Where-Object { $_ -ne '' }) -join ' '
if (-not $IsolateBundledRuntime) { $options; return }

# The native EXE loads jvm.dll by path, but instrument.dll's dependencies use
# Windows DLL lookup. A system JDK on PATH can otherwise supply an incompatible
# java.dll. Prepend the matching bundled directories for this game process only.
if (-not $GameDirectory) {
    throw '-IsolateBundledRuntime requires -GameDirectory (Steam > Manage > Browse local files). The game and Workshop can occupy different libraries.'
}
$GameDirectory = (Get-Item -LiteralPath $GameDirectory).FullName.TrimEnd('\', '/')
foreach ($relative in @('ProjectZomboid64.exe', 'ProjectZomboid64.json', 'jre64\bin\java.dll',
    'jre64\bin\jli.dll', 'jre64\bin\instrument.dll', 'jre64\bin\server\jvm.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $GameDirectory $relative) -PathType Leaf)) {
        throw "Missing bundled runtime/game file: $relative. Verify Project Zomboid through Steam."
    }
}
# Shell metacharacters in existing arguments cannot safely be forwarded through
# cmd without reinterpreting their quoting. Decline those cases rather than edit them.
if (($GameDirectory + $options) -match '[&|<>^%!\r\n\x00]' -or $GameDirectory.Contains('"')) {
    throw 'Runtime-isolation options contain shell metacharacters requiring a manual setup. No settings were changed.'
}
'cmd /d /v:off /s /c "set "PATH=' + $GameDirectory + '\jre64\bin;' +
    $GameDirectory + '\jre64\bin\server;%PATH%" && %command% ' + $options + '"'
