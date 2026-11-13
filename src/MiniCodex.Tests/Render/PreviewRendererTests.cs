using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Render.Rendering;
using Xunit;

namespace MiniCodex.Tests.Render;

public class PreviewRendererTests
{
    private static MeshGeometry Cube()
    {
        var v = new[]
        {
            new Vector3(-1,-1,-1), new Vector3(1,-1,-1), new Vector3(1,1,-1), new Vector3(-1,1,-1),
            new Vector3(-1,-1, 1), new Vector3(1,-1, 1), new Vector3(1,1, 1), new Vector3(-1,1, 1),
        };
        var idx = new[]
        {
            0,1,2, 0,2,3,  4,6,5, 4,7,6,
            0,4,5, 0,5,1,  1,5,6, 1,6,2,
            2,6,7, 2,7,3,  3,7,4, 3,4,0,
        };
        return new MeshGeometry { Vertices = v, Indices = idx };
    }

    [Fact]
    public void Render_ProducesValidPng()
    {
        var renderer = new SkiaPreviewRenderer();
        var png = renderer.Render(Cube(), 64, 64, 0f, 15f);
        Assert.NotNull(png);
        Assert.True(png.Length > 100);
        // PNG signature
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, png.Take(8).ToArray());
    }

    [Fact]
    public void Render_DifferentAngles_ProduceDifferentPngs()
    {
        // Куб имеет 90° симметрию вокруг Y — при фиксированном свете yaw 0° и 90°
        // дают байт-в-байт идентичный PNG. Берём 37° (не кратный 90°),
        // чтобы проверить, что yaw вообще влияет на рендер.
        var renderer = new SkiaPreviewRenderer();
        var a = renderer.Render(Cube(), 64, 64, 0f, 15f);
        var b = renderer.Render(Cube(), 64, 64, 37f, 15f);
        Assert.NotEqual(a, b);
    }
}