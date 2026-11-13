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