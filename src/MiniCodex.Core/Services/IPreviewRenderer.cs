using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IPreviewRenderer
{
    /// <summary>
    /// Render mesh to PNG bytes. supersample=2 renders at 2x internal resolution
    /// and downsamples, fixing sub-pixel triangle coverage at high polygon counts.
    /// </summary>
    byte[] Render(MeshGeometry mesh, int width, int height,
        float yawDegrees, float pitchDegrees, float zoom = 1.0f,
        RenderStyle? style = null, int supersample = 2);
}