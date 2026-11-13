namespace MiniCodex.Core.Services;

public interface IScannerService
{
    Task ScanAsync(
        IEnumerable<string> rootFolders,
        IProgress<ScanProgress>? progress = null,
        CancellationToken ct = default);
}