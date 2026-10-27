using System.Diagnostics;
using System.IO;

namespace Bllii.Setup.Setup;

public static class UninstallEngine
{
    public const string UninstallerName = "BlliiUninstall.exe";

    /// <summary>已知可能存放本地数据的位置（精确名，避免误删）。</summary>
    private static IEnumerable<string> DataCandidates()
    {
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        yield return Path.Combine(roaming, "video_collection_app");
        yield return Path.Combine(local, "video_collection_app");
        yield return Path.Combine(roaming, "Bllii");
        yield return Path.Combine(local, "Bllii");
        yield return Path.Combine(roaming, "com.example", "video_collection_app");
    }

    public static void Remove(
        string appDir,
        bool removeData,
        IProgress<SetupProgress>? progress)
    {
        appDir = Path.GetFullPath(appDir);
        Log.Write($"开始卸载 {appDir}");

        progress?.Report(new SetupProgress(3, 0, "检查应用文件"));
        Shortcuts.CloseRunningApp();
        var self = Environment.ProcessPath ?? string.Empty;

        var files = SafeFiles(appDir);
        var total = Math.Max(1, files.Count);
        var done = 0;

        foreach (var file in files)
        {
            if (string.Equals(file, self, StringComparison.OrdinalIgnoreCase)) continue;
            TryDelete(file);
            done++;
            progress?.Report(new SetupProgress(10 + (int)(68.0 * done / total), 1, Path.GetFileName(file)));
        }

        foreach (var dir in SafeDirectories(appDir).OrderByDescending(path => path.Length))
        {
            try { Directory.Delete(dir, recursive: false); }
            catch { /* 非空或占用，留给清理进程 */ }
        }

        progress?.Report(new SetupProgress(84, 2, "移除快捷方式"));
        Shortcuts.DeleteAll();

        progress?.Report(new SetupProgress(88, 2, removeData ? "清理本地数据" : "保留本地数据"));
        if (removeData) RemoveData();

        progress?.Report(new SetupProgress(94, 2, "移除卸载信息"));
        RegistryEntry.Delete();

        progress?.Report(new SetupProgress(100, 2, "完成"));
        Log.Write("卸载完成");
    }

    private static void RemoveData()
    {
        foreach (var path in DataCandidates())
        {
            try
            {
                if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
            }
            catch (Exception ex)
            {
                Log.Write($"删除本地数据失败：{path}", ex);
            }
        }
    }

    private static List<string> SafeFiles(string appDir)
    {
        try
        {
            return Directory.Exists(appDir)
                ? Directory.EnumerateFiles(appDir, "*", SearchOption.AllDirectories).ToList()
                : new List<string>();
        }
        catch (Exception ex)
        {
            Log.Write("枚举安装目录失败", ex);
            return new List<string>();
        }
    }

    private static List<string> SafeDirectories(string appDir)
    {
        try
        {
            return Directory.Exists(appDir)
                ? Directory.EnumerateDirectories(appDir, "*", SearchOption.AllDirectories).ToList()
                : new List<string>();
        }
        catch
        {
            return new List<string>();
        }
    }

    private static void TryDelete(string path)
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                var attributes = File.GetAttributes(path);
                if (attributes.HasFlag(FileAttributes.ReadOnly))
                    File.SetAttributes(path, attributes & ~FileAttributes.ReadOnly);
                File.Delete(path);
                return;
            }
            catch (Exception ex) when (attempt == 2)
            {
                Log.Write($"删除文件失败：{path}", ex);
            }
            catch
            {
                Thread.Sleep(120);
            }
        }
    }

    /// <summary>
    /// 卸载器就在待删目录里，自己删不掉自己：
    /// 复制到临时目录重启一份，由它等待本进程退出后清空目录并自删。
    /// </summary>
    public static void HandOffToCleanup(string appDir)
    {
        var self = Environment.ProcessPath;
        if (string.IsNullOrEmpty(self) || !File.Exists(self))
        {
            Log.Write("无法定位卸载器自身，跳过清理进程");
            return;
        }

        try
        {
            var temp = Path.Combine(Path.GetTempPath(), $"bllii-uninstall-{Guid.NewGuid():N}.exe");
            File.Copy(self, temp, overwrite: true);
            Process.Start(new ProcessStartInfo
            {
                FileName = temp,
                Arguments = $"--cleanup --dir=\"{appDir}\" --wait-pid={Environment.ProcessId}",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetTempPath(),
            });
            Log.Write($"已启动清理进程 {temp}");
        }
        catch (Exception ex)
        {
            Log.Write("启动清理进程失败", ex);
        }
    }
}

internal static class CleanupRunner
{
    public static void Run(LaunchOptions options)
    {
        var appDir = options.TargetDir;
        if (string.IsNullOrWhiteSpace(appDir)) return;

        WaitFor(options.WaitPid);
        Log.Write($"清理进程开始处理 {appDir}");

        for (var attempt = 0; attempt < 30; attempt++)
        {
            try
            {
                if (Directory.Exists(appDir)) Directory.Delete(appDir, recursive: true);
                break;
            }
            catch (Exception ex)
            {
                if (attempt == 29) Log.Write("清理安装目录失败", ex);
                Thread.Sleep(300);
            }
        }

        ScheduleSelfDelete(Environment.ProcessPath);
    }

    private static void WaitFor(int pid)
    {
        if (pid <= 0) return;
        try
        {
            var process = Process.GetProcessById(pid);
            process.WaitForExit(15000);
        }
        catch
        {
            // 进程已经退出
        }
    }

    private static void ScheduleSelfDelete(string? self)
    {
        if (string.IsNullOrEmpty(self)) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c ping -n 3 127.0.0.1 >nul & del /f /q \"{self}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            });
        }
        catch
        {
            // 删不掉就留个临时文件，不影响功能
        }
    }
}

internal static class SilentRunner
{
    public static int Install(LaunchOptions options)
    {
        try
        {
            var target = options.TargetDir ?? InstallEngine.DefaultTarget;
            InstallEngine.Install(target, options.DesktopShortcut, null, CancellationToken.None);
            if (options.LaunchAfterInstall) LaunchApp(target);
            return 0;
        }
        catch (Exception ex)
        {
            Log.Write("静默安装失败", ex);
            return 1;
        }
    }

    public static int Uninstall(LaunchOptions options)
    {
        try
        {
            var target = options.TargetDir ?? InstallEngine.DefaultTarget;
            UninstallEngine.Remove(target, options.RemoveData, null);
            UninstallEngine.HandOffToCleanup(target);
            return 0;
        }
        catch (Exception ex)
        {
            Log.Write("静默卸载失败", ex);
            return 1;
        }
    }

    public static void LaunchApp(string appDir)
    {
        try
        {
            var exe = Path.Combine(appDir, Shortcuts.ExeName);
            if (!File.Exists(exe)) return;
            Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = appDir });
        }
        catch (Exception ex)
        {
            Log.Write("启动 Bllii 失败", ex);
        }
    }
}
