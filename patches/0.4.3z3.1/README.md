# Patch 0.4.3z3.1 - Fix CS1501 in AboutViewModel

**Iteration:** 0.4

## Cause
App.Loc.Get(string key) takes one argument. AboutViewModel used App.Loc?.Get("key", "fallback")
(two arguments) - 7 x CS1501.

## Fix
Replace App.Loc?.Get("X", "fallback") with App.Loc?.Get("X") ?? "fallback".

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- About screen works.