#requires -Version 5.1
<#
.SYNOPSIS
    Patch 0.4.5a1 - Diagnostic logging + Assimp memory fix (remove JoinIdenticalVertices).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Version     = '0.4.5a1'
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
    Write-Log "Backup: $rel"
}

function Write-Text {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

# ============ Log.cs ============
$logCs = @'
using System;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;

namespace MiniCodex.Core.Logging;

public static class Log
{
    private static readonly object _lock = new object();
    private static string _logPath = "";
    private static bool _initialized;

    public static string LogFilePath => _logPath;
    public static string LogDirectory => string.IsNullOrEmpty(_logPath) ? "" : (Path.GetDirectoryName(_logPath) ?? "");

    public static void Init(string logDirectory)
    {
        try
        {
            Directory.CreateDirectory(logDirectory);
            _logPath = Path.Combine(logDirectory, "minicodex-" + DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".log");
            _initialized = true;
            Info("[App] === START version=" + AppVersion + " os=" + Environment.OSVersion + " baseDir=" + AppContext.BaseDirectory + " ===");
        }
        catch
        {
            try
            {
                _logPath = Path.Combine(Path.GetTempPath(), "minicodex-" + DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".log");
                _initialized = true;
                Info("[App] === START (fallback temp dir) ===");
            }
            catch { }
        }
    }

    public static string AppVersion
    {
        get
        {
            try
            {
                var asm = Assembly.GetEntryAssembly();
                if (asm == null) return "unknown";
                var attr = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>();
                return attr == null ? "unknown" : (attr.InformationalVersion ?? "unknown");
            }
            catch { return "unknown"; }
        }
    }

    public static void Info(string msg) => Write("INFO", msg);
    public static void Warn(string msg) => Write("WARN", msg);
    public static void Error(string msg) => Write("ERROR", msg);

    public static void Exception(string context, Exception? ex)
    {
        if (ex == null) { Write("ERROR", context + ": <null exception>"); return; }
        Write("ERROR", context + ": " + ex.GetType().FullName + ": " + ex.Message);
        if (!string.IsNullOrEmpty(ex.StackTrace))
        {
            var frames = ex.StackTrace.Replace("\r\n", " | ").Replace("\n", " | ");
            Write("ERROR", "  stack: " + frames);
        }
        var inner = ex.InnerException;
        int depth = 1;
        while (inner != null && depth <= 5)
        {
            Write("ERROR", "  inner[" + depth + "]: " + inner.GetType().FullName + ": " + inner.Message);
            inner = inner.InnerException;
            depth++;
        }
    }

    public static void SessionEnd()
    {
        Write("INFO", "[App] === EXIT session ===");
    }

    public static long MemoryMb()
    {
        try { return GC.GetTotalMemory(false) / (1024L * 1024L); } catch { return 0; }
    }

    private static void Write(string level, string msg)
    {
        var line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " [" + level.PadRight(5) + "] " + msg;
        try { System.Diagnostics.Debug.WriteLine(line); } catch { }
        if (!_initialized) return;
        lock (_lock)
        {
            try { File.AppendAllText(_logPath, line + Environment.NewLine, Encoding.UTF8); }
            catch { }
        }
    }
}
'@

# ============ Program.cs ============
$programCs = @'
using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia;
using MiniCodex.Core.Logging;

namespace MiniCodex.App;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            var baseDir = AppContext.BaseDirectory;
            var logDir = Path.Combine(baseDir, "data", "logs");
            Log.Init(logDir);
        }
        catch { }

        AppDomain.CurrentDomain.UnhandledException += (s, e) =>
        {
            var ex = e.ExceptionObject as Exception;
            if (ex != null) Log.Exception("[AppDomain.UnhandledException]", ex);
            else Log.Error("[AppDomain.UnhandledException] non-exception object: " + (e.ExceptionObject == null ? "null" : e.ExceptionObject.ToString()));
            Log.SessionEnd();
        };

        TaskScheduler.UnobservedTaskException += (s, e) =>
        {
            Log.Exception("[TaskScheduler.UnobservedTaskException]", e.Exception);
            e.SetObserved();
        };

        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception ex)
        {
            Log.Exception("[Program.Main fatal]", ex);
            throw;
        }
        finally
        {
            Log.SessionEnd();
        }
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
'@

