namespace MiniCodex.Core.Models;

public class MeshInfo
{
    public int PolygonCount { get; set; }
    public long FileSizeBytes { get; set; }
    public float[] BoundingBoxMin { get; set; } = Array.Empty<float>();
    public float[] BoundingBoxMax { get; set; } = Array.Empty<float>();

    public float SizeX => BoundingBoxMax.Length > 0 ? BoundingBoxMax[0] - BoundingBoxMin[0] : 0;
    public float SizeY => BoundingBoxMax.Length > 1 ? BoundingBoxMax[1] - BoundingBoxMin[1] : 0;
    public float SizeZ => BoundingBoxMax.Length > 2 ? BoundingBoxMax[2] - BoundingBoxMin[2] : 0;
}