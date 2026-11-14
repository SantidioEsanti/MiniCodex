$ErrorActionPreference = "Stop"
$ver = "0.5.1a1"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Spatial deduplication (Mesh Normal Smoother)"

$files = @(
    "$root\src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Create MeshNormalSmoother.cs
$smootherPath = "$root\src\MiniCodex.Render\Rendering\MeshNormalSmoother.cs"
$smootherCode = @"
using System;
using System.Collections.Generic;
using System.Numerics;
using MiniCodex.Core.Models;

namespace MiniCodex.Render.Rendering;

public static class MeshNormalSmoother
{
    public static void Smooth(MeshGeometry geometry, int minTriangles = 500_000, float precision = 1e-3f)
    {
        if (geometry == null || geometry.Vertices.Length == 0 || geometry.Indices.Length == 0) return;
        if (geometry.TriangleCount < minTriangles) return;

        var vertices = geometry.Vertices;
        var indices = geometry.Indices;
        var normals = geometry.VertexNormals;

        // Spatial hash map: rounded coordinates -> accumulated normal
        var spatialMap = new Dictionary<(int, int, int), Vector3>(vertices.Length);

        for (int i = 0; i < indices.Length; i += 3)
        {
            int i0 = indices[i];
            int i1 = indices[i + 1];
            int i2 = indices[i + 2];

            var v0 = vertices[i0];
            var v1 = vertices[i1];
            var v2 = vertices[i2];

            var faceNormal = Vector3.Cross(v1 - v0, v2 - v0);
            if (faceNormal.LengthSquared() > 1e-12f)
            {
                var key0 = GetKey(v0, precision);
                var key1 = GetKey(v1, precision);
                var key2 = GetKey(v2, precision);

                spatialMap[key0] = spatialMap.TryGetValue(key0, out var n0) ? n0 + faceNormal : faceNormal;
                spatialMap[key1] = spatialMap.TryGetValue(key1, out var n1) ? n1 + faceNormal : faceNormal;
                spatialMap[key2] = spatialMap.TryGetValue(key2, out var n2) ? n2 + faceNormal : faceNormal;
            }
        }

        for (int i = 0; i < vertices.Length; i++)
        {
            var key = GetKey(vertices[i], precision);
            if (spatialMap.TryGetValue(key, out var normal))
            {
                if (normal.LengthSquared() > 1e-12f)
                {
                    normals[i] = Vector3.Normalize(normal);
                }
            }
        }
    }

    private static (int, int, int) GetKey(Vector3 v, float precision)
    {
        return (
            (int)MathF.Round(v.X / precision),
            (int)MathF.Round(v.Y / precision),
            (int)MathF.Round(v.Z / precision)
        );
    }
}
"@
[IO.File]::WriteAllText($smootherPath, $smootherCode, [Text.Encoding]::UTF8)
Log "Created MeshNormalSmoother.cs"

# 2. Modify AssimpMeshLoader.cs
$loaderPath = "$root\src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs"
$loaderContent = [IO.File]::ReadAllText($loaderPath)

if ($loaderContent -notmatch "MeshNormalSmoother") {
    # Add using directive
    $loaderContent = $loaderContent -replace 'using MiniCodex.Core.Services;', "using MiniCodex.Core.Services;`nusing MiniCodex.Render.Rendering;"

    # Insert call after MeshGeometry result creation
    $target = @"
            var result = new MeshGeometry
            {
                Vertices = allVerts.ToArray(),
                VertexNormals = allNormals.ToArray(),
                Indices = allIndices.ToArray(),
            };
"@
    $replacement = @"
            var result = new MeshGeometry
            {
                Vertices = allVerts.ToArray(),
                VertexNormals = allNormals.ToArray(),
                Indices = allIndices.ToArray(),
            };

            MeshNormalSmoother.Smooth(result);
"@
    $loaderContent = $loaderContent -replace [regex]::Escape($target), $replacement
    [IO.File]::WriteAllText($loaderPath, $loaderContent)
    Log "Updated AssimpMeshLoader.cs to use MeshNormalSmoother."
}

# 3. Create MeshNormalSmootherTests.cs
$testPath = "$root\src\MiniCodex.Tests\MeshNormalSmootherTests.cs"
$testCode = @"
using System;
using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Render.Rendering;
using Xunit;

namespace MiniCodex.Tests;

public class MeshNormalSmootherTests
{
    [Fact]
    public void Smooth_AveragesNormalsForWeldedVertices()
    {
        var geometry = new MeshGeometry
        {
            Vertices = new[]
            {
                new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(0, 1, 0),
                new Vector3(1, 0, 0), new Vector3(1, 1, 0), new Vector3(0, 1, 0)
            },
            VertexNormals = new[]
            {
                new Vector3(0, 0, 1), new Vector3(0, 0, 1), new Vector3(0, 0, 1),
                new Vector3(0, 0, 2), new Vector3(0, 0, 2), new Vector3(0, 0, 2)
            },
            Indices = new[] { 0, 1, 2, 3, 4, 5 }
        };

        MeshNormalSmoother.Smooth(geometry, minTriangles: 2);

        foreach (var n in geometry.VertexNormals)
        {
            Assert.Equal(0f, n.X);
            Assert.Equal(0f, n.Y);
            Assert.Equal(1f, n.Z);
        }
    }

    [Fact]
    public void Smooth_DoesNotAffectLowPolyWhenGateEnabled()
    {
        var geometry = new MeshGeometry
        {
            Vertices = new[] { new Vector3(0,0,0), new Vector3(1,0,0), new Vector3(0,1,0) },
            VertexNormals = new[] { new Vector3(0,0,1), new Vector3(0,0,1), new Vector3(0,0,1) },
            Indices = new[] { 0, 1, 2 }
        };

        MeshNormalSmoother.Smooth(geometry, minTriangles: 500_000);

        Assert.Equal(new Vector3(0,0,1), geometry.VertexNormals[0]);
    }
}
"@
[IO.File]::WriteAllText($testPath, $testCode, [Text.Encoding]::UTF8)
Log "Created MeshNormalSmootherTests.cs"

# 4. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## 0.5.1a1
- Render: Added spatial deduplication (MeshNormalSmoother) for high-poly models (>500K tris) to fix layer-line artifacts on 3D-scanned STL files.
- Tests: Added unit tests for MeshNormalSmoother.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."