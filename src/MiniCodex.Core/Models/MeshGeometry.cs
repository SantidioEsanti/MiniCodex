using System.Numerics;

namespace MiniCodex.Core.Models;

public class MeshGeometry
{
    public Vector3[] Vertices { get; set; } = Array.Empty<Vector3>();
    public Vector3[] VertexNormals { get; set; } = Array.Empty<Vector3>();
    public int[] Indices { get; set; } = Array.Empty<int>();
    public int TriangleCount => Indices.Length / 3;
    public bool HasVertexNormals => VertexNormals.Length == Vertices.Length;
}