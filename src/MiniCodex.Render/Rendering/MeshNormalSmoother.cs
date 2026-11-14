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