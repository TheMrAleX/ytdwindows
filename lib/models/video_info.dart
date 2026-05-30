class VideoFormat {
  final String formatId;
  final String? ext;
  final int? height;
  final int? width;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final int? abr;
  final int? tbr;
  final int? filesize;
  final String? formatNote;
  final String? resolution;

  VideoFormat({
    required this.formatId,
    this.ext,
    this.height,
    this.width,
    this.fps,
    this.vcodec,
    this.acodec,
    this.abr,
    this.tbr,
    this.filesize,
    this.formatNote,
    this.resolution,
  });

  bool get hasVideo => vcodec != null && vcodec != 'none';
  bool get hasAudio => acodec != null && acodec != 'none';
  bool get isAudioOnly => !hasVideo && hasAudio;
  bool get isVideoOnly => hasVideo && !hasAudio;

  String get label {
    if (isAudioOnly) {
      final br = abr ?? tbr ?? 0;
      return '${ext ?? "?"} • ${br}kbps${formatNote != null ? " • $formatNote" : ""}';
    }
    final res = resolution ?? (height != null ? '${height}p' : '?');
    final fpsStr = fps != null && fps! > 0 ? ' ${fps!.toStringAsFixed(0)}fps' : '';
    return '$res$fpsStr • ${ext ?? "?"}${formatNote != null ? " • $formatNote" : ""}';
  }

  String get sizeLabel {
    if (filesize == null) return '';
    final mb = filesize! / 1024 / 1024;
    if (mb < 1) return '${(filesize! / 1024).toStringAsFixed(0)} KB';
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  factory VideoFormat.fromJson(Map<String, dynamic> j) {
    return VideoFormat(
      formatId: j['format_id']?.toString() ?? '',
      ext: j['ext']?.toString(),
      height: (j['height'] as num?)?.toInt(),
      width: (j['width'] as num?)?.toInt(),
      fps: (j['fps'] as num?)?.toDouble(),
      vcodec: j['vcodec']?.toString(),
      acodec: j['acodec']?.toString(),
      abr: (j['abr'] as num?)?.toInt(),
      tbr: (j['tbr'] as num?)?.toInt(),
      filesize: (j['filesize'] as num?)?.toInt() ?? (j['filesize_approx'] as num?)?.toInt(),
      formatNote: j['format_note']?.toString(),
      resolution: j['resolution']?.toString(),
    );
  }
}

class SubtitleTrack {
  final String lang;
  final String? name;
  final bool auto;

  SubtitleTrack({required this.lang, this.name, this.auto = false});
}

class VideoInfo {
  final String id;
  final String title;
  final String? uploader;
  final String? thumbnail;
  final int? duration;
  final int? viewCount;
  final String? description;
  final String webpageUrl;
  final List<VideoFormat> formats;
  final List<SubtitleTrack> subtitles;
  final List<SubtitleTrack> autoSubtitles;
  final bool partial;

  VideoInfo({
    required this.id,
    required this.title,
    required this.webpageUrl,
    required this.formats,
    required this.subtitles,
    required this.autoSubtitles,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.viewCount,
    this.description,
    this.partial = false,
  });

  static String? extractYtId(String url) {
    final m = RegExp(
      r'(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})',
    ).firstMatch(url);
    return m?.group(1);
  }

  factory VideoInfo.preview(String url) {
    final id = extractYtId(url);
    final thumb = id != null ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null;
    return VideoInfo(
      id: id ?? '',
      title: 'Analizando…',
      webpageUrl: url,
      thumbnail: thumb,
      formats: const [],
      subtitles: const [],
      autoSubtitles: const [],
      partial: true,
    );
  }

  int? get maxAvailableHeight {
    int? max;
    for (final f in formats) {
      if (f.hasVideo && f.height != null) {
        if (max == null || f.height! > max) max = f.height;
      }
    }
    return max;
  }

  String get durationLabel {
    if (duration == null) return '';
    final s = duration!;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, "0")}:${sec.toString().padLeft(2, "0")}';
    return '$m:${sec.toString().padLeft(2, "0")}';
  }

  List<VideoFormat> get videoFormats =>
      formats.where((f) => f.hasVideo).toList()
        ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));

  List<VideoFormat> get audioFormats =>
      formats.where((f) => f.isAudioOnly).toList()
        ..sort((a, b) => (b.abr ?? b.tbr ?? 0).compareTo(a.abr ?? a.tbr ?? 0));

  factory VideoInfo.fromJson(Map<String, dynamic> j) {
    final formats = <VideoFormat>[];
    if (j['formats'] is List) {
      for (final f in j['formats'] as List) {
        if (f is Map<String, dynamic>) formats.add(VideoFormat.fromJson(f));
      }
    }
    final subs = <SubtitleTrack>[];
    final auto = <SubtitleTrack>[];
    if (j['subtitles'] is Map) {
      (j['subtitles'] as Map).forEach((k, v) {
        subs.add(SubtitleTrack(lang: k.toString(), name: _subName(v)));
      });
    }
    if (j['automatic_captions'] is Map) {
      (j['automatic_captions'] as Map).forEach((k, v) {
        auto.add(SubtitleTrack(lang: k.toString(), name: _subName(v), auto: true));
      });
    }
    return VideoInfo(
      id: j['id']?.toString() ?? '',
      title: j['title']?.toString() ?? 'Sin título',
      uploader: j['uploader']?.toString() ?? j['channel']?.toString(),
      thumbnail: j['thumbnail']?.toString(),
      duration: (j['duration'] as num?)?.toInt(),
      viewCount: (j['view_count'] as num?)?.toInt(),
      description: j['description']?.toString(),
      webpageUrl: j['webpage_url']?.toString() ?? j['original_url']?.toString() ?? '',
      formats: formats,
      subtitles: subs,
      autoSubtitles: auto,
    );
  }

  static String? _subName(dynamic v) {
    if (v is List && v.isNotEmpty && v.first is Map) {
      return (v.first as Map)['name']?.toString();
    }
    return null;
  }
}
