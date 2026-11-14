# patch_0.5.2a.ps1 - Smart Collections + Tag color backend plumbing
# One logical step. No UI. No migrations. 50 tests must stay green.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.2a'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot ("backups\{0}_{1}" -f $Version, $Timestamp)
$PatchDir    = Join-Path $ProjectRoot ("patches\{0}" -f $Version)
$LogPath     = Join-Path $PatchDir 'patch.log'

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $PatchDir  | Out-Null

function Write-Log([string]$msg) {
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

Write-Log ("Patch {0} started" -f $Version)
Write-Log ("Project root: {0}" -f $ProjectRoot)
Write-Log ("Backup dir:   {0}" -f $BackupDir)

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.Core\Services\ITagService.cs',
    'src\MiniCodex.Core\Services\TagService.cs',
    'src\MiniCodex.App\AppServices.cs',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src = Join-Path $ProjectRoot $rel
    if (Test-Path -LiteralPath $src) {
        $dst    = Join-Path $BackupDir $rel
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path -LiteralPath $dstDir)) {
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Write-Log ("Backed up: {0}" -f $rel)
    } else {
        Write-Log ("Skip backup (not found): {0}" -f $rel)
    }
}

# ---------- 2. Safety check: test stubs implementing ITagService/ICollectionService ----------
$testDir = Join-Path $ProjectRoot 'src\MiniCodex.Tests'
$testHits = @()
if (Test-Path -LiteralPath $testDir) {
    $testFiles = Get-ChildItem -LiteralPath $testDir -Filter '*.cs' -File -Recurse
    foreach ($f in $testFiles) {
        $t = [IO.File]::ReadAllText($f.FullName, [Text.UTF8Encoding]::new($false))
        if (($t -match ':\s*ITagService\b') -or ($t -match ':\s*ICollectionService\b')) {
            $testHits += $f.FullName
        }
    }
}
if ($testHits.Count -gt 0) {
    Write-Log 'WARN: following test files implement ITagService/ICollectionService and may need a new stub method:'
    foreach ($h in $testHits) { Write-Log ("  - {0}" -f $h) }
} else {
    Write-Log 'OK: no test stubs implement ITagService/ICollectionService.'
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)

# ---------- 3. Create SmartCollectionFilter.cs ----------
$smartFilterPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Models\SmartCollectionFilter.cs'
if (-not (Test-Path -LiteralPath $smartFilterPath)) {
    $smartFilterContent = @'
namespace MiniCodex.Core.Models;

/// <summary>
/// Serializable filter payload for a Smart Collection (search + tag).
/// </summary>
public sealed record SmartCollectionFilter(string? Search, string? TagId, string? TagName)
{
    public static SmartCollectionFilter Empty { get; } = new(null, null, null);

    public bool IsEmpty => string.IsNullOrWhiteSpace(Search) && string.IsNullOrWhiteSpace(TagId);
}
'@
    [IO.File]::WriteAllText($smartFilterPath, $smartFilterContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $smartFilterPath)
} else {
    Write-Log ("Already exists, skip: {0}" -f $smartFilterPath)
}

# ---------- 4. Create ICollectionService.cs ----------
$iCollPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\ICollectionService.cs'
if (-not (Test-Path -LiteralPath $iCollPath)) {
    $iCollContent = @'
using MiniCodex.Core.Models;

namespace MiniCodex.Core.Services;

public interface ICollectionService
{
    Task<IReadOnlyList<Collection>> GetSmartAsync(CancellationToken ct = default);
    Task<Collection> SaveSmartAsync(string name, SmartCollectionFilter filter, CancellationToken ct = default);
    Task DeleteAsync(string id, CancellationToken ct = default);
}
'@
    [IO.File]::WriteAllText($iCollPath, $iCollContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $iCollPath)
} else {
    Write-Log ("Already exists, skip: {0}" -f $iCollPath)
}

