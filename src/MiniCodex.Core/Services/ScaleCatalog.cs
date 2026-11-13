using System.Globalization;
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public static class ScaleCatalog
{
    public static IReadOnlyList<ScalePreset> All { get; } = new[]
    {
        // Figures & miniatures
        new ScalePreset("figure", "1:6", 6f),
        new ScalePreset("figure", "1:10", 10f),
        new ScalePreset("figure", "1:12", 12f),
        new ScalePreset("figure", "1:16", 16f),
        new ScalePreset("figure", "1:18", 18f),
        new ScalePreset("figure", "1:24", 24f),
        new ScalePreset("figure", "1:32", 32f),
        new ScalePreset("figure", "1:35", 35f),
        new ScalePreset("figure", "1:43", 43f),
        new ScalePreset("figure", "1:48", 48f),
        new ScalePreset("figure", "1:56", 56f),
        new ScalePreset("figure", "1:60", 60f),
        new ScalePreset("figure", "1:64", 64f),
        new ScalePreset("figure", "1:72", 72f),
        new ScalePreset("figure", "1:100", 100f),
        // Vehicles
        new ScalePreset("vehicle", "1:12", 12f),
        new ScalePreset("vehicle", "1:18", 18f),
        new ScalePreset("vehicle", "1:24", 24f),
        new ScalePreset("vehicle", "1:25", 25f),
        new ScalePreset("vehicle", "1:43", 43f),
        new ScalePreset("vehicle", "1:64", 64f),
        // Aviation
        new ScalePreset("aviation", "1:32", 32f),
        new ScalePreset("aviation", "1:48", 48f),
        new ScalePreset("aviation", "1:72", 72f),
        new ScalePreset("aviation", "1:144", 144f),
        new ScalePreset("aviation", "1:200", 200f),
        // Armor
        new ScalePreset("armor", "1:35", 35f),
        new ScalePreset("armor", "1:48", 48f),
        new ScalePreset("armor", "1:72", 72f),
        new ScalePreset("armor", "1:76", 76f),
        // Naval
        new ScalePreset("naval", "1:200", 200f),
        new ScalePreset("naval", "1:350", 350f),
        new ScalePreset("naval", "1:700", 700f),
        // Railway
        new ScalePreset("railway", "1:76 (OO)", 76f),
        new ScalePreset("railway", "1:87 (HO)", 87f),
        new ScalePreset("railway", "1:120 (TT)", 120f),
        new ScalePreset("railway", "1:160 (N)", 160f),
        // Architecture
        new ScalePreset("architecture", "1:20", 20f),
        new ScalePreset("architecture", "1:50", 50f),
        new ScalePreset("architecture", "1:100", 100f),
        new ScalePreset("architecture", "1:200", 200f),
    };

    public static IReadOnlyList<ScalePreset> ForPrototype(string? prototypeType)
    {
        if (string.IsNullOrEmpty(prototypeType) || prototypeType == "any")
            return All;

        return prototypeType switch
        {
            "figure"   => All.Where(s => s.Category == "figure").ToList(),
            "vehicle"  => All.Where(s => s.Category == "vehicle" || s.Category == "aviation" || s.Category == "armor").ToList(),
            "building" => All.Where(s => s.Category == "architecture").ToList(),
            "ship"     => All.Where(s => s.Category == "naval").ToList(),
            _ => All,
        };
    }

    public static float? ParseManual(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var trimmed = input.Trim();
        var sep = trimmed.IndexOfAny(new[] { ':', '/' });
        var denomPart = sep >= 0 ? trimmed.Substring(sep + 1).Trim() : trimmed;
        return float.TryParse(denomPart, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) && v > 0
            ? v : null;
    }

    public static float? CalculateModelHeightMm(float prototypeHeightMm, float denominator)
        => denominator > 0 ? prototypeHeightMm / denominator : null;

    public static float? CalculatePrototypeHeightMm(float modelHeightMm, float denominator)
        => denominator > 0 ? modelHeightMm * denominator : null;
}