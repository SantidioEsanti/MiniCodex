# Patch 0.5.0a5 - Fix Theme-aware design tokens

## What
Moves custom UI colors (AppBackgroundBrush, CardBackgroundBrush, etc.) from the root dictionary into Light and Dark ThemeDictionaries.

## Why
To fix the broken dark theme where white text was rendered on hardcoded white backgrounds.

## Files affected
- src/MiniCodex.App/App.axaml
- CHANGELOG.md