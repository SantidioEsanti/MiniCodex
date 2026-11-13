#requires -Version 5.1
<#
.SYNOPSIS
    Патч 0.2.0 — Парсеры STL/OBJ/3MF, метаданные.
.DESCRIPTION
    Добавляет AssimpNet, IMeshLoader, AssimpMeshLoader, MeshInfo.
    Тесты: ASCII STL, OBJ, обработка несуществующего/битого файла.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.2.0'
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

# ============ MiniCodex.Render.csproj (обновление) ============
# (читаем, добавляем пакет, перезаписываем)
$renderCsprojPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\MiniCodex.Render.csproj'

# ============ Render/Models/MeshInfo.cs ============
$Files['src\MiniCodex.Render\Models\MeshInfo.cs'] = @'
namespace MiniCodex.Render.Models;

public class MeshInfo
{
    public int PolygonCount { get; set; }
    public long FileSizeBytes { get; set; }
    public float[] BoundingBoxMin { get; set; } = Array.Empty<float>();
    public float[] BoundingBoxMax { get; set; } = Array.Empty<float>();

    public float SizeX => BoundingBoxMax.Length > 0 ? BoundingBoxMax[0] - BoundingBoxMin[0] : 0;
    public float SizeY => BoundingBoxMax.Length > 1 ? BoundingBoxMax[1] - BoundingBoxMin[1] : 0;
    public float SizeZ => BoundingBoxMax.Length > 2 ? BoundingBoxMax[2] - BoundingBoxMin[2] : 0;
}
'@

# ============ Render/Loaders/IMeshLoader.cs ============
$Files['src\MiniCodex.Render\Loaders\IMeshLoader.cs'] = @'
using MiniCodex.Render.Models;

namespace MiniCodex.Render.Loaders;

public interface IMeshLoader
{
    /// <summary>
    /// Загружает меш и возвращает метаданные. Возвращает null при ошибке парсинга.
    /// </summary>
    MeshInfo? Load(string filePath);

    /// <summary>
    /// Поддерживаемые расширения (без точки, в нижнем регистре): stl, obj, 3mf.
    /// </summary>
    IReadOnlyCollection<string> SupportedExtensions { get; }
}
'@

# ============ Render/Loaders/AssimpMeshLoader.cs ============
$Files['src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'] = @'
using Assimp;
using MiniCodex.Render.Models;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader
{
    private static readonly HashSet<string> _extensions = new(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;

        try
        {
            using var context = new AssimpContext();
            var scene = context.ImportFile(filePath,
                PostProcessSteps.Triangulate | PostProcessSteps.JoinIdenticalVertices);

            if (scene == null || !scene.HasMeshes) return null;

            var polygonCount = 0;
            var min = new Vector3D(float.MaxValue, float.MaxValue, float.MaxValue);
            var max = new Vector3D(float.MinValue, float.MinValue, float.MinValue);
            var hasVertices = false;

            foreach (var mesh in scene.Meshes)
            {
                polygonCount += mesh.FaceCount;
                foreach (var v in mesh.Vertices)
                {
                    hasVertices = true;
                    if (v.X < min.X) min.X = v.X;
                    if (v.Y < min.Y) min.Y = v.Y;
                    if (v.Z < min.Z) min.Z = v.Z;
                    if (v.X > max.X) max.X = v.X;
                    if (v.Y > max.Y) max.Y = v.Y;
                    if (v.Z > max.Z) max.Z = v.Z;
                }
            }

            if (!hasVertices) return null;

            return new MeshInfo
            {
                PolygonCount = polygonCount,
                FileSizeBytes = new FileInfo(filePath).Length,
                BoundingBoxMin = new[] { min.X, min.Y, min.Z },
                BoundingBoxMax = new[] { max.X, max.Y, max.Z },
            };
        }
        catch
        {
            // Битый файл — возвращаем null, сканер зафиксирует parse_failed
            return null;
        }
    }
}
'@

# ============ Tests/Render/MeshLoaderTests.cs ============
$Files['src\MiniCodex.Tests\Render\MeshLoaderTests.cs'] = @'
using MiniCodex.Render.Loaders;
using Xunit;

namespace MiniCodex.Tests.Render;

public class MeshLoaderTests
{
    private const string AsciiStl = @"solid test
  facet normal 0 0 1
    outer loop
      vertex 0 0 0
      vertex 1 0 0
      vertex 0 1 0
    endloop
  endfacet
endsolid test
";

    private const string SimpleObj = @"v 0 0 0
v 1 0 0
v 0 1 0
f 1 2 3
";

