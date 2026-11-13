using Microsoft.Data.Sqlite;

namespace MiniCodex.Data.Migrations;

public class Migration_0001_InitialSchema : IMigration
{
    public int Version => 1;
    public string Description => "Initial schema (Model, ModelFile, Asset, Tag, ModelTag, Collection, Setting)";

    public async Task ApplyAsync(SqliteConnection conn, CancellationToken ct = default)
    {
        var sql = @"
CREATE TABLE IF NOT EXISTS Model (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    author TEXT,
    source_url TEXT,
    model_type TEXT,
    primary_model_file_id TEXT,
    status TEXT,
    difficulty INTEGER,
    real_height_mm REAL,
    model_height_mm REAL,
    scale_ratio TEXT,
    notes TEXT,
    created_at TEXT,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS ModelFile (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    path TEXT NOT NULL,
    file_role TEXT,
    part_name TEXT,
    file_size_bytes INTEGER,
    polygon_count INTEGER,
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Asset (
    id TEXT PRIMARY KEY,
    model_id TEXT NOT NULL,
    asset_type TEXT,
    absolute_path TEXT NOT NULL,
    thumbnail_path TEXT,
    sort_order INTEGER,
    storage_mode TEXT,
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Tag (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    color TEXT,
    FOREIGN KEY (parent_id) REFERENCES Tag(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS ModelTag (
    model_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    PRIMARY KEY (model_id, tag_id),
    FOREIGN KEY (model_id) REFERENCES Model(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES Tag(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Collection (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    filter_query TEXT,
    is_smart INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS Setting (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE INDEX IF NOT EXISTS IX_Model_Title ON Model(title);
CREATE INDEX IF NOT EXISTS IX_ModelFile_ModelId ON ModelFile(model_id);
CREATE INDEX IF NOT EXISTS IX_Asset_ModelId ON Asset(model_id);
CREATE INDEX IF NOT EXISTS IX_Tag_Name ON Tag(name);
";
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        await cmd.ExecuteNonQueryAsync(ct);
    }
}