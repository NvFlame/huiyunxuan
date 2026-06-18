import '../models/poem.dart';

class ProsodyMetadata {
  const ProsodyMetadata({
    required this.supported,
    required this.enabled,
    required this.system,
    required this.form,
    required this.rhymeBook,
    required this.note,
  });

  final bool supported;
  final bool enabled;
  final String system;
  final String form;
  final String rhymeBook;
  final String note;

  bool get canEnable => supported;

  ProsodyMetadata copyWith({
    bool? supported,
    bool? enabled,
    String? system,
    String? form,
    String? rhymeBook,
    String? note,
  }) {
    return ProsodyMetadata(
      supported: supported ?? this.supported,
      enabled: enabled ?? this.enabled,
      system: system ?? this.system,
      form: form ?? this.form,
      rhymeBook: rhymeBook ?? this.rhymeBook,
      note: note ?? this.note,
    );
  }
}

ProsodyMetadata inferProsodyMetadata({
  required String title,
  required String dynasty,
  required String content,
  String remark = '',
}) {
  final normalizedTitle = _normalizeTitle(title);
  final lineCharCounts = _contentLineCharCounts(content);
  final lineCount = lineCharCounts.length;
  final ciTune = _detectCiTune(normalizedTitle);
  if (ciTune != null) {
    return ProsodyMetadata(
      supported: true,
      enabled: true,
      system: Poem.prosodySystemCi,
      form: ciTune,
      rhymeBook: Poem.rhymeBookCiLin,
      note: '已识别为词牌。默认按词林正韵查看，详细词谱、平仄和押韵检查会逐步接入。',
    );
  }

  final quTune = _detectQuTune(normalizedTitle);
  if (quTune != null) {
    return ProsodyMetadata(
      supported: true,
      enabled: true,
      system: Poem.prosodySystemQu,
      form: quTune,
      rhymeBook: '',
      note: '已识别为曲牌。暂先记录曲牌信息；曲谱与中原音韵检查待接入。',
    );
  }

  final unsupportedReason = _unsupportedReason(
    title: normalizedTitle,
    dynasty: dynasty,
    remark: remark,
    lineCount: lineCount,
  );
  if (unsupportedReason != null) {
    return ProsodyMetadata(
      supported: false,
      enabled: false,
      system: Poem.prosodySystemUnsupported,
      form: '',
      rhymeBook: '',
      note: unsupportedReason,
    );
  }

  final regulatedForm = _detectRegulatedVerseForm(lineCharCounts);
  if (regulatedForm != null) {
    final dynastyReason = _regulatedVerseDynastyBlockReason(dynasty);
    if (dynastyReason != null) {
      return ProsodyMetadata(
        supported: false,
        enabled: false,
        system: Poem.prosodySystemUnsupported,
        form: regulatedForm,
        rhymeBook: '',
        note: dynastyReason,
      );
    }
    final rhymeBook = _isModernDynasty(dynasty)
        ? Poem.rhymeBookXinYun
        : Poem.rhymeBookPingShui;
    return ProsodyMetadata(
      supported: true,
      enabled: true,
      system: Poem.prosodySystemRegulatedVerse,
      form: regulatedForm,
      rhymeBook: rhymeBook,
      note: '结构已识别为$regulatedForm。默认按$rhymeBook 查看；多音字确认后自动进行格律审查。',
    );
  }

  return const ProsodyMetadata(
    supported: false,
    enabled: false,
    system: Poem.prosodySystemUnknown,
    form: '',
    rhymeBook: '',
    note: '暂未识别为近体诗或已支持的词牌，未启用格律检查。',
  );
}

ProsodyMetadata metadataFromPoem(Poem poem) {
  return ProsodyMetadata(
    supported: poem.prosodySupported,
    enabled: poem.prosodyEnabled,
    system: poem.prosodySystem,
    form: poem.prosodyForm,
    rhymeBook: poem.prosodyRhymeBook,
    note: poem.prosodyNote,
  );
}

String prosodySystemLabel(String system) {
  switch (system) {
    case Poem.prosodySystemRegulatedVerse:
      return '近体诗';
    case Poem.prosodySystemCi:
      return '词';
    case Poem.prosodySystemQu:
      return '曲';
    case Poem.prosodySystemUnsupported:
      return '暂不支持';
    default:
      return '未识别';
  }
}

String _normalizeTitle(String title) {
  return title
      .replaceAll('《', '')
      .replaceAll('》', '')
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
}

List<int> _contentLineCharCounts(String content) {
  return content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map(_chineseCharCount)
      .where((count) => count > 0)
      .toList(growable: false);
}

int _chineseCharCount(String text) {
  var count = 0;
  for (final rune in text.runes) {
    if (rune >= 0x4e00 && rune <= 0x9fff) {
      count += 1;
    }
  }
  return count;
}

