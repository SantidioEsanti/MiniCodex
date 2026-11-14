$ErrorActionPreference = "Stop"
$ver = "0.5.1a33"
$root = "D:\AI\MiniCodex"
$patchDir = "$root\patches\$ver"
$backupDir = "$root\backups\${ver}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

if (-not (Test-Path $patchDir)) { New-Item -ItemType Directory -Path $patchDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
$logFile = "$patchDir\patch.log"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Log "Starting patch $ver - Backend Duplicate Detection (Hash)"

$files = @(
    "$root\src\MiniCodex.Core\Models\Entities.cs",
    "$root\src\MiniCodex.Data\Repositories\ModelFileRepository.cs",
    "$root\src\MiniCodex.Core\Services\ScannerService.cs",
    "$root\CHANGELOG.md"
)

foreach ($f in $files) {
    if (Test-Path $f) {
        $dest = Join-Path $backupDir (Split-Path $f -Leaf)
        Copy-Item -LiteralPath $f -Destination $dest -Force
        Log "Backed up $f to $dest"
    }
}

# 1. Create Migration_0004
$migrationPath = "$root\src\MiniCodex.Data\Migrations\Migration_0004_ModelFile_Hash.cs"
$migrationCode = @"
using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0004_ModelFile_Hash : IMigration
{
    public int Version => 4;
    public string Description => "Add file_hash to ModelFile";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "ALTER TABLE ModelFile ADD COLUMN file_hash TEXT;";
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
"@
[IO.File]::WriteAllText($migrationPath, $migrationCode, [Text.Encoding]::UTF8)
Log "Created Migration_0004_ModelFile_Hash.cs"

# 2. Update Entities.cs
$entitiesPath = "$root\src\MiniCodex.Core\Models\Entities.cs"
$entitiesContent = [IO.File]::ReadAllText($entitiesPath)
$entitiesContent = $entitiesContent.Replace(
    "public DateTime? LastWriteTimeUtc { get; set; }",
    "public DateTime? LastWriteTimeUtc { get; set; }`r`n    public string? FileHash { get; set; }"
)
[IO.File]::WriteAllText($entitiesPath, $entitiesContent)
Log "Entities.cs updated with FileHash property."

# 3. Update ModelFileRepository.cs
$repoPath = "$root\src\MiniCodex.Data\Repositories\ModelFileRepository.cs"
$repoContent = [IO.File]::ReadAllText($repoPath)

$oldSql = @"
INSERT INTO ModelFile(id, model_id, path, file_role, part_name, file_size_bytes, polygon_count, last_write_time_utc)
VALUES(`$id, `$model_id, `$path, `$file_role, `$part_name, `$file_size_bytes, `$polygon_count, `$last_write_time_utc)
ON CONFLICT(id) DO UPDATE SET
    path = excluded.path, file_role = excluded.file_role, part_name = excluded.part_name,
    file_size_bytes = excluded.file_size_bytes, polygon_count = excluded.polygon_count,
    last_write_time_utc = excluded.last_write_time_utc;";
"@
$newSql = @"
INSERT INTO ModelFile(id, model_id, path, file_role, part_name, file_size_bytes, polygon_count, last_write_time_utc, file_hash)
VALUES(`$id, `$model_id, `$path, `$file_role, `$part_name, `$file_size_bytes, `$polygon_count, `$last_write_time_utc, `$file_hash)
ON CONFLICT(id) DO UPDATE SET
    path = excluded.path, file_role = excluded.file_role, part_name = excluded.part_name,
    file_size_bytes = excluded.file_size_bytes, polygon_count = excluded.polygon_count,
    last_write_time_utc = excluded.last_write_time_utc, file_hash = excluded.file_hash;";
"@
$repoContent = $repoContent -replace [regex]::Escape($oldSql), $newSql

$repoContent = $repoContent.Replace(
    "cmd.Parameters.AddWithValue(`"`$last_write_time_utc`", f.LastWriteTimeUtc.HasValue ? f.LastWriteTimeUtc.Value.ToString(`"o`") : DBNull.Value);",
    "cmd.Parameters.AddWithValue(`"`$last_write_time_utc`", f.LastWriteTimeUtc.HasValue ? f.LastWriteTimeUtc.Value.ToString(`"o`") : DBNull.Value);`r`n        cmd.Parameters.AddWithValue(`"`$file_hash`", (object?)f.FileHash ?? DBNull.Value);"
)

$oldMap = @"
        LastWriteTimeUtc = r.IsDBNull(7) ? null : DateTime.Parse(r.GetString(7), null, System.Globalization.DateTimeStyles.RoundtripKind),
    };
"@
$newMap = @"
        LastWriteTimeUtc = r.IsDBNull(7) ? null : DateTime.Parse(r.GetString(7), null, System.Globalization.DateTimeStyles.RoundtripKind),
        FileHash = r.IsDBNull(8) ? null : r.GetString(8),
    };
"@
$repoContent = $repoContent -replace [regex]::Escape($oldMap), $newMap

[IO.File]::WriteAllText($repoPath, $repoContent)
Log "ModelFileRepository.cs updated."

# 4. Update ScannerService.cs
$scannerPath = "$root\src\MiniCodex.Core\Services\ScannerService.cs"
$scannerContent = [IO.File]::ReadAllText($scannerPath)

if ($scannerContent -notmatch "using System.Security.Cryptography;") {
    $scannerContent = $scannerContent.Replace("using System.Linq;", "using System.Linq;`r`nusing System.Security.Cryptography;")
}

$scannerContent = $scannerContent.Replace(
    "existing.LastWriteTimeUtc = fi.LastWriteTimeUtc;",
    "existing.LastWriteTimeUtc = fi.LastWriteTimeUtc;`r`n                        existing.FileHash = ComputeSha256(filePath);"
)

$scannerContent = $scannerContent.Replace(
    "LastWriteTimeUtc = fi.LastWriteTimeUtc,",
    "LastWriteTimeUtc = fi.LastWriteTimeUtc,`r`n                            FileHash = ComputeSha256(filePath),"
)

# Add helper method before the last closing brace
$hashMethod = @"

    private static string ComputeSha256(string filePath)
    {
        try
        {
            using var sha256 = SHA256.Create();
            using var stream = File.OpenRead(filePath);
            var hash = sha256.ComputeHash(stream);
            return Convert.ToHexString(hash);
        }
        catch
        {
            return string.Empty;
        }
    }
}
"@

$lastBrace = $scannerContent.LastIndexOf("}")
if ($lastBrace -ge 0) {
    $scannerContent = $scannerContent.Substring(0, $lastBrace) + $hashMethod
}

[IO.File]::WriteAllText($scannerPath, $scannerContent)
Log "ScannerService.cs updated with SHA-256."

# 5. Update CHANGELOG.md
$changelog = "$root\CHANGELOG.md"
$clContent = [IO.File]::ReadAllText($changelog)
if ($clContent -notmatch "patch $ver applied") {
    $entry = @"

## $ver
- Data: Added `file_hash` column to ModelFile and Migration_0004.
- Scanner: Compute SHA-256 hash for added or updated files.
- Repository: Save and load file hashes.
<!-- patch $ver applied -->
"@
    [IO.File]::AppendAllText($changelog, $entry)
    Log "CHANGELOG.md updated."
}

Log "Patch $ver completed successfully."