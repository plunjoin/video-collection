part of 'player_mobile_page.dart';

/// 播放器右侧栏扩展：选集、AI 剧情助手、一起看房间、相关推荐
extension _PlayerSideRailExtension on _PlayerMobilePageState {
  /// 右栏 Tab 面板：选集 / AI 剧情助手 / 一起看（首屏与播放器同高）
  Widget _buildSideRail(bool isDark, PlayGroup? currentGroup) {
    final card = isDark ? AppColors.darkCard : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0);
    final labels = ['选集', 'AI 助手', '一起看'];
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                    child: _railTab(
                      labels[i],
                      active: _sideTab == i,
                      isDark: isDark,
                      onTap: () => updatePlayer(() => _sideTab = i),
                    ),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0),
          ),
          Expanded(
            child: IndexedStack(
              index: _sideTab,
              children: [
                _episodePanel(isDark, currentGroup),
                _aiPanel(isDark),
                _watchSheet(isDark),
              ],
            ),
          ),
          // 底部：相关推荐（两两往下排列，权重后置）
          if (_related.isNotEmpty)
            SizedBox(height: 248, child: _railRelated(isDark)),
        ],
      ),
    );
  }

  /// 相关推荐：两两往下排列
  Widget _railRelated(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '相关推荐',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: _related.length,
              itemBuilder: (context, i) {
                final item = _related[i];
                return InkWell(
                  onTap: () => _openRelated(item),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: double.infinity,
                            child: item.picture.isEmpty
                                ? ColoredBox(
                                    color: isDark
                                        ? AppColors.darkBg
                                        : const Color(0xFFE2E8F0),
                                  )
                                : Image.network(
                                    item.picture,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: ink),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _railTab(
    String label, {
    required bool active,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary600.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? AppColors.primary500 : muted,
            ),
          ),
        ),
      ),
    );
  }

  /// Tab1：集数搜索 + 分集列表（当前集高亮 + 播放图标）+ 底部相关推荐
  Widget _episodePanel(bool isDark, PlayGroup? currentGroup) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final groups = widget.video.playGroups;
    final episodes = currentGroup?.episodes ?? const <Episode>[];
    final query = _episodeSearch.text.trim();
    final shown = <int>[];
    for (var i = 0; i < episodes.length; i++) {
      final name = episodes[i].name;
      if (query.isEmpty || name.contains(query) || '${i + 1}'.contains(query)) {
        shown.add(i);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 集数搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _episodeSearch,
            onChanged: (_) => updatePlayer(() {}),
            style: TextStyle(fontSize: 12.5, color: ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索集数 / 输入编号',
              hintStyle: TextStyle(fontSize: 12, color: muted),
              prefixIcon: BrandIcon(
                BIcons.search,
                size: 16,
                color: muted,
                monochrome: true,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              filled: true,
              fillColor: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFe2e8f0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : const Color(0xFFe2e8f0),
                ),
              ),
            ),
          ),
        ),
        // 线路（多于一条时）
        if (groups.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < groups.length; i++)
                  _railTab(
                    groups[i].server.isNotEmpty
                        ? groups[i].server
                        : '线路${i + 1}',
                    active: i == _currentGroupIndex,
                    isDark: isDark,
                    onTap: () => _switchEpisode(i, 0),
                  ),
              ],
            ),
          ),
        // 分集列表
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的集数',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  itemCount: shown.length,
                  itemBuilder: (context, idx) {
                    final i = shown[idx];
                    final ep = episodes[i];
                    final current = i == _currentEpisodeIndex;
                    return InkWell(
                      onTap: () => _switchEpisode(_currentGroupIndex, i),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: current
                              ? AppColors.primary600.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            if (current)
                              const BrandIcon(
                                BIcons.play,
                                size: 13,
                                color: AppColors.primary500,
                              )
                            else
                              SizedBox(
                                width: 13,
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ep.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: current
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: current ? AppColors.primary500 : ink,
                                ),
                              ),
                            ),
                            if (current)
                              Text(
                                '播放中',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Tab2：AI 剧情助手（迷你时间轴 + 实时角色卡片 + 解读文本）
  Widget _aiPanel(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final hasDuration = _duration.inMilliseconds > 0;
    final relations = _wiki?.forwardRelations ?? const [];
    final cast = relations
        .where(
          (r) =>
              r.relationType == 'character_play' || r.relationType == 'actor',
        )
        .toList();
    final highlight = _currentHighlight();
    final summary = (_wiki?.summary.isNotEmpty == true)
        ? _wiki!.summary
        : (widget.video.content.isEmpty ? '加载剧情资料中…' : widget.video.content);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 迷你横向时间轴（拖拽跳转，与播放进度双向联动）
        Text(
          '播放进度',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        Row(
          children: [
            Text(
              _formatDuration(_position),
              style: TextStyle(
                fontSize: 10.5,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 10,
                  ),
                  overlayColor: AppColors.primary500.withValues(alpha: 0.15),
                  activeTrackColor: AppColors.primary500,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                ),
                child: Slider(
                  value: hasDuration
                      ? _position.inMilliseconds
                            .clamp(0, _duration.inMilliseconds)
                            .toDouble()
                      : 0,
                  max: hasDuration ? _duration.inMilliseconds.toDouble() : 1,
                  onChanged: hasDuration && !_watchGuestLocked()
                      ? (v) => _seekWithSync(Duration(milliseconds: v.toInt()))
                      : null,
                ),
              ),
            ),
            Text(
              _formatDuration(_duration),
              style: TextStyle(
                fontSize: 10.5,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 实时角色卡片
        Text(
          '出场角色',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        if (cast.isEmpty)
          Text('暂无角色资料', style: TextStyle(fontSize: 12, color: muted))
        else
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = cast[i];
                final subject = r.targetSubject;
                final name = subject?.name ?? r.roleDescription;
                final role = WikiSubject.relationLabel(r.relationType);
                return Container(
                  width: 128,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : const Color(0xFFe2e8f0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        // 实时解读文本
        Text(
          '实时解读',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (highlight != null) ...[
                Row(
                  children: [
                    BrandIcon(BIcons.sparkles, size: 12, color: AppColors.gold),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '本段看点 · ${_formatDuration(Duration(milliseconds: highlight.key))}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  highlight.value,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                summary,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.6, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => showAiQaSheet(
            context,
            seedQuestion:
                '${widget.video.name} 第${_currentEpisodeIndex + 1}集讲了什么？',
          ),
          icon: BrandIcon(
            BIcons.sparkles,
            size: 15,
            color: AppColors.primary500,
          ),
          label: const Text('向 AI 问答剧情'),
        ),
      ],
    );
  }

  /// 左栏纵向信息流：AI 深度解读 → 精选时间弹幕 → 评论区 → 相关推荐
  List<Widget> _buildFeed(bool isDark) {
    const gap = SizedBox(height: 16);
    return [
      _aiDeepCard(isDark),
      gap,
      _featuredDanmakuCard(isDark),
      gap,
      _commentCard(isDark),
      gap,
      _relatedFeedCard(isDark),
    ];
  }

  Widget _feedShell(
    bool isDark,
    String title,
    BrandIconData icon, {
    required Widget child,
    Widget? trailing,
  }) {
    final card = isDark ? AppColors.darkCard : Colors.white;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFe2e8f0);
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BrandIcon(icon, size: 16, color: AppColors.primary500),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// AI 深度解读大卡片：剧情摘要 + 角色关系 + 看点（伏笔）汇总
  Widget _aiDeepCard(bool isDark) {
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final wiki = _wiki;
    final relations = wiki?.forwardRelations ?? const [];
    final highlights = _danmakuHighlights();
    final summary = (wiki?.summary.isNotEmpty == true)
        ? wiki!.summary
        : widget.video.content.trim();

    return _feedShell(
      isDark,
      'AI 深度解读',
      BIcons.sparkles,
      trailing: InkWell(
        onTap: () => showAiQaSheet(
          context,
          seedQuestion: '${widget.video.name} 有哪些值得注意的伏笔？',
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary600.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '问 AI',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary500,
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.isEmpty ? '暂无剧情资料' : summary,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.7, color: muted),
          ),
          const SizedBox(height: 14),
          Text(
            '角色关系',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          if (relations.isEmpty)
            Text('暂无角色关系数据', style: TextStyle(fontSize: 12, color: muted))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in relations.take(10))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBg
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : const Color(0xFFe2e8f0),
                      ),
                    ),
                    child: Text(
                      '${r.sourceSubject?.name ?? '本作'}'
                      ' —${WikiSubject.relationLabel(r.relationType)}→ '
                      '${r.targetSubject?.name ?? r.roleDescription}',
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            '伏笔与看点汇总',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            Text(
              '这一集还没有足够的弹幕生成看点',
              style: TextStyle(fontSize: 12, color: muted),
            )
          else
            Column(
              children: [
                for (final h in highlights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDuration(Duration(milliseconds: h.key)),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            h.value,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// 精选时间弹幕：点击跳转对应时间
  Widget _featuredDanmakuCard(bool isDark) {
    final highlights = _danmakuHighlights();
    if (highlights.isEmpty) return const SizedBox.shrink();
    final ink = isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A);
    return _feedShell(
      isDark,
      '精选时间弹幕',
      BIcons.message,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final h in highlights)
            InkWell(
              onTap: () {
                if (_watchGuestLocked()) return;
                _seekWithSync(Duration(milliseconds: h.key));
                _showTopToast(
                  '跳转到 ${_formatDuration(Duration(milliseconds: h.key))}',
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBg : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : const Color(0xFFe2e8f0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDuration(Duration(milliseconds: h.key)),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        h.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentCard(bool isDark) {
    // VideoCommentSection 自带卡片/标题/输入框/空态，不再套外层边框；
    // 无评论时收紧高度避免大段空白，有评论时给足浏览空间
    return SizedBox(
      height: _commentTotal > 0 ? 620 : 224,
      child: VideoCommentSection(
        targetId: widget.video.id,
        onTotal: (total) {
          if (_commentTotal == total) return;
          updatePlayer(() => _commentTotal = total);
        },
      ),
    );
  }

  Widget _relatedFeedCard(bool isDark) {
    if (_related.isEmpty) return const SizedBox.shrink();
    return _feedShell(
      isDark,
      '相关推荐',
      BIcons.compass,
      child: SizedBox(
        height: 216,
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
    );
  }

  /// 弹幕密度看点：按时长分桶，取每桶最长的一条弹幕作为该段代表
  List<MapEntry<int, String>> _danmakuHighlights() {
    if (_danmaku.isEmpty || _duration.inMilliseconds <= 0) {
      return const [];
    }
    final total = _duration.inMilliseconds;
    const bins = 10;
    final picked = <MapEntry<int, String>>[];
    for (var b = 0; b < bins; b++) {
      final from = total * b ~/ bins;
      final to = total * (b + 1) ~/ bins;
      MapEntry<int, String>? best;
      for (final d in _danmaku) {
        if (d.playTimeMs < from || d.playTimeMs >= to) continue;
        if (d.content.trim().length < 2) continue;
        if (best == null || d.content.length > best.value.length) {
          best = MapEntry(d.playTimeMs, d.content.trim());
        }
      }
      if (best != null) {
        picked.add(
          MapEntry(
            best.key,
            best.value.length > 16
                ? '${best.value.substring(0, 16)}…'
                : best.value,
          ),
        );
      }
    }
    return picked;
  }

  String? _bubbleLabelFor(double ms) {
    for (final h in _danmakuHighlights()) {
      if ((h.key - ms).abs() < _duration.inMilliseconds * 0.02) return h.value;
    }
    return null;
  }

  MapEntry<int, String>? _currentHighlight() {
    final highlights = _danmakuHighlights();
    if (highlights.isEmpty) return null;
    MapEntry<int, String>? nearest;
    for (final h in highlights) {
      if (nearest == null ||
          (h.key - _position.inMilliseconds).abs() <
              (nearest.key - _position.inMilliseconds).abs()) {
        nearest = h;
      }
    }
    return nearest;
  }

  /// 更多菜单（底部控制栏）
  List<PopupMenuEntry<String>> _moreMenuItems(List<PlayGroup> groups) {
    return [
      if (groups.length > 1) ...[
        const PopupMenuItem<String>(
          enabled: false,
          child: Text(
            '切换线路',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),
        for (var i = 0; i < groups.length; i++)
          PopupMenuItem<String>(
            value: 'route:$i',
            child: Text(
              groups[i].server.isNotEmpty ? groups[i].server : '线路${i + 1}',
              style: TextStyle(
                fontSize: 12.5,
                color: i == _currentGroupIndex ? AppColors.primary400 : null,
                fontWeight: i == _currentGroupIndex ? FontWeight.w700 : null,
              ),
            ),
          ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem<String>(
        value: 'chapters',
        child: Text(
          '章节时间线',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'danmaku',
        child: Text(
          '发弹幕',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      PopupMenuItem<String>(
        value: 'enhance',
        child: Text(
          _isEnhanced ? '关闭极光画质增强' : '开启极光画质增强',
          style: const TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      PopupMenuItem<String>(
        value: 'aspect',
        child: Text(
          '画面比例：${_aspectModeLabel(_aspectMode)}',
          style: const TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'share',
        child: Text(
          '分享本片',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'cast',
        child: Text(
          '投屏到电视',
          style: TextStyle(fontSize: 12.5, color: Colors.white),
        ),
      ),
    ];
  }

  void _onMoreSelected(String value) {
    if (value.startsWith('route:')) {
      final idx = int.tryParse(value.split(':')[1]) ?? 0;
      _switchEpisode(idx, 0);
      return;
    }
    switch (value) {
      case 'chapters':
        _showChapterTimeline();
      case 'danmaku':
        _composeDanmaku();
      case 'enhance':
        _toggleEnhance();
      case 'aspect':
        _toggleAspectMode();
      case 'share':
        _showShareDialog();
      case 'cast':
        _showTopToast('投屏功能即将上线');
    }
  }

  /// 章节时间线面板（横向时间线，标记取自弹幕密度看点）。
  /// 桌面端从右侧滑入，移动端从底部滑入。
  Future<void> _showChapterTimeline() async {
    if (_duration.inMilliseconds <= 0) {
      _showTopToast('暂无进度信息');
      return;
    }
    final highlights = _danmakuHighlights();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showBrandSheet(
      context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '章节时间线',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            highlights.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      '这一集还没有足够的弹幕生成章节看点',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  )
                : SizedBox(
                    height: 110,
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final w = cons.maxWidth;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 62,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            Positioned(
                              left:
                                  (_position.inMilliseconds /
                                          _duration.inMilliseconds)
                                      .clamp(0.0, 1.0) *
                                  (w - 20),
                              top: 56,
                              child: Container(
                                width: 4,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: AppColors.primary400,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            for (final h in highlights)
                              Positioned(
                                left:
                                    (h.key / _duration.inMilliseconds).clamp(
                                      0.0,
                                      1.0,
                                    ) *
                                    (w - 20),
                                top: 0,
                                width: 130,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    if (!_watchGuestLocked()) {
                                      _seekWithSync(
                                        Duration(milliseconds: h.key),
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDuration(
                                          Duration(milliseconds: h.key),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary400,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        h.value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isDark
                                              ? AppColors.darkTextSecondary
                                              : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary400,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 分享面板：复制链接。桌面端从右侧滑入，移动端从底部滑入。
  Future<void> _showShareDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var link = '${_appState.apiBaseUrl}/play/${widget.video.id}';
    link += '?ep=$_currentEpisodeIndex';
    if (_currentGroupIndex > 0) link += '&route=$_currentGroupIndex';
    await showBrandSheet(
      context,
      builder: (context) {
        final controller = TextEditingController(text: link);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '分享给同好',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
                '${widget.video.name} · 第${_currentEpisodeIndex + 1}话',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                readOnly: true,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkBg
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    _showTopToast('链接已复制');
                  },
                  icon: const BrandIcon(
                    BIcons.link,
                    size: 15,
                    color: Colors.white,
                  ),
                  label: const Text('复制链接'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 右上角轻提示 Toast
  void _showTopToast(String message) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: kBrandAppBarTopInset + 56,
        right: 28,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (_, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * -10),
                child: child,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(milliseconds: 1900), () {
      if (entry.mounted) entry.remove();
    });
  }

  /// 画布内滚轮调节音量（通过 PointerSignalResolver 独占，页面不滚动）
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is! PointerScrollEvent) return;
      if (_isLocked) return;
      final delta = event.scrollDelta.dy;
      if (delta == 0) return;
      final v = (_volume - delta / 10).clamp(0.0, 100.0);
      updatePlayer(() => _volume = v);
      _player.setVolume(v);
      _showHudMessage(
        '音量: ${v.round()}%',
        v == 0 ? BIcons.muted : BIcons.volume,
      );
    });
  }

  void _setDockVolume(double v) {
    updatePlayer(() => _volume = v);
    _player.setVolume(v);
  }

  /// 状态B：右下角 280px 悬浮小窗（拖拽限定右下区域；点击还原；关闭即暂停）
}
