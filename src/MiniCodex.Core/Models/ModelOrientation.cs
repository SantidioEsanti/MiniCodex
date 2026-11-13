using System.Text.Json;

namespace MiniCodex.Core.Models;

public class ModelOrientation
{
    public float Yaw { get; set; } = 180f;
    public float Pitch { get; set; } = 15f;

    public static ModelOrientation Default => new();

    public static ModelOrientation Parse(string? json)
    {
        if (string.IsNullOrEmpty(json)) return Default;
        try
        {
            var o = JsonSerializer.Deserialize<ModelOrientation>(json);
            return o ?? Default;
        }
        catch { return Default; }
    }

    public string Serialize() => JsonSerializer.Serialize(this);
}