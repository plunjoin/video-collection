using System.Diagnostics;
using System.IO;

namespace Bllii.Setup.Setup;

internal static class Shortcuts
{
    public const string AppName = "Bllii";
    public const string ExeName = "video_collection_app.exe";

    private static string StartMenuPrograms => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Microsoft", "Windows", "Start Menu", "Programs");

    private static string Desktop => Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);

    public static string StartMenuLink => Path.Combine(StartMenuPrograms, $"{AppName}.lnk");
    public static string DesktopLink => Path.Combine(Desktop, $"{AppName}.lnk");

    public static void CreateAll(string appDir, bool desktop)
    {
        Create(StartMenuLink, appDir);
        if (desktop) Create(DesktopLink, appDir);
    }

    public static void DeleteAll()
    {
        TryDelete(StartMenuLink);
        TryDelete(DesktopLink);
    }

    private static void Create(string linkPath, string appDir)
    {
        var target = Path.Combine(appDir, ExeName);
        if (!File.Exists(target))
        {
            Log.Write($"跳过快捷方式：目标不存在 {target}");
            return;
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(linkPath)!);
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type is null) throw new InvalidOperationException("WScript.Shell 不可用");

            dynamic shell = Activator.CreateInstance(type)!;
            dynamic link = shell.CreateShortcut(linkPath);
            link.TargetPath = target;
            link.WorkingDirectory = appDir;
            link.IconLocation = target + ",0";
            link.Description = "Bllii · More Stories, Together";
            link.WindowStyle = 1;
            link.Save();
        }
        catch (Exception ex)
        {
            // 快捷方式失败不该让整个安装失败
            Log.Write($"创建快捷方式失败：{linkPath}", ex);
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception ex)
        {
            Log.Write($"删除快捷方式失败：{path}", ex);
        }
    }

    /// <summary>结束正在运行的应用，避免卸载时文件占用。</summary>
    public static void CloseRunningApp()
    {
        try
        {
            foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(ExeName)))
            {
                try
                {
                    if (process.MainWindowHandle != IntPtr.Zero) process.CloseMainWindow();
                    if (!process.WaitForExit(2500)) process.Kill(entireProcessTree: true);
                }
                catch (Exception ex)
                {
                    Log.Write($"结束进程失败：{process.ProcessName}", ex);
                }
            }
        }
        catch (Exception ex)
        {
            Log.Write("查找运行中的 Bllii 失败", ex);
        }
    }
}
