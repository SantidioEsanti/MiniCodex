namespace MiniCodex.Core.Services;

public interface IAssetThumbnailGenerator
{
    /// <summary>
    /// Возвращает PNG-байты миниатюры (квадрат maxSize×maxSize) для sourcePath.
    /// Если файл не изображение — генерирует заглушку с буквой типа.
    /// </summary>
    byte[] Generate(string sourcePath, string assetType, int maxSize);
}