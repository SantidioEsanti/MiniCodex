using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia;
using MiniCodex.Core.Logging;

namespace MiniCodex.App;

internal static class Program
{
    private static System.Threading.Mutex? _mutex;

    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
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

        _mutex = new System.Threading.Mutex(true, "MiniCodex_SingleInstance_Mutex", out bool createdNew);
        if (!createdNew)
        {
            Log.Warn("[Program.Main] Another instance is already running. Exiting.");
            MessageBoxW(IntPtr.Zero, "MiniCodex is already running. Please check your taskbar.", "MiniCodex", 0x00000040);
            _mutex.Dispose();
            _mutex = null;
            return;
        }

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
            if (_mutex != null)
            {
                try { _mutex.ReleaseMutex(); } catch { }
                _mutex.Dispose();
            }
        }
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}