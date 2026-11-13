# Patch 0.4.5a13.1 - Fix compile errors

**Iteration:** 0.4.5

## Cause

1. CS0103: ModelCardPageViewModel uses Log.Exception in ScheduleSave/DebouncedSaveAsync,
   but no `using MiniCodex.Core.Logging;` was added.

2. CS8602 (warning): AssimpMeshLoader line ~99 `mesh.Normals[i]` - compiler cannot prove
   non-null even though meshHasNormals guarantees it.

## Fix

1. Add `using MiniCodex.Core.Logging;` to ModelCardPageViewModel.cs.
2. Use null-forgiving operator: `mesh.Normals![i]`.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.