    [Fact]
    public void Load_AsciiStl_ReturnsOnePolygonAndBox()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, AsciiStl);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);

            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
            Assert.Equal(0, info.BoundingBoxMin[0], 3);
            Assert.Equal(1, info.BoundingBoxMax[0], 3);
            Assert.Equal(1, info.BoundingBoxMax[1], 3);
            Assert.Equal(0, info.BoundingBoxMin[2], 3);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_SimpleObj_ReturnsOnePolygon()
    {
        var path = Path.GetTempFileName() + ".obj";
        try
        {
            File.WriteAllText(path, SimpleObj);
            var loader = new AssimpMeshLoader();
            var info = loader.Load(path);

            Assert.NotNull(info);
            Assert.Equal(1, info!.PolygonCount);
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void Load_Nonexistent_ReturnsNull()
    {
        var loader = new AssimpMeshLoader();
        Assert.Null(loader.Load(@"C:\definitely\not\here\missing.stl"));
    }

    [Fact]
    public void Load_CorruptFile_ReturnsNull()
    {
        var path = Path.GetTempFileName() + ".stl";
        try
        {
            File.WriteAllText(path, "not a mesh at all");
            var loader = new AssimpMeshLoader();
            Assert.Null(loader.Load(path));
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
'@

# ============ README патча ============
$Files['patches\0.2.0\README.md'] = @'
# Патч 0.2.0 — Парсеры STL/OBJ/3MF, метаданные

**Итерация:** 0.2 (Сканирование и превью) · **Статус:** реализован

## Что делает

- Добавляет пакет `AssimpNet 4.1.0` в `MiniCodex.Render`.
- Создаёт `MeshInfo` (полигоны, размер файла, bounding box, SizeX/Y/Z).
- Создаёт `IMeshLoader` (интерфейс) и `AssimpMeshLoader` (реализация, поддержка stl/obj/3mf/ply).
- `AssimpMeshLoader.Load()` при битом/отсутствующем файле возвращает `null` — по ROADMAP 3.1 («битый файл → запись в лог, модель не теряется»).
- Тесты: ASCII STL, OBJ, отсутствующий файл, битый файл (4 теста).

## Запуск

powershell -ExecutionPolicy Bypass -File "D:\AI\MiniCodex\patches\0.2.0\patch_0.2.0.ps1"

## DoD

- `dotnet build src/MiniCodex.sln` — успешно.
- `dotnet test src/MiniCodex.sln` — 12 тестов (8 старых + 4 новых), все зелёные.
'@

# ============ Основной сценарий ============
try {
    Write-Log "Патч $Version стартует."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Бэкап-каталог: $BackupDir"

    Backup-File $renderCsprojPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    # --- Обновление csproj Render: добавляем AssimpNet ---
    if (Test-Path $renderCsprojPath) {
        $csproj = [IO.File]::ReadAllText($renderCsprojPath, [Text.Encoding]::UTF8)
        if ($csproj -notmatch 'AssimpNet') {
            $csproj = $csproj -replace '(<TargetFramework>net8\.0</TargetFramework>)',
                "`$1`r`n  </PropertyGroup>`r`n  <ItemGroup>`r`n    <PackageReference Include=`"AssimpNet`" Version=`"4.1.0`" />`r`n  </ItemGroup>`r`n  <PropertyGroup>"
            Write-Text -Path $renderCsprojPath -Content $csproj
            Write-Log 'updated: src\MiniCodex.Render\MiniCodex.Render.csproj (AssimpNet 4.1.0)'
        } else {
            Write-Log 'Render.csproj: AssimpNet уже подключён, пропускаю.' 'WARN'
        }
    }

    # --- Создание файлов ---
    foreach ($rel in $Files.Keys) {
        $full = Join-Path $ProjectRoot $rel
        $existed = Test-Path -LiteralPath $full
        Write-Text -Path $full -Content $Files[$rel]
        Write-Log ('{0}: {1}' -f ($(if ($existed) { 'updated' } else { 'created' })), $rel)
    }

    # --- CHANGELOG ---
    $marker = '<!-- patch 0.2.0 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`n$marker`n`n## [0.2.0] - 2026-11-10`n`n### Added`n- AssimpNet 4.1.0 в MiniCodex.Render.`n- IMeshLoader, AssimpMeshLoader (STL/OBJ/3MF/PLY).`n- MeshInfo (полигоны, размер, bounding box).`n- 4 юнит-теста парсинга.`n"
            $cl = $cl -replace '(?m)^(## \[0\.1\.1\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md: добавлена запись 0.2.0.'
        }
    }

    Write-Log "Патч $Version успешно завершён."
    Write-Log 'Следующий шаг: dotnet build + dotnet test'
}
catch {
    Write-Log "ОШИБКА: $($_.Exception.Message)" 'ERROR'
    Write-Log "Бэкап: $BackupDir" 'ERROR'
    Write-Log "Восстановление: скопируйте файлы из '$BackupDir' обратно в '$ProjectRoot'." 'ERROR'
    exit 1
}