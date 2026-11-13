# Patch 0.4.5a12 - Smooth rotation + scan warning + theme icon

**Iteration:** 0.4.5

## What it does

1. YawDegrees: { 180, 270, 0, 90 } -> { 180, 220, 260, 300 }.
   Hover rotation in library now spans 120deg instead of 270deg.
   Smoother transitions between the 4 preview angles, still shows different sides.

2. First-scan warning (overlay dialog):
   - Setting "Scan.WarningShown" tracks if user has seen warning.
   - First scan -> ShowScanWarning=true -> overlay with title/message/buttons.
   - Continue -> saves "Scan.WarningShown"="true", runs DoScanAsync.
   - Cancel -> dismisses, no scan.
   - Subsequent scans go directly to DoScanAsync.

3. Theme ComboBox replaced with icon button:
   - Single button in top toolbar.
   - Click cycles: auto -> light -> dark -> auto.
   - Icon (Segoe Fluent Icons): light=Sun E706, dark=Moon E708, auto=Contrast E7F4.
   - Tooltip: current theme name (from existing Settings.Theme.* keys).

4. RendererVersion 0.4.5a12 (angles changed -> regen needed).

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.
- First run after patch: click Scan -> warning overlay appears. Cancel dismisses. Click Scan again -> warning again (until user clicks Continue at least once). After Continue once -> subsequent scans go directly.
- Hover rotation in library: smoother angle steps (40deg apart, not 90deg).
- Top toolbar: no theme ComboBox, icon button with sun/moon/contrast glyph. Click cycles.