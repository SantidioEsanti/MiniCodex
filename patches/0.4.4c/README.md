# Patch 0.4.4c - Fix exe name

**Iteration:** 0.4

## Cause

dotnet publish produced MiniCodex.App.exe (from csproj name),
but build-release.ps1 checked for MiniCodex.exe and exited with error
before running Compress-Archive. No zip was created.

## Fix

1. MiniCodex.App.csproj: add AssemblyName=MiniCodex
   -> exe becomes MiniCodex.exe (user-friendly)
2. build-release.ps1: remove old publish dir before publishing
   (avoids stale MiniCodex.App.exe alongside new MiniCodex.exe)
3. build-release.ps1: accept both MiniCodex.exe and MiniCodex.App.exe
   (defensive fallback; print publish dir contents on failure)

## DoD

- csproj has AssemblyName=MiniCodex.
- build-release.ps1 has fallback + cleanup.
- Re-run build-release.ps1 -> dist/MiniCodex-v0.1.0-alpha-win-x64.zip created.
- Zip contains MiniCodex.exe.