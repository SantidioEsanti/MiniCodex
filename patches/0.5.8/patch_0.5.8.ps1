# patch_0.5.8.ps1
# 0.5.8 - Release prep v0.1.3 (docs)
#   v2 fix: previous version put markdown code fences (triple backticks) inside
#   a here-string. The outer chat code block was truncated at the first inner
#   fence, so the copied file was missing the here-string closer '@
#   ("missing terminator" at line 118).
#   v2: $notes and $checklist are built from line-by-line arrays (no here-strings
#   for multi-line markdown). No triple-backtick fences anywhere. No backticks
#   inside content. This eliminates the copy-paste hazard entirely.
#
#   Pre-flight verification (warn, do not abort):
#     csproj Version=0.1.3, InformationalVersion=0.1.3
#     CHANGELOG [0.1.3] - 2026-11-15
#     HANDOFF Document version=3.1, Current version=v0.1.3
#     build-release.ps1 exists
#     docs/screenshots/0*.png >= 5 (warning only)
#   Creates docs/release-notes-v0.1.3.md (GitHub Release body).
#   Creates docs/RELEASE_CHECKLIST.md (reusable checklist).
#   CHANGELOG marker 0.5.8.
#   No source code touched. No tests affected.
#
# ASCII-only. Run:
#   powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.5.8\patch_0.5.8.ps1"

Write-Host "=== MiniCodex patch 0.5.8 STARTING ===" -ForegroundColor Cyan
Write-Host ("Script: " + $PSCommandPath)

