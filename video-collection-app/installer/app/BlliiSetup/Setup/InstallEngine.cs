using System.IO.Compression;
using System.Reflection;
using System.IO;

namespace Bllii.Setup.Setup;

public static class InstallEngine
{
    public static string DefaultTarget => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Programs", "Bllii");

    /// <summary>解包 + 建快捷方式 + 写卸载信息。整体 0–100 的进度由 SetupProgress 汇报。</summary>
    public static void Install(
        string targetDir,
        bool desktopShortcut,
        IProgress<SetupProgress>? progress,
        CancellationToken cancellationToken)
    {
        targetDir = Path.GetFullPath(targetDir);
        Log.Write($"开始安装到 {targetDir}");

        progress?.Report(new SetupProgress(1, 0, "准备安装目录"));
        EnsureWritable(targetDir);
        // 覆盖安装时先让旧实例退出，否则文件会被占用
        Shortcuts.CloseRunningApp();

        using var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip")
                            ?? throw new InvalidOperationException("安装载荷缺失，请重新获取安装包。");
        using var archive = new ZipArchive(payload, ZipArchiveMode.Read);

        var entries = archive.Entries.Where(entry => !string.IsNullOrEmpty(entry.Name)).ToList();
        var totalBytes = entries.Sum(entry => Math.Max(1L, entry.Length));
        long copied = 0;

        foreach (var entry in entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destination = Path.Combine(targetDir, entry.FullName.Replace('/', '\\'));
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            entry.ExtractToFile(destination, overwrite: true);

            copied += Math.Max(1L, entry.Length);
            var percent = 8 + (int)(84.0 * copied / totalBytes);
            progress?.Report(new SetupProgress(Math.Min(92, percent), 1, entry.Name));
        }

        progress?.Report(new SetupProgress(93, 2, "创建应用入口"));
        Shortcuts.CreateAll(targetDir, desktopShortcut);

        progress?.Report(new SetupProgress(96, 2, "写入卸载信息"));
        DeployUninstaller(targetDir);
        RegistryEntry.Write(targetDir);

        progress?.Report(new SetupProgress(100, 2, "完成"));
        Log.Write("安装完成");
    }

    /// <summary>写一个探针文件确认目录可写，把「权限不足」提前暴露成友好错误。</summary>
    private static void EnsureWritable(string targetDir)
    {
        try
        {
            Directory.CreateDirectory(targetDir);
            var probe = Path.Combine(targetDir, $".bllii-{Guid.NewGuid():N}.tmp");
            File.WriteAllText(probe, "probe");
            File.Delete(probe);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException)
        {
            throw new UnauthorizedAccessException("无法写入所选安装目录，请更换位置或检查权限。", ex);
        }
    }

    private static void DeployUninstaller(string targetDir)
    {
        var destination = Path.Combine(targetDir, UninstallEngine.UninstallerName);
        using var stub = Assembly.GetExecutingAssembly().GetManifestResourceStream("BlliiUninstall.exe");
        if (stub is null)
        {
            Log.Write("卸载器资源缺失，跳过部署");
            return;
        }

        using var file = File.Create(destination);
        stub.CopyTo(file);
    }

    public static bool IsValidTarget(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        var value = path.Trim();
        if (value.Length < 4 || value.Length > 180) return false;
        if (value[1] != ':' || value[2] != '\\') return false;
        if (!char.IsLetter(value[0])) return false;
        if (value.IndexOfAny(new[] { '<', '>', '"', '|', '?', '*' }) >= 0) return false;

        foreach (var part in value[3..].Split('\\', StringSplitOptions.RemoveEmptyEntries))
        {
            if (part.Length == 0) continue;
            if (part.EndsWith(' ') || part.EndsWith('.')) return false;
            var bare = part.Split('.')[0];
            if (bare.Equals("con", StringComparison.OrdinalIgnoreCase)
                || bare.Equals("prn", StringComparison.OrdinalIgnoreCase)
                || bare.Equals("aux", StringComparison.OrdinalIgnoreCase)
                || bare.Equals("nul", StringComparison.OrdinalIgnoreCase)) return false;
        }

        return true;
    }
}
