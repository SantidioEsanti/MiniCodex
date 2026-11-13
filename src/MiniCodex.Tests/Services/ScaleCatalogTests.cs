using MiniCodex.Core.Services;
using Xunit;

namespace MiniCodex.Tests.Services;

public class ScaleCatalogTests
{
    [Fact]
    public void All_HasExpectedCategories()
    {
        var cats = ScaleCatalog.All.Select(s => s.Category).Distinct().OrderBy(x => x).ToArray();
        Assert.Contains("figure", cats);
        Assert.Contains("vehicle", cats);
        Assert.Contains("aviation", cats);
        Assert.Contains("armor", cats);
        Assert.Contains("naval", cats);
        Assert.Contains("railway", cats);
        Assert.Contains("architecture", cats);
    }

    [Fact]
    public void ForPrototype_Figure_OnlyFigureScales()
    {
        var scales = ScaleCatalog.ForPrototype("figure");
        Assert.NotEmpty(scales);
        Assert.All(scales, s => Assert.Equal("figure", s.Category));
    }

    [Fact]
    public void ForPrototype_Vehicle_IncludesVehicleAviationArmor()
    {
        var scales = ScaleCatalog.ForPrototype("vehicle");
        var cats = scales.Select(s => s.Category).Distinct().ToHashSet();
        Assert.Contains("vehicle", cats);
        Assert.Contains("aviation", cats);
        Assert.Contains("armor", cats);
        Assert.DoesNotContain("figure", cats);
    }

    [Fact]
    public void ForPrototype_Ship_OnlyNaval()
    {
        var scales = ScaleCatalog.ForPrototype("ship");
        Assert.NotEmpty(scales);
        Assert.All(scales, s => Assert.Equal("naval", s.Category));
    }

    [Fact]
    public void ForPrototype_Any_ReturnsAll()
    {
        var scales = ScaleCatalog.ForPrototype("any");
        Assert.Equal(ScaleCatalog.All.Count, scales.Count);
    }

    [Fact]
    public void ParseManual_HandlesFormats()
    {
        Assert.Equal(24f, ScaleCatalog.ParseManual("1:24"));
        Assert.Equal(24f, ScaleCatalog.ParseManual("24"));
        Assert.Equal(24f, ScaleCatalog.ParseManual("1/24"));
        Assert.Equal(35.5f, ScaleCatalog.ParseManual("1:35.5"));
        Assert.Null(ScaleCatalog.ParseManual("abc"));
        Assert.Null(ScaleCatalog.ParseManual("1:0"));
        Assert.Null(ScaleCatalog.ParseManual(""));
    }

    [Fact]
    public void CalculateModelHeight_From1800mm_At1to24_Is75mm()
    {
        var mh = ScaleCatalog.CalculateModelHeightMm(1800f, 24f);
        Assert.NotNull(mh);
        Assert.Equal(75f, mh!.Value, 2);
    }

    [Fact]
    public void CalculatePrototypeHeight_From75mm_At1to24_Is1800mm()
    {
        var ph = ScaleCatalog.CalculatePrototypeHeightMm(75f, 24f);
        Assert.NotNull(ph);
        Assert.Equal(1800f, ph!.Value, 0);
    }
}