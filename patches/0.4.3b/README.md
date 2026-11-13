# Patch 0.4.3b - Global styles

**Iteration:** 0.4

## What it does

- Program.cs: .WithInterFont() (Avalonia.Fonts.Inter package already referenced).
- App.axaml: ThemeDictionaries override SystemAccentColor (+6 shades) and SystemAccentColorBrush to amber #E67E22.
- App.axaml: CardBackgroundBrush (White light / #252525 dark) - prepared for 0.4.3c.
- App.axaml styles:
  - Window: FontFamily = "Inter, Segoe UI".
  - Button / TextBox / ComboBox: CornerRadius=6.
  - TextBox: SelectionBrush = amber, SelectionForegroundBrush = white.
  - ListBoxItem:selected and ComboBoxItem:selected: amber background (explicit backup).
- No C# logic changes.

## DoD

- dotnet build: 0 errors.
- dotnet test: 48/48.
- All buttons/textboxes/comboboxes have rounded corners.
- Font in main window is Inter (or Segoe UI if Inter failed to load).
- Sidebar tag selection is amber (not blue).
- Tab underline, focus rings, checkboxes, sliders, radio buttons - all amber.
- Text selection in textboxes is amber.