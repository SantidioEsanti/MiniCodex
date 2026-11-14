# patch_0.5.3a.ps1 - Tag rename/delete (backend)
# One logical step. No UI. No ViewModel changes. Tests 55 -> 60.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3a'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $ProjectRoot ("backups\{0}_{1}" -f $Version, $Timestamp)
$PatchDir    = Join-Path $ProjectRoot ("patches\{0}" -f $Version)
$LogPath     = Join-Path $PatchDir 'patch.log'
$utf8NoBom   = [Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
New-Item -ItemType Directory -Force -Path $PatchDir  | Out-Null

function Write-Log([string]$msg) {
    $line = ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Replace-Exact([string]$path, $pairs) {
    $c = [IO.File]::ReadAllText($path, $utf8NoBom)
    $hadCrLf = $c.Contains("`r`n")
    if ($hadCrLf) { $c = $c.Replace("`r`n", "`n") }
    foreach ($p in $pairs) {
        $old = $p.Old.Replace("`r`n", "`n")
        $new = $p.New.Replace("`r`n", "`n")
        $cnt = [regex]::Matches($c, [regex]::Escape($old)).Count
        if ($cnt -eq 0) { throw ("Anchor not found: {0}" -f $p.Label) }
        if ($cnt -gt 1) { throw ("Anchor ambiguous ({0}): {1}" -f $cnt, $p.Label) }
        $c = $c.Replace($old, $new)
        Write-Log ("  replaced: {0}" -f $p.Label)
    }
    if ($hadCrLf) { $c = $c.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $c, $utf8NoBom)
}

Write-Log ("Patch {0} started" -f $Version)
Write-Log ("Backup dir: {0}" -f $BackupDir)

# ---------- 0. Pre-flight ----------
$itagPath  = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\ITagService.cs'
$tagPath   = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\TagService.cs'
$imtrPath  = Join-Path $ProjectRoot 'src\MiniCodex.Core\Repositories\IModelTagRepository.cs'
$mtrPath   = Join-Path $ProjectRoot 'src\MiniCodex.Data\Repositories\ModelTagRepository.cs'
$chPath    = Join-Path $ProjectRoot 'CHANGELOG.md'
$testNew   = Join-Path $ProjectRoot 'src\MiniCodex.Tests\TagCrudTests.cs'

foreach ($p in @($itagPath, $tagPath, $imtrPath, $mtrPath, $chPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ("Required file missing: {0}" -f $p) }
}

$itagCheck = [IO.File]::ReadAllText($itagPath, $utf8NoBom)
if ($itagCheck -notmatch 'SetColorAsync')  { throw 'Pre-flight: ITagService.cs missing SetColorAsync (0.5.2a not applied).' }
if ($itagCheck -match  'RenameAsync')      { throw 'Pre-flight: ITagService.cs already has RenameAsync. 0.5.3a applied.' }

$tagCheck = [IO.File]::ReadAllText($tagPath, $utf8NoBom)
if ($tagCheck -notmatch 'SetColorAsync') { throw 'Pre-flight: TagService.cs missing SetColorAsync (0.5.2a not applied).' }

Write-Log 'Pre-flight OK.'

# ---------- 1. Backup ----------
$filesToBackup = @(
    'src\MiniCodex.Core\Services\ITagService.cs',
    'src\MiniCodex.Core\Services\TagService.cs',
    'src\MiniCodex.Core\Repositories\IModelTagRepository.cs',
    'src\MiniCodex.Data\Repositories\ModelTagRepository.cs',
    'CHANGELOG.md'
)
foreach ($rel in $filesToBackup) {
    $src    = Join-Path $ProjectRoot $rel
    $dst    = Join-Path $BackupDir $rel
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Log ("Backed up: {0}" -f $rel)
}

# ---------- 2. IModelTagRepository.cs += RemoveAllForTagAsync ----------
$imtrPairs = @(
    @{
        Label = 'IModelTagRepository RemoveAllForTagAsync'
        Old = '    Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default);'
        New = @'
    Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default);
    Task RemoveAllForTagAsync(string tagId, CancellationToken ct = default);
'@
    }
)
Replace-Exact $imtrPath $imtrPairs
Write-Log ("Updated: {0}" -f $imtrPath)

# ---------- 3. ModelTagRepository.cs += RemoveAllForTagAsync ----------
$mtrPairs = @(
    @{
        Label = 'ModelTagRepository RemoveAllForTagAsync impl'
        Old = @'
    public async Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT 1 FROM ModelTag WHERE model_id = $m AND tag_id = $t LIMIT 1;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }
'@
        New = @'
    public async Task<bool> ExistsAsync(string modelId, string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT 1 FROM ModelTag WHERE model_id = $m AND tag_id = $t LIMIT 1;";
        cmd.Parameters.AddWithValue("$m", modelId);
        cmd.Parameters.AddWithValue("$t", tagId);
        return await cmd.ExecuteScalarAsync(ct) != null;
    }

    public async Task RemoveAllForTagAsync(string tagId, CancellationToken ct = default)
    {
        await using var conn = await _factory.OpenAsync(ct);
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "DELETE FROM ModelTag WHERE tag_id = $t;";
        cmd.Parameters.AddWithValue("$t", tagId);
        await cmd.ExecuteNonQueryAsync(ct);
    }
'@
    }
)
Replace-Exact $mtrPath $mtrPairs
Write-Log ("Updated: {0}" -f $mtrPath)

