using System.IO;

namespace Bllii.Setup.Setup;

public enum LaunchMode
{
    Install,
    Uninstall,
    Cleanup,
}

/// <summary>安装器的命令行参数。</summary>
public sealed class LaunchOptions
{
    public LaunchMode Mode { get; private init; } = LaunchMode.Install;
    public bool Silent { get; private init; }
    public string? TargetDir { get; private init; }
    public bool DesktopShortcut { get; private init; } = true;
    public bool LaunchAfterInstall { get; private init; } = true;
    public bool RemoveData { get; private init; }
    public int WaitPid { get; private init; }

    public static LaunchOptions Parse(string[] args)
    {
        var mode = LaunchMode.Install;
        var silent = false;
        string? dir = null;
        var desktop = true;
        var launch = true;
        var removeData = false;
        var waitPid = 0;

        foreach (var raw in args)
        {
            var arg = raw.Trim();
            if (arg.Length == 0) continue;

            if (arg is "--uninstall" or "/uninstall") mode = LaunchMode.Uninstall;
            else if (arg is "--cleanup" or "/cleanup") mode = LaunchMode.Cleanup;
            else if (arg is "--silent" or "/silent" or "/S") silent = true;
            else if (arg is "--no-desktop") desktop = false;
            else if (arg is "--no-launch") launch = false;
            else if (arg is "--remove-data") removeData = true;
            else if (arg.StartsWith("--dir=", StringComparison.OrdinalIgnoreCase)) dir = arg[6..].Trim('"');
            else if (arg.StartsWith("--wait-pid=", StringComparison.OrdinalIgnoreCase)
                     && int.TryParse(arg[11..], out var pid)) waitPid = pid;
        }

        return new LaunchOptions
        {
            Mode = mode,
            Silent = silent,
            TargetDir = string.IsNullOrWhiteSpace(dir) ? null : dir,
            DesktopShortcut = desktop,
            LaunchAfterInstall = launch,
            RemoveData = removeData,
            WaitPid = waitPid,
        };
    }
}

public sealed record SetupProgress(int Percent, int Stage, string Detail);

public static class Log
{
    public static readonly string FilePath =
        Path.Combine(Path.GetTempPath(), "bllii-setup.log");

    public static void Write(string message, Exception? error = null)
    {
        try
        {
            var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}";
            if (error is not null) line += Environment.NewLine + error;
            File.AppendAllText(FilePath, line + Environment.NewLine);
        }
        catch
        {
            // 日志写不进去不影响安装
        }
    }
}
