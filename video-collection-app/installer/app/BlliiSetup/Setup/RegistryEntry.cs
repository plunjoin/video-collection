using Microsoft.Win32;
using System.IO;

namespace Bllii.Setup.Setup;

internal static class RegistryEntry
{
    /// <summary>沿用 Inno 时期的 AppId，保证「设置 → 应用」里只有一条 Bllii。</summary>
    private const string AppId = "{D377B73F-9109-4DF5-B86B-13AC76CD699F}";
    private const string KeyPath = $@"Software\Microsoft\Windows\CurrentVersion\Uninstall\{AppId}_is1";

    public static string DisplayVersion =>
        typeof(RegistryEntry).Assembly.GetName().Version?.ToString(3) ?? "1.0.1";

    public static void Write(string appDir)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath, writable: true);
            if (key is null) return;

            var exe = Path.Combine(appDir, Shortcuts.ExeName);
            var uninstaller = Path.Combine(appDir, UninstallEngine.UninstallerName);

            key.SetValue("DisplayName", "Bllii", RegistryValueKind.String);
            key.SetValue("DisplayVersion", DisplayVersion, RegistryValueKind.String);
            key.SetValue("Publisher", "Bllii", RegistryValueKind.String);
            key.SetValue("DisplayIcon", exe, RegistryValueKind.String);
            key.SetValue("InstallLocation", appDir, RegistryValueKind.String);
            key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"), RegistryValueKind.String);
            key.SetValue("UninstallString", $"\"{uninstaller}\" --uninstall", RegistryValueKind.String);
            key.SetValue("QuietUninstallString", $"\"{uninstaller}\" --uninstall --silent", RegistryValueKind.String);
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            key.SetValue("EstimatedSize", EstimateSizeKb(appDir), RegistryValueKind.DWord);
        }
        catch (Exception ex)
        {
            Log.Write("写入卸载信息失败", ex);
        }
    }

    public static void Delete()
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(KeyPath, throwOnMissingSubKey: false);
        }
        catch (Exception ex)
        {
            Log.Write("移除卸载信息失败", ex);
        }
    }

    private static int EstimateSizeKb(string appDir)
    {
        try
        {
            var bytes = Directory
                .EnumerateFiles(appDir, "*", SearchOption.AllDirectories)
                .Sum(path =>
                {
                    try { return new FileInfo(path).Length; }
                    catch { return 0L; }
                });
            return (int)Math.Clamp(bytes / 1024, 1, int.MaxValue);
        }
        catch
        {
            return 1;
        }
    }
}
