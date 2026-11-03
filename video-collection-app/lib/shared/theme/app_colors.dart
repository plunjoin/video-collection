import '../ui/kit.dart';

class AppColors {
  static const brandGradient = LinearGradient(
    colors: [Color(0xFFFF89C7), Color(0xFF6C5CE7), Color(0xFF80B6FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// 浅色柔和彩虹渐变底衬(卡片/横幅背景使用)。
  static const brandSoftGradient = LinearGradient(
    colors: [Color(0xFFFFEFF8), Color(0xFFEEE9FF), Color(0xFFE8F1FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 深色柔和底衬。
  static const brandSoftGradientDark = LinearGradient(
    colors: [Color(0xFF34304F), Color(0xFF263650)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---- 品牌三原色(对齐 web --brand-* / Tailwind) ----
  static const Color brandBlue = Color(0xFF4B9FFF);
  static const Color brandPurple = Color(0xFF6C5CE7);
  static const Color brandPink = Color(0xFFFF89C7);
  /// 链接 / 激活态实色(web `--brand-gradient` 的实色,非彩虹渐变)。
  static const Color brandSolid = Color(0xFF3F6FD8);

  // ---- 中性墨色(对齐 web --brand-ink / --brand-muted / --brand-line) ----
  static const Color ink = Color(0xFF30364C); // 主文字
  static const Color muted = Color(0xFF6E7895); // 次要文字
  static const Color line = Color(0xFFE2E6F0); // 分隔线 / 描边

  // 主题核心色彩 (与 video-collection-web / Tailwind 严格对齐)
  static const Color primary50 = Color(0xFFF1F5FF);
  static const Color primary100 = Color(0xFFE6EDFF);
  static const Color primary200 = Color(0xFFD5E0FF);
  static const Color primary300 = Color(0xFFB6D2FF);
  static const Color primary400 = Color(0xFF80B6FF);
  static const Color primary500 = Color(0xFF4B9FFF);
  static const Color primary600 = Color(0xFF597BEA); // 已弃用,改用 brandSolid
  static const Color primary700 = Color(0xFF5265C6);
  static const Color primary800 = Color(0xFF46539C);
  static const Color primary900 = Color(0xFF353B58);

  // 二次元与流媒体质感辅助色
  static const Color gold = Color(0xFFFFA24B); // 评分、榜单第一名
  static const Color silver = Color(0xFF94A3B8); // 榜单第二名
  static const Color bronze = Color(0xFFD97706); // 榜单第三名
  static const Color rose = Color(0xFFFF89C7); // 正在热播、高能角标
  static const Color emerald = Color(0xFF10B981); // 完结、正常状态
  static const Color purple = Color(0xFF9A83FF); // 专属合集标签

  // 深色夜空主题 (Slate 系列)
  static const Color darkBg = Color(0xFF0F172A); // slate-900 极夜背景
  static const Color darkCard = Color(0xFF1E293B); // slate-800 浮层卡片
  static const Color darkBorder = Color(0xFF334155); // slate-700 细边框
  static const Color darkTextPrimary = Color(0xFFF9FAFF);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // 浅色现代主题
  static const Color lightBg = Color(0xFFF9FAFF); // slate-50
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE9EDFA); // slate-200
  static const Color lightTextPrimary = Color(0xFF353B58);
  static const Color lightTextSecondary = Color(0xFF7D88AA); // slate-500
}
