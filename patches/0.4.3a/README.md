# Patch 0.4.3a - Scale UI tab in card

**Iteration:** 0.4

## What it does

- ModelCardPageViewModel: scale fields/commands/methods (full rewrite).
- ModelCardView.axaml: Scale TabItem inserted before Notes.
- lang: Card.Tabs.Scale (en + ru).

## Scale tab

- Prototype type: dropdown any/figure/vehicle/building/ship.
- Scale: dropdown filtered by prototype type.
- Manual: textbox (1:24, 24, 1/24) + Apply button.
- Real prototype height (mm), Model height (mm): editable, bidirectional auto-calc.
- Save via top button persists RealHeightMm / ModelHeightMm / ScaleRatio.
- Load on open: parses ScaleRatio (matches preset or manual).

## DoD

- dotnet build: 0 errors (2 warnings pre-existing).
- dotnet test: 48/48.
- Open card -> Scale tab.
- Type 1800 in Real with scale 1:24 -> Model becomes 75.
- Type 75 in Model with scale 1:24 -> Real becomes 1800.
- Save -> reopen card -> values preserved.
- Switch prototype type -> dropdown filters.
- Manual 1:35 + Apply -> scale used for calc, label "Applied: 1:35".