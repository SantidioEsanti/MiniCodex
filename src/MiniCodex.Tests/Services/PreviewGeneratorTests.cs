using System.Numerics;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using Xunit;

namespace MiniCodex.Tests.Services;

public class StubRenderer : IPreviewRenderer
{
    public int CallCount { get; private set; }
    public byte[] Render(MeshGeometry mesh, int width, int height, float yawDegrees, float pitchDegrees, float zoom = 1.0f, RenderStyle? style = null, int supersample = 2)
    {
        CallCount++;
        return new byte[] { 0x89, 0x50, 0x4E, 0x47, (byte)CallCount, 0, 0, 0 };
    }
}

public class StubGeometryLoader : IMeshGeometryLoader
{
    public MeshGeometry? LoadGeometry(string filePath) => new()
    {
        Vertices = new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(0, 1, 0) },
        Indices = new[] { 0, 1, 2 },
    };
}

public class PreviewGeneratorTests : IDisposable
{
    private readonly string _cacheDir;
    private readonly StubRenderer _renderer = new();

    public PreviewGeneratorTests()
    {
        _cacheDir = Path.Combine(Path.GetTempPath(), $"minicodex_cache_{Guid.NewGuid()}");
        Directory.CreateDirectory(_cacheDir);
    }

    public void Dispose() { try { Directory.Delete(_cacheDir, true); } catch { } }

    private PreviewGenerator NewGen() => new(_renderer, new StubGeometryLoader(), _cacheDir);

    [Fact]
    public async Task EnsurePreviews_CreatesFourFiles()
    {
        var gen = NewGen();
        var results = await gen.EnsurePreviewsAsync("m1", "fake.stl", DateTime.UtcNow);

        Assert.Equal(4, results.Count);
        Assert.All(results, r => Assert.NotNull(r));
        Assert.All(results, r => Assert.True(File.Exists(r!)));
        Assert.Equal(4, _renderer.CallCount);
    }

    [Fact]
    public async Task EnsurePreviews_SecondCall_UsesCache()
    {
        var gen = NewGen();
        var dt = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", dt);
        var callsAfterFirst = _renderer.CallCount;
        await gen.EnsurePreviewsAsync("m1", "fake.stl", dt);
        Assert.Equal(callsAfterFirst, _renderer.CallCount);
    }

    [Fact]
    public async Task EnsurePreviews_SourceChanged_Regenerates()
    {
        var gen = NewGen();
        var t1 = new DateTime(2026, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", t1);
        var callsAfterFirst = _renderer.CallCount;
        var t2 = t1.AddHours(1);
        await gen.EnsurePreviewsAsync("m1", "fake.stl", t2);
        Assert.True(_renderer.CallCount > callsAfterFirst);
    }

    [Fact]
    public async Task EnsurePreviews_MissingGeometry_ReturnsNulls()
    {
        var gen = new PreviewGenerator(_renderer, new NullGeometryLoader(), _cacheDir);
        var results = await gen.EnsurePreviewsAsync("m1", "fake.stl", DateTime.UtcNow);
        Assert.All(results, r => Assert.Null(r));
        Assert.Equal(0, _renderer.CallCount);
    }

    private class NullGeometryLoader : IMeshGeometryLoader
    {
        public MeshGeometry? LoadGeometry(string filePath) => null;
    }
}