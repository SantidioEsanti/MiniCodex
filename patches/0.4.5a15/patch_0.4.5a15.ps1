#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a15 - HANDOFF v2.2 (append section 16: post-release state).
.DESCRIPTION
    Append-only: insert section 16 before "End of HANDOFF", update version header.
    Preserves sections 1-15 from previous patches.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a15'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel"
}

$newSection = @'
---

## 16. Post-release state (2026-11-13)

MVP v0.1.0-alpha is PUBLISHED on GitHub.

- Release page: https://github.com/SantidioEsanti/MiniCodex/releases/tag/v0.1.0-alpha
- Repository: https://github.com/SantidioEsanti/MiniCodex (public, MIT license)
- Tag: v0.1.0-alpha (pre-release)
- Artifact: MiniCodex-v0.1.0-alpha-win-x64.zip (~42 MB zip, ~95 MB extracted)
- SHA-256: see Release description on GitHub
- CI: GitHub Actions build.yml succeeded on first push (green check on initial commit)
- Topics: 20 (3d-printing, 3d-models, miniatures, stl, 3mf, obj, 3d-model-manager,
  stl-library, 3d-viewer, scale-converter, slicer-integration, dotnet, avalonia,
  csharp, sqlite, windows, portable, desktop-app, catalog, hobby)
  - NOTE: 'object-detection' was added accidentally. Remove via repo Settings if desired.

### 16.1 Metrics at release

- 0 downloads, 0 stars, 0 forks, 0 watchers (as of 2026-11-13)
- No issues yet

### 16.2 First 48h checklist (post-release)

1. Verify README screenshots render correctly in browser (5 images in docs/screenshots/,
   named 01-library-light.png ... 05-settings-integrations.png).
   If broken -> rename SCR_*.png and push again.
2. Announce on Reddit (r/3Dprinting, r/PrintedMinis, r/minipainting),
   Boosty, relevant Telegram channels.
3. Monitor GitHub Issues, respond within 24h.
4. Track download counter on Release page (metric: <10 = repitch,
   10-50 = normal solo-MVP start, 50-200 = good reception, 200+ = prioritize v0.1.1).

### 16.3 v0.1.1 backlog (priority by expected user impact)

1. Spatial deduplication for 3D-scanned STL (smooth normals; layer-line artifacts
   remain on scanned meshes because normals are per-face or degenerate).
2. Grid virtualization (ItemsRepeater + UniformGridLayout) for 1000+ models.
   WrapPanel in ScrollViewer is not virtualized.
3. Single-instance lock (SQLite race when multiple launches).
4. Tag hierarchy in UI (Tag.parent_id already in DB, currently flat).
5. Custom icons for status (replace Unicode glyphs with SVG for consistent rendering).
6. If z-fighting resurfaces: per-face depth sorting or MSAA (currently zbias on
   regular triangles; sub-pixel path uses max-z without bias).

### 16.4 What is NOT in v0.1.0-alpha (see §15 for full list)

- No archives (ZIP/RAR/7Z) - planned v1.1
- No duplicate geometry detection
- No printer bed fit check
- No multi-select in library grid
- render/document/profile asset types stored in DB but hidden from UI
- No tag color picker UI (Tag.color field unused)

### 16.5 Development workflow reminder for next session

- All changes through patch scripts (section 10).
- .ps1 = ASCII-only. If Cyrillic needed: BOM-fix prepend + here-strings closing
  marker at column 0 (no leading spaces), or use [char] codes, or base64.
- One patch = one logical step. Do NOT bundle plumbing + full UI rewrite.
- 48 tests must stay green after every patch. Build: 0 errors, 0 warnings.
- When changing an interface signature (e.g. IPreviewRenderer.Render, IPreviewGenerator),
  grep for Stub*/Fake*/Test*/Mock* implementations in MiniCodex.Tests - update them too
  (hard-won lesson from 0.3.0a, 0.4.5a1, 0.4.5a5.1).
- Next session: start by reading HANDOFF.md fully, then plan before patching.