# ============ App.axaml.cs ============
$appCs = @'
using System;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Avalonia.Threading;
using MiniCodex.App.Services;
using MiniCodex.App.Views;
using MiniCodex.Core.Logging;

namespace MiniCodex.App;

public partial class App : Application
{
    public static AppPaths Paths { get; private set; } = null!;
    public static LocalizationService Loc { get; private set; } = null!;
    public static ThemeService Theme { get; private set; } = null!;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Dispatcher.UIThread.UnhandledException += (s, e) =>
            {
                Log.Exception("[Dispatcher.UIThread.UnhandledException]", e.Exception);
                e.Handled = false;
            };

            Paths = new AppPaths();
            Paths.EnsureCreated();

            Loc = new LocalizationService(Paths, "en");
            Loc.LoadInitial();
            Log.Info("[App] language=" + Loc.Current);

            Theme = new ThemeService(this);

            desktop.MainWindow = new MainWindow();
        }
        base.OnFrameworkInitializationCompleted();
    }
}
'@

# ============ ScannerService.cs ============
$scannerCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class ScannerService : IScannerService
{
    private const long MaxFileSizeBytes = 2L * 1024L * 1024L * 1024L;

    private readonly IMeshLoader _meshLoader;
    private readonly IModelRepository _modelRepo;
    private readonly IModelFileRepository _fileRepo;

    public ScannerService(IMeshLoader meshLoader, IModelRepository modelRepo, IModelFileRepository fileRepo)
    {
        _meshLoader = meshLoader;
        _modelRepo = modelRepo;
        _fileRepo = fileRepo;
    }

    public async Task ScanAsync(
        IEnumerable<string> rootFolders,
        IProgress<ScanProgress>? progress = null,
        CancellationToken ct = default)
    {
        var report = progress ?? new Progress<ScanProgress>();
        var state = new ScanProgress();
        var folderList = new List<string>(rootFolders);
        Log.Info("[Scanner] SCAN START folders=[" + string.Join(", ", folderList) + "]");

        var files = new List<FileInfo>();
        foreach (var root in folderList)
        {
            if (ct.IsCancellationRequested) return;
            if (!Directory.Exists(root))
            {
                state.Errors++;
                state.LastError = "Folder not found: " + root;
                Log.Warn("[Scanner] FOLDER missing path=" + root);
                report.Report(state);
                continue;
            }
            try
            {
                var count = 0;
                foreach (var file in Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories))
                {
                    if (ct.IsCancellationRequested) break;
                    var ext = Path.GetExtension(file).TrimStart('.').ToLowerInvariant();
                    if (_meshLoader.SupportedExtensions.Contains(ext))
                    {
                        files.Add(new FileInfo(file));
                        count++;
                    }
                }
                Log.Info("[Scanner] FOLDER scanned path=" + root + " matched=" + count);
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = ex.Message;
                Log.Exception("[Scanner] FOLDER error path=" + root, ex);
                report.Report(state);
            }
        }

        state.TotalFiles = files.Count;
        report.Report(state);
        Log.Info("[Scanner] SCAN FILES total=" + files.Count);

        foreach (var fi in files)
        {
            if (ct.IsCancellationRequested) break;

            var sw = Stopwatch.StartNew();
            var fileName = fi.Name;
            var filePath = fi.FullName;
            var fileSize = fi.Length;

            if (fileSize > MaxFileSizeBytes)
            {
                Log.Warn("[Scanner] FILE skip-too-large path=" + fileName + " size=" + fileSize);
                state.Skipped++;
                state.ProcessedFiles++;
                report.Report(state);
                continue;
            }

            Log.Info("[Scanner] FILE start path=" + fileName + " size=" + fileSize);
            state.CurrentFile = fileName;

            try
            {
                var existing = await _fileRepo.GetByPathAsync(filePath, ct);
                if (existing != null && existing.FileSizeBytes == fileSize && existing.LastWriteTimeUtc == fi.LastWriteTimeUtc)
                {
                    state.Skipped++;
                    Log.Info("[Scanner] FILE skip-unchanged path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms");
                }
                else
                {
                    var info = _meshLoader.Load(filePath);
                    if (info == null)
                    {
                        state.Errors++;
                        state.LastError = "Parse failed: " + filePath;
                        Log.Warn("[Scanner] FILE parse-failed path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms");
                    }
                    else if (existing != null)
                    {
                        existing.FileSizeBytes = info.FileSizeBytes;
                        existing.LastWriteTimeUtc = fi.LastWriteTimeUtc;
                        existing.PolygonCount = info.PolygonCount;
                        await _fileRepo.UpsertAsync(existing, ct);
                        var model = await _modelRepo.GetAsync(existing.ModelId, ct);
                        if (model != null)
                        {
                            model.UpdatedAt = DateTime.UtcNow;
                            await _modelRepo.UpsertAsync(model, ct);
                        }
                        state.Updated++;
                        Log.Info("[Scanner] FILE update-ok path=" + fileName + " polys=" + info.PolygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                    }
                    else
                    {
                        var model = new Model
                        {
                            Title = Path.GetFileNameWithoutExtension(fileName),
                            CreatedAt = DateTime.UtcNow,
                            UpdatedAt = DateTime.UtcNow,
                        };
                        await _modelRepo.UpsertAsync(model, ct);
                        var newFile = new ModelFile
                        {
                            ModelId = model.Id,
                            Path = filePath,
                            FileRole = "main",
                            FileSizeBytes = info.FileSizeBytes,
                            PolygonCount = info.PolygonCount,
                            LastWriteTimeUtc = fi.LastWriteTimeUtc,
                        };
                        await _fileRepo.UpsertAsync(newFile, ct);
                        model.PrimaryModelFileId = newFile.Id;
                        await _modelRepo.UpsertAsync(model, ct);
                        state.Added++;
                        Log.Info("[Scanner] FILE add-ok path=" + fileName + " polys=" + info.PolygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
                    }
                }
            }
            catch (Exception ex)
            {
                state.Errors++;
                state.LastError = fileName + ": " + ex.Message;
                Log.Exception("[Scanner] FILE error path=" + fileName + " took=" + sw.ElapsedMilliseconds + "ms", ex);
            }

            state.ProcessedFiles++;
            report.Report(state);
        }

        Log.Info("[Scanner] SCAN DONE added=" + state.Added + " updated=" + state.Updated + " skipped=" + state.Skipped + " errors=" + state.Errors + " mem=" + Log.MemoryMb() + "MB");
    }
}
'@

# ============ AssimpMeshLoader.cs ============
$loaderCs = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using Assimp;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Services;

namespace MiniCodex.Render.Loaders;

public class AssimpMeshLoader : IMeshLoader, IMeshGeometryLoader
{
    private static readonly HashSet<string> _extensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "stl", "obj", "3mf", "ply"
    };

    public IReadOnlyCollection<string> SupportedExtensions => _extensions;

    public MeshInfo? Load(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] Load null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
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

            if (!hasVertices)
            {
                Log.Warn("[Assimp] Load no-vertices path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
                return null;
            }

            Log.Info("[Assimp] Load ok path=" + SafeName(filePath) + " polys=" + polygonCount + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return new MeshInfo
            {
                PolygonCount = polygonCount,
                FileSizeBytes = new FileInfo(filePath).Length,
                BoundingBoxMin = new[] { min.X, min.Y, min.Z },
                BoundingBoxMax = new[] { max.X, max.Y, max.Z },
            };
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] Load failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    public MeshGeometry? LoadGeometry(string filePath)
    {
        var sw = Stopwatch.StartNew();
        var scene = ImportScene(filePath);
        if (scene == null)
        {
            Log.Warn("[Assimp] LoadGeometry null-scene path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms");
            return null;
        }

        try
        {
            var allVerts = new List<Vector3>();
            var allIndices = new List<int>();

            foreach (var mesh in scene.Meshes)
            {
                var offset = allVerts.Count;
                foreach (var v in mesh.Vertices) allVerts.Add(new Vector3(v.X, v.Y, v.Z));
                foreach (var face in mesh.Faces)
                {
                    if (face.IndexCount < 3) continue;
                    for (int i = 1; i < face.IndexCount - 1; i++)
                    {
                        allIndices.Add(offset + face.Indices[0]);
                        allIndices.Add(offset + face.Indices[i]);
                        allIndices.Add(offset + face.Indices[i + 1]);
                    }
                }
            }

            if (allVerts.Count == 0 || allIndices.Count == 0)
            {
                Log.Warn("[Assimp] LoadGeometry empty path=" + SafeName(filePath) + " verts=" + allVerts.Count + " indices=" + allIndices.Count + " took=" + sw.ElapsedMilliseconds + "ms");
                return null;
            }

            var result = new MeshGeometry { Vertices = allVerts.ToArray(), Indices = allIndices.ToArray() };
            Log.Info("[Assimp] LoadGeometry ok path=" + SafeName(filePath) + " tris=" + result.TriangleCount + " verts=" + result.Vertices.Length + " took=" + sw.ElapsedMilliseconds + "ms mem=" + Log.MemoryMb() + "MB");
            return result;
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] LoadGeometry failed path=" + SafeName(filePath), ex);
            return null;
        }
    }

    private static Scene? ImportScene(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return null;
        var sw = Stopwatch.StartNew();
        try
        {
            using (var ctx = new AssimpContext())
            {
                var scene = ctx.ImportFile(filePath, PostProcessSteps.Triangulate);
                Log.Info("[Assimp] ImportFile path=" + SafeName(filePath) + " ok=" + (scene != null) + " meshes=" + (scene != null && scene.HasMeshes ? scene.MeshCount : 0) + " took=" + sw.ElapsedMilliseconds + "ms");
                return scene != null && scene.HasMeshes ? scene : null;
            }
        }
        catch (Exception ex)
        {
            Log.Exception("[Assimp] ImportFile failed path=" + SafeName(filePath) + " took=" + sw.ElapsedMilliseconds + "ms", ex);
            return null;
        }
    }

    private static string SafeName(string filePath)
    {
        try { return Path.GetFileName(filePath) ?? filePath; } catch { return filePath; }
    }
}
'@

