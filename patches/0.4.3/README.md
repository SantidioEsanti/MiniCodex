# Patch 0.4.3 - ScaleCatalog (Core) + tests

**Iteration:** 0.4

## What it does

- Core/Models/ScalePreset.cs: record (Category, Label, Denominator).
- Core/Services/ScaleCatalog.cs:
  - All: 43 presets (7 categories: figure, vehicle, aviation, armor, naval, railway, architecture) - per HANDOFF section 8.1.
  - ForPrototype(type): filter by prototype type (figure / vehicle / building / ship / any) - per HANDOFF section 8.2.
  - ParseManual(input): "1:24" / "24" / "1/24" / "1:35.5" -> denominator; invalid / <=0 -> null.
  - CalculateModelHeightMm(protoMm, denom) = protoMm / denom.
  - CalculatePrototypeHeightMm(modelMm, denom) = modelMm * denom.
- Tests/Services/ScaleCatalogTests.cs: 8 tests (categories, filtering, parsing, math).

## No UI

UI (Scale tab in card) comes in 0.4.3a.
No changes to existing files.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48 (40 + 8 new).