import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_state_provider.dart';
import '../theme/app_colors.dart';
import 'brand_widgets.dart';
import 'member_avatar.dart';

const sidebarExpandedWidth = 256.0;
const sidebarCollapsedWidth = 64.0;

/// 桌面侧栏，布局对齐 entropy-ui Sidebar：品牌行、搜索、导航、底部账号卡，可收成图标轨。
class EntropySidebar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onAccount;
  final ValueChanged<double>? onWidthChanged;

  const EntropySidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onSearch,
    required this.onSettings,
    required this.onAccount,
    this.onWidthChanged,
  });

  @override
  State<EntropySidebar> createState() => _EntropySidebarState();
}

class _EntropySidebarState extends State<EntropySidebar> {
  static const _nav = [
    _NavEntry(0, Icons.home_outlined, Icons.home_rounded, '首页'),
    _NavEntry(1, Icons.grid_view_outlined, Icons.grid_view_rounded, '番剧分类'),
    _NavEntry(
      2,
      Icons.emoji_events_outlined,
      Icons.emoji_events_rounded,
      '热度排行',
    ),
    _NavEntry(
      3,
      Icons.calendar_month_outlined,
      Icons.calendar_month_rounded,
      '更新时间表',
    ),
    _NavEntry(4, Icons.person_outline_rounded, Icons.person_rounded, '个人中心'),
  ];

  bool _collapsed = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final collapsed = prefs.getBool('sidebar_collapsed') ?? false;
    setState(() {
      _collapsed = collapsed;
      _ready = true;
    });
    widget.onWidthChanged?.call(
      collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
    );
  }

  Future<void> _toggle() async {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    widget.onWidthChanged?.call(
      next ? sidebarCollapsedWidth : sidebarExpandedWidth,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sidebar_collapsed', next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFF1F5F9);
    final card = isDark ? const Color(0xFF131B2E) : Colors.white;
    final app = context.watch<AppStateProvider>();
    return AnimatedContainer(
      duration: _ready ? const Duration(milliseconds: 280) : Duration.zero,
      curve: Curves.easeInOut,
      width: _collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: card,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB),
          ),
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
          maxWidth: _collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
          child: SizedBox(
            width: _collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
            child: Column(
              children: [
                _BrandRow(
                  collapsed: _collapsed,
                  borderColor: border,
                  onToggle: _toggle,
                ),
                _SearchSlot(collapsed: _collapsed, onSearch: widget.onSearch),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      _collapsed ? 8 : 12,
                      12,
                      _collapsed ? 8 : 12,
                      12,
                    ),
                    children: [
                      for (final item in _nav) ...[
                        _NavButton(
                          entry: item,
                          selected: widget.currentIndex == item.index,
                          collapsed: _collapsed,
                          onTap: () => widget.onSelect(item.index),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
                _UserCard(
                  collapsed: _collapsed,
                  borderColor: border,
                  app: app,
                  onOpen: () {
                    if (app.isLoggedIn) {
                      widget.onSelect(4);
                    } else {
                      widget.onAccount();
                    }
                  },
                  onSettings: widget.onSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavEntry {
  final int index;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavEntry(this.index, this.icon, this.activeIcon, this.label);
}

class _BrandRow extends StatelessWidget {
  final bool collapsed;
  final Color borderColor;
  final VoidCallback onToggle;

  const _BrandRow({
    required this.collapsed,
    required this.borderColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF94A3B8);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: collapsed
          ? Center(
              child: _HoverSwapButton(
                tooltip: '打开边栏',
                onTap: onToggle,
                hoverChild: Icon(
                  Icons.view_sidebar_outlined,
                  size: 20,
                  color: ink,
                ),
                child: const BrandLogo(symbolOnly: true, width: 32),
              ),
            )
          : Row(
              children: [
                const BrandLogo(symbolOnly: true, width: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'bllii',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: ink,
                        ),
                      ),
                      Text(
                        'More Stories',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onToggle,
                  tooltip: '收起边栏',
                  icon: Icon(
                    Icons.view_sidebar_outlined,
                    size: 20,
                    color: muted,
                  ),
                ),
              ],
            ),
    );
  }
}

class _HoverSwapButton extends StatefulWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final Widget hoverChild;

  const _HoverSwapButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
    required this.hoverChild,
  });

  @override
  State<_HoverSwapButton> createState() => _HoverSwapButtonState();
}

class _HoverSwapButtonState extends State<_HoverSwapButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: _hover
              ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _hover ? 0 : 1,
                    child: widget.child,
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: _hover ? 1 : 0,
                    child: widget.hoverChild,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchSlot extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onSearch;

  const _SearchSlot({required this.collapsed, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : const Color(0xFF94A3B8);
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: _RoundIconButton(
          tooltip: '搜索番剧 (Ctrl+K)',
          icon: Icons.search_rounded,
          onTap: onSearch,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Material(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onSearch,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 16, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '搜索番剧...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Ctrl+K',
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final _NavEntry entry;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  const _NavButton({
    required this.entry,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark
        ? AppColors.primary600.withValues(alpha: 0.22)
        : const Color(0xFFEFF6FF);
    final activeFg = isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D68FE);
    final idle = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final hoverBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final background = widget.selected
        ? activeBg
        : _hover
        ? hoverBg
        : Colors.transparent;
    final color = widget.selected
        ? activeFg
        : _hover
        ? ink
        : idle;
    final icon = Icon(
      widget.selected ? widget.entry.activeIcon : widget.entry.icon,
      size: 18,
      color: color,
    );
    final button = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: background,
        shape: widget.collapsed ? const CircleBorder() : null,
        borderRadius: widget.collapsed ? null : BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onTap,
          customBorder: widget.collapsed ? const CircleBorder() : null,
          borderRadius: widget.collapsed ? null : BorderRadius.circular(8),
          child: widget.collapsed
              ? SizedBox(width: 40, height: 40, child: icon)
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: widget.selected ? activeFg : ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
    if (!widget.collapsed) return button;
    return Center(
      child: Tooltip(message: widget.entry.label, child: button),
    );
  }
}

class _UserCard extends StatelessWidget {
  final bool collapsed;
  final Color borderColor;
  final AppStateProvider app;
  final VoidCallback onOpen;
  final VoidCallback onSettings;

  const _UserCard({
    required this.collapsed,
    required this.borderColor,
    required this.app,
    required this.onOpen,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = app.user;
    final nickname = user?['nickname']?.toString().trim();
    final username = user?['username']?.toString() ?? '';
    final name = app.isLoggedIn
        ? (nickname != null && nickname.isNotEmpty ? nickname : username)
        : '登录 / 注册';
    final subtitle = app.isLoggedIn ? '@$username' : '登录后同步追番';
    final avatar = user?['avatar']?.toString() ?? '';
    final frame = user?['decorations']?['frame']?.toString() ?? '';
    return Container(
      padding: EdgeInsets.all(collapsed ? 8 : 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: collapsed
          ? Center(
              child: Tooltip(
                message: name,
                child: InkWell(
                  onTap: onOpen,
                  customBorder: const CircleBorder(),
                  child: MemberAvatar(avatar: avatar, frame: frame, size: 40),
                ),
              ),
            )
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      MemberAvatar(avatar: avatar, frame: frame, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '设置',
                        onPressed: onSettings,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        icon: Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 18,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