'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $handoffPath = Join-Path $ProjectRoot 'docs\HANDOFF.md'
    Backup-File $handoffPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    $handoff = [IO.File]::ReadAllText($handoffPath, [Text.Encoding]::UTF8)
    $original = $handoff

    # 1. Header updates
    $handoff = $handoff.Replace(
        '**Document version:** 2.1 (after ~65 patches)',
        '**Document version:** 2.2 (after ~66 patches, post-release)')
    $handoff = $handoff.Replace(
        '**Current version:** 0.4.5a13.1 (pre-release, ready for v0.1.0-alpha release)',
        '**Current version:** v0.1.0-alpha (PUBLISHED 2026-11-13)')

    # 2. Idempotency guard
    if ($handoff -match '## 16\. Post-release state') {
        Write-Log 'HANDOFF.md: section 16 already present, skipping insert.' 'WARN'
    } else {
        $marker = 'End of HANDOFF.'
        if (-not $handoff.Contains($marker)) {
            Write-Log 'HANDOFF.md: "End of HANDOFF." marker not found - abort.' 'ERROR'
            exit 1
        }
        # Try CRLF variant first
        $crlfTarget = "---`r`n`r`n$marker"
        $lfTarget = "---`n`n$marker"
        if ($handoff.Contains($crlfTarget)) {
            $handoff = $handoff.Replace($crlfTarget, "$newSection`r`n$marker")
            Write-Log 'HANDOFF.md: inserted section 16 before End marker (CRLF)'
        } elseif ($handoff.Contains($lfTarget)) {
            $handoff = $handoff.Replace($lfTarget, "$newSection`n$marker")
            Write-Log 'HANDOFF.md: inserted section 16 before End marker (LF)'
        } else {
            $handoff = $handoff.Replace($marker, "$newSection`r`n$marker")
            Write-Log 'HANDOFF.md: inserted section 16 before End marker (fallback)' 'WARN'
        }
    }

    if ($handoff -ne $original) {
        [IO.File]::WriteAllText($handoffPath, $handoff, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: docs\HANDOFF.md'
    } else {
        Write-Log 'HANDOFF.md: no changes (already updated?)' 'WARN'
    }

    # 3. Verify
    $verify = [IO.File]::ReadAllText($handoffPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('version header 2.2', ($verify -match 'Document version:.*2\.2')),
        @('section 16 present', ($verify -match '## 16\. Post-release state')),
        @('release link', ($verify -match 'releases/tag/v0\.1\.0-alpha')),
        @('v0.1.1 backlog', ($verify -match 'v0\.1\.1 backlog')),
        @('End of HANDOFF retained', ($verify -match 'End of HANDOFF\.'))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    $size = (Get-Item -LiteralPath $handoffPath).Length
    $lines = (Get-Content -LiteralPath $handoffPath).Count
    Write-Log ("HANDOFF.md size: {0} bytes, {1} lines" -f $size, $lines)

    # 4. Patch README
    $patchReadme = @'
# Patch 0.4.5a15 - HANDOFF v2.2 (post-release)

**Iteration:** 0.4.5 (final)

## What it does

Appends section 16 to docs/HANDOFF.md (append-only, sections 1-15 preserved):

- 16.0 Release details (URL, tag, artifact, CI, topics, note about stray 'object-detection' topic)
- 16.1 Metrics at release (0/0/0/0)
- 16.2 First 48h checklist (screenshots, announcements, monitoring, download counter thresholds)
- 16.3 v0.1.1 backlog (6 prioritized items)
- 16.4 What is NOT in v0.1.0-alpha (see section 15)
- 16.5 Development workflow reminder for next session

Header updates:
- Document version 2.1 -> 2.2
- Current version 0.4.5a13.1 -> v0.1.0-alpha (PUBLISHED 2026-11-13)

## Why

This is the escape hatch for the next dialogue. After this patch, a new AI session
can read HANDOFF.md top-to-bottom (about 5 minutes) and be fully oriented:
architecture, DB, patch workflow, 0.4.5 changes, release state, backlog, lessons.

## DoD

- docs/HANDOFF.md has section 16, version header 2.2, ~750 lines.
- Release link present.
- End marker preserved.
- No changes to src/, tests, or runtime behavior.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $patchReadme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a15\README.md'

    # 5. CHANGELOG
    $marker = '<!-- patch 0.4.5a15 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a15] - 2026-11-13`r`n`r`n### Changed`r`n- docs/HANDOFF.md v2.2: section 16 (post-release state, metrics, v0.1.1 backlog, workflow reminder).`r`n`r`n### Released`r`n- v0.1.0-alpha published on GitHub: https://github.com/SantidioEsanti/MiniCodex/releases/tag/v0.1.0-alpha`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a14\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}