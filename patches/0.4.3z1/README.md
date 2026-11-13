# Patch 0.4.3z1 - Cleanup warnings + image clip

**Iteration:** 0.4

## What it does

1. ThreeDViewer.axaml.cs: removed unused _suppressPropSync field + try/finally.
2. AppServices.cs: OS guard for WindowsRegistryProbe (CA1416).
   Added NoopIntegrationProbe for non-Windows.
3. ModelCardView.axaml: Image inside item tile wrapped in inner Border (CornerRadius 6, ClipToBounds)
   so thumbnails clip to rounded corners of the outer tile.

## DoD
- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Reference / Photo tiles have rounded image corners.