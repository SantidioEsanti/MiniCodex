using MiniCodex.Render.Loaders;
using Xunit;

namespace MiniCodex.Tests.Render;

public class MeshLoaderTests
{
    private const string AsciiStl = @"solid test
  facet normal 0 0 1
    outer loop
      vertex 0 0 0
      vertex 1 0 0
      vertex 0 1 0
    endloop
  endfacet
endsolid test
";

    private const string SimpleObj = @"v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
";

    [Fact]
    public void Load_AsciiStl_ReturnsOnePolygonAndBox()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, AsciiStl);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);

            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
            Assert.Equal(0, info.BoundingBoxMin[0], 3);
            Assert.Equal(1, info.BoundingBoxMax[0], 3);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_SimpleObj_ReturnsOnePolygon()
    {
        var path = Path.GetTempFileName() + ".obj";
        try
        {
            File.WriteAllText(path, SimpleObj);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);
            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_Nonexistent_ReturnsNull()
    {
        var loader = new AssimpMeshLoader();
        Assert.Null(loader.Load(@"C:\definitely\not\here\missing.stl"));
    }

    [Fact]
    public void Load_CorruptFile_ReturnsNull()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, "not a mesh at all");
            var loader = new AssimpMeshLoader();
            Assert.Null(loader.Load(path));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}