# ---------- 5. Create CollectionService.cs ----------
$collPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\CollectionService.cs'
if (-not (Test-Path -LiteralPath $collPath)) {
    $collContent = @'
using System.Text.Json;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class CollectionService : ICollectionService
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ICollectionRepository _repo;

    public CollectionService(ICollectionRepository repo) => _repo = repo;

    public async Task<IReadOnlyList<Collection>> GetSmartAsync(CancellationToken ct = default)
    {
        var all = await _repo.GetAllAsync(ct);
        return all.Where(c => c.IsSmart).ToList();
    }

    public async Task<Collection> SaveSmartAsync(string name, SmartCollectionFilter filter, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Collection name is required", nameof(name));

        var trimmed = name.Trim();
        var existing = (await _repo.GetAllAsync(ct))
            .FirstOrDefault(c => c.IsSmart && string.Equals(c.Name, trimmed, StringComparison.OrdinalIgnoreCase));

        var collection = existing ?? new Collection
        {
            Id = Guid.NewGuid().ToString("N"),
            IsSmart = true,
        };
        collection.Name        = trimmed;
        collection.FilterQuery = SerializeFilter(filter);
        collection.IsSmart     = true;

        await _repo.UpsertAsync(collection, ct);
        return collection;
    }

    public Task DeleteAsync(string id, CancellationToken ct = default) => _repo.DeleteAsync(id, ct);

    public static string SerializeFilter(SmartCollectionFilter filter)
        => JsonSerializer.Serialize(filter ?? SmartCollectionFilter.Empty, JsonOpts);

    public static SmartCollectionFilter DeserializeFilter(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return SmartCollectionFilter.Empty;
        try
        {
            return JsonSerializer.Deserialize<SmartCollectionFilter>(json, JsonOpts) ?? SmartCollectionFilter.Empty;
        }
        catch (JsonException)
        {
            return SmartCollectionFilter.Empty;
        }
    }
}
'@
    [IO.File]::WriteAllText($collPath, $collContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $collPath)
} else {
    Write-Log ("Already exists, skip: {0}" -f $collPath)
}

# ---------- 6. Create CollectionServiceTests.cs ----------
$testPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\CollectionServiceTests.cs'
if (-not (Test-Path -LiteralPath $testPath)) {
    $testContent = @'
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests;

public class CollectionServiceTests
{
    private static async Task<(string path, CollectionService svc)> CreateServiceAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), "minicodex_coll_" + Guid.NewGuid().ToString("N") + ".db");
        await DatabaseInitializer.InitializeAsync(path);
        var factory = new SqliteConnectionFactory(path);
        var repo    = new CollectionRepository(factory);
        return (path, new CollectionService(repo));
    }

    [Fact]
    public async Task SaveSmart_RoundTripsFilter()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var filter = new SmartCollectionFilter("dragon", "tag-1", "Orcs");
            var saved  = await svc.SaveSmartAsync("My Dragons", filter);
            Assert.False(string.IsNullOrEmpty(saved.Id));

            var all = await svc.GetSmartAsync();
            Assert.Single(all);
            var loaded = CollectionService.DeserializeFilter(all[0].FilterQuery);
            Assert.Equal("dragon", loaded.Search);
            Assert.Equal("tag-1",  loaded.TagId);
            Assert.Equal("Orcs",   loaded.TagName);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task SaveSmart_UpdatesExistingByName()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var a = await svc.SaveSmartAsync("Filter A", new SmartCollectionFilter("a", null, null));
            var b = await svc.SaveSmartAsync("Filter A", new SmartCollectionFilter("b", "tag-2", "Elves"));
            Assert.Equal(a.Id, b.Id);

            var all = await svc.GetSmartAsync();
            Assert.Single(all);
            var loaded = CollectionService.DeserializeFilter(all[0].FilterQuery);
            Assert.Equal("b",     loaded.Search);
            Assert.Equal("tag-2", loaded.TagId);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task Delete_RemovesCollection()
    {
        var (path, svc) = await CreateServiceAsync();
        try
        {
            var c = await svc.SaveSmartAsync("ToDelete", new SmartCollectionFilter("x", null, null));
            await svc.DeleteAsync(c.Id);
            var all = await svc.GetSmartAsync();
            Assert.Empty(all);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void DeserializeFilter_HandlesNullAndEmpty()
    {
        var a = CollectionService.DeserializeFilter(null);
        var b = CollectionService.DeserializeFilter("");
        Assert.True(a.IsEmpty);
        Assert.True(b.IsEmpty);
    }

    [Fact]
    public void SmartCollectionFilter_IsEmpty_Works()
    {
        Assert.True(SmartCollectionFilter.Empty.IsEmpty);
        Assert.False(new SmartCollectionFilter("x", null, null).IsEmpty);
        Assert.False(new SmartCollectionFilter(null, "id", null).IsEmpty);
    }
}
'@
    [IO.File]::WriteAllText($testPath, $testContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $testPath)
} else {
    Write-Log ("Already exists, skip: {0}" -f $testPath)
}

# ---------- 7. Update ITagService.cs ----------
$itagPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\ITagService.cs'
if (Test-Path -LiteralPath $itagPath) {
    $c = [IO.File]::ReadAllText($itagPath, $utf8NoBom)
    if ($c -notmatch 'SetColorAsync') {
        $nl  = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
        $old = '    Task<IReadOnlyList<TagWithUsage>> GetAllWithUsageAsync(CancellationToken ct = default);'
        $new = $old + $nl + '    Task SetColorAsync(string tagId, string? color, CancellationToken ct = default);'
        if ($c.Contains($old)) {
            $c = $c.Replace($old, $new)
            [IO.File]::WriteAllText($itagPath, $c, $utf8NoBom)
            Write-Log ("Updated: {0}" -f $itagPath)
        } else {
            Write-Log 'WARN: ITagService.cs anchor not found; skipped.'
        }
    } else {
        Write-Log 'ITagService.cs: SetColorAsync already present, skip.'
    }
} else {
    Write-Log 'WARN: ITagService.cs not found.'
}

