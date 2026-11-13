# Patch 0.4.4a - build-release.ps1

**Iteration:** 0.4

## What it does

Creates build-release.ps1 at project root. No src/ changes, no README rewrite.

Script contents (generated via line array, no here-strings):
- param(-Version "0.1.0-alpha")
- dotnet publish -c Release -r win-x64 --self-contained /p:PublishSingleFile=true
- remove *.pdb
- remove data/ if present
- Compress-Archive to dist/MiniCodex-v{Version}-win-x64.zip
- print zip path, size, SHA-256, file count
- uses $PSScriptRoot, works from any cwd

## DoD

- build-release.ps1 present at root.
- Verify checks OK in log (param, Compress-Archive, Get-FileHash).
- User can run: powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\build-release.ps1"