$ErrorActionPreference = 'Stop'
$version     = '0.5.8'
$projectRoot = 'D:\AI\MiniCodex'
$patchDir    = Join-Path $projectRoot ('patches\' + $version)
$stamp       = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir   = Join-Path $projectRoot ('backups\' + $version + '_' + $stamp)
$logPath     = Join-Path $patchDir ('patch_' + $version + '.log')

if (-not (Test-Path $projectRoot)) { throw ("Project root not found: " + $projectRoot) }
New-Item -ItemType Directory -Force -Path $patchDir  | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}
function Assert([bool]$cond, [string]$msg) {
    if (-not $cond) { throw ("ASSERT FAILED: " + $msg) }
}

Log ("=== MiniCodex patch " + $version + " ===")

$csprojPath    = Join-Path $projectRoot 'src\MiniCodex.App\MiniCodex.App.csproj'
$clPath        = Join-Path $projectRoot 'CHANGELOG.md'
$hoPath        = Join-Path $projectRoot 'docs\HANDOFF.md'
$brPath        = Join-Path $projectRoot 'build-release.ps1'
$notesPath     = Join-Path $projectRoot 'docs\release-notes-v0.1.3.md'
$checklistPath = Join-Path $projectRoot 'docs\RELEASE_CHECKLIST.md'

# ================================================================
# STEP 1: Backup
# ================================================================
Log "STEP 1: Backup"
if (Test-Path $clPath) {
    Copy-Item -LiteralPath $clPath -Destination (Join-Path $backupDir 'CHANGELOG.md') -Force
    Log "  backup: CHANGELOG.md"
}

# ================================================================
# STEP 2: Pre-flight verification
# ================================================================
Log "STEP 2: Pre-flight verification"

Assert (Test-Path $csprojPath) "csproj missing"
Assert (Test-Path $clPath)     "CHANGELOG missing"
Assert (Test-Path $hoPath)     "HANDOFF missing"

$csRaw = Get-Content -LiteralPath $csprojPath -Raw -Encoding UTF8
Assert ($csRaw.Contains('<Version>0.1.3</Version>')) "csproj: Version 0.1.3 missing - run 0.5.7 first"
Assert ($csRaw.Contains('<InformationalVersion>0.1.3</InformationalVersion>')) "csproj: InformationalVersion 0.1.3 missing"
Log "  csproj: 0.1.3 OK"

$clRaw = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
Assert ($clRaw.Contains('## [0.1.3] - 2026-11-15')) "CHANGELOG: [0.1.3] section missing"
Log "  CHANGELOG: [0.1.3] section OK"

$hoRaw = Get-Content -LiteralPath $hoPath -Raw -Encoding UTF8
Assert ($hoRaw.Contains('**Document version:** 3.1 (post v0.1.3 release prep)')) "HANDOFF: v3.1 header missing"
Assert ($hoRaw.Contains('**Current version:** v0.1.3')) "HANDOFF: Current version v0.1.3 missing"
Assert ($hoRaw.Contains('## 13. Next step - v0.1.3 Release')) "HANDOFF: section 13 not rewritten"
Log "  HANDOFF: v3.1 + v0.1.3 OK"

if (Test-Path $brPath) {
    Log "  build-release.ps1: exists"
    $brRaw = Get-Content -LiteralPath $brPath -Raw -Encoding UTF8
    $verMatch = [regex]::Match($brRaw, '0\.\d+\.\d+')
    if ($verMatch.Success) {
        Log ("  build-release.ps1 version literal: " + $verMatch.Value + " (verify matches 0.1.3)")
    }
} else {
    Log ("  WARN: build-release.ps1 not found: " + $brPath)
}

$shotsDir = Join-Path $projectRoot 'docs\screenshots'
if (Test-Path $shotsDir) {
    $shotFiles = @(Get-ChildItem $shotsDir -Filter '0*.png' -ErrorAction SilentlyContinue | Sort-Object Name)
    Log ("  screenshots: " + $shotFiles.Count + " file(s)")
    if ($shotFiles.Count -lt 5) { Log "  WARN: expected 5 (01..05.png)" }
} else {
    Log "  WARN: docs/screenshots/ not found"
}

# ================================================================
# STEP 3: docs/release-notes-v0.1.3.md (line-by-line arrays, no here-strings)
# ================================================================
Log "STEP 3: docs/release-notes-v0.1.3.md"

if (Test-Path $notesPath) {
    Log "  already exists - skipping (idempotent)"
} else {
    $notesLines = @(
        '# MiniCodex v0.1.3',
        '',
        'Portable 3D model library for Windows. **Pre-release.**',
        '',
        'A lightweight desktop app for organizing, viewing, and printing 3D models. No install, no admin rights, data lives next to the exe.',
        '',
        '## Highlights',
        '',
        '- **Associated files viewer**',
        '  - Fullscreen image viewer: double-click a thumbnail, navigate Left/Right, Esc to close.',
        '  - Context menu on every thumbnail: Open (fullscreen) / Open with default viewer / Open in Explorer / Copy path / Replace... / Remove (with confirmation).',
        '  - Third "Other" section for render / document / profile assets (icon fallback for non-images).',
        '- **Multi-select in library grid**',
        '  - Plain click, Ctrl+click (toggle), Shift+click (range), rubber-band on empty space (Ctrl = additive).',
        '  - Esc clears selection, Ctrl+A selects all visible.',
        '  - Group toolbar appears when 2+ cards selected: Add tag (autocomplete) / Copy paths / Find duplicates in selection / Remove selected / Clear.',
        '- **Collection colors** - 8 preset swatches + Clear via context menu on each collection in the sidebar.',
        '- **Tag autocomplete** - in Add tag dialogs (both on the card and in the group dialog).',
        '- **Delete-tag dialog breakdown** - shows direct vs subtree usage count.',
        '',
        '## What is new (full changelog)',
        '',
        'See CHANGELOG.md in the repository for the full [0.1.3] section with all changes.',
        '',
        '## Download',
        '',
        '- MiniCodex-v0.1.3-win-x64.zip (attached below)',
        '',
        '## Install',
        '',
        '1. Extract anywhere (Desktop, portable USB drive, etc.).',
        '2. Run MiniCodex.exe.',
        '3. Data is stored in ./data/ next to the exe. First run creates it.',
        '',
        'No installer, no admin rights, no .NET install required (self-contained build).',
        '',
        '## Requirements',
        '',
        '- Windows 10/11 x64.',
        '',
        '## Known limitations',
        '',
        '- Windows x64 only.',
        '- Fullscreen image viewer: no zoom/pan, no rotation, no EXIF orientation.',
        '- Replace re-imports the file as a new asset row; old thumbnail stays in cache (harmless).',
        '- Tag rename/delete does not merge same-named children.',
        '- Software renderer: ~50-100ms per frame at 480x480 on 100k triangles. No LOD.',
        '- Search: SQLite LIKE is case-sensitive for Cyrillic (English fine).',
        '',
        '## Checksums',
        '',
        '    SHA-256 (MiniCodex-v0.1.3-win-x64.zip): <fill after build>',
        '',
        '---',
        '',
        'Licensed under MIT. Repository: https://github.com/SantidioEsanti/MiniCodex'
    )
    $notes = ($notesLines -join "`n")
    Set-Content -LiteralPath $notesPath -Value $notes -Encoding UTF8 -NoNewline
    Log ("  created (" + $notes.Length + " chars)")
}

# ================================================================
# STEP 4: docs/RELEASE_CHECKLIST.md (line-by-line arrays, no here-strings)
# ================================================================
Log "STEP 4: docs/RELEASE_CHECKLIST.md"

if (Test-Path $checklistPath) {
    Log "  already exists - skipping (idempotent)"
} else {
    $checklistLines = @(
        '# MiniCodex Release Checklist',
        '',
        'Reusable checklist for any MiniCodex version X.Y.Z. Run through top to bottom.',
        '',
        '## Pre-flight',
        '',
        '- [ ] dotnet build "src/MiniCodex.sln" - 0 errors, 0 warnings',
        '- [ ] dotnet test "src/MiniCodex.sln" - all green (currently 60)',
        '- [ ] dotnet run --project "src/MiniCodex.App/MiniCodex.App.csproj" - smoke-test UI',
        '- [ ] csproj: Version and InformationalVersion match target',
        '- [ ] CHANGELOG.md: target [X.Y.Z] - YYYY-MM-DD section is present at top',
        '- [ ] docs/HANDOFF.md: Document version, Current version, and section 13 next-step updated',
        '- [ ] docs/release-notes-vX.Y.Z.md exists',
        '- [ ] docs/screenshots/01..05.png present (per README references)',
        '- [ ] build-release.ps1 present and its version literal (if any) matches target',
        '',
        '## Build and verify',
        '',
        '- [ ] powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"',
        '- [ ] dist/MiniCodex-vX.Y.Z-win-x64.zip exists and is > 30 MB',
        '- [ ] Extract zip to a clean Windows x64 folder',
        '- [ ] MiniCodex.exe starts, no crash, main window shows',
        '- [ ] Smoke-test:',
        '  - [ ] Library loads (previous DB intact)',
        '  - [ ] Scan folder works',
        '  - [ ] Open a card, close, back',
        '  - [ ] Associations tab: fullscreen viewer (double-click, Esc, Left/Right)',
        '  - [ ] Multi-select: rubber band, Ctrl/Shift, group toolbar actions',
        '  - [ ] Collections: apply one, set color via context menu',
        '  - [ ] Settings: integrations list loads',
        '- [ ] Compute SHA-256 of zip: (Get-FileHash -Path "dist\MiniCodex-vX.Y.Z-win-x64.zip" -Algorithm SHA256).Hash',
        '',
        '## Git',
        '',
        '- [ ] git status - only expected changes (no stray .log/.tmp)',
        '- [ ] git add . ; git commit -m "Release vX.Y.Z: <one-line summary>"',
        '- [ ] git tag -a vX.Y.Z -m "MiniCodex vX.Y.Z"',
        '- [ ] git push origin master ; git push origin vX.Y.Z',
        '- [ ] git tag -n - tag listed with message',
        '',
        '## GitHub Release',
        '',
        '- [ ] Open https://github.com/SantidioEsanti/MiniCodex/releases/new',
        '- [ ] Choose existing tag vX.Y.Z',
        '- [ ] Title: MiniCodex vX.Y.Z',
        '- [ ] Body: paste from docs/release-notes-vX.Y.Z.md, fill SHA-256',
        '- [ ] Attach dist/MiniCodex-vX.Y.Z-win-x64.zip',
        '- [ ] Check "Set as a pre-release" (for 0.x)',
        '- [ ] Publish',
        '',
        '## Post-release',
        '',
        '- [ ] Verify download + extract + run on a fresh machine',
        '- [ ] Update docs/HANDOFF.md section 13 for next version',
        '- [ ] Update README.md "Latest release" link if pinned to a version'
    )
    $checklist = ($checklistLines -join "`n")
    Set-Content -LiteralPath $checklistPath -Value $checklist -Encoding UTF8 -NoNewline
    Log ("  created (" + $checklist.Length + " chars)")
}

# ================================================================
# STEP 5: CHANGELOG marker (line-by-line, no here-string)
# ================================================================
Log "STEP 5: CHANGELOG marker 0.5.8"

$cl = Get-Content -LiteralPath $clPath -Raw -Encoding UTF8
if ($cl.Contains('<!-- patch 0.5.8 applied -->')) {
    Log "  marker already present - skipping"
} else {
    $clLines = @(
        '',
        '## 0.5.8 - Release prep v0.1.3 (docs)',
        '',
        '- docs/release-notes-v0.1.3.md: ready-to-paste GitHub Release body.',
        '- docs/RELEASE_CHECKLIST.md: reusable checklist for future releases.',
        '- Pre-flight verification: csproj 0.1.3, CHANGELOG [0.1.3], HANDOFF v3.1, build-release.ps1, docs/screenshots.',
        '- No source code touched. No tests affected.',
        '<!-- patch 0.5.8 applied -->'
    )
    $clEntry = ($clLines -join "`n")
    Add-Content -LiteralPath $clPath -Value $clEntry -Encoding UTF8
    Log "  CHANGELOG appended"
}

Log ("=== Patch " + $version + " applied ===")
Log ("Backup: " + $backupDir)
Write-Host ""
Write-Host ("Done. Backup: " + $backupDir) -ForegroundColor Green
Write-Host "Next: run dotnet build/test, then build-release.ps1, then git tag v0.1.3 + GitHub Release." -ForegroundColor Cyan