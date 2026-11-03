part of 'player_desktop_page.dart';

/// 播放器移动端底部抽屉扩展：选集列表、弹幕管理、讨论与评论
extension _PlayerBottomSheetsExtension on _PlayerDesktopPageState {
  /// 一起看面板（房间 / 聊天）。
  Widget _watchSheet(bool isDark) {
    return WatchTogetherPanel(
      watch: _watch,
      isDark: isDark,
      loggedIn: _appState.isLoggedIn,
      videoId: widget.video.id,
      videoName: widget.video.name,
      currentGroupIndex: () => _currentGroupIndex,
      currentEpisodeIndex: () => _currentEpisodeIndex,
      currentEpisodeName: () {
        final groups = widget.video.playGroups;
        if (_currentGroupIndex < groups.length &&
            _currentEpisodeIndex < groups[_currentGroupIndex].episodes.length) {
          return groups[_currentGroupIndex].episodes[_currentEpisodeIndex].name;
        }
        return '';
      },
    );
  }

  /// 胶囊分段选项卡：激活项品牌渐变高亮，弹幕/评论带计数，一起看在房时带直播点。
  Widget _sheetTabs(bool isDark) {
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final entries = <(String, int?, bool)>[
      ('视频', null, false),
      ('弹幕', _danmaku.isEmpty ? null : _danmaku.length, false),
      ('一起看', null, _watch.active),
      ('评论', _commentTotal > 0 ? _commentTotal : null, false),
    ];
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(bottom: BorderSide(color: border, width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (var index = 0; index < entries.length; index++)
            Expanded(
              child: Center(
                child: _sheetTabPill(
                  isDark: isDark,
                  label: entries[index].$1,
                  count: entries[index].$2,
                  live: entries[index].$3,
                  active: _sheetIndex == index,
                  onTap: () => updatePlayer(() => _sheetIndex = index),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sheetTabPill({
    required bool isDark,
    required String label,
    required int? count,
    required bool live,
    required bool active,
    required VoidCallback onTap,
  }) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final idleBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF1F5F9);
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [
                      Color(0xFFFF89C7),
                      Color(0xFFAE8CFF),
                      Color(0xFF80B6FF),
                    ],
                  )
                : null,
            color: active ? null : idleBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live && !active) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF43F5E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? Colors.white : muted,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.22)
                        : muted.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count > 999 ? '999+' : '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoSheet(
    bool isDark,
    Episode? currentEp,
    PlayGroup? currentGroup, {
    bool embedEpisodes = true,
    bool showHeader = true,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _danmakuBar(isDark),
        if (showHeader) ...[
          const SizedBox(height: 14),
          _titleBlock(isDark, currentEp, currentGroup),
          const SizedBox(height: 16),
          _actionRow(isDark),
        ],
        if (embedEpisodes) ...[
          const SizedBox(height: 18),
          _episodeHeading(isDark, currentGroup),
          const SizedBox(height: 8),
          _episodeCards(),
        ],
        if (!embedEpisodes) ...[
          const SizedBox(height: 16),
          _buildDesktopMetaCard(isDark),
          _buildDesktopShortcutGuide(isDark),
        ],
        if (_related.isNotEmpty) ...[
          const SizedBox(height: 18),
          _relatedHeading(isDark),
          const SizedBox(height: 12),
          SizedBox(
            height: 196,
            child: DesktopHorizontalScroll(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _related.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = _related[index];
                  return AudiencePosterTile(
                    video: item,
                    onTap: () => _openRelated(item),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _episodeKey() {
    final groups = widget.video.playGroups;
    if (groups.isEmpty || _currentGroupIndex >= groups.length) return '0';
    final group = groups[_currentGroupIndex];
    if (_currentEpisodeIndex >= group.episodes.length) {
      return '$_currentGroupIndex';
    }
    final name = group.episodes[_currentEpisodeIndex].name.trim();
    final key = '$_currentGroupIndex:$name';
    final runes = key.runes.toList();
    if (runes.length <= 80) return key;
    return String.fromCharCodes(runes.take(80));
  }

  Future<void> _loadDanmaku() async {
    final key = _episodeKey();
    final generation = ++_danmakuGeneration;
    try {
      final raw = await ApiService().listDanmaku(
        videoId: widget.video.id,
        episodeKey: key,
      );
      if (!mounted ||
          generation != _danmakuGeneration ||
          key != _episodeKey()) {
        return;
      }
      updatePlayer(() {
        _danmaku = raw.map(DanmakuItem.fromJson).toList();
      });
    } catch (_) {
      if (!mounted || generation != _danmakuGeneration) return;
      updatePlayer(() => _danmaku = []);
    }
  }

  Future<void> _composeDanmaku() async {
    if (!_appState.isLoggedIn) {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AccountDesktopPage()));
      if (!mounted || !_appState.isLoggedIn) return;
    }
    final draft = await showDanmakuComposer(context);
    if (draft == null || !mounted || _sendingDanmaku) return;
    updatePlayer(() => _sendingDanmaku = true);
    try {
      final created = await ApiService().sendDanmaku(
        videoId: widget.video.id,
        episodeKey: _episodeKey(),
        playTimeMs: _position.inMilliseconds,
        mode: draft.mode,
        color: draft.color,
        content: draft.text,
      );
      if (!mounted) return;
      updatePlayer(
        () => _danmaku = [..._danmaku, DanmakuItem.fromJson(created)],
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      updatePlayer(() => _sendingDanmaku = false);
    }
  }

  Future<void> _removeDanmaku(DanmakuItem item) async {
    final mine = _appState.user?['id']?.toString() == '${item.userId}';
    if (!mine) return;
    try {
      await ApiService().deleteDanmaku(item.id);
      if (!mounted) return;
      updatePlayer(
        () =>
            _danmaku = _danmaku.where((entry) => entry.id != item.id).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _danmakuBar(bool isDark) {
    final fill = isDark ? AppColors.darkCard : const Color(0xFFF3F4F8);
    final enabled = _appState.danmakuEnabled;
    return Row(
      children: [
        Text(
          '弹幕',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        Transform.scale(
          scale: .8,
          child: Switch.adaptive(
            value: enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary500,
            onChanged: (value) {
              _appState.setDanmakuEnabled(value);
              updatePlayer(() {});
            },
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _sendingDanmaku ? null : _composeDanmaku,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _sendingDanmaku ? '发送中…' : '点我发弹幕～',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _titleBlock(bool isDark, Episode? currentEp, PlayGroup? currentGroup) {
    final count = currentGroup?.episodes.length ?? 0;
    final update = [
      widget.video.remarks,
      if (count > 0) '全$count话',
    ].where((item) => item.isNotEmpty).join(' · ');
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.video.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: ink,
                ),
              ),
            ),
            if (widget.video.hits > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8A34).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandIcon(
                      BIcons.flame,
                      size: 14,
                      color: Color(0xFFFF8A34),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${formatAudienceCount(widget.video.hits)}人气',
                      style: const TextStyle(
                        color: Color(0xFFFF8A34),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (currentEp != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary500.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandIcon(
                      BIcons.playCircle,
                      size: 12,
                      color: AppColors.primary500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      currentEp.name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (update.isNotEmpty)
              Expanded(
                child: Text(
                  update,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _actionRow(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _actionItem(
            icon: BIcons.thumbUp,
            label: widget.video.hits > 0
                ? formatAudienceCount(widget.video.hits)
                : '点赞',
            color: muted,
          ),
          _actionItem(
            icon: _favorite ? BIcons.star : BIcons.star,
            label: _favorite ? '已追番' : '追番',
            color: _favorite ? const Color(0xFFFFB020) : muted,
            onTap: _savingFavorite ? null : _toggleFavorite,
          ),
          _actionItem(
            icon: BIcons.download,
            label: '下载',
            color: muted,
            onTap: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('暂不支持缓存下载，请在线观看')));
            },
          ),
          _actionItem(
            icon: BIcons.share,
            label: '分享',
            color: muted,
            onTap: _sharePlayback,
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required BrandIconData icon,
    required String label,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BrandIcon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeHeading(bool isDark, PlayGroup? currentGroup) {
    final count = currentGroup?.episodes.length ?? 0;
    final trailing = widget.video.remarks.isNotEmpty
        ? widget.video.remarks
        : (count > 0 ? '全$count话' : '');
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Row(
      children: [
        Text(
          '选集',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        BrandIcon(BIcons.chevronRight, size: 18, color: muted),
        const Spacer(),
        if (trailing.isNotEmpty)
          Text(trailing, style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }

  Widget _episodeCards() {
    return EpisodeCardList(
      playGroups: widget.video.playGroups,
      currentGroupIndex: _currentGroupIndex,
      currentEpisodeIndex: _currentEpisodeIndex,
      posterUrl: widget.video.picture,
      onSelected: _switchEpisode,
    );
  }

  Widget _relatedHeading(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Row(
      children: [
        Text(
          '猜你喜欢',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
        BrandIcon(BIcons.chevronRight, size: 18, color: muted),
      ],
    );
  }

  Widget _danmakuSheet(bool isDark) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final ink = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final mineId = _appState.user?['id']?.toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            Text(
              _appState.danmakuEnabled ? '弹幕开着' : '弹幕关着',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text('${_danmaku.length} 条', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '弹幕会按这一集的播放时间出现在画面上。想慢慢聊，去评论区。',
          style: TextStyle(fontSize: 13, height: 1.5, color: muted),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: _sendingDanmaku ? null : _composeDanmaku,
            child: const Text('发弹幕'),
          ),
        ),
        const SizedBox(height: 12),
        if (_danmaku.isEmpty)
          Text('这一集还没有弹幕。', style: TextStyle(color: muted))
        else
          for (final item in _danmaku)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                item.content,
                style: TextStyle(color: ink, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_clock(item.playTimeMs)}  ${item.authorName}',
                style: TextStyle(color: muted),
              ),
              trailing: mineId == '${item.userId}'
                  ? IconButton(
                      tooltip: '删除',
                      onPressed: () => _removeDanmaku(item),
                      icon: const BrandIcon(BIcons.trash),
                    )
                  : null,
            ),
      ],
    );
  }

  String _clock(int milliseconds) {
    final total = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _commentSheet() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        VideoCommentSection(
          targetId: widget.video.id,
          onTotal: (total) {
            if (_commentTotal == total) return;
            updatePlayer(() => _commentTotal = total);
          },
        ),
      ],
    );
  }

  Future<void> _toggleFavorite() async {
    updatePlayer(() => _savingFavorite = true);
    try {
      await _appState.toggleFavorite(widget.video);
      if (!mounted) return;
      updatePlayer(() => _favorite = _appState.isFavorite(widget.video.id));
      if (_appState.accountError != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_appState.accountError!)));
      }
    } finally {
      updatePlayer(() => _savingFavorite = false);
    }
  }

  Future<void> _sharePlayback() async {
    final group =
        widget.video.playGroups.isNotEmpty &&
            _currentGroupIndex < widget.video.playGroups.length
        ? widget.video.playGroups[_currentGroupIndex]
        : null;
    final episode =
        group != null && _currentEpisodeIndex < group.episodes.length
        ? group.episodes[_currentEpisodeIndex].name
        : '';
    final text = [
      widget.video.name,
      episode,
    ].where((item) => item.isNotEmpty).join(' · ');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制片名，可以分享给同好')));
  }

  Future<void> _openRelated(VideoRecord video) async {
    final wasPlaying = _isPlaying;
    await _player.pause();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnimeDetailDesktopPage(videoId: video.id)),
    );
    if (mounted && wasPlaying) _player.play();
  }

  Widget _buildDesktopMetaCard(bool isDark) {
    if (widget.video.content.isEmpty && widget.video.tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.video.typeName,
                  style: const TextStyle(
                    color: AppColors.primary500,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  [
                    widget.video.area,
                    widget.video.year,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (widget.video.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.video.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkBg : AppColors.lightBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (widget.video.content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                widget.video.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopShortcutGuide(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkCard.withValues(alpha: 0.5)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const BrandIcon(
              BIcons.keyboard,
              size: 16,
              color: AppColors.primary500,
            ),
            const SizedBox(width: 8),
            const Text(
              '桌面快捷键:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '空格 播放/暂停  ·  ←/→ 快退进5s  ·  ↑/↓ 调音量  ·  [/] 上下集  ·  F 全屏',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 画面渲染与多模式自适应
  Widget _buildVideoSurface() {
    BoxFit fit;
    double? customAspect;

    switch (_aspectMode) {
      case AspectRatioMode.contain:
        fit = BoxFit.contain;
        break;
      case AspectRatioMode.widescreen:
        fit = BoxFit.fill;
        customAspect = 16 / 9;
        break;
      case AspectRatioMode.classic:
        fit = BoxFit.fill;
        customAspect = 4 / 3;
        break;
      case AspectRatioMode.fill:
        fit = BoxFit.cover;
        break;
    }

    Widget videoWidget = Center(
      child: customAspect != null
          ? AspectRatio(
              aspectRatio: customAspect,
              child: Video(
                controller: _videoController,
                fit: fit,
                controls: NoVideoControls,
              ),
            )
          : Video(
              controller: _videoController,
              fit: fit,
              controls: NoVideoControls,
            ),
    );

    if (_isEnhanced) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(_PlayerDesktopPageState._auroraMatrix),
        child: videoWidget,
      );
    }
    return videoWidget;
  }

  String _aspectModeLabel(AspectRatioMode mode) {
    switch (mode) {
      case AspectRatioMode.contain:
        return '自适应';
      case AspectRatioMode.widescreen:
        return '16:9';
      case AspectRatioMode.classic:
        return '4:3';
      case AspectRatioMode.fill:
        return '铺满';
    }
  }

  // 现代质感品牌控制层
  Widget _buildControlsOverlay(
    Episode? currentEp,
    PlayGroup? currentGroup,
    List<PlayGroup> groups,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < 560 || constraints.maxHeight < 280;
        final bufferRatio = _duration.inMilliseconds > 0
            ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 顶部环境微光渐变 (暗夜星空质感)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: isCompact ? 90 : 130,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF070B16).withValues(alpha: 0.88),
                        const Color(0xFF070B16).withValues(alpha: 0.40),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 2. 底部环境微光渐变
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: isCompact ? 110 : 150,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF070B16).withValues(alpha: 0.45),
                        const Color(0xFF070B16).withValues(alpha: 0.95),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. 屏幕锁定状态按键 (防误触设计)
            BrandPlayerScreenLock(
              isLocked: _isLocked,
              isCompact: isCompact,
              onToggleLock: () {
                updatePlayer(() {
                  _isLocked = !_isLocked;
                  if (_isLocked) _showFullscreenDrawer = false;
                });
                _showHudMessage(
                  _isLocked ? '屏幕已锁定 (防误触)' : '屏幕已解锁',
                  _isLocked ? BIcons.lock : BIcons.unlock,
                );
                _resetHideControlsTimer();
              },
            ),

            // 4. 未锁定时渲染完整控制框架
            if (!_isLocked) ...[
              // 顶部控制栏（桌面非全屏时为右上角原生窗口按钮让位）
              // 悬停期间控制层保持可见，标题栏随时可拖拽
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => _enterControlsHover(),
                  onExit: (_) => _exitControlsHover(),
                  child: BrandPlayerTopBar(
                    title: widget.video.name,
                    episodeName: currentEp?.name,
                    serverName: currentGroup?.server,
                    isEnhanced: _isEnhanced,
                    aspectModeLabel: _aspectModeLabel(_aspectMode),
                    isCompact: isCompact,
                    topInset: _nativeWindowControlsInset(),
                    draggable: !_isFullscreen,
                    // 桌面非全屏：工具胶囊收进更多菜单，右上角放投屏/分享
                    showTools: _isFullscreen,
                    trailing: (!_isFullscreen && Responsive.isDesktop(context))
                        ? [
                            _topIconButton(
                              icon: BIcons.ratio,
                              tooltip: '投屏到电视',
                              onTap: () => _showTopToast('投屏功能即将上线'),
                            ),
                            _topIconButton(
                              icon: BIcons.share,
                              tooltip: '分享',
                              onTap: _showShareDialog,
                            ),
                            const SizedBox(width: 6),
                          ]
                        : null,
                    onBack: () {
                      if (_isFullscreen) {
                        _toggleFullscreen();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    onToggleEnhance: _toggleEnhance,
                    onToggleAspect: _toggleAspectMode,
                  ),
                ),
              ),

              // 居中主控岛屿
              Center(
                child: BrandPlayerCenterDeck(
                  isPlaying: _isPlaying,
                  isCompact: isCompact,
                  onTogglePlay: _togglePlayPause,
                  onPlayPrev: _currentEpisodeIndex > 0
                      ? _playPrevEpisode
                      : null,
                  onPlayNext:
                      (currentGroup != null &&
                          _currentEpisodeIndex + 1 <
                              currentGroup.episodes.length)
                      ? _playNextEpisode
                      : null,
                  onSeekBackward: () => _seekBy(-10),
                  onSeekForward: () => _seekBy(10),
                ),
              ),

              // 底部磨砂玻璃悬浮底栏（悬停期间保持可见）
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => _enterControlsHover(),
                  onExit: (_) => _exitControlsHover(),
                  child: BrandPlayerBottomDock(
                    position: _position,
                    duration: _duration,
                    bufferProgress: bufferRatio,
                    isPlaying: _isPlaying,
                    isFullscreen: _isFullscreen,
                    danmakuEnabled: _appState.danmakuEnabled,
                    speed: _currentSpeed,
                    volume: _volume,
                    isCompact: isCompact,
                    formatDuration: _formatDuration,
                    onSeek: (val) {
                      if (_watchGuestLocked()) return;
                      _seekWithSync(Duration(milliseconds: val.toInt()));
                      _resetHideControlsTimer();
                    },
                    onTogglePlay: _togglePlayPause,
                    onPlayPrev: _playPrevEpisode,
                    onPlayNext:
                        (currentGroup != null &&
                            _currentEpisodeIndex + 1 <
                                currentGroup.episodes.length)
                        ? _playNextEpisode
                        : null,
                    onVolume: _setDockVolume,
                    onToggleDanmaku: _toggleDanmaku,
                    onSelectSpeed: () {
                      updatePlayer(() {
                        _showSpeedPanel = !_showSpeedPanel;
                        if (_showSpeedPanel) {
                          _showFullscreenDrawer = false;
                        }
                      });
                      _resetHideControlsTimer();
                    },
                    onToggleDrawer: _isFullscreen
                        ? () {
                            updatePlayer(() {
                              _showFullscreenDrawer = !_showFullscreenDrawer;
                              if (_showFullscreenDrawer) {
                                _drawerRange =
                                    _currentEpisodeIndex ~/ episodeRangeSize;
                              }
                            });
                            _resetHideControlsTimer();
                          }
                        : (!Responsive.isDesktop(context)
                              ? () {
                                  updatePlayer(() {
                                    _sheetIndex = 0;
                                  });
                                }
                              : null),
                    onToggleFullscreen: _toggleFullscreen,
                    moreItems: _moreMenuItems(groups),
                    onMoreSelected: _onMoreSelected,
                    bubbleLabelFor: _bubbleLabelFor,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 播放器顶栏右侧的圆形磨砂小按钮（投屏/分享）
  Widget _topIconButton({
    required BrandIconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return BrandPlayerButton(
      icon: icon,
      onPressed: onTap,
      size: 38,
      iconSize: 18,
      tooltip: tooltip,
    );
  }

  // 全屏内嵌选集抽屉 (亚克力磨砂质感与流光卡片)
  Widget _buildFullscreenDrawer(List<PlayGroup> groups) {
    final currentGroup = groups.isNotEmpty && _currentGroupIndex < groups.length
        ? groups[_currentGroupIndex]
        : null;
    final episodes = currentGroup?.episodes ?? [];

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 300,
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: const Color(0xFF0F172A).withValues(alpha: 0.90),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '选集与线路',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    BrandPlayerButton(
                      icon: BIcons.close,
                      size: 32,
                      iconSize: 18,
                      onPressed: () {
                        updatePlayer(() {
                          _showFullscreenDrawer = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 线路切换
                DesktopHorizontalScroll(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(groups.length, (index) {
                        final isSel = _currentGroupIndex == index;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: BrandPill(
                            label: Text(groups[index].server),
                            selected: isSel,
                            onSelected: (selected) {
                              if (selected) {
                                _switchEpisode(index, _currentEpisodeIndex);
                              }
                            },
                            onDark: true,
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                if (episodeRanges(episodes.length).length > 1) ...[
                  DesktopHorizontalScroll(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final (index, range) in episodeRanges(
                            episodes.length,
                          ).indexed)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: BrandPill(
                                label: Text(range.label),
                                selected: _drawerRange == index,
                                onDark: true,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  updatePlayer(() => _drawerRange = index);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 集数网格。超过 99 集时只显示当前分页。
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final ranges = episodeRanges(episodes.length);
                      final range = ranges.isEmpty
                          ? const EpisodeRange(0, 0)
                          : ranges[_drawerRange.clamp(0, ranges.length - 1)];
                      final visible = episodes.isEmpty
                          ? 0
                          : range.end - range.start;
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 2.0,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                        itemCount: visible,
                        itemBuilder: (context, idx) {
                          final episodeIndex = range.start + idx;
                          final isPlaying =
                              episodeIndex == _currentEpisodeIndex;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _switchEpisode(
                              _currentGroupIndex,
                              episodeIndex,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                gradient: isPlaying
                                    ? AppColors.brandGradient
                                    : null,
                                color: isPlaying
                                    ? null
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isPlaying
                                      ? Colors.transparent
                                      : Colors.white.withValues(alpha: 0.12),
                                  width: 0.8,
                                ),
                                boxShadow: isPlaying
                                    ? [
                                        BoxShadow(
                                          color: AppColors.purple.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                episodes[episodeIndex].name,
                                style: TextStyle(
                                  color: isPlaying
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isPlaying
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
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
