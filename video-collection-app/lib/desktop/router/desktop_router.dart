/// 桌面端页面工厂与 push 助手(保持 Navigator.push,不上 GoRouter)。
library;
import '../../shared/models/video_model.dart';
import '../../shared/ui/kit.dart';
import '../pages/account_desktop_page.dart';
import '../pages/account_security_desktop_page.dart';
import '../pages/anime_detail_desktop_page.dart';
import '../pages/content_detail_desktop_page.dart';
import '../pages/discover_desktop_page.dart';
import '../pages/growth_desktop_page.dart';
import '../pages/history_center_desktop_page.dart';
import '../pages/player_desktop_page.dart';
import '../pages/profile_edit_desktop_page.dart';
import '../pages/profile_hub_desktop_page.dart';
import '../pages/reset_password_desktop_page.dart';
import '../pages/search_desktop_page.dart';
import '../pages/settings_desktop_page.dart';
import '../pages/timeline_desktop_page.dart';
import '../pages/watch_lobby_desktop_page.dart';
import '../pages/wiki_subject_desktop_page.dart';

class DesktopRouter {
  DesktopRouter._();

  static Widget search() => const SearchDesktopPage();
  static Widget settings() => const SettingsDesktopPage();
  static Widget account() => const AccountDesktopPage();
  static Widget accountSecurity() => const AccountSecurityDesktopPage();
  static Widget resetPassword() => const ResetPasswordDesktopPage();
  static Widget animeDetail({required int videoId}) =>
      AnimeDetailDesktopPage(videoId: videoId);
  static Widget player({
    required VideoRecord video,
    int initialGroupIndex = 0,
    int initialEpisodeIndex = 0,
    Duration initialPosition = Duration.zero,
    String? watchRoomCode,
  }) =>
      PlayerDesktopPage(
        video: video,
        initialGroupIndex: initialGroupIndex,
        initialEpisodeIndex: initialEpisodeIndex,
        initialPosition: initialPosition,
        watchRoomCode: watchRoomCode,
      );
  static Widget contentDetail({required String kind, required int contentId}) =>
      ContentDetailDesktopPage(kind: kind, contentId: contentId);
  static Widget wikiSubject({required int subjectId}) =>
      WikiSubjectDesktopPage(subjectId: subjectId);
  static Widget historyCenter() => const HistoryCenterDesktopPage();
  static Widget timeline() => const TimelineDesktopPage();
  static Widget profileEdit() => const ProfileEditDesktopPage();
  static Widget profileHub() => const ProfileHubDesktopPage();
  static Widget growth() => const GrowthDesktopPage();
  static Widget discover() => const DiscoverDesktopPage();
  static Widget watchLobby() => const WatchLobbyDesktopPage();

  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  static Future<T?> pushSearch<T>(BuildContext context) =>
      push(context, search());
  static Future<T?> pushSettings<T>(BuildContext context) =>
      push(context, settings());
  static Future<T?> pushAccount<T>(BuildContext context) =>
      push(context, account());
  static Future<T?> pushAnimeDetail<T>(BuildContext context, int videoId) =>
      push(context, animeDetail(videoId: videoId));
  static Future<T?> pushPlayer<T>(
    BuildContext context, {
    required VideoRecord video,
    int initialGroupIndex = 0,
    int initialEpisodeIndex = 0,
    Duration initialPosition = Duration.zero,
    String? watchRoomCode,
  }) =>
      push(
        context,
        player(
          video: video,
          initialGroupIndex: initialGroupIndex,
          initialEpisodeIndex: initialEpisodeIndex,
          initialPosition: initialPosition,
          watchRoomCode: watchRoomCode,
        ),
      );
  static Future<T?> pushContentDetail<T>(
    BuildContext context, {
    required String kind,
    required int contentId,
  }) =>
      push(context, contentDetail(kind: kind, contentId: contentId));
  static Future<T?> pushWikiSubject<T>(BuildContext context, int subjectId) =>
      push(context, wikiSubject(subjectId: subjectId));
  static Future<T?> pushHistoryCenter<T>(BuildContext context) =>
      push(context, historyCenter());
  static Future<T?> pushTimeline<T>(BuildContext context) =>
      push(context, timeline());
  static Future<T?> pushProfileEdit<T>(BuildContext context) =>
      push(context, profileEdit());
}
