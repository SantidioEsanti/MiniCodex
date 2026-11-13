# Patch 0.4.3g.1 - Close 0.4.3g

**Iteration:** 0.4

## Cause
0.4.3g applied all code changes, then hung on Remove-Item without -LiteralPath.
User pressed Ctrl+C; CHANGELOG entry and thumbs cleanup were skipped.

## Fix
- CHANGELOG entry 0.4.3g added.
- Old 128px thumbs ({assetId}.png) cleaned from dev bin/ using -LiteralPath (safe).
- Verified that 0.4.3g changes are in place (Assoc first tab, HasReferenceAssets, 256x256, _selectedTabIndex=0, _256.png).

## DoD
- dotnet build: 0 errors.
- dotnet test: 48/48.
- All verify checks OK in log.