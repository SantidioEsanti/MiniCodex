# Patch 0.4.3d - Card view layout restructure

**Iteration:** 0.4

## What it does

- ModelCardView.axaml (full rewrite):
  - Left column (480px): ThreeDViewer (fixed 320px height) + Info panel below (Title, Author, SourceURL, Status, Difficulty - editable fields).
  - Right column: TabControl (Files, Associations, Tags, Scale, Notes) - Info tab removed.
  - Default tab: Associations (index 1).
  - All major panels wrapped in Border.elevated (rounded + soft shadow).
  - Drop zone in Associations: removed hard border, only background.
- ModelCardPageViewModel.cs (one line):
  - _selectedTabIndex = 1 (Associations default after Info moved to left panel).
- App.axaml (one style added):
  - Border.elevated: CardBackgroundBrush + CornerRadius 8 + BoxShadow + ClipToBounds.

## Deferred

- 0.4.3e: Status as clickable buttons, Difficulty as 5 stars.
- 0.4.3f: Associations two-column (Reference / Photo with separate drop zones).

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Open card: left column has square 3D viewer (320px) with Info panel below.
- Right column: tabs without Info.
- Default tab: Associations.
- All panels (viewer, info, tabs) have rounded corners and soft shadow.
- Library tiles still have rounded corners with shadow (0.4.3c).