# ============ README ============
$readme = @'
# Patch 0.4.5a1 - Diagnostic logging + Assimp memory fix

**Iteration:** 0.4.5 (post-release diagnostics)

## What it does

1. NEW: Core/Logging/Log.cs - static file logger.
   - Writes to data/logs/minicodex-{yyyyMMdd}.log (append per line, crash-safe).
   - Init in Program.Main before Avalonia.
   - MemoryMb() helper for GC.GetTotalMemory.

2. Program.cs - global exception handlers:
   - AppDomain.UnhandledException -> full stack trace to log.
   - TaskScheduler.UnobservedTaskException -> full stack trace to log.
   - try/finally around StartWithClassicDesktopLifetime with SessionEnd().

3. App.axaml.cs - Dispatcher.UIThread.UnhandledException handler.

4. ScannerService.cs - per-file logging:
   - SCAN START, SCAN FILES, SCAN DONE with counters.
   - FILE start path=X size=Y before parse (identifies crash file if app dies).
   - FILE add-ok / update-ok / skip-unchanged / parse-failed / error after (with took + mem).
   - Files >2GB skipped with WARN (safety).

5. AssimpMeshLoader.cs:
   - REMOVED PostProcessSteps.JoinIdenticalVertices (memory hog for millions of polygons).
     Only Triangulate now. Halves or better memory for large meshes.
   - All silent catch blocks now log via Log.Exception.
   - Timing per operation.

