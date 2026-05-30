import 'video_info.dart';

enum DownloadKind { videoAudio, audioOnly }

class DownloadOptions {
  final VideoInfo info;
  final DownloadKind kind;

  // Modo preset (cuando el usuario eligió antes que termine el análisis o
  // simplemente quiere "1080p / 4K / etc"). Si esto está, se ignora videoFormat.
  final int? maxHeight;
  final bool best;

  // Modo detalle (formato exacto detectado por yt-dlp).
  final VideoFormat? videoFormat;
  final VideoFormat? audioFormat;

  // Audio preset.
  final String? audioPresetCodec;
  final String? audioPresetQuality;

  final String container;
  final bool downloadSubtitles;
  final List<String> subtitleLangs;
  final bool embedSubtitles;
  final bool sponsorBlock;
  final List<String> sponsorBlockCategories;
  final bool embedThumbnail;
  final bool embedMetadata;
  final String outputDir;

  // Auth opcional: navegador para `--cookies-from-browser` o ruta `cookies.txt`.
  final String? cookiesBrowser;
  final String? cookiesFile;

  DownloadOptions({
    required this.info,
    required this.kind,
    this.maxHeight,
    this.best = false,
    this.videoFormat,
    this.audioFormat,
    this.audioPresetCodec,
    this.audioPresetQuality,
    this.container = 'mp4',
    this.downloadSubtitles = false,
    this.subtitleLangs = const [],
    this.embedSubtitles = true,
    this.sponsorBlock = false,
    this.sponsorBlockCategories = const ['sponsor', 'selfpromo', 'interaction'],
    this.embedThumbnail = true,
    this.embedMetadata = true,
    required this.outputDir,
    this.cookiesBrowser,
    this.cookiesFile,
  });
}

class DownloadProgress {
  final double percent;
  final String? speed;
  final String? eta;
  final String? totalSize;
  final String? phase;
  final String? raw;
  final String? destinationTitle;

  DownloadProgress({
    required this.percent,
    this.speed,
    this.eta,
    this.totalSize,
    this.phase,
    this.raw,
    this.destinationTitle,
  });
}
