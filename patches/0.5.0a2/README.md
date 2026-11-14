# Patch 0.5.0a2 - Apply Soft Glass tokens to Cards (v2)

## What
Replaces hardcoded visual properties in ModelCardTile.axaml with the dynamic resources introduced in 0.5.0a1. Targets only the first Border element.

## Why
To achieve the soft, floating card look without breaking nested property elements (like Border.Background).

## Files affected
- src/MiniCodex.App/Views/ModelCardTile.axaml
- CHANGELOG.md