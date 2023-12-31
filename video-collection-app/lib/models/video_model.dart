class Episode {
  final String name;
  final String url;

  Episode({required this.name, required this.url});

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'url': url};
  }
}

class PlayGroup {
  final String playerCode;
  final String server;
  final String note;
  final List<Episode> episodes;

  PlayGroup({
    required this.playerCode,
    required this.server,
    required this.note,
    required this.episodes,
  });

  factory PlayGroup.fromJson(Map<String, dynamic> json) {
    var rawEpisodes = json['episodes'] as List? ?? [];
    List<Episode> parsedEpisodes = [];
    for (var item in rawEpisodes) {
      if (item is Map<String, dynamic>) {
        parsedEpisodes.add(Episode.fromJson(item));
      } else if (item is Map) {
        parsedEpisodes.add(Episode.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return PlayGroup(
      playerCode: json['player_code']?.toString() ?? '',
      server: json['server']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      episodes: parsedEpisodes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'player_code': playerCode,
      'server': server,
      'note': note,
      'episodes': episodes.map((e) => e.toJson()).toList(),
    };
  }
}

class VideoRecord {
  final int id;
  final String name;
  final String subName;
  final int typeId;
  final String typeName;
  final String picture;
  final String actor;
  final String director;
  final String area;
  final String language;
  final String year;
  final String remarks;
  final String content;
  final int hits;
  final List<String> tags;
  final List<PlayGroup> playGroups;

  VideoRecord({
    required this.id,
    required this.name,
    required this.subName,
    required this.typeId,
    required this.typeName,
    required this.picture,
    required this.actor,
    required this.director,
    required this.area,
    required this.language,
    required this.year,
    required this.remarks,
    required this.content,
    required this.hits,
    required this.tags,
    required this.playGroups,
  });

  factory VideoRecord.fromJson(Map<String, dynamic> json) {
    int id = int.tryParse(json['id']?.toString() ?? '0') ?? 0;
    int hits = int.tryParse(json['hits']?.toString() ?? '0') ?? 0;
    int typeId = int.tryParse(json['type_id']?.toString() ?? '4') ?? 4;
    String rawContent = json['content']?.toString() ?? '';
    String cleanText = cleanSynopsis(rawContent);

    // 智能推断番剧题材类型 (与 Web 端 100% 对齐)
    List<String> genres = [];
    String textToScan =
        '${json['name'] ?? ''} $cleanText ${json['remarks'] ?? ''} ${json['sub_name'] ?? ''}'
            .toLowerCase();

    if (RegExp(r'热血|战斗|打斗|干架|少年|神帝|神尊|破天|武魂|逆天|觉醒|征程|斩|剑道|强者|斗破|遮天|英雄|战士|拳|霸|武')
        .hasMatch(textToScan)) {
      genres.add('热血');
    }
    if (RegExp(r'玄幻|修真|修仙|仙侠|宗门|沧元图|神帝|神尊|灵气|飞升|长生|凡人|洪荒|天尊|武动|至尊|元尊|妖神|九天')
        .hasMatch(textToScan)) {
      genres.add('玄幻');
      genres.add('修真');
    }
    if (RegExp(r'冒险|异世界|转生|魔王|旅途|勇者|迷宫|探索|地下城|寻宝|奇遇|猎人').hasMatch(textToScan)) {
      genres.add('冒险');
    }
    if (RegExp(r'奇幻|魔法|恶魔|魔王|入魔|妖怪|神话|幻想|妖精|超自然|灵异').hasMatch(textToScan)) {
      genres.add('奇幻');
    }
    if (RegExp(r'搞笑|喜剧|轻松|欢乐|幽默|沙雕|马戏团|吐槽|无厘头').hasMatch(textToScan)) {
      genres.add('搞笑');
    }
    if (RegExp(r'科幻|未来|科技|星际|机甲|宇宙|战舰|仿生|元宇宙|赛博|末世').hasMatch(textToScan)) {
      genres.add('科幻');
    }
    if (RegExp(r'治愈|温馨|日常|感动|陪伴|温暖|田园|治愈系|成长').hasMatch(textToScan)) {
      genres.add('治愈');
    }
    if (RegExp(r'恋爱|纯爱|情侣|浪漫|甜蜜|假扮恋人|动了真心|少女|指尖浪漫|晴转恋|恋人|爱情')
        .hasMatch(textToScan)) {
      genres.add('恋爱');
    }
    if (RegExp(r'悬疑|推理|侦探|柯南|破案|密室|真相|凶手|死亡|游戏|秘密|解密|诡异')
        .hasMatch(textToScan)) {
      genres.add('悬疑');
    }
    String typeName = json['type_name']?.toString() ?? '番剧';
    Set<String> tagSet = {typeName, ...genres};

    // 解析播放组
    var rawGroups = json['play_groups'] as List? ?? [];
    List<PlayGroup> parsedGroups = [];
    for (var item in rawGroups) {
      if (item is Map<String, dynamic>) {
        parsedGroups.add(PlayGroup.fromJson(item));
      } else if (item is Map) {
        parsedGroups.add(PlayGroup.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return VideoRecord(
      id: id,
      name: json['name']?.toString() ?? '',
      subName: json['sub_name']?.toString() ?? '',
      typeId: typeId,
      typeName: typeName,
      picture: json['picture']?.toString() ?? '',
      actor: json['actor']?.toString() ?? '',
      director: json['director']?.toString() ?? '',
      area: json['area']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
      content: cleanText,
      hits: hits,
      tags: tagSet.toList(),
      playGroups: parsedGroups,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sub_name': subName,
      'type_id': typeId,
      'type_name': typeName,
      'picture': picture,
      'actor': actor,
      'director': director,
      'area': area,
      'language': language,
      'year': year,
      'remarks': remarks,
      'content': content,
      'hits': hits,
      'tags': tags,
      'play_groups': playGroups.map((g) => g.toJson()).toList(),
    };
  }

  static String cleanSynopsis(String? html) {
    if (html == null || html.isEmpty) return '暂无剧情简介';
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class Category {
  final int id;
  final int pid;
  final String name;
  final int sort;

  Category({
    required this.id,
    required this.pid,
    required this.name,
    required this.sort,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      pid: int.tryParse(json['pid']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      sort: int.tryParse(json['sort']?.toString() ?? '0') ?? 0,
    );
  }
}

class FriendLink {
  final String name;
  final String url;
  final String description;

  FriendLink({required this.name, required this.url, this.description = ''});

  factory FriendLink.fromJson(Map<String, dynamic> json) {
    return FriendLink(
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }
}

class SiteConfig {
  final String siteName;
  final String siteSubtitle;
  final String siteAnnouncement;
  final String siteKeywords;
  final String siteDescription;
  final String siteContactEmail;
  final String siteContactGroup;
  final String siteDisclaimer;
  final List<FriendLink> friendLinks;

  SiteConfig({
    required this.siteName,
    required this.siteSubtitle,
    required this.siteAnnouncement,
    required this.siteKeywords,
    required this.siteDescription,
    required this.siteContactEmail,
    required this.siteContactGroup,
    required this.siteDisclaimer,
    required this.friendLinks,
  });

  factory SiteConfig.defaultConfig() {
    return SiteConfig(
      siteName: 'bllii · More Stories, Together',
      siteSubtitle: '追番库 • 让生活多一种可能',
      siteAnnouncement: '欢迎访问Bllii客户端！全新升级流媒体视觉、极光画质增强引擎与全站新番排行榜已全面开启！',
      siteKeywords: '高清动漫,番剧新番,日漫,国漫,免费在线观看',
      siteDescription: 'Bllii致力于提供全面、快速的高清二次元番剧与动漫流媒体在线观看服务与智能聚合。',
      siteContactEmail: 'contact@Bllii.com',
      siteContactGroup: '官方交流群: 876543210 (TG: @Bllii)',
      siteDisclaimer: '【免责声明】本站所有视频资源均系第三方公开网络接口与网络爬虫自动检索聚合，本站服务器不存储、不制作、不上传任何视听节目及视频文件。若相关内容无意侵犯了贵司版权或合法权益，请联系我们处理。',
      friendLinks: [
        FriendLink(
          name: 'Bangumi 番组计划',
          url: 'https://bangumi.tv',
          description: '动画与游戏分享社区',
        ),
        FriendLink(
          name: '萌娘百科',
          url: 'https://zh.moegirl.org.cn',
          description: '万物皆可萌的ACG百科全书',
        ),
        FriendLink(
          name: 'ACG 动漫社区',
          url: 'https://acg.rip',
          description: '动漫资源分享与爱好者交流',
        ),
        FriendLink(
          name: 'MyAnimeList',
          url: 'https://myanimelist.net',
          description: '全球知名动漫资料库',
        ),
      ],
    );
  }
}