# ---------- 4. ITagService.cs += RenameAsync, DeleteAsync ----------
$itagPairs = @(
    @{
        Label = 'ITagService RenameAsync + DeleteAsync'
        Old = '    Task SetColorAsync(string tagId, string? color, CancellationToken ct = default);'
        New = @'
    Task SetColorAsync(string tagId, string? color, CancellationToken ct = default);
    Task RenameAsync(string tagId, string newName, CancellationToken ct = default);
    Task DeleteAsync(string tagId, CancellationToken ct = default);
'@
    }
)
Replace-Exact $itagPath $itagPairs
Write-Log ("Updated: {0}" -f $itagPath)

# ---------- 5. TagService.cs += RenameAsync, DeleteAsync ----------
$tagPairs = @(
    @{
        Label = 'TagService RenameAsync + DeleteAsync'
        Old = @'
        => _tags.GetAllWithUsageAsync(ct);

    public async Task SetColorAsync(string tagId, string? color, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagId)) return;
        var tag = await _tags.GetAsync(tagId, ct);
        if (tag == null) return;
        tag.Color = string.IsNullOrWhiteSpace(color) ? null : color.Trim();
        await _tags.UpsertAsync(tag, ct);
    }
'@
        New = @'
        => _tags.GetAllWithUsageAsync(ct);

    public async Task SetColorAsync(string tagId, string? color, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagId)) return;
        var tag = await _tags.GetAsync(tagId, ct);
        if (tag == null) return;
        tag.Color = string.IsNullOrWhiteSpace(color) ? null : color.Trim();
        await _tags.UpsertAsync(tag, ct);
    }

    public async Task RenameAsync(string tagId, string newName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagId)) return;
        if (string.IsNullOrWhiteSpace(newName)) return;
        var tag = await _tags.GetAsync(tagId, ct);
        if (tag == null) return;
        tag.Name = newName.Trim();
        await _tags.UpsertAsync(tag, ct);
    }

    public async Task DeleteAsync(string tagId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(tagId)) return;
        await _modelTags.RemoveAllForTagAsync(tagId, ct);
        await _tags.DeleteAsync(tagId, ct);
    }
'@
    }
)
Replace-Exact $tagPath $tagPairs
Write-Log ("Updated: {0}" -f $tagPath)

# ---------- 6. New test file TagCrudTests.cs ----------
if (-not (Test-Path -LiteralPath $testNew)) {
    $testContent = @'
using MiniCodex.Core.Services;
using MiniCodex.Data;
using MiniCodex.Data.Repositories;
using Xunit;

namespace MiniCodex.Tests;

public class TagCrudTests
{
    private static async Task<(string path, TagRepository tags, ModelTagRepository modelTags, TagService svc)> CreateEnvAsync()
    {
        var path = Path.Combine(Path.GetTempPath(), "minicodex_tag_" + Guid.NewGuid().ToString("N") + ".db");
        await DatabaseInitializer.InitializeAsync(path);
        var factory   = new SqliteConnectionFactory(path);
        var tags      = new TagRepository(factory);
        var modelTags = new ModelTagRepository(factory);
        var svc       = new TagService(tags, modelTags);
        return (path, tags, modelTags, svc);
    }

    [Fact]
    public async Task RenameAsync_UpdatesName()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Old");
            await svc.RenameAsync(t.Id, "New");
            var all = await tags.GetAllAsync();
            Assert.Single(all);
            Assert.Equal("New", all[0].Name);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task RenameAsync_EmptyName_NoOp()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Keep");
            await svc.RenameAsync(t.Id, "");
            await svc.RenameAsync(t.Id, "   ");
            var reloaded = await tags.GetAsync(t.Id);
            Assert.NotNull(reloaded);
            Assert.Equal("Keep", reloaded!.Name);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task RenameAsync_EmptyId_NoOp()
    {
        var (path, _, _, svc) = await CreateEnvAsync();
        try
        {
            await svc.RenameAsync("", "New");
            await svc.RenameAsync("   ", "New");
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task DeleteAsync_RemovesTagAndAssociations()
    {
        var (path, tags, modelTags, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("ToDelete");
            await modelTags.AddAsync("fake-model-1", t.Id);
            await modelTags.AddAsync("fake-model-2", t.Id);
            Assert.True(await modelTags.ExistsAsync("fake-model-1", t.Id));
            Assert.True(await modelTags.ExistsAsync("fake-model-2", t.Id));

            await svc.DeleteAsync(t.Id);

            Assert.Empty(await tags.GetAllAsync());
            Assert.False(await modelTags.ExistsAsync("fake-model-1", t.Id));
            Assert.False(await modelTags.ExistsAsync("fake-model-2", t.Id));
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task DeleteAsync_EmptyId_NoOp()
    {
        var (path, tags, _, svc) = await CreateEnvAsync();
        try
        {
            var t = await svc.CreateOrGetAsync("Survivor");
            await svc.DeleteAsync("");
            await svc.DeleteAsync("   ");
            Assert.Single(await tags.GetAllAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@
    [IO.File]::WriteAllText($testNew, $testContent, $utf8NoBom)
    Write-Log ("Created: {0}" -f $testNew)
} else {
    Write-Log ("Already exists, skip: {0}" -f $testNew)
}

# ---------- 7. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3a applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3a - Tag rename/delete (backend)' + $nl + $nl +
        '- ITagService: added RenameAsync, DeleteAsync.' + $nl +
        '- TagService: implemented RenameAsync (trim, no-op on empty name/id), DeleteAsync (removes ModelTag associations first, then tag).' + $nl +
        '- IModelTagRepository: added RemoveAllForTagAsync.' + $nl +
        '- ModelTagRepository: implemented RemoveAllForTagAsync (DELETE FROM ModelTag WHERE tag_id = $t).' + $nl +
        '- New tests: TagCrudTests (5) - rename update, empty name/id no-op, delete with association cleanup, empty id no-op.' + $nl + $nl +
        '<!-- patch 0.5.3a applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next: build + test (expect 60 tests)'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)