namespace MiniCodex.Core.Services;

/// <summary>Render parameters. Colors are ARGB (0xAARRGGBB).</summary>
public record RenderStyle
{
    public uint BackgroundArgb { get; init; } = 0xFFE0E0E0;
    public uint ModelArgb { get; init; } = 0xFFFFFFFF;
    public float MinLambert { get; init; } = 0.45f;
    public bool Wireframe { get; init; }
}