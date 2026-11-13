using MiniCodex.Core.Services;
using SkiaSharp;

namespace MiniCodex.Render.Rendering;

public class SkiaThumbnailGenerator : IAssetThumbnailGenerator
{
    public byte[] Generate(string sourcePath, string assetType, int maxSize)
    {
        try
        {
            var ext = Path.GetExtension(sourcePath).ToLowerInvariant();
            var isImage = ext == ".png" || ext == ".jpg" || ext == ".jpeg" ||
                          ext == ".webp" || ext == ".gif" || ext == ".bmp";
            if (isImage)
            {
                using var src = SKBitmap.Decode(sourcePath);
                if (src != null)
                    return ResizeToPng(src, maxSize);
            }
        }
        catch { /* fall through to placeholder */ }
        return Placeholder(assetType, maxSize);
    }

    private static byte[] ResizeToPng(SKBitmap src, int maxSize)
    {
        var side = Math.Max(src.Width, src.Height);
        var scale = side > maxSize ? (float)maxSize / side : 1f;
        var w = Math.Max(1, (int)(src.Width * scale));
        var h = Math.Max(1, (int)(src.Height * scale));

        using var resized = new SKBitmap(w, h, SKColorType.Rgba8888, SKAlphaType.Premul);
        using (var canvas = new SKCanvas(resized))
        using (var paint = new SKPaint { FilterQuality = SKFilterQuality.High })
        {
            canvas.Clear(SKColors.Transparent);
            canvas.DrawBitmap(src, SKRect.Create(w, h), paint);
        }
        using var img = SKImage.FromBitmap(resized);
        using var data = img.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }

    private static byte[] Placeholder(string assetType, int maxSize)
    {
        using var bitmap = new SKBitmap(maxSize, maxSize, SKColorType.Rgba8888, SKAlphaType.Premul);
        using (var canvas = new SKCanvas(bitmap))
        using (var bg = new SKPaint { Color = new SKColor(0x44, 0x44, 0x44), IsAntialias = true })
        using (var fg = new SKPaint { Color = SKColors.White, IsAntialias = true, TextSize = maxSize * 0.4f, TextAlign = SKTextAlign.Center, Typeface = SKTypeface.FromFamilyName("Segoe UI", SKFontStyle.Bold) })
        {
            canvas.Clear(new SKColor(0x44, 0x44, 0x44));
            var letter = assetType switch
            {
                "render" => "R",
                "photo" => "P",
                "document" => "D",
                "profile" => "Pr",
                _ => "Re",
            };
            var metrics = fg.FontMetrics;
            var y = maxSize * 0.5f - (metrics.Ascent + metrics.Descent) * 0.5f;
            canvas.DrawText(letter, maxSize * 0.5f, y, fg);
        }
        using var img = SKImage.FromBitmap(bitmap);
        using var data = img.Encode(SKEncodedImageFormat.Png, 90);
        return data.ToArray();
    }
}