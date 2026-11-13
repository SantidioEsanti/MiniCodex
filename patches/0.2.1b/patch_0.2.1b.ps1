#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.1b — устойчивые к миграциям тесты DatabaseInitializer.
.DESCRIPTION
    Экспортирует Migrations и LatestSchemaVersion из DatabaseInitializer.
    Тесты используют LatestSchemaVersion вместо хардкода "1".
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.1b'
$ProjectRoot = 'D:\AI\MiniCodex'
$PatchDir    = Join-Path $ProjectRoot "patches\$Version"
$BackupRoot  = Join-Path $ProjectRoot 'backups'
$LogFile     = Join-Path $PatchDir 'patch.log'
$Timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$BackupDir   = Join-Path $BackupRoot "${Version}_${Timestamp}"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $rel = $Path.Substring($ProjectRoot.Length).TrimStart('\')
    $dst = Join-Path $BackupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination $dst -Force
    Write-Log "Backup: $rel -> $dst"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

$Files = @{}

# ============ Data/DatabaseInitializer.cs (обновление) ============
$Files['src\MiniCodex.Data\DatabaseInitializer.cs'] = @'
using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public static class DatabaseInitializer
{
    public static IReadOnlyList<IMigration> Migrations { get; } = new IMigration[]
    {
        new Migration_0001_InitialSchema(),
        new Migration_0002_ModelFile_LastWriteTime(),
    };

    public static int LatestSchemaVersion => Migrations.Max(m => m.Version);

    public static async Task InitializeAsync(string dbPath, CancellationToken ct = default)
    {
        var dir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var factory = new SqliteConnectionFactory(dbPath);
        await using var conn = await factory.OpenAsync(ct);

        var runner = new MigrationRunner(Migrations);
        await runner.RunAsync(conn, ct);
    }
}
'@

# ============ Tests/DatabaseInitializerTests.cs (обновление) ============
$Files['src\MiniCodex.Tests\DatabaseInitializerTests.cs'] = @'
using Microsoft.Data.Sqlite;
using MiniCodex.Data;
using Xunit;

namespace MiniCodex.Tests;

public class DatabaseInitializerTests
{
    [Fact]
    public async Task Initialize_CreatesAllTables_AndSchemaVersion()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            Assert.True(File.Exists(path));

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();

            var expected = new[] { "Model","ModelFile","Asset","Tag","ModelTag","Collection","Setting" };
            foreach (var table in expected)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name=$n;";
                cmd.Parameters.AddWithValue("$n", table);
                Assert.Equal(table, await cmd.ExecuteScalarAsync());
            }

            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal(DatabaseInitializer.LatestSchemaVersion.ToString(), await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task Initialize_IsIdempotent()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            await DatabaseInitializer.InitializeAsync(path);

            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();
            await using var v = conn.CreateCommand();
            v.CommandText = "SELECT value FROM Setting WHERE key='Db.SchemaVersion';";
            Assert.Equal(DatabaseInitializer.LatestSchemaVersion.ToString(), await v.ExecuteScalarAsync());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public async Task ModelFile_HasLastWriteTimeColumn()
    {
        var path = Path.Combine(Path.GetTempPath(), $"minicodex_{Guid.NewGuid()}.db");
        try
        {
            await DatabaseInitializer.InitializeAsync(path);
            await using var conn = new SqliteConnection($"Data Source={path}");
            await conn.OpenAsync();

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "PRAGMA table_info(ModelFile);";
            await using var r = await cmd.ExecuteReaderAsync();

            var hasColumn = false;
            while (await r.ReadAsync())
            {
                if (string.Equals(r.GetString(1), "last_write_time_utc", StringComparison.OrdinalIgnoreCase))
                {
                    hasColumn = true;
                    break;
                }
            }
            Assert.True(hasColumn, "ModelFile должна содержать колонку last_write_time_utc (миграция 2).");
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ README патча ============
$Files['patches\0.2.1b\README.md'] = @'
# Патч 0.2.1b — устойчивые к миграциям тесты

**Итерация:** 0.2 · **Статус:** реализован

## Причина

После добавления миграции №2 в патче 0.2.1 (`ModelFile.last_write_time_utc`) тесты `DatabaseInitializerTests` (написаны в 0.1.1) хардкодили `Db.SchemaVersion = "1"` и падали с `Expected: 1, Actual: 2`.

## Что делает

- Экспортирует `DatabaseInitializer.Migrations` (публичный список) и `LatestSchemaVersion`.
- Тесты используют `DatabaseInitializer.LatestSchemaVersion.ToString()` вместо хардкода `"1"` — при любой новой миграции в будущем тесты останутся зелёными.
- Добавляет тест `ModelFile_HasLastWriteTimeColumn` — проверка, что миграция 2 применилась (PRAGMA table_info).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.1b\patch_0.2.1b.ps1"

## DoD

- `dotnet build` — 0 ошибок.
- `dotnet test` — 18 тестов (17 + 1 новый), все зелёные.
'@

try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.Data\DatabaseInitializer.cs')
    Backup-File (Join-Path $ProjectRoot 'src\MiniCodex.Tests\DatabaseInitializerTests.cs')
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # CHANGELOG
    $marker = '<!-- patch 0.2.1b applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n### Fixed`n- 0.2.1b: DatabaseInitializerTests используют LatestSchemaVersion вместо хардкода версии.`n`n### Added`n- DatabaseInitializer.Migrations (публичный) + LatestSchemaVersion.`n- Тест ModelFile_HasLastWriteTimeColumn.`n"
            $cl = $cl -replace '(?m)^(## \[0\.2\.1a\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.1b.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    exit 1
}