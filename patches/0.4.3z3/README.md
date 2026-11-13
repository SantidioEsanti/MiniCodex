# Patch 0.4.3z3 - Fix missing lang keys, About screen, version bump

**Iteration:** 0.4

## What it does

1. Fix bug: Card.Scale.InvalidManual and Card.Scale.AppliedFormat were used in code but missing from lang/*.json
   (seen as raw key on Scale tab). Added to both en.json and ru.json.

2. About screen:
   - New AboutViewModel + AboutView.axaml(.cs).
   - App name, tagline, version (from AssemblyInformationalVersion), Author, MIT License.
   - Buttons: GitHub (https://github.com/SantidioEsanti), Support the author (https://boosty.to/santidioesanti).
   - Copyright 2026 Santidio Esanti.

3. Version bump:
   - MiniCodex.App.csproj: Version=0.1.0, AssemblyVersion=0.1.0.0, FileVersion=0.1.0.0, InformationalVersion=0.1.0-alpha.

4. Wiring:
   - MainWindowViewModel: ShowAboutCommand, AboutButtonText.
   - MainWindow.axaml: About button next to Library / Settings.
   - App.axaml: DataTemplate for AboutViewModel.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- Scale tab: no more raw keys (Invalid scale format / Applied: 1:35).
- About button works, shows version 0.1.0-alpha, GitHub / Boosty buttons open browser.