# patch_0.5.4.ps1 - Release v0.1.2 Prep
# Updates .csproj version, finalizes CHANGELOG.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.4'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot ("backups\{0}_{1}" -f $Version, $Timestamp)
$PatchDir    = Join-Path $ProjectRoot ("patches\{0}" -f $Version)
$LogPath     = Join-Path $PatchDir 'patch.log'
$utf8NoBom   = [Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $PatchDir  | Out-Null

function Write-Log([string]$msg) {
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Replace-Exact([string]$path, $pairs) {
    $c = [IO.File]::ReadAllText($path, $utf8NoBom)
    $hadCrLf = $c.Contains("`r`n")
    if ($hadCrLf) { $c = $c.Replace("`r`n", "`n") }
    foreach ($p in $pairs) {
        $old = $p.Old.Replace("`r`n", "`n")
        $new = $p.New.Replace("`r`n", "`n")
        $cnt = [regex]::Matches($c, [regex]::Escape($old)).Count
        if ($cnt -eq 0) { throw ("Anchor not found: {0}" -f $p.Label) }
        $c = $c.Replace($old, $new)
        Write-Log ("  replaced: {0}" -f $p.Label)
    }
    if ($hadCrLf) { $c = $c.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $c, $utf8NoBom)
}

Write-Log ("Patch {0} started" -f $Version)

# ---------- 0. Pre-flight ----------
$csprojPath = Join-Path $ProjectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
$chPath     = Join-Path $ProjectRoot 'CHANGELOG.md'

if (-not (Test-Path -LiteralPath $csprojPath)) { throw 'MiniCodex.App.csproj not found.' }
if (-not (Test-Path -LiteralPath $chPath))     { throw 'CHANGELOG.md not found.' }

$csproj = [IO.File]::ReadAllText($csprojPath, $utf8NoBom)
if ($csproj -match '<Version>0\.1\.2') { throw 'Pre-flight: already at v0.1.2.' }

# ---------- 1. Backup ----------
$filesToBackup = @('src\MiniCodex.App\MiniCodex.App.csproj', 'CHANGELOG.md')
foreach ($rel in $filesToBackup) {
    $src    = Join-Path $ProjectRoot $rel
    $dst    = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. Update csproj ----------
$c = [IO.File]::ReadAllText($csprojPath, $utf8NoBom)
# Version
if ($c -match '<Version>[^<]+</Version>') {
    $c = $c -replace '<Version>[^<]+</Version>', '<Version>0.1.2</Version>'
    Write-Log 'csproj: Version -> 0.1.2'
}
# InformationalVersion
if ($c -match '<InformationalVersion>[^<]+</InformationalVersion>') {
    $c = $c -replace '<InformationalVersion>[^<]+</InformationalVersion>', '<InformationalVersion>0.1.2</InformationalVersion>'
    Write-Log 'csproj: InformationalVersion -> 0.1.2'
}
[IO.File]::WriteAllText($csprojPath, $c, $utf8NoBom)

# ---------- 3. Prepend Release section to CHANGELOG ----------
$ch = [IO.File]::ReadAllText($chPath, $utf8NoBom)
$nl = if ($ch.Contains("`r`n")) { "`r`n" } else { "`n" }

$releaseHeader = '# Changelog' + $nl + $nl +
    '## [0.1.2] - 2026-11-14' + $nl + $nl +
    '### Added' + $nl +
    '- **Smart Collections**: Save current search + tag filter as a named collection in the sidebar. ' + $nl +
    '- **Tag Management**: Right-click tag menu with Rename, Delete, and Clear Color. ' + $nl +
    '- **Tag Colors**: 8 preset palette swatches + custom HEX color picker dialog with live preview. ' + $nl +
    '- **Keyboard UX**: Enter (Save) and Esc (Cancel) now work in all modal dialogs. ' + $nl +
    '- **MeshNormalSmoother**: Spatial deduplication for 3D-scanned STLs (fixes layer lines). ' + $nl +
    '- **Duplicate Detection**: Find models with identical SHA-256 file hashes (toolbar button). ' + $nl +
    '- **Single-Instance Lock**: Named Mutex prevents multiple instances from corrupting SQLite. ' + $nl + $nl +
    '### Fixed' + $nl +
    '- **UI Stability**: Reverted to ItemsControl + WrapPanel (Avalonia 11.1.5 ItemsRepeater was causing invisible cards). ' + $nl +
    '- **Context Menus**: Right-click on tags now works on the full row, not just the text. ' + $nl +
    '- **Localization**: Fixed indents and missing keys in `en.json` / `ru.json`. ' + $nl + $nl +
    '### Changed' + $nl +
    '- Redesigned UI using "Soft Glass" concept (rounded corners, soft shadows, gradients). ' + $nl + $nl +
    '---' + $nl + $nl

if ($ch.StartsWith('# Changelog')) {
    # Remove the first line and replace with header + release
    $ch = $ch.Substring($ch.IndexOf($nl) + $nl.Length).TrimStart()
    $ch = $releaseHeader + $ch
} else {
    $ch = $releaseHeader + $ch
}

[IO.File]::WriteAllText($chPath, $ch, $utf8NoBom)
Write-Log 'CHANGELOG.md: added [0.1.2] release section.'

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)