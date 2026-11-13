# Patch 0.4.3e.2 - Fix AVLN2000 (StackPanel.Padding)

**Iteration:** 0.4

## Cause
AVLN2000: StackPanel does not have Padding property in Avalonia 11.
My XAML had: <StackPanel Padding="12" Spacing="6"> - invalid.

## Fix
Moved Padding="12" from StackPanel to parent Border.elevated (which does have Padding).

## DoD
- dotnet build: 0 errors (2 pre-existing warnings).
- dotnet test: 48/48.
- Info panel keeps 12px inner padding.