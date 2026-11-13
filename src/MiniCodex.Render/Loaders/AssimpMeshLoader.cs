using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using Assimp;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader, IMeshGeometryLoader
{
    private static readonly HashSet<string> _extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] Load null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
            var polygonCount = 0;
            var min = new Vector3D(float.MaxValue, float.MaxValue, float.MaxValue);
            var max = new Vector3D(float.MinValue, float.MinValue, float.MinValue);
            var hasVertices = false;

            foreach (var mesh in scene.Meshes)
            {
                polygonCount += mesh.FaceCount;
                foreach (var v in mesh.Vertices)
                {
                    hasVertices = true;
                    if (v.X < min.X) min.X = v.X;
                    if (v.Y < min.Y) min.Y = v.Y;
                    if (v.Z < min.Z) min.Z = v.Z;
                    if (v.X > max.X) max.X = v.X;
                    if (v.Y > max.Y) max.Y = v.Y;
                    if (v.Z > max.Z) max.Z = v.Z;
                }
            }

            if (!hasVertices) return null;

            Log.Info("[Assimp] Load ok path=" + SafeName(filePath) + " polys=" + polygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return new MeshInfo
            {
                PolygonCount = polygonCount,
                FileSizeBytes = new FileInfo(filePath).Length,
                BoundingBoxMin = new[] { min.X, min.Y, min.Z },
                BoundingBoxMax = new[] { max.X, max.Y, max.Z },
            };
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] Load failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    public MeshGeometry? LoadGeometry(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] LoadGeometry null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
            var allVerts = new List<Vector3>();
            var allNormals = new List<Vector3>();
            var allIndices = new List<int>();
            var hasAnyNormals = true;

            foreach (var mesh in scene.Meshes)
            {
                var offset = allVerts.Count;
                var meshHasNormals = mesh.Normals != null && mesh.Normals.Count == mesh.VertexCount && mesh.VertexCount > 0;

                if (meshHasNormals)
                {
                    for (int i = 0; i < mesh.VertexCount; i++)
                    {
                        var v = mesh.Vertices[i];
                        var n = mesh.Normals![i];
                        allVerts.Add(new Vector3(v.X, v.Y, v.Z));
                        allNormals.Add(new Vector3(n.X, n.Y, n.Z));
                    }
                }
                else
                {
                    hasAnyNormals = false;
                    for (int i = 0; i < mesh.VertexCount; i++)
                    {
                        var v = mesh.Vertices[i];
                        allVerts.Add(new Vector3(v.X, v.Y, v.Z));
                        allNormals.Add(Vector3.Zero);
                    }
                }

                // Faces -> triangles
                foreach (var face in mesh.Faces)
                {
                    if (face.IndexCount < 3) continue;
                    for (int i = 1; i < face.IndexCount - 1; i++)
                    {
                        var ia = offset + face.Indices[0];
                        var ib = offset + face.Indices[i];
                        var ic = offset + face.Indices[i + 1];
                        allIndices.Add(ia);
                        allIndices.Add(ib);
                        allIndices.Add(ic);

                        // If no normals from file, compute from this triangle.
                        if (!meshHasNormals)
                        {
                            var a = allVerts[ia];
                            var b = allVerts[ib];
                            var c = allVerts[ic];
                            var fn = Vector3.Cross(b - a, c - a);
                            if (fn.LengthSquared() > 1e-12f) fn = Vector3.Normalize(fn);
                            allNormals[ia] += fn;
                            allNormals[ib] += fn;
                            allNormals[ic] += fn;
                        }
                    }
                }
            }

            if (allVerts.Count == 0 || allIndices.Count == 0) return null;

            // Fallback path: normalize accumulated normals (per-vertex averaged).
            if (!hasAnyNormals)
            {
                for (int i = 0; i < allNormals.Count; i++)
                {
                    var n = allNormals[i];
                    if (n.LengthSquared() > 1e-12f) allNormals[i] = Vector3.Normalize(n);
                    else allNormals[i] = Vector3.UnitZ;
                }
            }

            var result = new MeshGeometry
            {
                Vertices = allVerts.ToArray(),
                VertexNormals = allNormals.ToArray(),
                Indices = allIndices.ToArray(),
            };
            Log.Info("[Assimp] LoadGeometry ok path=" + SafeName(filePath) +
                     " tris=" + result.TriangleCount +
                     " verts=" + result.Vertices.Length +
                     " hasFileNormals=" + hasAnyNormals +
                     " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return result;
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] LoadGeometry failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    private static Scene? ImportScene(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;
        var sw = Stopwatch.StartNew();
        try
        {
            using (var ctx = new AssimpContext())
            {
                var scene = ctx.ImportFile(filePath, PostProcessSteps.Triangulate);
                Log.Info("[Assimp] ImportFile path=" + SafeName(filePath) + " ok=" + (scene != null) + " meshes=" + (scene != null && scene.HasMeshes ? scene.MeshCount : 0) + " took=" + sw.ElapsedMilliseconds + "ms");
                return scene != null && scene.HasMeshes ? scene : null;
            }
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] ImportFile failed path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms", ex);
            return null;
        }
    }

    private static string SafeName(string filePath)
    {
        try { return Path.GetFileName(filePath) ?? filePath; } catch { return filePath; }
    }
}