using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using Bllii.Setup.Setup;

namespace Bllii.Setup;

public partial class MainWindow : Window
{
    private readonly LaunchOptions _options;
    private readonly bool _uninstallMode;
    private string _targetDir;
    private bool _busy;
    private bool _finished;
    private bool _allowClose;
    private bool _removeData;
    private bool _cleanupStarted;
    private string[] _stageCaptions = Array.Empty<string>();
    private string[] _stageLabels = Array.Empty<string>();
    private string[] _stageDetails = Array.Empty<string>();

    public MainWindow(LaunchOptions options)
    {
        InitializeComponent();

        _options = options;
        _uninstallMode = options.Mode == LaunchMode.Uninstall;
        _targetDir = options.TargetDir ?? InstallEngine.DefaultTarget;

        PathInput.Text = _targetDir;
        ChkDesktop.IsChecked = options.DesktopShortcut;
        ChkLaunch.IsChecked = options.LaunchAfterInstall;
        PathInput.TextChanged += (_, _) => ClearPathError();

        ApplyFlow();
        ShowPage(_uninstallMode ? PageUninstall : PageInstallWelcome, animate: false);
        Loaded += OnWindowLoaded;
        SourceInitialized += (_, _) => Native.RoundCorners(this);
    }

    private void OnWindowLoaded(object sender, RoutedEventArgs e)
    {
        // 品牌标志缓慢浮动
        var floatAnimation = new DoubleAnimationUsingKeyFrames
        {
            Duration = TimeSpan.FromSeconds(6),
            RepeatBehavior = RepeatBehavior.Forever,
        };
        var ease = new SineEase { EasingMode = EasingMode.EaseInOut };
        floatAnimation.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.Zero)));
        floatAnimation.KeyFrames.Add(new EasingDoubleKeyFrame(-9, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(3)))
        {
            EasingFunction = ease,
        });
        floatAnimation.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(6)))
        {
            EasingFunction = ease,
        });
        LogoFloat.BeginAnimation(TranslateTransform.YProperty, floatAnimation);
    }

    // ================= 流程外观 =================

    private void ApplyFlow()
    {
        WindowTitle.Text = _uninstallMode ? "Bllii 卸载程序" : "Bllii 安装程序";
        Title = WindowTitle.Text;
        FooterLabel.Text = _uninstallMode ? "尊重你的每一次选择" : "为当前用户安装";

        if (_uninstallMode)
        {
            BrandGlow.Fill = (Brush)FindResource("UninstallPanelGlow");
            BrandHeading.Inlines.Clear();
            BrandHeading.Inlines.Add(new System.Windows.Documents.Run("故事有暂停，"));
            BrandHeading.Inlines.Add(new System.Windows.Documents.LineBreak());
            BrandHeading.Inlines.Add(new System.Windows.Documents.Run("热爱不散场。"));
            BrandDescription.Text = "每一次相遇，都值得好好说再见。";
        }
        else
        {
            BrandGlow.Fill = (Brush)FindResource("BrandPanelGlow");
            BrandHeading.Inlines.Clear();
            BrandHeading.Inlines.Add(new System.Windows.Documents.Run("让每个故事，"));
            BrandHeading.Inlines.Add(new System.Windows.Documents.LineBreak());
            BrandHeading.Inlines.Add(new System.Windows.Documents.Run("生动一点。"));
            BrandDescription.Text = "把热爱留在身边，把精彩交给 Bllii。";
        }
    }

    private void ShowPage(FrameworkElement page, bool animate = true)
    {
        foreach (var candidate in new FrameworkElement[] { PageInstallWelcome, PageUninstall, PageProgress, PageSuccess, PageError })
        {
            candidate.Visibility = ReferenceEquals(candidate, page) ? Visibility.Visible : Visibility.Collapsed;
        }

        if (ReferenceEquals(page, PageProgress)) StartSpinner();
        else StopSpinner();

        if (!animate) return;

        page.BeginAnimation(OpacityProperty, null);
        page.Opacity = 0;
        var offset = new TranslateTransform(0, 6);
        page.RenderTransform = offset;

        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        page.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(280)) { EasingFunction = ease });
        offset.BeginAnimation(TranslateTransform.YProperty,
            new DoubleAnimation(6, 0, TimeSpan.FromMilliseconds(280)) { EasingFunction = ease });
    }

    private void StartSpinner()
    {
        ArcRotate.BeginAnimation(RotateTransform.AngleProperty,
            new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1.15)) { RepeatBehavior = RepeatBehavior.Forever });
    }

    private void StopSpinner() => ArcRotate.BeginAnimation(RotateTransform.AngleProperty, null);

    // ================= 安装 =================

    private async void OnInstallClick(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        var target = PathInput.Text.Trim();
        if (!InstallEngine.IsValidTarget(target))
        {
            PathError.Visibility = Visibility.Visible;
            PathField.BorderBrush = new SolidColorBrush(Color.FromRgb(0xD7, 0x85, 0x90));
            PathInput.Focus();
            return;
        }

        ClearPathError();
        _targetDir = target;
        await RunInstallAsync();
    }

    private void ClearPathError()
    {
        PathError.Visibility = Visibility.Collapsed;
        PathField.BorderBrush = new SolidColorBrush(Color.FromRgb(0xE6, 0xE8, 0xF1));
    }

    private async Task RunInstallAsync()
    {
        var desktop = ChkDesktop.IsChecked == true;
        var launch = ChkLaunch.IsChecked == true;

        _busy = true;
        _stageCaptions = new[] { "正在准备安装文件", "正在安装 Bllii", "正在完成最后的配置" };
        _stageLabels = new[] { "准备文件", "安装应用", "完成配置" };
        _stageDetails = new[] { "准备安装目录", "正在写入客户端文件", "正在配置应用入口" };
        PrepareProgressPage(isInstall: true, removeData: false);
        ShowPage(PageProgress);

        var watch = Stopwatch.StartNew();
        var progress = new Progress<SetupProgress>(ApplyProgress);

        try
        {
            await Task.Run(() => InstallEngine.Install(_targetDir, desktop, progress, CancellationToken.None));
            await KeepVisibleFor(watch, 1600);
            ShowSuccess(install: true, desktop: desktop, launch: launch, removeData: false);
        }
        catch (Exception ex)
        {
            Log.Write("安装失败", ex);
            ShowError(install: true, ex);
        }
        finally
        {
            _busy = false;
        }
    }

    // ================= 卸载 =================

    private void OnKeepClick(object sender, RoutedEventArgs e) => Close();

    private void OnUninstallClick(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (RadioRemove.IsChecked == true)
        {
            ShowDialog(
                "同时清除本地数据？",
                "本地设置、登录状态和观看记录将一并删除。此操作无法撤销。",
                ("返回", false, () => { }),
                ("清除并卸载", true, async () => await RunUninstallAsync(removeData: true)));
            return;
        }

        _ = RunUninstallAsync(removeData: false);
    }

    private async Task RunUninstallAsync(bool removeData)
    {
        _busy = true;
        _removeData = removeData;
        _stageCaptions = new[]
        {
            "正在检查运行状态",
            "正在移除应用文件",
            removeData ? "正在清除本地数据" : "正在保留本地数据",
        };
        _stageLabels = new[]
        {
            "检查应用",
            "移除文件",
            removeData ? "清理数据" : "保留数据",
        };
        _stageDetails = new[]
        {
            "检查应用文件",
            "正在移除客户端文件",
            removeData ? "清理设置与观看记录" : "保留设置与观看记录",
        };

        PrepareProgressPage(isInstall: false, removeData: removeData);
        ShowPage(PageProgress);

        var watch = Stopwatch.StartNew();
        var progress = new Progress<SetupProgress>(ApplyProgress);

        try
        {
            var dir = _targetDir;
            await Task.Run(() => UninstallEngine.Remove(dir, removeData, progress));
            // 文件已清空，立刻交接给清理进程：它等本窗口退出后再删目录与自身
            UninstallEngine.HandOffToCleanup(dir);
            _cleanupStarted = true;
            await KeepVisibleFor(watch, 1500);
            ShowSuccess(install: false, desktop: false, launch: false, removeData: removeData);
        }
        catch (Exception ex)
        {
            Log.Write("卸载失败", ex);
            ShowError(install: false, ex);
        }
        finally
        {
            _busy = false;
        }
    }

    // ================= 进度 =================

    private void PrepareProgressPage(bool isInstall, bool removeData)
    {
        ProgressKicker.Text = isInstall ? "GETTING EVERYTHING READY" : "TAKING CARE OF THE DETAILS";
        ProgressHeading.Text = isInstall ? "好故事，即将开场。" : "正在轻轻地告别。";
        ProgressDescription.Text = isInstall ? "正在为你准备桌面上的新伙伴，请稍候。" : "正在移除应用文件，请保持窗口开启。";
        ProgressNote.Text = isInstall
            ? "精彩正在路上，马上就好。"
            : removeData ? "正在按你的选择清除本地数据。" : "你的本地数据会被妥善保留。";

        Bar.Value = 0;
        ProgressPercent.Text = "0%";
        ProgressCaption.Text = _stageCaptions[0];
        ProgressFile.Text = _stageDetails[0];
        UpdateSteps(0);
    }

    private void ApplyProgress(SetupProgress report)
    {
        Bar.Value = report.Percent;
        ProgressPercent.Text = $"{report.Percent}%";

        var stage = Math.Clamp(report.Stage, 0, 2);
        ProgressCaption.Text = _stageCaptions[stage];
        ProgressFile.Text = string.IsNullOrWhiteSpace(report.Detail) ? _stageDetails[stage] : report.Detail;
        UpdateSteps(stage);
    }

    private void UpdateSteps(int active)
    {
        var icons = new[] { StepIcon0, StepIcon1, StepIcon2 };
        var texts = new[] { StepText0, StepText1, StepText2 };
        var done = new SolidColorBrush(Color.FromRgb(0x8A, 0x7B, 0xC1));
        var idle = new SolidColorBrush(Color.FromRgb(0xA5, 0xA8, 0xB9));

        for (var index = 0; index < 3; index++)
        {
            icons[index].Kind = index < active ? Controls.IconKind.Check : Controls.IconKind.Desktop;
            var brush = index <= active ? done : idle;
            icons[index].Stroke = brush;
            texts[index].Foreground = brush;
            texts[index].Text = _stageLabels[index];
        }
    }

    private static async Task KeepVisibleFor(Stopwatch watch, int minimumMilliseconds)
    {
        var remaining = minimumMilliseconds - (int)watch.ElapsedMilliseconds;
        if (remaining > 0) await Task.Delay(remaining);
    }

    // ================= 结果页 =================

    private void ShowSuccess(bool install, bool desktop, bool launch, bool removeData)
    {
        _finished = true;

        if (install)
        {
            SuccessKicker.Text = "READY FOR YOUR NEXT STORY";
            SuccessHeading.Text = "准备好了，开场吧！";
            SuccessDescription.Text = "Bllii 已准备就绪，新的故事正等着你。";
            SuccessNoteIcon.Kind = Controls.IconKind.Desktop;
            SuccessNoteTitle.Text = desktop ? "桌面见，我们的故事继续。" : "下一段精彩，随时开启。";
            SuccessNoteBody.Text = desktop ? "双击桌面上的 Bllii，即可再次打开。" : "可以从开始菜单打开 Bllii。";
            FinishLabel.Text = launch ? "开启 Bllii" : "完成安装";
            FinishIcon.Kind = launch ? Controls.IconKind.Arrow : Controls.IconKind.Check;
            SuccessNote.Text = "More Stories, Together";
        }
        else
        {
            SuccessKicker.Text = "THANK YOU FOR THE GOOD TIMES";
            SuccessHeading.Text = "已卸载，后会有期。";
            SuccessDescription.Text = "Bllii 已从这台电脑移除。谢谢你曾经的陪伴。";
            SuccessNoteIcon.Kind = removeData ? Controls.IconKind.Check : Controls.IconKind.Folder;
            SuccessNoteTitle.Text = removeData ? "本地数据已清除" : "本地数据已保留";
            SuccessNoteBody.Text = removeData
                ? "此电脑上的设置、登录状态与观看记录已删除。"
                : "下次安装时，可继续使用原有设置与观看记录。";
            FinishLabel.Text = "完成卸载";
            FinishIcon.Kind = Controls.IconKind.Check;
            SuccessNote.Text = "愿你的下一个故事，同样精彩。";
        }

        ShowPage(PageSuccess);
    }

    private void ShowError(bool install, Exception error)
    {
        _finished = false;
        ErrorHeading.Text = install ? "安装遇到一点小插曲。" : "暂时还不能完成卸载。";

        if (error is UnauthorizedAccessException)
        {
            ErrorTitle.Text = install ? "暂时无法写入安装目录" : "Bllii 的部分文件正在使用中";
            ErrorBody.Text = install ? "请检查文件夹的写入权限，或更换一个安装位置。" : "请先关闭正在运行的 Bllii，再重试卸载。";
        }
        else
        {
            ErrorTitle.Text = install ? "安装没有完成" : "卸载没有完成";
            ErrorBody.Text = error.Message;
        }

        ErrorStepA.Text = install ? "1. 确认所选磁盘有足够的可用空间。" : "1. 保存当前进度，并退出 Bllii。";
        ErrorStepB.Text = install ? "2. 关闭占用安装文件夹的应用后重试。" : "2. 关闭可能占用应用文件的其他窗口。";
        BtnErrorBack.Content = install ? "更改位置" : "返回";
        RetryLabel.Text = install ? "重试安装" : "重试卸载";
        ErrorNote.Text = install ? "你的安装选项已保留" : "卸载选项已保留，可以稍后继续";

        ShowPage(PageError);
    }

    // ================= 按钮 =================

    private void OnBrowseClick(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "选择安装位置",
            Multiselect = false,
        };

        try
        {
            var current = PathInput.Text.Trim();
            if (InstallEngine.IsValidTarget(current)) dialog.InitialDirectory = current;
        }
        catch
        {
            // 初始目录无效就用系统默认
        }

        if (dialog.ShowDialog(this) == true && !string.IsNullOrWhiteSpace(dialog.FolderName))
        {
            PathInput.Text = Path.Combine(dialog.FolderName, "Bllii");
            ClearPathError();
        }
    }

    private void OnFinishClick(object sender, RoutedEventArgs e)
    {
        if (_uninstallMode)
        {
            if (!_cleanupStarted) UninstallEngine.HandOffToCleanup(_targetDir);
            _allowClose = true;
            Close();
            return;
        }

        if (ChkLaunch.IsChecked == true) SilentRunner.LaunchApp(_targetDir);
        _allowClose = true;
        Close();
    }

    private void OnErrorBackClick(object sender, RoutedEventArgs e)
    {
        ShowPage(_uninstallMode ? PageUninstall : PageInstallWelcome);
    }

    private void OnErrorRetryClick(object sender, RoutedEventArgs e)
    {
        if (_uninstallMode) _ = RunUninstallAsync(_removeData);
        else _ = RunInstallAsync();
    }

    private void OnMinimizeClick(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnCloseClick(object sender, RoutedEventArgs e) => RequestClose();

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            RequestClose();
            return;
        }

        base.OnClosing(e);
    }

    private void RequestClose()
    {
        if (_busy)
        {
            ShowDialog("正在处理文件", "请等待当前步骤完成，窗口会自动继续。", ("好", false, () => { }));
            return;
        }

        if (_finished)
        {
            _allowClose = true;
            Close();
            return;
        }

        var installing = !_uninstallMode;
        ShowDialog(
            installing ? "暂时不安装？" : "取消卸载？",
            installing ? "关闭安装向导后，你可以随时重新开始。" : "Bllii 会继续留在你的电脑上。",
            (installing ? "继续安装" : "继续卸载", false, () => { }),
            (installing ? "退出安装" : "保留 Bllii", true, () =>
            {
                _allowClose = true;
                Close();
            }));
    }

    // ================= 自绘对话框 =================

    private void ShowDialog(string title, string body, params (string Label, bool Primary, Action Action)[] actions)
    {
        DialogTitle.Text = title;
        DialogBody.Text = body;
        DialogActions.Children.Clear();

        foreach (var (label, primary, action) in actions)
        {
            var button = new Button
            {
                Content = label,
                MinWidth = 92,
                Margin = new Thickness(10, 0, 0, 0),
                Style = (Style)FindResource(primary ? "PrimaryButton" : "SecondaryButton"),
            };
            button.Click += (_, _) =>
            {
                HideDialog();
                action();
            };
            DialogActions.Children.Add(button);
        }

        ContentRoot.Effect = new BlurEffect { Radius = 4, KernelType = KernelType.Gaussian };
        Overlay.Visibility = Visibility.Visible;
    }

    private void HideDialog()
    {
        Overlay.Visibility = Visibility.Collapsed;
        ContentRoot.Effect = null;
    }
}
