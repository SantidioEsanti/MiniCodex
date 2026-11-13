using MiniCodex.App.Services;
using MiniCodex.Core.Repositories;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using MiniCodex.Render.Loaders;
using MiniCodex.Render.Rendering;

namespace MiniCodex.App;

public static class AppServices
{
    public static SqliteConnectionFactory? Factory { get; private set; }
    public static IModelRepository? Models { get; private set; }
    public static IModelFileRepository? ModelFiles { get; private set; }
    public static IAssetRepository? Assets { get; private set; }
    public static ISettingRepository? Settings { get; private set; }
    public static IModelTagRepository? ModelTags { get; private set; }
    public static ScannerService? Scanner { get; private set; }
    public static PreviewGenerator? PreviewGenerator { get; private set; }
    public static IAssetService? AssetService { get; private set; }
    public static ITagService? TagService { get; private set; }
    public static IIntegrationService? IntegrationService { get; private set; }
    public static AppPaths? Paths { get; private set; }

    public static void Init(AppPaths paths)
    {
        Paths = paths;
        Factory = new SqliteConnectionFactory(paths.LibraryDb);
        Models = new ModelRepository(Factory);
        ModelFiles = new ModelFileRepository(Factory);
        Assets = new AssetRepository(Factory);
        Settings = new SettingRepository(Factory);
        ModelTags = new ModelTagRepository(Factory);

        var meshLoader = new AssimpMeshLoader();
        Scanner = new ScannerService(meshLoader, Models, ModelFiles);

        var renderer = new SkiaPreviewRenderer();
        PreviewGenerator = new PreviewGenerator(renderer, meshLoader, paths.CacheDir);

        var thumbs = new SkiaThumbnailGenerator();
        var thumbsRoot = Path.Combine(paths.DataDir, "cache", "asset-thumbs");
        AssetService = new AssetService(Assets, ModelFiles, thumbs, paths.AssetsDir, thumbsRoot);

        TagService = new TagService(new TagRepository(Factory), ModelTags);

        if (OperatingSystem.IsWindows())
        {
            var probe = new WindowsRegistryProbe();
            IntegrationService = new IntegrationService(probe, Settings);
        }
        else
        {
            IntegrationService = new IntegrationService(new NoopIntegrationProbe(), Settings);
        }
    }

internal sealed class NoopIntegrationProbe : IIntegrationProbe
{
    public Task<IReadOnlyDictionary<string, string>> ProbeAsync(CancellationToken ct = default)
        => Task.FromResult<IReadOnlyDictionary<string, string>>(new Dictionary<string, string>());
}
}