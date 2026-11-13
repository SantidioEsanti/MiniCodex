# Patch 0.4.5a10.1 - Fix CS1061

**Iteration:** 0.4.5

## Cause

0.4.5a10 removed `BaseSupersample` from PreviewGeneratorOptions
(replaced with fixed `Supersample = 2`), but one reference remained in
PreviewGenerator.cs: `int chosenSS = _options.BaseSupersample;` -> CS1061.

## Fix

Replace `_options.BaseSupersample` with `_options.Supersample`
(+ defensive regex for any leftover `PickSupersample` calls).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.