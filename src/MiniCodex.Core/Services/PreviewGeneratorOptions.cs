namespace MiniCodex.Core.Services;

public class PreviewGeneratorOptions
{
    public int Width { get; set; } = 384;
    public int Height { get; set; } = 384;
    public float PitchDegrees { get; set; } = 15f;

    // 4 stops over 90deg (220 -> 310). Smoother rotation, starts more "3/4 back".
    public float[] YawDegrees { get; set; } = { 220f, 250f, 280f, 310f };

    public int Supersample { get; set; } = 2;
}