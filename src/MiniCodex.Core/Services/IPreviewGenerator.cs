namespace MiniCodex.Core.Services;

public interface IPreviewGenerator
{
    /// <summary>
    /// Guarantees 4 PNG previews for the model.
    /// baseYawDegrees / basePitchDegrees are ADDITIVE offsets on top of standard angles
    /// (default 180, 270, 0, 90 yaw and 15 pitch). forceRegenerate bypasses the cache check.
    /// </summary>
    Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        float baseYawDegrees = 0f,
        float basePitchDegrees = 0f,
        bool forceRegenerate = false,
        CancellationToken ct = default);
}