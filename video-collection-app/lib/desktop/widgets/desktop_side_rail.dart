import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/services/api_service.dart';
import '../pages/history_center_desktop_page.dart';
import '../pages/profile_edit_desktop_page.dart';
import '../pages/timeline_desktop_page.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/episode_selector.dart' show formatAudienceCount;
import '../../shared/widgets/member_avatar.dart';

const sidebarExpandedWidth = 256.0;

/// 桌面侧栏：个人资料卡 + 菜单分组（我的空间 / 发现 / 个人设置）。
class DesktopSideRail extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSettings;
  final VoidCallback onAccount;

  const DesktopSideRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onSettings,
    required this.onAccount,
  });

  @override
  State<DesktopSideRail> createState() => _DesktopSideRailState();
}

class _DesktopSideRailState extends State<DesktopSideRail> {
  int _points = 0;
  bool _pointsForLoggedIn = false;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshPointsIfNeeded();
  }

  /// 积分只在登录状态变化后刷新一次，避免每次重建都打接口。
  void _refreshPointsIfNeeded() {
    final loggedIn = context.read<AppStateProvider>().isLoggedIn;
    if (loggedIn == _pointsForLoggedIn) return;
    _pointsForLoggedIn = loggedIn;
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    if (!mounted) return;
    if (!context.read<AppStateProvider>().isLoggedIn) {
      if (_points != 0) setState(() => _points = 0);
      return;
    }
    try {
      final res = await _apiService.userRequest('/api/user/points');
      if (!mounted) return;
      setState(() => _points = _parsePoints(res));
    } catch (_) {
      // 积分拉取失败时静默保持 0，不影响侧栏其它信息
    }
  }

  static int _parsePoints(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is! Map) return 0;
    final wallet = data['wallet'];
    if (wallet is! Map) return 0;
    return int.tryParse(wallet['balance']?.toString() ?? '') ?? 0;
  }

  void _openProfileEditor() {
    final app = context.read<AppStateProvider>();
    if (app.isLoggedIn) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileEditDesktopPage()),
      );
    } else {
      widget.onAccount();
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryCenterDesktopPage()),
    );
  }

  void _openTimeline() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TimelineDesktopPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF131B2E) : Colors.white;
    return Container(
      width: sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: card,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _ProfileCard(
            isDark: isDark,
            points: _points,
            onEditProfile: _openProfileEditor,
          ),
          const SizedBox(height: 16),
          _MenuSection(
            isDark: isDark,
            currentIndex: widget.currentIndex,
            title: '我的空间',
            items: [
              _SidebarMenu(
                icon: BIcons.heart,
                label: '我的追番',
                tab: 4,
                onTap: () => widget.onSelect(4),
              ),
              _SidebarMenu(
                icon: BIcons.history,
                label: '观看历史',
                onTap: _openHistory,
              ),
              _SidebarMenu(
                icon: BIcons.user,
                label: '账号与积分',
                onTap: widget.onAccount,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MenuSection(
            isDark: isDark,
            currentIndex: widget.currentIndex,
            title: '发现',
            items: [
              _SidebarMenu(
                icon: BIcons.grid,
                label: '番剧分类',
                tab: 1,
                onTap: () => widget.onSelect(1),
              ),
              _SidebarMenu(
                icon: BIcons.rank,
                label: '热度排行',
                tab: 2,
                onTap: () => widget.onSelect(2),
              ),
              _SidebarMenu(
                icon: BIcons.calendar,
                label: '新番时间表',
                onTap: _openTimeline,
              ),
              _SidebarMenu(
                icon: BIcons.forum,
                label: '资讯社区',
                tab: 3,
                onTap: () => widget.onSelect(3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MenuSection(
            isDark: isDark,
            currentIndex: widget.currentIndex,
            title: '个人设置',
            items: [
              _SidebarMenu(
                icon: BIcons.settings,
                label: '偏好设置',
                onTap: widget.onSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 个人资料卡
// ---------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  final bool isDark;
  final int points;
  final VoidCallback onEditProfile;

  const _ProfileCard({
    required this.isDark,
    required this.points,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppStateProvider>();
    final user = app.user;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final cardBg = isDark ? const Color(0xFF182238) : const Color(0xFFF6F8FF);

    final nickname = app.isLoggedIn
        ? (user?['nickname']?.toString().trim().isNotEmpty == true
              ? user!['nickname'].toString()
              : user?['username']?.toString() ?? '未命名旅人')
        : '未登录';
    final bio = app.isLoggedIn
        ? (user?['bio']?.toString().trim().isNotEmpty == true
              ? user!['bio'].toString().trim()
              : '记录生活，也记录灵感')
        : '登录后同步追番与播放历史';
    final avatar = user?['avatar']?.toString() ?? '';
    final frame = user?['decorations']?['frame']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MemberAvatar(avatar: avatar, frame: frame, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _RailStat(
                isDark: isDark,
                value: formatAudienceCount(app.favoriteVideos.length),
                label: '追番',
              ),
              _RailStat(
                isDark: isDark,
                value: formatAudienceCount(app.playHistory.length),
                label: '足迹',
              ),
              _RailStat(
                isDark: isDark,
                value: app.isLoggedIn ? formatAudienceCount(points) : '—',
                label: '积分',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _EditProfileButton(
            isDark: isDark,
            label: app.isLoggedIn ? '编辑资料' : '登录 / 注册',
            onTap: onEditProfile,
          ),
        ],
      ),
    );
  }
}

class _RailStat extends StatelessWidget {
  final bool isDark;
  final String value;
  final String label;

  const _RailStat({
    required this.isDark,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 10, color: muted)),
        ],
      ),
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  final bool isDark;
  final String label;
  final VoidCallback onTap;

  const _EditProfileButton({
    required this.isDark,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? const Color(0xFF93C5FD) : AppColors.primary600;
    return Container(
        decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(19)),
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ),
      );
  }
}

// ---------------------------------------------------------------------------
// 菜单分组
// ---------------------------------------------------------------------------

class _SidebarMenu {
  final BrandIconData icon;
  final String label;
  final VoidCallback onTap;

  /// 与主框架 Tab 对应的项会参与选中态高亮；弹页类菜单不高亮。
  final int? tab;

  const _SidebarMenu({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tab,
  });
}

class _MenuSection extends StatelessWidget {
  final bool isDark;
  final int currentIndex;
  final String title;
  final List<_SidebarMenu> items;

  const _MenuSection({
    required this.isDark,
    required this.currentIndex,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: muted,
            ),
          ),
        ),
        for (final item in items)
          _MenuButton(
            isDark: isDark,
            item: item,
            selected: item.tab != null && currentIndex == item.tab,
          ),
      ],
    );
  }
}

class _MenuButton extends StatefulWidget {
  final bool isDark;
  final _SidebarMenu item;
  final bool selected;

  const _MenuButton({
    required this.isDark,
    required this.item,
    required this.selected,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    // 悬停只加深文字颜色、不铺背景块:背景块与选中胶囊叠在一起
    // 反而显得脏;可点击性由手型光标 + 颜色变化表达。
    final activeBg = isDark
        ? AppColors.primary600.withValues(alpha: 0.22)
        : const Color(0xFFEFF6FF);
    final activeFg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D68FE);
    final foreground = widget.selected
        ? activeFg
        : _hover
        ? ink
        : muted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.item.onTap,
        borderRadius: BorderRadius.circular(10),
        // 关掉 InkWell 自带的淡紫悬停覆盖:菜单项的悬停反馈
        // 只用文字变色表达,不再出现整行背景块。
        hoverColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              BrandIcon(
                widget.item.icon,
                size: 20,
                color: foreground,
                monochrome: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
