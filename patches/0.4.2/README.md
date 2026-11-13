# Patch 0.4.2 - Model orientation (save/load in card)

**Iteration:** 0.4

## What it does

- Migration 3: Model.orientation_json column.
- Model.OrientationJson - {yaw, pitch} as JSON.
- ThreeDViewer.Yaw / ThreeDViewer.Pitch - TwoWay bindable properties (updated on drag).
- ModelCardPageViewModel: ViewerYaw/ViewerPitch, LoadOrientation on open, SaveOrientationCommand, ResetOrientationCommand, OrientationStatusText.
- ModelCardView: "Reset" and "Save orientation" buttons in top row.
- lang/ru.json: 3 new keys (Card.Actions.ResetOrientation, Card.Actions.SaveOrientation, Card.Orientation.Saved).

## Deferred to 0.4.2a

- "Regenerate previews" button.
- PreviewGenerator taking baseYaw/basePitch.
- Library tiles using stored orientation for previews.

## DoD

- dotnet build: 0 errors.
- dotnet test: 40/40 (migration 3 not covered by tests, but LatestSchemaVersion test passes).
- Open card, rotate model, click "Save orientation" -> badge "Orientation saved".
- Close card, reopen -> viewer starts with the saved yaw/pitch.
- Click "Reset" -> viewer goes back to default (180/15).