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