# Patch 0.4.5a2 - Restore Init + null-service logging

**Iteration:** 0.4.5

## Root cause

0.4.5a1 rewrote App.axaml.cs and LOST two critical calls:
  DatabaseInitializer.InitializeAsync(Paths.LibraryDb)
  AppServices.Init(Paths)

Without them: AppServices.Scanner = null, Models = null, etc.
LibraryViewModel.ScanAsync silently returns at first null check.
No "SCAN START" in log; no scanning; no user feedback.

## What it does

1. App.axaml.cs: restore DatabaseInitializer.InitializeAsync + AppServices.Init.
   Each step logs begin/ok/fail. Logs service availability after Init.

2. LibraryViewModel:
   - ctor logs which services are non-null.
   - LoadAsync logs begin / skip-reason / done.
   - ScanAsync logs begin + folder count + service availability.
     ABORT reasons (services null / empty folders) logged as WARN.
     try/catch around Scanner call + post-scan reload; final "end cards=N".

3. LibraryView.axaml.cs:
   - OnLoaded logs begin / DataContext type / end.
   - OnScanClick logs each step: click, DataContext type, StorageProvider null-check,
     folder picker returned count, resolved paths, each path, vm.ScanAsync call, end.
   - try/catch -> Log.Exception.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scan folder works. Log shows [LibraryView] OnScanClick -> [LibraryViewModel] ScanAsync
  -> [Scanner] SCAN START -> FILE start/ok per file -> SCAN DONE -> post-scan reload.

## If crash now

Log tail after crash clearly shows:
- last [Scanner] FILE start path=X (but no following add-ok) -> crash on X
- OutOfMemoryException stack -> memory
- AccessViolationException -> native crash