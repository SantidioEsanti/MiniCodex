using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public class PreviewGenerator : IPreviewGenerator
{
    private const string RendererVersion = "0.4.5a13";

    private readonly IPreviewRenderer _renderer;
    private readonly IMeshGeometryLoader _loader;
    private readonly string _cacheDir;
    private readonly PreviewGeneratorOptions _options;

    public PreviewGenerator(
        IPreviewRenderer renderer,
        IMeshGeometryLoader loader,
        string cacheDir,
        PreviewGeneratorOptions? options = null)
    {
        _renderer = renderer;
        _loader = loader;
        _cacheDir = cacheDir;
        _options = options ?? new PreviewGeneratorOptions();
    }

    public async Task<IReadOnlyList<string?>> EnsurePreviewsAsync(
        string modelId,
        string meshPath,
        DateTime sourceUpdatedAt,
        float baseYawDegrees = 0f,
        float basePitchDegrees = 0f,
        bool forceRegenerate = false,
        CancellationToken ct = default)
    {
        return await Task.Run(
            () => GenerateAll(modelId, meshPath, sourceUpdatedAt, baseYawDegrees, basePitchDegrees, forceRegenerate, ct),
            ct);
    }

    private IReadOnlyList<string?> GenerateAll(
        string modelId, string meshPath, DateTime sourceUpdatedAt,
        float baseYaw, float basePitch, bool forceRegenerate, CancellationToken ct)
    {
        var results = new string?[_options.YawDegrees.Length];
        var modelDir = Path.Combine(_cacheDir, modelId);
        Directory.CreateDirectory(modelDir);

        var metaPath = Path.Combine(modelDir, "metadata.json");
        CacheMetadata? meta = null;
        if (File.Exists(metaPath))
        {
            try { meta = JsonSerializer.Deserialize<CacheMetadata>(File.ReadAllText(metaPath)); } catch { }
        }

        var needsRegen =
            forceRegenerate ||
            meta == null ||
            meta.RendererVersion != RendererVersion ||
            meta.SourceUpdatedAt < sourceUpdatedAt ||
            Math.Abs(meta.BaseYaw - baseYaw) > 0.01f ||
            Math.Abs(meta.BasePitch - basePitch) > 0.01f;

        var modelShort = SafeName(meshPath);
        Log.Info("[PreviewGen] START model=" + modelId + " path=" + modelShort + " needsRegen=" + needsRegen + " mem=" + Log.MemoryMb() + "MB");

        MeshGeometry? geometry = null;
        int chosenSS = _options.Supersample;
        try
        {
            if (needsRegen)
            {
                // Load once to know triangle count for adaptive SS.
                var swLoad = Stopwatch.StartNew();
                try { geometry = _loader.LoadGeometry(meshPath); }
                catch (Exception ex)
                {
                    Log.Exception("[PreviewGen] LoadGeometry failed model=" + modelId, ex);
                    geometry = null;
                }
                var triCount = geometry == null ? 0 : geometry.TriangleCount;
                chosenSS = _options.Supersample;
                Log.Info("[PreviewGen] LoadGeometry model=" + modelId +
                         " tris=" + triCount +
                         " took=" + swLoad.ElapsedMilliseconds + "ms" +
                         " chosenSS=" + chosenSS +
                         " mem=" + Log.MemoryMb() + "MB");
            }

            for (int i = 0; i < _options.YawDegrees.Length; i++)
            {
                if (ct.IsCancellationRequested) break;

                var pngPath = Path.Combine(modelDir, ((int)_options.YawDegrees[i]).ToString() + ".png");
                var needThisAngle = needsRegen || !File.Exists(pngPath);

                if (needThisAngle && geometry != null && geometry.TriangleCount > 0)
                {
                    var swRender = Stopwatch.StartNew();
                    try
                    {
                        var yaw = _options.YawDegrees[i] + baseYaw;
                        var pitch = _options.PitchDegrees + basePitch;
                        var png = _renderer.Render(geometry, _options.Width, _options.Height, yaw, pitch, 1.0f, null, chosenSS);
                        File.WriteAllBytes(pngPath, png);
                        Log.Info("[PreviewGen] Render model=" + modelId +
                                 " angle=" + (int)_options.YawDegrees[i] +
                                 " ss=" + chosenSS +
                                 " took=" + swRender.ElapsedMilliseconds + "ms" +
                                 " mem=" + Log.MemoryMb() + "MB");
                    }
                    catch (Exception ex)
                    {
                        Log.Exception("[PreviewGen] Render failed model=" + modelId + " angle=" + i, ex);
                    }
                }

                results[i] = File.Exists(pngPath) ? pngPath : null;
            }
        }
        finally
        {
            geometry = null;
            try { GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false); } catch { }
            Log.Info("[PreviewGen] DONE model=" + modelId + " mem=" + Log.MemoryMb() + "MB");
        }

        if (needsRegen)
        {
            try
            {
                var newMeta = new CacheMetadata
                {
                    ModelId = modelId,
                    SourcePath = meshPath,
                    SourceUpdatedAt = sourceUpdatedAt,
                    GeneratedAt = DateTime.UtcNow,
                    RendererVersion = RendererVersion,
                    BaseYaw = baseYaw,
                    BasePitch = basePitch,
                };
                File.WriteAllText(metaPath, JsonSerializer.Serialize(newMeta, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch (Exception ex)
            {
                Log.Exception("[PreviewGen] write metadata failed model=" + modelId, ex);
            }
        }
        return results;
    }

    private static string SafeName(string filePath)
    {
        try { return Path.GetFileName(filePath) ?? filePath; } catch { return filePath; }
    }

    private class CacheMetadata
    {
        [JsonPropertyName("modelId")] public string ModelId { get; set; } = string.Empty;
        [JsonPropertyName("sourcePath")] public string SourcePath { get; set; } = string.Empty;
        [JsonPropertyName("sourceUpdatedAt")] public DateTime SourceUpdatedAt { get; set; }
        [JsonPropertyName("generatedAt")] public DateTime GeneratedAt { get; set; }
        [JsonPropertyName("rendererVersion")] public string? RendererVersion { get; set; }
        [JsonPropertyName("baseYaw")] public float BaseYaw { get; set; }
        [JsonPropertyName("basePitch")] public float BasePitch { get; set; }
    }
}