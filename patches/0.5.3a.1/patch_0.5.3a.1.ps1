# patch_0.5.3a.1.ps1 - fix FK constraint in TagCrudTests.DeleteAsync_RemovesTagAndAssociations
# One logical step. Test-only fix. No production code changes.

$ErrorActionPreference = 'Stop'
$ProjectRoot = 'D:\AI\MiniCodex'
$Version     = '0.5.3a.1'
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

# ---------- 0. Pre-flight ----------
$testPath = Join-Path $ProjectRoot 'src\MiniCodex.Tests\TagCrudTests.cs'
$chPath   = Join-Path $ProjectRoot 'CHANGELOG.md'
foreach ($p in @($testPath, $chPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw ("Required file missing: {0}" -f $p) }
}
$testCheck = [IO.File]::ReadAllText($testPath, $utf8NoBom)
if ($testCheck -notmatch 'class TagCrudTests')              { throw 'Pre-flight: TagCrudTests.cs missing.' }
if ($testCheck -match  'var models = new ModelRepository')  { throw 'Pre-flight: fix already applied.' }
if ($testCheck -notmatch 'fake-model-1')                    { throw 'Pre-flight: expected fake-model-1 not found; test file changed unexpectedly.' }
Write-Log 'Pre-flight OK.'

# ---------- 1. Backup ----------
$filesToBackup = @('src\MiniCodex.Tests\TagCrudTests.cs', 'CHANGELOG.md')
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

# ---------- 2. Fix test ----------
$testPairs = @(
    @{
        Label = 'seed real Model rows before ModelTag.AddAsync'
        Old = @'
            var t = await svc.CreateOrGetAsync("ToDelete");
            await modelTags.AddAsync("fake-model-1", t.Id);
            await modelTags.AddAsync("fake-model-2", t.Id);
'@
        New = @'
            var t = await svc.CreateOrGetAsync("ToDelete");
            var models = new ModelRepository(new SqliteConnectionFactory(path));
            await models.UpsertAsync(new MiniCodex.Core.Models.Model { Id = "fake-model-1", Title = "Fake 1" });
            await models.UpsertAsync(new MiniCodex.Core.Models.Model { Id = "fake-model-2", Title = "Fake 2" });
            await modelTags.AddAsync("fake-model-1", t.Id);
            await modelTags.AddAsync("fake-model-2", t.Id);
'@
    }
)
Replace-Exact $testPath $testPairs
Write-Log ("Updated: {0}" -f $testPath)

# ---------- 3. CHANGELOG ----------
$c = [IO.File]::ReadAllText($chPath, $utf8NoBom)
if ($c -notmatch 'patch 0\.5\.3a\.1 applied') {
    $nl = if ($c.Contains("`r`n")) { "`r`n" } else { "`n" }
    $entry = $nl +
        '## 0.5.3a.1 - test-only fix' + $nl + $nl +
        '- TagCrudTests.DeleteAsync_RemovesTagAndAssociations: seed real Model rows via ModelRepository.UpsertAsync before ModelTag.AddAsync. Root cause: SqliteConnectionFactory.OpenAsync issues PRAGMA foreign_keys = ON, so inserting ModelTag for a non-existent model id violated the FK on ModelTag.model_id -> Model.id. Production code unchanged.' + $nl + $nl +
        '<!-- patch 0.5.3a.1 applied -->' + $nl
    [IO.File]::AppendAllText($chPath, $entry, $utf8NoBom)
    Write-Log 'CHANGELOG.md updated.'
} else {
    Write-Log 'CHANGELOG.md: marker already present, skip.'
}

Write-Log ("Patch {0} done." -f $Version)
Write-Log ("Backup at: {0}" -f $BackupDir)
Write-Log 'Next: dotnet test (expect 60/60)'
Write-Log 'Rollback:'
Write-Log ("  Copy-Item -Path '{0}\*' -Destination 'D:\AI\MiniCodex\' -Recurse -Force" -f $BackupDir)