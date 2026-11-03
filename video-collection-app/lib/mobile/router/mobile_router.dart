/// 移动端页面工厂与 push 助手(保持 Navigator.push,不上 GoRouter)。
library;
import '../../shared/models/video_model.dart';
import '../../shared/ui/kit.dart';
import '../pages/account_mobile_page.dart';
import '../pages/account_security_mobile_page.dart';
import '../pages/anime_detail_mobile_page.dart';
import '../pages/content_detail_mobile_page.dart';
import '../pages/discover_mobile_page.dart';
import '../pages/growth_mobile_page.dart';
import '../pages/history_center_mobile_page.dart';
import '../pages/player_mobile_page.dart';
import '../pages/profile_edit_mobile_page.dart';
import '../pages/profile_hub_mobile_page.dart';
import '../pages/reset_password_mobile_page.dart';
import '../pages/search_mobile_page.dart';
import '../pages/settings_mobile_page.dart';
import '../pages/timeline_mobile_page.dart';
import '../pages/watch_lobby_mobile_page.dart';
import '../pages/wiki_subject_mobile_page.dart';

class MobileRouter {
  MobileRouter._();

  static Widget search() => const SearchMobilePage();
  static Widget settings() => const SettingsMobilePage();
  static Widget account() => const AccountMobilePage();
  static Widget accountSecurity() => const AccountSecurityMobilePage();
  static Widget resetPassword() => const ResetPasswordMobilePage();
  static Widget animeDetail({required int videoId}) =>
      AnimeDetailMobilePage(videoId: videoId);
  static Widget player({
    required VideoRecord video,
    int initialGroupIndex = 0,
    int initialEpisodeIndex = 0,
    Duration initialPosition = Duration.zero,
    String? watchRoomCode,
  }) =>
      PlayerMobilePage(
        video: video,
        initialGroupIndex: initialGroupIndex,
        initialEpisodeIndex: initialEpisodeIndex,
        initialPosition: initialPosition,
        watchRoomCode: watchRoomCode,
      );
  static Widget contentDetail({required String kind, required int contentId}) =>
      ContentDetailMobilePage(kind: kind, contentId: contentId);
  static Widget wikiSubject({required int subjectId}) =>
      WikiSubjectMobilePage(subjectId: subjectId);
  static Widget historyCenter() => const HistoryCenterMobilePage();
  static Widget timeline() => const TimelineMobilePage();
  static Widget profileEdit() => const ProfileEditMobilePage();
  static Widget profileHub() => const ProfileHubMobilePage();
  static Widget growth() => const GrowthMobilePage();
  static Widget discover() => const DiscoverMobilePage();
  static Widget watchLobby() => const WatchLobbyMobilePage();

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
