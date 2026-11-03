import '../../shared/ui/kit.dart';
import 'package:provider/provider.dart';

import '../../shared/providers/app_state_provider.dart';
import '../../shared/theme/brand_icons.dart';
import '../../shared/widgets/brand_controls.dart';
import './account_mobile_page.dart';
import './discover_mobile_page.dart';
import './growth_mobile_page.dart';
import './history_center_mobile_page.dart';
import './profile_edit_mobile_page.dart';
import './settings_mobile_page.dart';
import './timeline_mobile_page.dart';
import './watch_lobby_mobile_page.dart';

/// 功能中心：把账号、观看、社交、成长等入口分组聚合，补足页面纵深。
class ProfileHubMobilePage extends StatelessWidget {
  const ProfileHubMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final cardColor = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.line;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.muted;
    final loggedIn = context.watch<AppStateProvider>().isLoggedIn;

    final sections = [
      (
        '一起看 & 发现',
        [
          _HubEntry(
            icon: BIcons.live,
            gradient: const [Color(0xFFFF89C7), Color(0xFFF43F5E)],
            title: '一起看大厅',
            subtitle: '用房间码加入朋友的房间，进度实时同步',
            onTap: () => _push(context, const WatchLobbyMobilePage()),
          ),
          _HubEntry(
            icon: BIcons.search,
            gradient: const [Color(0xFF80B6FF), Color(0xFF597BEA)],
            title: '搜索发现',
            subtitle: '热搜词、搜索历史与快捷入口',
            onTap: () => _push(context, const DiscoverMobilePage()),
          ),
        ],
      ),
      (
        '观看与记录',
        [
          _HubEntry(
            icon: BIcons.history,
            gradient: const [Color(0xFF93C5FD), Color(0xFF60A5FA)],
            title: '观看历史中心',
            subtitle: '继续观看、按天回顾与清空管理',
            onTap: () => _push(context, const HistoryCenterMobilePage()),
          ),
          _HubEntry(
            icon: BIcons.calendar,
            gradient: const [Color(0xFFC4B5FD), Color(0xFF9A83FF)],
            title: '新番时间表',
            subtitle: '每周更新节奏一览，追番不迷路',
            onTap: () => _push(context, const TimelineMobilePage()),
          ),
        ],
      ),
      (
        '账号与成长',
        [
          if (!loggedIn)
            _HubEntry(
              icon: BIcons.user,
              gradient: const [Color(0xFF6EE7B7), Color(0xFF10B981)],
              title: '登录 / 注册',
              subtitle: '登录后同步追番、历史与一起看',
              onTap: () => _push(context, const AccountMobilePage()),
            )
          else ...[
            _HubEntry(
              icon: BIcons.user,
              gradient: const [Color(0xFF6EE7B7), Color(0xFF10B981)],
              title: '编辑资料',
              subtitle: '昵称、头像与个性签名',
              onTap: () => _push(context, const ProfileEditMobilePage()),
            ),
          ],
          _HubEntry(
            icon: BIcons.sparkles,
            gradient: const [Color(0xFFFCD34D), Color(0xFFF59E0B)],
            title: '成长中心',
            subtitle: '积分、等级与观看数据报告',
            onTap: () => _push(context, const GrowthMobilePage()),
          ),
          _HubEntry(
            icon: BIcons.settings,
            gradient: const [Color(0xFF94A3B8), Color(0xFF475569)],
            title: '设置',
            subtitle: '服务端地址、弹幕与外观偏好',
            onTap: () => _push(context, const SettingsMobilePage()),
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: pageColor,
      appBar: BrandAppBar(title: const Text('功能中心')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final section in sections) ...[
                Text(
                  section.$1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      for (final entry in section.$2)
                        _entryListTile(entry, ink, muted, borderColor),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _entryListTile(
      _HubEntry entry, Color ink, Color muted, Color borderColor) {
    return Container(
        decoration: BoxDecoration(color: Colors.transparent),
        child: InkWell(
        onTap: entry.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: borderColor.withValues(alpha: 0.6),
                width: 0.6,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: entry.gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: BrandIcon(
                  entry.icon,
                  size: 20,
                  color: Colors.white,
                  monochrome: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ],
                ),
              ),
              BrandIcon(
                BIcons.chevronRight,
                size: 16,
                color: muted,
                monochrome: true,
              ),
            ],
          ),
        ),
      ),
      );
  }
}

class _HubEntry {
  final BrandIconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubEntry({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
