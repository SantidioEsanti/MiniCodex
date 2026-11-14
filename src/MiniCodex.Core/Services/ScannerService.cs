using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using MiniCodex.Core.Logging;
using MiniCodex.Core.Models;
using MiniCodex.Core.Repositories;

namespace MiniCodex.Core.Services;

public class ScannerService : IScannerService
{
    private const long MaxFileSizeBytes = 2L * 1024L * 1024L * 1024L;
    private const int GcEveryNFiles = 10;

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
                        existing.FileHash = ComputeSha256(filePath);
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
                            FileHash = ComputeSha256(filePath),
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

            if (state.ProcessedFiles % GcEveryNFiles == 0)
            {
                try
                {
                    GC.Collect(GC.MaxGeneration, GCCollectionMode.Optimized, blocking: false);
                }
                catch { }
                Log.Info("[Scanner] GC after " + state.ProcessedFiles + " files mem=" + Log.MemoryMb() + "MB");
            }
        }

        Log.Info("[Scanner] SCAN DONE added=" + state.Added + " updated=" + state.Updated + " skipped=" + state.Skipped + " errors=" + state.Errors + " mem=" + Log.MemoryMb() + "MB");
    }

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