using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface IAssetService
{
    /// <summary>
    /// Копирует файл в assets/{modelId}/{8hex}_{origName}{ext}, создаёт запись Asset.
    /// </summary>
    Task<Asset> ImportAsync(string modelId, string sourcePath, string assetType, CancellationToken ct = default);

    /// <summary>
    /// Удаляет запись Asset из БД. Файл на диске НЕ удаляется (решение MVP).
    /// </summary>
    Task RemoveFromCardAsync(string assetId, CancellationToken ct = default);

    /// <summary>
    /// Ищет рядом с primary-файлом модели файлы {basename}_*.{png,jpg,jpeg,webp,pdf}
    /// и импортирует ещё не привязанные как reference.
    /// </summary>
    Task<IReadOnlyList<Asset>> AutoLinkAsync(string modelId, CancellationToken ct = default);

    /// <summary>
    /// Возвращает путь к миниатюре (создаёт при необходимости). null — если не удалось.
    /// </summary>
    Task<string?> EnsureThumbnailAsync(Asset asset, CancellationToken ct = default);
}