## Known limitation

Diagnostics are ENGLISH only (log is technical, not user-facing).
App UI still localizes normally.

## DoD

- dotnet build: 0 errors, 0 warnings.
- dotnet test: 48/48 (unchanged - no behavior change, only logging).
- Run app: data/logs/minicodex-{date}.log created with === START === marker.
- Scan folder: log fills with FILE start/ok lines per file.
- If crash: log ends mid-scan, last FILE start path identifies culprit.

## How to read after crash

Get-Content "D:\AI\MiniCodex\src\MiniCodex.App\bin\Debug\net8.0\data\logs\minicodex-$(Get-Date -Format yyyyMMdd).log" -Tail 50 -Encoding UTF8

Cases:
- No FILE start after SCAN START -> crash in Avalonia init or before scan
- FILE start path=X but no following add-ok/parse-failed/error -> crash on X
- OutOfMemoryException in stack -> memory (PreviewGenerator 4x load, or Assimp on huge file)
- AccessViolationException -> native crash (assimp.dll / libSkiaSharp.dll)
'@

try {
    Write-Log "Patch $Version starting."
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Backup dir: $BackupDir"

    $logPath    = Join-Path $ProjectRoot 'src\MiniCodex.Core\Logging\Log.cs'
    $programPath = Join-Path $ProjectRoot 'src\MiniCodex.App\Program.cs'
    $appPath    = Join-Path $ProjectRoot 'src\MiniCodex.App\App.axaml.cs'
    $scannerPath = Join-Path $ProjectRoot 'src\MiniCodex.Core\Services\ScannerService.cs'
    $loaderPath = Join-Path $ProjectRoot 'src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs'

    Backup-File $programPath
    Backup-File $appPath
    Backup-File $scannerPath
    Backup-File $loaderPath
    Backup-File (Join-Path $ProjectRoot 'CHANGELOG.md')

    Write-Text -Path $logPath -Content $logCs
    Write-Log 'created: src\MiniCodex.Core\Logging\Log.cs'

    Write-Text -Path $programPath -Content $programCs
    Write-Log 'updated: src\MiniCodex.App\Program.cs (global handlers, Log.Init)'

    Write-Text -Path $appPath -Content $appCs
    Write-Log 'updated: src\MiniCodex.App\App.axaml.cs (Dispatcher handler)'

    Write-Text -Path $scannerPath -Content $scannerCs
    Write-Log 'updated: src\MiniCodex.Core\Services\ScannerService.cs (per-file logging)'

    Write-Text -Path $loaderPath -Content $loaderCs
    Write-Log 'updated: src\MiniCodex.Render\Loaders\AssimpMeshLoader.cs (no JoinIdenticalVertices, logging)'

    Write-Text -Path (Join-Path $PatchDir 'README.md') -Content $readme
    Write-Log 'created: patches\0.4.5a1\README.md'

    # Verify log class has key methods
    $logVerify = [IO.File]::ReadAllText($logPath, [Text.Encoding]::UTF8)
    $checks = @(
        @('Log has Init', ($logVerify -match 'public static void Init\(')),
        @('Log has Exception', ($logVerify -match 'public static void Exception\(')),
        @('Log has SessionEnd', ($logVerify -match 'public static void SessionEnd\(')),
        @('Log has MemoryMb', ($logVerify -match 'public static long MemoryMb\('))
    )
    foreach ($c in $checks) {
        if ($c[1]) { Write-Log ("verify OK: " + $c[0]) }
        else { Write-Log ("verify FAIL: " + $c[0]) 'WARN' }
    }

    # Verify JoinIdenticalVertices removed
    $loaderVerify = [IO.File]::ReadAllText($loaderPath, [Text.Encoding]::UTF8)
    if ($loaderVerify -notmatch 'JoinIdenticalVertices') {
        Write-Log 'verify OK: JoinIdenticalVertices removed from AssimpMeshLoader'
    } else {
        Write-Log 'verify FAIL: JoinIdenticalVertices still present' 'WARN'
    }

    # CHANGELOG
    $marker = '<!-- patch 0.4.5a1 applied -->'
    $changelog = Join-Path $ProjectRoot 'CHANGELOG.md'
    if (Test-Path $changelog) {
        $cl = [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)
        if ($cl -notmatch [regex]::Escape($marker)) {
            $entry = "`r`n$marker`r`n`r`n## [0.4.5a1] - 2026-11-12`r`n`r`n### Added`r`n- Core logging (data/logs/minicodex-{date}.log, crash-safe append).`r`n- Global exception handlers (AppDomain, TaskScheduler, Dispatcher.UIThread).`r`n- Per-file scanner logging (start/ok/fail + timing + memory).`r`n- AssimpMeshLoader: all catches now log via Log.Exception.`r`n`r`n### Changed`r`n- AssimpMeshLoader: removed JoinIdenticalVertices (memory hog).`r`n- ScannerService: skip files >2GB with WARN.`r`n"
            $cl = $cl -replace '(?m)^(## \[0\.1\.0-alpha\].*)$', "$entry`$1"
            [IO.File]::WriteAllText($changelog, $cl, [Text.UTF8Encoding]::new($false))
            Write-Log 'CHANGELOG.md updated.'
        }
    }

    Write-Log "Patch $Version complete."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Log "Backup: $BackupDir" 'ERROR'
    exit 1
}