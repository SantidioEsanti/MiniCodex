# Patch 0.4.3c - Card shadow, distinct background, double-click

**Iteration:** 0.4

## What it does

- App.axaml: WindowBackgroundBrush (Light #F2F2F2, Dark #1A1A1A); Window.Background uses it.
- App.axaml: Border.card style - soft BoxShadow (0 2 8 #18000000), CardBackgroundBrush, CornerRadius 8, transition.
- App.axaml: Border.card:pointerover - enhanced BoxShadow (0 4 16 #30000000).
- ModelCardTile.axaml: removed BorderBrush / BorderThickness; Classes="card"; no inline Background/CornerRadius.
- ModelCardTile.axaml.cs: DoubleTapped -> OpenCommand.Execute (returns navigation lost in 0.4.1).
- No logic changes.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Cards have no hard grey border, only soft shadow.
- Light theme: window grey #F2F2F2, cards white. Dark: window #1A1A1A, cards #252525.
- Hover on card: shadow grows smoothly.
- Double-click on card preview: opens model card.
- Single click does nothing (except context menu / "...").