String? _detectRegulatedVerseForm(List<int> counts) {
  if (counts.length != 4 && counts.length != 8) {
    return null;
  }
  if (counts.any((count) => count != 5 && count != 7)) {
    return null;
  }
  final first = counts.first;
  if (counts.any((count) => count != first)) {
    return null;
  }
  if (counts.length == 4 && first == 5) {
    return '五绝';
  }
  if (counts.length == 4 && first == 7) {
    return '七绝';
  }
  if (counts.length == 8 && first == 5) {
    return '五律';
  }
  if (counts.length == 8 && first == 7) {
    return '七律';
  }
  return null;
}

bool _isModernDynasty(String dynasty) {
  final text = dynasty.trim();
  const modernMarkers = <String>[
    '当代',
    '现代',
    '近现代',
    '现当代',
  ];
  return modernMarkers.any(text.contains);
}

String? _regulatedVerseDynastyBlockReason(String dynasty) {
  final text = dynasty.trim();
  if (text.isEmpty) {
    return '朝代信息为空，暂不自动开启近体诗格律显示。请补充朝代后重新识别。';
  }

  const supportedDynastyMarkers = <String>[
    '唐',
    '五代',
    '后梁',
    '后唐',
    '后晋',
    '后汉',
    '后周',
    '宋',
    '辽',
    '金',
    '元',
    '明',
    '清',
    '近代',
    '现代',
    '当代',
    '现当代',
    '近现代',
    '民国',
  ];
  if (supportedDynastyMarkers.any(text.contains)) {
    return null;
  }

  const earlyDynastyMarkers = <String>[
    '先秦',
    '秦',
    '汉',
    '魏',
    '晋',
    '南北朝',
    '梁',
    '陈',
    '齐',
    '北周',
    '北齐',
  ];
  if (earlyDynastyMarkers.any(text.contains)) {
    return '朝代早于近体诗成熟期，默认视为古体或非近体作品，暂不启用格律显示。';
  }

  return '朝代暂未能确认为唐及以后，暂不自动开启近体诗格律显示。';
}

String? _unsupportedReason({
  required String title,
  required String dynasty,
  required String remark,
  required int lineCount,
}) {
  final markerSource = '$title$remark';
  const unsupportedMarkers = <String>[
    '古诗十九首',
    '古诗',
    '古风',
    '乐府',
    '歌行',
    '杂诗',
    '拟古',
    '行路难',
    '将进酒',
    '短歌行',
    '长歌行',
    '兵车行',
    '丽人行',
    '琵琶行',
    '秦妇吟',
  ];
  for (final marker in unsupportedMarkers) {
    if (markerSource.contains(marker)) {
      return '标题或备注显示此作更接近古体、乐府、歌行、赋或杂体，暂不按近体诗格律检查。';
    }
  }
  if ((title.endsWith('赋') && !title.startsWith('赋得')) ||
      title.contains('赋并序') ||
      title.contains('赋序')) {
    return '标题显示此作更接近赋体，暂不按诗词格律检查。';
  }

  if (lineCount > 8) {
    return '正文超过 8 个非空诗句，第一版暂不支持排律、长篇古体或长篇歌行的格律检查。';
  }

  return null;
}

String? _detectCiTune(String title) {
  final titleBeforeSeparator = title.split(RegExp(r'[·・]')).first;
  for (final name in _ciTuneNames) {
    if (title.startsWith(name) || titleBeforeSeparator == name) {
      return name;
    }
  }
  return null;
}

String? _detectQuTune(String title) {
  for (final name in _quTuneNames) {
    if (title.startsWith(name)) {
      return name;
    }
  }
  return null;
}

const _ciTuneNames = <String>{
  '永遇乐',
  '念奴娇',
  '水调歌头',
  '满江红',
  '虞美人',
  '蝶恋花',
  '鹊桥仙',
  '江城子',
  '浣溪沙',
  '卜算子',
  '如梦令',
  '声声慢',
  '青玉案',
  '雨霖铃',
  '破阵子',
  '渔家傲',
  '苏幕遮',
  '定风波',
  '西江月',
  '临江仙',
  '菩萨蛮',
  '沁园春',
  '扬州慢',
  '摸鱼儿',
  '暗香',
  '疏影',
  '贺新郎',
  '一剪梅',
  '踏莎行',
  '南乡子',
  '浪淘沙',
  '清平乐',
  '忆江南',
  '点绛唇',
  '减字木兰花',
  '木兰花慢',
  '八声甘州',
  '桂枝香',
};

const _quTuneNames = <String>{
  '天净沙',
  '山坡羊',
  '水仙子',
  '折桂令',
  '沉醉东风',
};
