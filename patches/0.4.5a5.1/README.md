# Patch 0.4.5a5.1 - Fix StubRenderer signature

**Iteration:** 0.4.5

## Cause
0.4.5a5 added `int supersample = 2` to IPreviewRenderer.Render.
StubRenderer in PreviewGeneratorTests.cs still implemented the old signature (CS0535).

## Fix
Add `RenderStyle? style = null, int supersample = 2` to StubRenderer.Render.

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.