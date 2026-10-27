using System.Windows;
using System.Windows.Threading;
using Bllii.Setup.Setup;

namespace Bllii.Setup;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += OnUnhandled;
        var options = LaunchOptions.Parse(e.Args);

        switch (options.Mode)
        {
            case LaunchMode.Cleanup:
                CleanupRunner.Run(options);
                Shutdown(0);
                return;

            case LaunchMode.Install when options.Silent:
                Shutdown(SilentRunner.Install(options));
                return;

            case LaunchMode.Uninstall when options.Silent:
                Shutdown(SilentRunner.Uninstall(options));
                return;
        }

        var window = new MainWindow(options);
        MainWindow = window;
        window.Show();
    }

    private void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        Log.Write("UI 线程异常", e.Exception);
        MessageBox.Show(
            $"安装程序遇到意外错误，请重试或联系支持。\n\n{e.Exception.Message}",
            "Bllii",
            MessageBoxButton.OK,
            MessageBoxImage.Warning);
        e.Handled = true;
        Shutdown(1);
    }
}
