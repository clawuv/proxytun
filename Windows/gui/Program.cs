using Avalonia;
using System;
using System.Threading;

namespace ProxyTun.GUI;

class Program
{
    private static Mutex? _instanceMutex;
    private const string MutexName = "Global\\ProxyTun_SingleInstance_Mutex_v1";
    private const string EventName = "Global\\ProxyTun_ShowWindow_Event_v1";

    [STAThread]
    public static void Main(string[] args)
    {
        _instanceMutex = new Mutex(true, MutexName, out bool isNewInstance);

        if (!isNewInstance)
        {
            SignalExistingInstance();
            return;
        }

        try
        {
            App.StartMinimized = args.Length > 0 && args[0] == "--minimized";
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        finally
        {
            _instanceMutex?.ReleaseMutex();
            _instanceMutex?.Dispose();
        }
    }

    private static void SignalExistingInstance()
    {
        try
        {
            using var showEvent = EventWaitHandle.OpenExisting(EventName);
            showEvent.Set();
        }
        catch { }
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
