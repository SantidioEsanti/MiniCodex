#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a14 - HANDOFF refresh (v2.1) before v0.1.0-alpha release.
.DESCRIPTION
    Append-only: insert section 14 before "End of HANDOFF", update version header.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a14'
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

## 14. Iteration 0.4.5 - Post-release stabilization (2026-11-12/13)

After 0.4.3z3 was usable, testing with 76 heavy models (1.5M polys each) revealed issues.
Iteration 0.4.5a1..a13.1 fixed them. All 48 tests still pass, 0 build warnings.

### 14.1 Logging (0.4.5a1, a2)

- Core/Logging/Log.cs - static file logger. Appends to data/logs/minicodex-{yyyyMMdd}.log
  (crash-safe: per-line File.AppendAllText with lock). Log.Info/Warn/Error/Exception/SessionEnd/MemoryMb.
- Program.Main wraps StartWithClassicDesktopLifetime in try/finally + global handlers:
  AppDomain.UnhandledException, TaskScheduler.UnobservedTaskException, Dispatcher.UIThread.UnhandledException.
- App.OnFrameworkInitializationCompleted restores DatabaseInitializer.InitializeAsync + AppServices.Init
  (lost in a1 refactor - caused silent no-op scanning until a2).
- ScannerService: per-file logging (FILE start/ok/fail with size, polys, took, mem).
- AssimpMeshLoader: all silent catches now log via Log.Exception.

### 14.2 Memory / OOM fixes (0.4.5a1, a3, a4)

Cause: LibraryViewModel launched 76 parallel Task.Run(LoadDetailsAsync) - each one spawned
an Assimp ImportFile of 1.5M poly -> 10+ GB native alloc -> "bad allocation".

Fixes:
- 0.4.5a1: removed PostProcessSteps.JoinIdenticalVertices (memory hog).
- 0.4.5a3: SemaphoreSlim(1,1) in LibraryViewModel - preview gen is serialized.
  PreviewGenerator: LoadGeometry once per model (was 4x), GC.Collect after each model.
  ScannerService: GC.Collect every 10 files.
- 0.4.5a4: preview progress in status bar ("Previews: X / Y"). IAsyncDisposable
  cancels pending preview tasks on detach (no duplicate parallel after nav).

### 14.3 Rendering fixes (0.4.5a5..a11, a13)

Many iterations to fix shading artifacts on dense meshes:
- a5: sub-pixel force-draw, supersample param in IPreviewRenderer.Render.
- a6: bbox fill (not just center pixel), degenerate triangles drawn with MinLambert,
  scale safety for collapsed bbox, SS=3 default.
- a7: two-sided lighting (MathF.Abs on lambert dot) - fixed STL winding sparkle.
- a8: ZBias on regular triangles (fixed z-fighting on bases/plinths), fill light.
- a9: sub-pixel uses max-z (front-most triangle wins), fill light always (no inversion).
- a10: file normals from Assimp mesh.Normals + Gouraud per-vertex lambert.
  Fixed flat grey on 1.5M+ poly models. ModelCardViewModel passes orientation offset.
- a11: fill light removed (single key light) - less "chrome", more contrast.
- a13: YawDegrees {220, 250, 280, 310} - 90deg span, 30deg per step.

### 14.4 UI polish (0.4.5a4, a12, a13)

- a4: preview progress in library status bar.
- a12: first-scan warning overlay (Setting "Scan.WarningShown"). Theme ComboBox
  replaced with icon button (sun/moon/contrast, Segoe Fluent Icons E706/E708/E7F4).
- a13: theme persisted in Setting "UI.Theme" (loaded sync in MainWindowViewModel ctor).
  Auto-save card fields Title/Author/SourceUrl/Notes/Scale (500ms debounce);
  Save button removed from toolbar. Library preview: no grey rectangle, rounded corners.

### 14.5 Version

0.4.5a13.1. 48 tests passing. 0 build warnings.

---

## 15. Next step - v0.1.0-alpha release

Prerequisites (already done):
- build-release.ps1 at project root.
- README.md with 5 screenshot references.
- AssemblyName=MiniCodex (exe name), Version 0.1.0, InformationalVersion 0.1.0-alpha.
- Screenshots must be saved in docs/screenshots/ with names 01..05 (see README.md).

Release steps:
1. `powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"`
   -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip
2. Verify by extracting on clean Windows x64, running MiniCodex.exe.
3. git init, git add ., git commit -m "MiniCodex v0.1.0-alpha".
4. Push to https://github.com/SantidioEsanti/MiniCodex
5. GitHub Release: tag v0.1.0-alpha, pre-release flag, attach zip.

### Known limitations (deferred to v0.1.1+)

