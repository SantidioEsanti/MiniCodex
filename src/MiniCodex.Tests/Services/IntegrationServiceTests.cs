using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests.Services;

public class FakeProbe : IIntegrationProbe
{
    private readonly Dictionary<string, string> _paths;
    public FakeProbe(Dictionary<string, string>? paths = null) => _paths = paths ?? new();
    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
        => Task.FromResult<IReadOnlyDictionary<string, string>>(_paths);
}

public class IntegrationServiceTests : IDisposable
{
    private readonly string _dbPath;
    private readonly SqliteConnectionFactory _factory;

    public IntegrationServiceTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        DatabaseInitializer.InitializeAsync(_dbPath).GetAwaiter().GetResult();
        _factory = new SqliteConnectionFactory(_dbPath);
    }

    public void Dispose() { try { File.Delete(_dbPath); } catch { } }

    [Fact]
    public async Task GetApps_EmptyProbe_AllMissing()
    {
        var svc = new IntegrationService(new FakeProbe(), new SettingRepository(_factory));
        var apps = await svc.GetAppsAsync();
        Assert.Equal(IntegrationCatalog.All.Count, apps.Count);
        Assert.All(apps, a => Assert.Null(a.Path));
        Assert.All(apps, a => Assert.False(a.IsDetected));
    }

    [Fact]
    public async Task GetApps_WithProbe_DetectedAppsHavePath()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\fake\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"C:\fake\bambu.exe", bambu.Path);
        Assert.True(bambu.IsDetected);
        Assert.False(bambu.IsUserOverride);
    }

    [Fact]
    public async Task SetPath_Override_Wins()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\detected\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));

        await svc.SetPathAsync("bambustudio", @"D:\custom\bambu-custom.exe");
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"D:\custom\bambu-custom.exe", bambu.Path);
        Assert.True(bambu.IsUserOverride);
        Assert.False(bambu.IsDetected);
    }

    [Fact]
    public async Task ClearOverride_RevertsToDetected()
    {
        var fake = new Dictionary<string, string> { ["bambustudio"] = @"C:\detected\bambu.exe" };
        var svc = new IntegrationService(new FakeProbe(fake), new SettingRepository(_factory));

        await svc.SetPathAsync("bambustudio", @"D:\custom\bambu-custom.exe");
        await svc.SetPathAsync("bambustudio", null);
        var apps = await svc.GetAppsAsync();

        var bambu = apps.First(a => a.Id == "bambustudio");
        Assert.Equal(@"C:\detected\bambu.exe", bambu.Path);
        Assert.True(bambu.IsDetected);
        Assert.False(bambu.IsUserOverride);
    }
}