# ---------- 8. Update TagService.cs ----------
$tagPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\TagService.cs'
if (Test-Path -LiteralPath $tagPath) {
    $c = [IO.File]::ReadAllText($tagPath, $utf8NoBom)
    if ($c -notmatch 'SetColorAsync') {
        $nl  = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
        $old = '        => _tags.GetAllWithUsageAsync(ct);'
        $new = $old + $nl + $nl +
               '    public async Task SetColorAsync(string tagId, string? color, CancellationToken ct = default)' + $nl +
               '    {' + $nl +
               '        if (string.IsNullOrWhiteSpace(tagId)) return;' + $nl +
               '        var tag = await _tags.GetAsync(tagId, ct);' + $nl +
               '        if (tag == null) return;' + $nl +
               '        tag.Color = string.IsNullOrWhiteSpace(color) ? null : color.Trim();' + $nl +
               '        await _tags.UpsertAsync(tag, ct);' + $nl +
               '    }'
        if ($c.Contains($old)) {
            $c = $c.Replace($old, $new)
            [IO.File]::WriteAllText($tagPath, $c, $utf8NoBom)
            Write-Log ("Updated: {0}" -f $tagPath)
        } else {
            Write-Log 'WARN: TagService.cs anchor not found; skipped.'
        }
    } else {
        Write-Log 'TagService.cs: SetColorAsync already present, skip.'
    }
} else {
    Write-Log 'WARN: TagService.cs not found.'
}

# ---------- 9. Update AppServices.cs (property + init) ----------
$appSvcPath = Join-Path $ProjectRoot 'src\MiniCodex.App\AppServices.cs'
if (Test-Path -LiteralPath $appSvcPath) {
    $c = [IO.File]::ReadAllText($appSvcPath, $utf8NoBom)
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $changed = $false

    if ($c -notmatch 'ICollectionService\? CollectionService') {
        $old = '    public static ITagService? TagService { get; private set; }'
        $new = $old + $nl + '    public static ICollectionService? CollectionService { get; private set; }'
        if ($c.Contains($old)) {
            $c = $c.Replace($old, $new)
            $changed = $true
            Write-Log 'AppServices.cs: added CollectionService property.'
        } else {
            Write-Log 'WARN: AppServices.cs TagService property anchor not found.'
        }
    } else {
        Write-Log 'AppServices.cs: CollectionService property already present, skip.'
    }

    if ($c -notmatch 'new CollectionService\(new CollectionRepository') {
        $old = '        TagService = new TagService(new TagRepository(Factory), ModelTags);'
        $new = $old + $nl + '        CollectionService = new CollectionService(new CollectionRepository(Factory));'
        if ($c.Contains($old)) {
            $c = $c.Replace($old, $new)
            $changed = $true
            Write-Log 'AppServices.cs: wired CollectionService in Init().'
        } else {
            Write-Log 'WARN: AppServices.cs TagService init anchor not found.'
        }
    } else {
        Write-Log 'AppServices.cs: CollectionService init already present, skip.'
    }

    if ($changed) {
        [IO.File]::WriteAllText($appSvcPath, $c, $utf8NoBom)
    }
} else {
    Write-Log 'WARN: AppServices.cs not found.'
}

# ---------- 10. CHANGELOG.md ----------
$chPath = Join-Path $ProjectRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $chPath) {
    $c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
    if ($c -notmatch 'patch 0\.5\.2a applied') {
        $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
        $entry = $nl +
            '## 0.5.2a - Smart Collections (backend plumbing)' + $nl + $nl +
            '- Added SmartCollectionFilter DTO (MiniCodex.Core.Models).' + $nl +
            '- Added ICollectionService / CollectionService (save/get/delete smart collections, JSON filter serialization).' + $nl +
            '- Added ITagService.SetColorAsync + implementation in TagService.' + $nl +
            '- Registered CollectionService in AppServices.' + $nl +
            '- New tests: CollectionServiceTests (5).' + $nl + $nl +
            '<!-- patch 0.5.2a applied -->' + $nl
        [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
        Write-Log 'CHANGELOG.md updated.'
    } else {
        Write-Log 'CHANGELOG.md already has patch 0.5.2a marker, skip.'
    }
} else {
    Write-Log 'CHANGELOG.md not found; skipped.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next:'
Write-Log '  1) dotnet build D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  2) dotnet test  D:\AI\MiniCodex\src\MiniCodex.sln -c Debug'
Write-Log '  Expect: 0 errors, 0 warnings, 55 tests (50 + 5 new).'
Write-Log 'Rollback (if needed):'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)