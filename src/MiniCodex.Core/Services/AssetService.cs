using System.Security.Cryptography;
using MiniCodex.Core.Models;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class AssetService : IAssetService
{
    private static readonly string[] ImageExtensions = { ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp" };
    private static readonly string[] AutoLinkExtensions = { ".png", ".jpg", ".jpeg", ".webp", ".pdf" };

    private readonly IAssetRepository _assets;
    private readonly IModelFileRepository _files;
    private readonly IAssetThumbnailGenerator _thumbs;
    private readonly string _assetsRoot;
    private readonly string _thumbsRoot;

    public AssetService(
        IAssetRepository assets,
        IModelFileRepository files,
        IAssetThumbnailGenerator thumbs,
        string assetsRoot,
        string thumbsRoot)
    {
        _assets = assets;
        _files = files;
        _thumbs = thumbs;
        _assetsRoot = assetsRoot;
        _thumbsRoot = thumbsRoot;
    }

    public async Task<Asset> ImportAsync(string modelId, string sourcePath, string assetType, CancellationToken ct = default)
    {
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("Asset source not found", sourcePath);

        var modelDir = Path.Combine(_assetsRoot, modelId);
        Directory.CreateDirectory(modelDir);

        var origName = Path.GetFileName(sourcePath);
        var ext = Path.GetExtension(sourcePath);
        var baseName = Path.GetFileNameWithoutExtension(sourcePath);
        var hex = Convert.ToHexString(RandomNumberGenerator.GetBytes(4)).ToLowerInvariant();
        var destPath = Path.Combine(modelDir, $"{hex}_{baseName}{ext}");

        // Dedup: if an asset with the same original basename already exists for this model,
        // return it instead of importing a duplicate. No schema change required.
        var existing = await _assets.GetByModelAsync(modelId, ct);
        var origBase = Path.GetFileNameWithoutExtension(sourcePath);
        foreach (var a in existing)
        {
            var aName = Path.GetFileNameWithoutExtension(a.AbsolutePath);
            if (string.Equals(aName, origBase, StringComparison.OrdinalIgnoreCase)
                || aName.EndsWith("_" + origBase, StringComparison.OrdinalIgnoreCase))
            {
                Log.Info("[AssetService] dedup hit: " + sourcePath + " -> existing " + a.Id);
                return a;
            }
        }

        File.Copy(sourcePath, destPath, overwrite: false);

        var asset = new Asset
        {
            ModelId = modelId,
            AssetType = assetType,
            AbsolutePath = destPath,
            StorageMode = "hybrid",
            SortOrder = (int)(DateTime.UtcNow.Ticks % int.MaxValue),
        };
        await _assets.UpsertAsync(asset, ct);
        return asset;
    }

    public async Task RemoveFromCardAsync(string assetId, CancellationToken ct = default)
    {
        await _assets.DeleteAsync(assetId, ct);
        // Файл на диске НЕ удаляем — решение MVP (см. docs/ROADMAP.md, раздел 0).
    }

    public async Task<IReadOnlyList<Asset>> AutoLinkAsync(string modelId, CancellationToken ct = default)
    {
        var files = await _files.GetByModelAsync(modelId, ct);
        var primary = files.FirstOrDefault(f => f.FileRole == "main") ?? files.FirstOrDefault();
        if (primary == null) return Array.Empty<Asset>();

        var dir = Path.GetDirectoryName(primary.Path);
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return Array.Empty<Asset>();

        var baseName = Path.GetFileNameWithoutExtension(primary.Path);
        var existing = await _assets.GetByModelAsync(modelId, ct);
        var existingSourceNames = new HashSet<string>(
            existing.Select(a => Path.GetFileName(a.AbsolutePath)).Where(n => n != null)!.Cast<string>(),
            StringComparer.OrdinalIgnoreCase);

        var imported = new List<Asset>();
        foreach (var candidate in Directory.EnumerateFiles(dir, baseName + "_*"))
        {
            var ext = Path.GetExtension(candidate).ToLowerInvariant();
            if (!AutoLinkExtensions.Contains(ext)) continue;

            // Пропускаем, если файл уже привязан (по basename после 8hex_)
            var candidateName = Path.GetFileNameWithoutExtension(candidate);
            if (existingSourceNames.Any(n => n.EndsWith("_" + candidateName + ext, StringComparison.OrdinalIgnoreCase)))
                continue;

            try
            {
                var asset = await ImportAsync(modelId, candidate, "reference", ct);
                imported.Add(asset);
            }
            catch { /* пропускаем битые */ }
        }
        return imported;
    }

    public async Task<string?> EnsureThumbnailAsync(Asset asset, CancellationToken ct = default)
    {
        Directory.CreateDirectory(_thumbsRoot);
        var thumbPath = Path.Combine(_thumbsRoot, asset.Id + "_256.png");
        if (File.Exists(thumbPath)) return thumbPath;

        try
        {
            var type = asset.AssetType ?? "reference";
            var bytes = await Task.Run(() => _thumbs.Generate(asset.AbsolutePath, type, 256), ct);
            await File.WriteAllBytesAsync(thumbPath, bytes, ct);
            return thumbPath;
        }
        catch { return null; }
    }
}