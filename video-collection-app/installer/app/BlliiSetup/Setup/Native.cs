using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Bllii.Setup.Setup;

internal static class Native
{
    private const int DwmwaWindowCornerPreference = 33;
    private const int DwmwcpRound = 2;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>Windows 11 上给无边框窗口加原生圆角（Win10 上自动忽略）。</summary>
    public static void RoundCorners(Window window)
    {
        try
        {
            var handle = new WindowInteropHelper(window).Handle;
            if (handle == IntPtr.Zero) return;
            var preference = DwmwcpRound;
            DwmSetWindowAttribute(handle, DwmwaWindowCornerPreference, ref preference, sizeof(int));
        }
        catch
        {
            // 老系统没有这个 API，保持直角即可
        }
    }
}
