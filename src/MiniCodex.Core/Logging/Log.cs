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