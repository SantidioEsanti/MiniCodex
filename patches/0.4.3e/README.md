# Patch 0.4.3e - Status as 3 icon buttons, Difficulty as 5 stars

**Iteration:** 0.4

## What it does

- ModelCardPageViewModel:
  - _difficultyValue (int), DifficultyValue property.
  - IsPlanned/IsPrinted/IsPainted (bool) - for Classes.statusActive binding.
  - Star1Glyph..Star5Glyph - filled/empty star Unicode glyphs.
  - SetStatusCommand / SetDifficultyCommand.
  - SetDifficulty: click same value -> toggle to 0.
  - Save uses _difficultyValue (int).
  - Load initializes _difficultyValue from Model.Difficulty.
- ModelCardView.axaml:
  - Status: 3 icon buttons (Clock / Print / CheckMark) via Segoe Fluent Icons.
  - Difficulty: 5 clickable stars, amber.
- App.axaml:
  - Style Button.statusActive: amber background, white foreground.
  - Style Button.star: transparent bg, no border.
  - Style Button.star:pointerover: light amber hover.

## Notes

- Status and Difficulty changes are LOCAL until user clicks Save.
- If highlighting (Classes.statusActive) does not work on some Avalonia version,
  fix in follow-up patch.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- Card Info panel: Status = 3 icon buttons, Difficulty = 5 stars.
- Click status icon -> highlights amber.
- Click star N -> first N stars filled, rest empty.
- Click same star again -> clears to 0.
- Save -> reopen -> values preserved.