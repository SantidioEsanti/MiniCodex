using MiniCodex.Data.Migrations;

namespace MiniCodex.Data;

public static class DatabaseInitializer
{
    public static IReadOnlyList<IMigration> Migrations { get; } = new IMigration[]
    {
        new Migration_0001_InitialSchema(),
        new Migration_0002_ModelFile_LastWriteTime(),
        new Migration_0003_ModelOrientation(),
        new Migration_0004_ModelFile_Hash(),
        new Migration_0005_Collection_Color(),
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