# MiniCodex Release Checklist

Reusable checklist for any MiniCodex version X.Y.Z. Run through top to bottom.

## Pre-flight

- [ ] dotnet build "src/MiniCodex.sln" - 0 errors, 0 warnings
- [ ] dotnet test "src/MiniCodex.sln" - all green (currently 60)
- [ ] dotnet run --project "src/MiniCodex.App/MiniCodex.App.csproj" - smoke-test UI
- [ ] csproj: Version and InformationalVersion match target
- [ ] CHANGELOG.md: target [X.Y.Z] - YYYY-MM-DD section is present at top
- [ ] docs/HANDOFF.md: Document version, Current version, and section 13 next-step updated
- [ ] docs/release-notes-vX.Y.Z.md exists
- [ ] docs/screenshots/01..05.png present (per README references)
- [ ] build-release.ps1 present and its version literal (if any) matches target

## Build and verify

- [ ] powershell -ExecutionPolicy Bypass -File ".\build-release.ps1"
- [ ] dist/MiniCodex-vX.Y.Z-win-x64.zip exists and is > 30 MB
- [ ] Extract zip to a clean Windows x64 folder
- [ ] MiniCodex.exe starts, no crash, main window shows
- [ ] Smoke-test:
  - [ ] Library loads (previous DB intact)
  - [ ] Scan folder works
  - [ ] Open a card, close, back
  - [ ] Associations tab: fullscreen viewer (double-click, Esc, Left/Right)
  - [ ] Multi-select: rubber band, Ctrl/Shift, group toolbar actions
  - [ ] Collections: apply one, set color via context menu
  - [ ] Settings: integrations list loads
- [ ] Compute SHA-256 of zip: (Get-FileHash -Path "dist\MiniCodex-vX.Y.Z-win-x64.zip" -Algorithm SHA256).Hash

## Git

- [ ] git status - only expected changes (no stray .log/.tmp)
- [ ] git add . ; git commit -m "Release vX.Y.Z: <one-line summary>"
- [ ] git tag -a vX.Y.Z -m "MiniCodex vX.Y.Z"
- [ ] git push origin master ; git push origin vX.Y.Z
- [ ] git tag -n - tag listed with message

## GitHub Release

- [ ] Open https://github.com/SantidioEsanti/MiniCodex/releases/new
- [ ] Choose existing tag vX.Y.Z
- [ ] Title: MiniCodex vX.Y.Z
- [ ] Body: paste from docs/release-notes-vX.Y.Z.md, fill SHA-256
- [ ] Attach dist/MiniCodex-vX.Y.Z-win-x64.zip
- [ ] Check "Set as a pre-release" (for 0.x)
- [ ] Publish

## Post-release

- [ ] Verify download + extract + run on a fresh machine
- [ ] Update docs/HANDOFF.md section 13 for next version
- [ ] Update README.md "Latest release" link if pinned to a version