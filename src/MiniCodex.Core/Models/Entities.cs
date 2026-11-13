namespace MiniCodex.Core.Models;

public class Model
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Title { get; set; } = string.Empty;
    public string? Author { get; set; }
    public string? SourceUrl { get; set; }
    public string? ModelType { get; set; }
    public string? PrimaryModelFileId { get; set; }
    public string? Status { get; set; }
    public int? Difficulty { get; set; }
    public double? RealHeightMm { get; set; }
    public double? ModelHeightMm { get; set; }
    public string? ScaleRatio { get; set; }
    public string? Notes { get; set; }
    public string? OrientationJson { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class ModelFile
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ModelId { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public string? FileRole { get; set; }
    public string? PartName { get; set; }
    public long? FileSizeBytes { get; set; }
    public int? PolygonCount { get; set; }
    public DateTime? LastWriteTimeUtc { get; set; }
}

public class Asset
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ModelId { get; set; } = string.Empty;
    public string? AssetType { get; set; }
    public string AbsolutePath { get; set; } = string.Empty;
    public string? ThumbnailPath { get; set; }
    public int SortOrder { get; set; }
    public string? StorageMode { get; set; }
}

public class Tag
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? ParentId { get; set; }
    public string? Color { get; set; }
}

public class Collection
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string? FilterQuery { get; set; }
    public bool IsSmart { get; set; } = true;
}