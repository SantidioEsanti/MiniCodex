using System;
using System.IO;

namespace MiniCodex.App.Services;

public class AppPaths
{
    public string Root { get; }
    public string DataDir => Path.Combine(Root, "data");
    public string LibraryDb => Path.Combine(DataDir, "library.db");
    public string CacheDir => Path.Combine(DataDir, "cache", "previews");
    public string AssetsDir => Path.Combine(DataDir, "assets");
    public string LangDir { get; }

    public AppPaths()
    {
        Root = AppContext.BaseDirectory;

        var candidate = Path.Combine(Root, "lang");
        if (!Directory.Exists(candidate))
        {
            var repoLang = Path.Combine(Root, "..", "..", "..", "..", "..", "lang");
            repoLang = Path.GetFullPath(repoLang);
            if (Directory.Exists(repoLang)) candidate = repoLang;
        }
        LangDir = candidate;
    }

    public void EnsureCreated()
    {
        Directory.CreateDirectory(DataDir);
        Directory.CreateDirectory(CacheDir);
        Directory.CreateDirectory(AssetsDir);
        if (!File.Exists(LibraryDb)) File.WriteAllBytes(LibraryDb, Array.Empty<byte>());
    }
}