- STL with layer-lines from 3D scanners still shows micro texture (spatial dedup for smoothing planned).
- No single-instance lock (multiple launches race on SQLite file).
- Grid not virtualized (WrapPanel in ScrollViewer; OK for <1000 cards).
- Drag-rotate during 3D drag renders at half resolution internally (~5 fps).
- Tag hierarchy flat in UI (parent_id in DB, unused).
- Tag color field unused (no picker UI).
- render/document/profile asset types stored but hidden from Associations tab.
- Multi-select in library not implemented (delete only via context menu).
- No Copy/Paste/Undo in notes/fields.

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

    # 1. Update version header
    $handoff = $handoff.Replace(
        '**Document version:** 2.0 (after ~50 patches)',
        '**Document version:** 2.1 (after ~65 patches)')
    $handoff = $handoff.Replace(
        '**Last updated:** 2026-11-12',
        '**Last updated:** 2026-11-13')
    $handoff = $handoff.Replace(
        '**Current version:** 0.4.3z2 (pre-release)',
        '**Current version:** 0.4.5a13.1 (pre-release, ready for v0.1.0-alpha release)')

    # 2. Insert new sections before "End of HANDOFF"
    $marker = 'End of HANDOFF.'
    if ($handoff.Contains($marker)) {
        # Insert before "---`r`n`r`nEnd of HANDOFF." or "---`n`nEnd of HANDOFF."
        $handoff = $handoff.Replace("---`r`n`r`n$marker", "$newSection`r`n$marker")
        if ($handoff -eq $original) {
            # Try LF variant
            $handoff = $handoff.Replace("---`n`n$marker", "$newSection`n$marker")
        }
        if ($handoff -eq $original) {
            # Fallback: just insert before marker
            $handoff = $handoff.Replace($marker, "$newSection`r`n$marker")
        }
        Write-Log 'HANDOFF.md: inserted sections 14 and 15 before End of HANDOFF'
    } else {
        Write-Log 'HANDOFF.md: "End of HANDOFF." marker not found - appending at end' 'WARN'
        $handoff = $handoff + "`r`n" + $newSection
    }

    if ($handoff -ne $original) {
        [IO.File]::WriteAllText($handoffPath, $handoff, [Text.UTF8Encoding]::new($false))
        Write-Log 'updated: docs\HANDOFF.md'
    } else {
        Write-Log 'HANDOFF.md: no changes detected (already updated?)' 'WARN'
    }

    # 3. Verify
    $verify = [IO.File]::ReadAllText($handoffPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('version header 2.1', ($verify -match 'Document version:.*2\.1')),
        @('section 14 present', ($verify -match '## 14\. Iteration 0\.4\.5')),
        @('section 15 present', ($verify -match '## 15\. Next step')),
        @('known limitations', ($verify -match 'Known limitations \(deferred')),
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
# Patch 0.4.5a14 - HANDOFF refresh (v2.1)

**Iteration:** 0.4.5

## What it does

Appends to docs/HANDOFF.md (append-only, existing sections 1-13 preserved):

- Section 14: Iteration 0.4.5 (Post-release stabilization)
  - 14.1 Logging (Log.cs, Program.Main handlers, ScannerService, AssimpMeshLoader)
  - 14.2 Memory / OOM fixes (SemaphoreSlim, load-once, GC)
  - 14.3 Rendering fixes (a5..a13 sequence explained)
  - 14.4 UI polish (progress, warning, theme icon, autosave, rounded corners)
  - 14.5 Version 0.4.5a13.1

- Section 15: Next step - v0.1.0-alpha release
  - Prerequisites already in place
  - Release steps (build-release.ps1 -> verify -> git -> GitHub Release)
  - Known limitations (deferred to v0.1.1+)

Header updates:
- Document version 2.0 -> 2.1
- Last updated 2026-11-12 -> 2026-11-13
- Current version 0.4.3z2 -> 0.4.5a13.1

## Why append-only

Rewriting 400+ lines of ASCII HANDOFF through a .ps1 here-string risks parser errors
(proven by earlier experience with 0.4.1, 0.4.2). Append-only is safe and preserves
all historical context.

## DoD

- docs/HANDOFF.md ~700 lines (was ~380).
- Verify checks: version 2.1, sections 14/15, known limitations, End marker.
- Next: build-release.ps1 + GitHub Release.
'@
    [IO.File]::WriteAllText((Join-Path $PatchDir 'README.md'), $patchReadme, [Text.UTF8Encoding]::new($false))
    Write-Log 'created: patches\0.4.5a14\README.md'

    # 5. CHANGELOG
    $marker = '<!-- patch 0.4.5a14 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a14] - 2026-11-13`r`n`r`n### Changed`r`n- docs/HANDOFF.md v2.1 (append-only): section 14 (0.4.5 post-release stabilization), section 15 (v0.1.0-alpha release steps + known limitations).`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.4\.5a13\.1\].*)$', "$entry`$1"
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