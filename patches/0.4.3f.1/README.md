# Patch 0.4.3f.1 - Fix AVLN2000 (DragOver/Drop attached events)

**Iteration:** 0.4

## Cause
In Avalonia 11 DragOver and Drop are attached events on DragDrop class.
XAML: DragOver="OnDragOver" Drop="OnDrop..." -> AVLN2000.
Fix: DragDrop.DragOver="OnDragOver" DragDrop.Drop="OnDrop...".

## DoD
- dotnet build: 0 errors (2 pre-existing warnings).
- dotnet test: 48/48.
- Both drop zones (Reference / Photo) accept drag-and-drop.