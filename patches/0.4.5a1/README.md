# Patch 0.4.5a1 - Diagnostic logging + Assimp memory fix

**Iteration:** 0.4.5 (post-release diagnostics)

## What it does

1. NEW: Core/Logging/Log.cs - static file logger.
   - Writes to data/logs/minicodex-{yyyyMMdd}.log (append per line, crash-safe).
   - Init in Program.Main before Avalonia.
   - MemoryMb() helper for GC.GetTotalMemory.

2. Program.cs - global exception handlers:
   - AppDomain.UnhandledException -> full stack trace to log.
   - TaskScheduler.UnobservedTaskException -> full stack trace to log.
   - try/finally around StartWithClassicDesktopLifetime with SessionEnd().

3. App.axaml.cs - Dispatcher.UIThread.UnhandledException handler.

4. ScannerService.cs - per-file logging:
   - SCAN START, SCAN FILES, SCAN DONE with counters.
   - FILE start path=X size=Y before parse (identifies crash file if app dies).
   - FILE add-ok / update-ok / skip-unchanged / parse-failed / error after (with took + mem).
   - Files >2GB skipped with WARN (safety).

5. AssimpMeshLoader.cs:
   - REMOVED PostProcessSteps.JoinIdenticalVertices (memory hog for millions of polygons).
     Only Triangulate now. Halves or better memory for large meshes.
   - All silent catch blocks now log via Log.Exception.
   - Timing per operation.

## Known limitation

Diagnostics are ENGLISH only (log is technical, not user-facing).
App UI still localizes normally.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48 (unchanged - no behavior change, only logging).
- Run app: data/logs/minicodex-{date}.log created with === START === marker.
- Scan folder: log fills with FILE start/ok lines per file.
- If crash: log ends mid-scan, last FILE start path identifies culprit.

## How to read after crash

Get-Content "D:\AI\MiniCodex\src\MiniCodex.App\bin\Debug\net8.0\data\logs\minicodex-$(Get-Date -Format yyyyMMdd).log" -Tail 50 -Encoding UTF8

Cases:
- No FILE start after SCAN START -> crash in Avalonia init or before scan
- FILE start path=X but no following add-ok/parse-failed/error -> crash on X
- OutOfMemoryException in stack -> memory (PreviewGenerator 4x load, or Assimp on huge file)
- AccessViolationException -> native crash (assimp.dll / libSkiaSharp.dll)