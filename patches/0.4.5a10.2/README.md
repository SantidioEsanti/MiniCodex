# Patch 0.4.5a10.2 - Fix CS1061 Mesh.NormalCount

**Iteration:** 0.4.5

## Cause

AssimpNet 4.1.0 (the NuGet we use) does not expose Mesh.NormalCount.
Mesh.Normals is List<Vector3D>, so use .Count. Same for Mesh.Vertices.

0.4.5a10 used:
  mesh.NormalCount == mesh.VertexCount

Correct form:
  mesh.Normals != null && mesh.Normals.Count == mesh.VertexCount

## Fix

Replace NormalCount reference with Normals.Count and add null check.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48.