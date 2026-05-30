import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/download_options.dart';
import '../models/video_info.dart';
import '../services/deep_link_service.dart';
import '../services/settings_service.dart';
import '../services/ytdlp_service.dart';
import '../services/ytdlp_updater.dart';
import '../widgets/download_row.dart';
import '../widgets/quality_dialog.dart';

class _Job {
  VideoInfo info;
  final String qualityTag;
  DownloadProgress? progress;
  String? error;
  bool done = false;
  bool paused = false;
  StreamSubscription? sub;
  DownloadHandle? handle;
  _Job(this.info, this.qualityTag);
}

class HomeScreen extends StatefulWidget {
  final List<String> launchArgs;
  const HomeScreen({super.key, this.launchArgs = const []});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _yt = YtdlpService();
  final _deepLink = DeepLinkService();
  final _settingsService = SettingsService();
  final _urlController = TextEditingController();
  final _focusNode = FocusNode();
  String? _analyzeError;
  String? _outputDir;
  bool _ytdlpOk = true;
  String _ytdlpVersion = '';
  bool _ytdlpOutdated = false;
  AppSettings _settings = const AppSettings();
  final List<_Job> _jobs = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final ok = await _yt.isAvailable();
    final ver = ok ? await _yt.version() : '';
    final dir = await _resolveOutputDir();
    final settings = await _settingsService.load();
    if (!mounted) return;
    setState(() {
      _ytdlpOk = ok;
      _ytdlpVersion = ver;
      _ytdlpOutdated = ok && _yt.isLikelyOutdated(ver);
      _outputDir = dir;
      _settings = settings;
    });

    final initial = await _deepLink.initial(launchArgs: widget.launchArgs);
    if (initial != null) _handleIntent(initial);
    _deepLink.start();
    _deepLink.intentStream.listen(_handleIntent);
  }

  Future<String> _resolveOutputDir() async {
    try {
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          final candidate = Directory('$userProfile\\Videos\\ytdlinux');
          if (!candidate.existsSync()) candidate.createSync(recursive: true);
          return candidate.path;
        }
      } else {
        final home = Platform.environment['HOME'];
        if (home != null) {
          final candidate = Directory('$home/Videos/ytdlinux');
          if (!candidate.existsSync()) candidate.createSync(recursive: true);
          return candidate.path;
        }
      }
    } catch (_) {}
    final fallback = await getApplicationDocumentsDirectory();
    final sep = Platform.isWindows ? '\\' : '/';
    final d = Directory('${fallback.path}${sep}ytdlinux');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  DeepLinkIntent? _pendingIntent;

  void _handleIntent(DeepLinkIntent intent) {
    _urlController.text = intent.url;
    _focusNode.requestFocus();
    _pendingIntent = intent;
    _analyze();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _focusNode.dispose();
    _deepLink.dispose();
    for (final j in _jobs) {
      j.sub?.cancel();
    }
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null) {
        _urlController.text = data!.text!.trim();
        setState(() {});
      }
    } catch (_) {}
  }

  static final _ytUrlRegex = RegExp(
    r'^(https?:\/\/)?(www\.|m\.|music\.)?(youtube\.com|youtu\.be)\/.+',
    caseSensitive: false,
  );

  String? _validateUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Pega un enlace primero';
    if (!_ytUrlRegex.hasMatch(t)) {
      return 'No parece un enlace de YouTube. Ejemplo: https://www.youtube.com/watch?v=…';
    }
    // Si no tiene scheme, lo dejamos pasar — _normalizeUrl lo arregla.
    return null;
  }

  String _normalizeUrl(String s) {
    final t = s.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return 'https://$t';
  }

  Future<void> _analyze() async {
    final raw = _urlController.text.trim();
    final err = _validateUrl(raw);
    if (err != null) {
      setState(() => _analyzeError = err);
      return;
    }
    if (!_ytdlpOk) {
      setState(() => _analyzeError = 'yt-dlp no está instalado');
      return;
    }
    final url = _normalizeUrl(raw);
    setState(() => _analyzeError = null);

    try {
      await _runAnalyzeFlow(url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzeError = 'Error inesperado: $e');
    }
  }

  Future<void> _runAnalyzeFlow(String url) async {
    final preview = VideoInfo.preview(url);
    final infoFuture = _yt.fetchInfo(
      url,
      cookiesBrowser: _settings.cookiesBrowser,
      cookiesFile: _settings.cookiesFile,
    );

    final intent = _pendingIntent;
    _pendingIntent = null;

    // Si la extension ya eligió calidad, descargar al toque sin diálogo.
    // El análisis sigue corriendo en background para reemplazar título/uploader
    // cuando se resuelva.
    if (intent != null && _intentHasFullQuality(intent)) {
      final result = _qualityResultFromIntent(intent, preview);
      final job = _startDownload(preview, result);
      infoFuture.then((real) {
        if (!mounted) return;
        if (!_jobs.contains(job)) return;
        setState(() => job.info = real);
      }).catchError((_) {});
      return;
    }

    VideoInfo? resolvedInfo;
    final tracker = Completer<void>();
    infoFuture.then((v) {
      resolvedInfo = v;
      if (!tracker.isCompleted) tracker.complete();
    }, onError: (_) {
      if (!tracker.isCompleted) tracker.complete();
    });

    final result = await showDialog<QualityResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QualityDialog(
        preview: preview,
        infoFuture: infoFuture,
        initialKind: intent?.kind,
        initialHeight: intent?.height,
        initialAbr: intent?.abr,
        initialCodec: intent?.codec,
        initialSubs: intent?.subs,
        initialSponsorBlock: intent?.sponsorBlock,
      ),
    );

    if (result == null) {
      tracker.future.ignore();
      return;
    }
    final infoForJob =
        result.info.partial ? (resolvedInfo ?? result.info) : result.info;
    final job = _startDownload(infoForJob, result);

    // Si arrancamos con info parcial (preview), esperamos a que termine el
    // análisis en background para reemplazar título/uploader/duración reales.
    if (infoForJob.partial) {
      infoFuture.then((real) {
        if (!mounted) return;
        if (!_jobs.contains(job)) return;
        setState(() => job.info = real);
      }).catchError((_) {
        // Análisis falló; el job sigue con preview pero yt-dlp puede extraer
        // el título y emitirlo en stdout — lo capturamos abajo en el listener.
      });
    }
  }

  bool _intentHasFullQuality(DeepLinkIntent i) {
    if (i.kind == 'video') return i.height != null;
    if (i.kind == 'audio') return true;
    return false;
  }

  // Mapea codec de la extension al codec que pasa --audio-format en yt-dlp.
  String _mapAudioCodec(String? c) {
    final lc = c?.toLowerCase();
    if (lc == 'opus' || lc == 'mp3' || lc == 'm4a' ||
        lc == 'flac' || lc == 'wav') {
      return lc!;
    }
    if (lc == 'aac') return 'm4a';
    return 'opus'; // fallback razonable: mejor calidad sin recompresión.
  }

  QualityResult _qualityResultFromIntent(DeepLinkIntent i, VideoInfo info) {
    final subs = i.subs ?? false;
    final sb = i.sponsorBlock ?? true;
    if (i.kind == 'audio') {
      final codec = _mapAudioCodec(i.codec);
      return QualityResult(
        info: info,
        kind: DownloadKind.audioOnly,
        audioPresetCodec: codec,
        audioPresetQuality: '0',
        container: codec,
        downloadSubtitles: false,
        subtitleLangs: const [],
        embedSubtitles: false,
        sponsorBlock: sb,
        embedThumbnail: true,
        embedMetadata: true,
      );
    }
    return QualityResult(
      info: info,
      kind: DownloadKind.videoAudio,
      maxHeight: i.height,
      best: false,
      container: 'mp4',
      downloadSubtitles: subs,
      subtitleLangs: subs ? const ['es', 'en'] : const [],
      embedSubtitles: subs,
      sponsorBlock: sb,
      embedThumbnail: true,
      embedMetadata: true,
    );
  }

  String _qualityTag(QualityResult r) {
    if (r.kind == DownloadKind.audioOnly) {
      return r.audioPresetCodec?.toUpperCase() ?? 'AUDIO';
    }
    if (r.videoFormat != null) {
      final h = r.videoFormat!.height;
      return h != null ? '${h}p' : r.videoFormat!.formatId;
    }
    if (r.best) return 'BEST';
    return r.maxHeight != null ? '${r.maxHeight}p' : 'AUTO';
  }

  _Job _startDownload(VideoInfo info, QualityResult r) {
    final outDir = _outputDir!;
    final opts = DownloadOptions(
      info: info,
      kind: r.kind,
      maxHeight: r.maxHeight,
      best: r.best,
      videoFormat: r.videoFormat,
      audioFormat: r.audioFormat,
      audioPresetCodec: r.audioPresetCodec,
      audioPresetQuality: r.audioPresetQuality,
      container: r.container,
      downloadSubtitles: r.downloadSubtitles,
      subtitleLangs: r.subtitleLangs,
      embedSubtitles: r.embedSubtitles,
      sponsorBlock: r.sponsorBlock,
      embedThumbnail: r.embedThumbnail,
      embedMetadata: r.embedMetadata,
      outputDir: outDir,
      cookiesBrowser: _settings.cookiesBrowser,
      cookiesFile: _settings.cookiesFile,
    );
    final job = _Job(info, _qualityTag(r));
    _jobs.insert(0, job);
    setState(() {});

    final handle = _yt.download(opts);
    job.handle = handle;
    job.sub = handle.stream.listen(
      (p) {
        setState(() {
          job.progress = p;
          // Si aún tenemos info parcial y yt-dlp emitió el título por stdout,
          // úsalo como fallback (cuando -J falló pero la descarga sí extrae).
          final t = p.destinationTitle;
          if (job.info.partial &&
              t != null &&
              t.isNotEmpty &&
              t != 'NA' &&
              t != job.info.title) {
            job.info = VideoInfo(
              id: job.info.id,
              title: t,
              webpageUrl: job.info.webpageUrl,
              thumbnail: job.info.thumbnail,
              uploader: job.info.uploader,
              duration: job.info.duration,
              formats: job.info.formats,
              subtitles: job.info.subtitles,
              autoSubtitles: job.info.autoSubtitles,
              partial: true,
            );
          }
        });
      },
      onError: (e) {
        setState(() {
          job.error = e is YtdlpException ? e.message : e.toString();
          job.paused = false;
        });
      },
      onDone: () {
        setState(() {
          if (job.error == null) job.done = true;
          job.paused = false;
        });
      },
    );

    _urlController.clear();
    return job;
  }

  void _pauseJob(_Job j) {
    j.handle?.pause();
    setState(() => j.paused = true);
  }

  void _resumeJob(_Job j) {
    j.handle?.resume();
    setState(() => j.paused = false);
  }

  Future<void> _pickOutputDir() async {
    final r = await FilePicker.platform.getDirectoryPath(initialDirectory: _outputDir);
    if (r != null) setState(() => _outputDir = r);
  }

  Future<void> _openDir(String path) async {
    try {
      await launchUrl(Uri.file(path));
    } catch (_) {
      try {
        await Process.run('xdg-open', [path]);
      } catch (_) {}
    }
  }

  void _cancelJob(_Job j) {
    if (j.paused) {
      // SIGTERM no llega a un proceso pausado; reanudar antes de cancelar.
      j.handle?.resume();
    }
    j.handle?.cancel();
    j.sub?.cancel();
    setState(() {
      j.error = 'Cancelado';
      j.paused = false;
    });
  }

  Future<void> _dismissJob(_Job j) async {
    j.sub?.cancel();
    // Si no terminó, limpiar parciales del disco. yt-dlp deja `.part`, `.ytdl`,
    // streams separados `.f<id>.<ext>`, etc. Todos contienen `[<videoId>]` en
    // el nombre porque el template es `%(title)s [%(id)s].%(ext)s`.
    final shouldClean = !j.done && _outputDir != null && j.info.id.isNotEmpty;
    if (shouldClean) {
      await _cleanupPartials(_outputDir!, j.info.id);
    }
    if (!mounted) return;
    setState(() => _jobs.remove(j));
  }

  Future<void> _cleanupPartials(String dir, String videoId) async {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return;
      final marker = '[$videoId]';
      await for (final entity in d.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!name.contains(marker)) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _clearFinished() {
    setState(() => _jobs.removeWhere((j) => j.done || j.error != null));
  }

  Future<void> _showUpdaterDialog() async {
    final hasActive = _jobs.any((j) => !j.done && j.error == null);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _UpdaterDialog(
        updater: YtdlpUpdater(_yt),
        hasActiveDownloads: hasActive,
      ),
    );
    if (result == true) {
      // Re-bootstrap version + outdated banner tras actualizar.
      final ok = await _yt.isAvailable();
      final ver = ok ? await _yt.version() : '';
      if (!mounted) return;
      setState(() {
        _ytdlpOk = ok;
        _ytdlpVersion = ver;
        _ytdlpOutdated = ok && _yt.isLikelyOutdated(ver);
      });
    }
  }

  Future<void> _showCookiesDialog() async {
    final result = await showDialog<AppSettings>(
      context: context,
      builder: (_) => _CookiesDialog(initial: _settings),
    );
    if (result == null) return;
    await _settingsService.save(result);
    if (!mounted) return;
    setState(() => _settings = result);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'ytdlinux',
      applicationVersion: '1.0.0',
      applicationIcon: Icon(Icons.download_for_offline,
          size: 36, color: Theme.of(context).colorScheme.primary),
      applicationLegalese:
          'Descargador de YouTube nativo para Linux.\nUsa yt-dlp $_ytdlpVersion + ffmpeg.',
    );
  }

  // Stats agregados para la status bar.
  ({int active, int done, int error, double speedBps, int? etaSec}) _stats() {
    int active = 0, done = 0, errors = 0;
    double speed = 0;
    int? etaMax;
    for (final j in _jobs) {
      if (j.done) {
        done++;
      } else if (j.error != null) {
        errors++;
      } else {
        active++;
        final s = _parseSpeed(j.progress?.speed);
        if (s != null) speed += s;
        final e = _parseEta(j.progress?.eta);
        if (e != null) etaMax = (etaMax == null || e > etaMax) ? e : etaMax;
      }
    }
    return (active: active, done: done, error: errors, speedBps: speed, etaSec: etaMax);
  }

  static double? _parseSpeed(String? s) {
    if (s == null) return null;
    final m = RegExp(r'([\d.]+)\s*(KiB|MiB|GiB|B)/s').firstMatch(s);
    if (m == null) return null;
    final v = double.tryParse(m.group(1) ?? '');
    if (v == null) return null;
    final mult = switch (m.group(2)) {
      'KiB' => 1024.0,
      'MiB' => 1024.0 * 1024,
      'GiB' => 1024.0 * 1024 * 1024,
      _ => 1.0,
    };
    return v * mult;
  }

  static int? _parseEta(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }
    if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return null;
  }

  static String _formatBps(double bps) {
    if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KiB/s';
    if (bps < 1024 * 1024 * 1024) return '${(bps / 1024 / 1024).toStringAsFixed(1)} MiB/s';
    return '${(bps / 1024 / 1024 / 1024).toStringAsFixed(2)} GiB/s';
  }

  static String _formatEta(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = _stats();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            _AppIcon(color: scheme.primary),
            const SizedBox(width: 10),
            const Text('ytdlinux',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            if (_ytdlpVersion.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'yt-dlp $_ytdlpVersion',
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Carpeta de salida',
            icon: const Icon(Icons.folder_outlined, size: 20),
            onPressed: _pickOutputDir,
          ),
          PopupMenuButton<String>(
            tooltip: 'Menú',
            icon: const Icon(Icons.menu, size: 20),
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'paste':
                  _pasteFromClipboard().then((_) => _focusNode.requestFocus());
                  break;
                case 'clear':
                  _clearFinished();
                  break;
                case 'open':
                  if (_outputDir != null) _openDir(_outputDir!);
                  break;
                case 'cookies':
                  _showCookiesDialog();
                  break;
                case 'update_ytdlp':
                  _showUpdaterDialog();
                  break;
                case 'about':
                  _showAbout();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'paste',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.content_paste, size: 16),
                  title: Text('Pegar enlace'),
                ),
              ),
              const PopupMenuItem(
                value: 'open',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.folder_open, size: 16),
                  title: Text('Abrir carpeta de salida'),
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.cleaning_services, size: 16),
                  title: Text('Limpiar terminados'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'cookies',
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.cookie_outlined, size: 16),
                  title: const Text('Cookies de navegador'),
                  subtitle: _settings.hasCookies
                      ? Text(
                          _settings.cookiesBrowser != null
                              ? 'Navegador: ${_settings.cookiesBrowser}'
                              : 'Archivo configurado',
                          style: const TextStyle(fontSize: 11),
                        )
                      : null,
                ),
              ),
              if (Platform.isWindows)
                PopupMenuItem(
                  value: 'update_ytdlp',
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.system_update_alt,
                      size: 16,
                      color: _ytdlpOutdated || !_ytdlpOk
                          ? Theme.of(context).colorScheme.tertiary
                          : null,
                    ),
                    title: const Text('Actualizar yt-dlp'),
                    subtitle: _ytdlpVersion.isNotEmpty
                        ? Text('Actual: $_ytdlpVersion',
                            style: const TextStyle(fontSize: 11))
                        : null,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.info_outline, size: 16),
                  title: Text('Acerca de'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!_ytdlpOk)
            _Banner(
              icon: Icons.error_outline,
              color: scheme.errorContainer,
              fg: scheme.onErrorContainer,
              text: Platform.isWindows
                  ? 'yt-dlp no encontrado. Abre el menú → "Actualizar yt-dlp" para descargarlo.'
                  : 'yt-dlp no instalado. Ejecuta: pip install --user --break-system-packages -U yt-dlp',
              action: Platform.isWindows
                  ? _ActionLabel(
                      label: 'Descargar',
                      onTap: _showUpdaterDialog,
                    )
                  : null,
            )
          else if (_ytdlpOutdated)
            _Banner(
              icon: Icons.warning_amber,
              color: scheme.tertiaryContainer,
              fg: scheme.onTertiaryContainer,
              text: Platform.isWindows
                  ? 'yt-dlp $_ytdlpVersion desactualizado. Abre el menú → "Actualizar yt-dlp".'
                  : 'yt-dlp $_ytdlpVersion desactualizado. Actualiza: pip install --user --break-system-packages -U yt-dlp',
              action: Platform.isWindows
                  ? _ActionLabel(
                      label: 'Actualizar',
                      onTap: _showUpdaterDialog,
                    )
                  : null,
            ),
          _Toolbar(
            controller: _urlController,
            focusNode: _focusNode,
            onAnalyze: _analyze,
            onPaste: _pasteFromClipboard,
            onChanged: () {
              if (_analyzeError != null) {
                setState(() => _analyzeError = null);
              } else {
                setState(() {});
              }
            },
            error: _analyzeError,
          ),
          Expanded(
            child: _jobs.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    itemCount: _jobs.length,
                    itemBuilder: (_, i) {
                      final j = _jobs[i];
                      return DownloadRow(
                        info: j.info,
                        qualityTag: j.qualityTag,
                        progress: j.progress,
                        error: j.error,
                        done: j.done,
                        paused: j.paused,
                        onPause: Platform.isWindows ? null : () => _pauseJob(j),
                        onResume: Platform.isWindows ? null : () => _resumeJob(j),
                        onCancel: () => _cancelJob(j),
                        onOpenFolder: () => _openDir(_outputDir!),
                        onDismiss: () => _dismissJob(j),
                      );
                    },
                  ),
          ),
          _StatusBar(
            outputDir: _outputDir,
            stats: stats,
            speedFormatter: _formatBps,
            etaFormatter: _formatEta,
            onOpenDir: () => _outputDir != null ? _openDir(_outputDir!) : null,
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final Color color;
  const _AppIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Icon(Icons.arrow_downward, size: 14, color: Colors.white),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onAnalyze;
  final VoidCallback onPaste;
  final VoidCallback onChanged;
  final String? error;

  const _Toolbar({
    required this.controller,
    required this.focusNode,
    required this.onAnalyze,
    required this.onPaste,
    required this.onChanged,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => onAnalyze(),
                  onChanged: (_) => onChanged(),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Pega un enlace de YouTube y presiona Enter…',
                    hintStyle: TextStyle(fontSize: 14, color: theme.hintColor),
                    prefixIcon: Icon(Icons.link, size: 18, color: theme.hintColor),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: 'Limpiar',
                            onPressed: () {
                              controller.clear();
                              onChanged();
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.content_paste, size: 16),
                          tooltip: 'Pegar (Ctrl+V)',
                          onPressed: onPaste,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAnalyze,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Iniciar', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Text(error!,
                      style: TextStyle(fontSize: 13, color: scheme.error)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String? outputDir;
  final ({int active, int done, int error, double speedBps, int? etaSec}) stats;
  final String Function(double) speedFormatter;
  final String Function(int) etaFormatter;
  final VoidCallback? onOpenDir;

  const _StatusBar({
    required this.outputDir,
    required this.stats,
    required this.speedFormatter,
    required this.etaFormatter,
    required this.onOpenDir,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasActive = stats.active > 0;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (outputDir != null)
            InkWell(
              onTap: onOpenDir,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 14, color: theme.hintColor),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        _shortenPath(outputDir!),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          if (hasActive) ...[
            _StatChip(
              icon: Icons.download,
              label: '${stats.active} activos',
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            _StatChip(
              icon: Icons.speed,
              label: speedFormatter(stats.speedBps),
              color: scheme.primary,
            ),
            if (stats.etaSec != null) ...[
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.timer_outlined,
                label: 'ETA ${etaFormatter(stats.etaSec!)}',
                color: theme.hintColor,
              ),
            ],
            const SizedBox(width: 8),
          ],
          if (stats.done > 0) ...[
            _StatChip(
              icon: Icons.check,
              label: '${stats.done}',
              color: Colors.green.shade600,
            ),
            const SizedBox(width: 8),
          ],
          if (stats.error > 0)
            _StatChip(
              icon: Icons.error_outline,
              label: '${stats.error}',
              color: scheme.error,
            ),
        ],
      ),
    );
  }

  static String _shortenPath(String p) {
    final home = Platform.environment['HOME'];
    if (home != null && p.startsWith(home)) return '~${p.substring(home.length)}';
    return p;
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color fg;
  final String text;
  final _ActionLabel? action;
  const _Banner({
    required this.icon,
    required this.color,
    required this.fg,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: fg, fontSize: 13)),
          ),
          if (action != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: action!.onTap,
              style: TextButton.styleFrom(
                foregroundColor: fg,
                backgroundColor: fg.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: Text(action!.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionLabel {
  final String label;
  final VoidCallback onTap;
  const _ActionLabel({required this.label, required this.onTap});
}

enum _CookiesMode { none, browser, file }

class _CookiesDialog extends StatefulWidget {
  final AppSettings initial;
  const _CookiesDialog({required this.initial});

  @override
  State<_CookiesDialog> createState() => _CookiesDialogState();
}

class _CookiesDialogState extends State<_CookiesDialog> {
  static const _browsers = [
    'chrome',
    'chromium',
    'brave',
    'edge',
    'firefox',
    'opera',
    'vivaldi',
  ];

  late _CookiesMode _mode;
  late String _browser;
  String? _file;

  @override
  void initState() {
    super.initState();
    if (widget.initial.cookiesBrowser != null) {
      _mode = _CookiesMode.browser;
      _browser = widget.initial.cookiesBrowser!;
    } else if (widget.initial.cookiesFile != null) {
      _mode = _CookiesMode.file;
      _browser = _browsers.first;
      _file = widget.initial.cookiesFile;
    } else {
      _mode = _CookiesMode.none;
      _browser = _browsers.first;
    }
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Seleccionar cookies.txt',
      type: FileType.any,
    );
    if (r != null && r.files.single.path != null) {
      setState(() => _file = r.files.single.path);
    }
  }

  AppSettings _build() {
    switch (_mode) {
      case _CookiesMode.none:
        return const AppSettings();
      case _CookiesMode.browser:
        return AppSettings(cookiesBrowser: _browser);
      case _CookiesMode.file:
        return AppSettings(cookiesFile: _file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Cookies de navegador'),
      content: SizedBox(
        width: 420,
        child: RadioGroup<_CookiesMode>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? _CookiesMode.none),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para videos privados, con restricción de edad o solo-miembros. '
                'yt-dlp lee las cookies del navegador o de un archivo cookies.txt.',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
              const SizedBox(height: 14),
              const RadioListTile<_CookiesMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Sin cookies'),
                value: _CookiesMode.none,
              ),
              RadioListTile<_CookiesMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Desde navegador'),
                subtitle: _mode == _CookiesMode.browser
                    ? DropdownButton<String>(
                        isDense: true,
                        isExpanded: true,
                        value: _browser,
                        items: [
                          for (final b in _browsers)
                            DropdownMenuItem(value: b, child: Text(b)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _browser = v);
                        },
                      )
                    : null,
                value: _CookiesMode.browser,
              ),
              RadioListTile<_CookiesMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Archivo cookies.txt'),
                subtitle: _mode == _CookiesMode.file
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              _file ?? 'Sin archivo',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: theme.hintColor),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: const Text('Elegir'),
                          ),
                        ],
                      )
                    : null,
                value: _CookiesMode.file,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_mode == _CookiesMode.file && _file == null)
              ? null
              : () => Navigator.pop(context, _build()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _UpdaterDialog extends StatefulWidget {
  final YtdlpUpdater updater;
  final bool hasActiveDownloads;
  const _UpdaterDialog({
    required this.updater,
    required this.hasActiveDownloads,
  });

  @override
  State<_UpdaterDialog> createState() => _UpdaterDialogState();
}

class _UpdaterDialogState extends State<_UpdaterDialog> {
  UpdateCheck? _check;
  bool _checking = false;
  bool _downloading = false;
  bool _installed = false;
  UpdateDownloadProgress? _progress;
  StreamSubscription<UpdateDownloadProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _runCheck() async {
    setState(() => _checking = true);
    final r = await widget.updater.check();
    if (!mounted) return;
    setState(() {
      _check = r;
      _checking = false;
    });
  }

  void _startDownload() {
    final url = _check?.downloadUrl;
    if (url == null) return;
    setState(() {
      _downloading = true;
      _progress = null;
    });
    _sub = widget.updater.download(url).listen(
      (p) {
        if (!mounted) return;
        setState(() => _progress = p);
        if (p.done) {
          setState(() {
            _downloading = false;
            _installed = true;
          });
        } else if (p.error != null) {
          setState(() => _downloading = false);
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _progress = UpdateDownloadProgress(received: 0, error: '$e');
        });
      },
    );
  }

  static String _fmtBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KiB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MiB';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GiB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _check;

    Widget content;
    if (_checking) {
      content = const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Consultando GitHub…'),
        ],
      );
    } else if (c == null) {
      content = const Text('Error inesperado.');
    } else if (c.error != null) {
      content = Text(c.error!, style: TextStyle(color: scheme.error));
    } else {
      final hasUpdate = c.hasUpdate;
      final upToDate = c.upToDate;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _kv('Instalada', c.localVersion ?? '— no instalada —'),
          const SizedBox(height: 6),
          _kv('Última estable', c.latestVersion ?? 'desconocida'),
          const SizedBox(height: 14),
          if (_installed)
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                const Text('Instalado. Reiniciar descargas para usar la nueva versión.'),
              ],
            )
          else if (_downloading) ...[
            LinearProgressIndicator(
              value: _progress?.fraction,
              minHeight: 6,
            ),
            const SizedBox(height: 6),
            Text(
              _progress == null
                  ? 'Iniciando…'
                  : (_progress!.error ??
                      (_progress!.total != null
                          ? '${_fmtBytes(_progress!.received)} / ${_fmtBytes(_progress!.total!)}'
                          : _fmtBytes(_progress!.received))),
              style: TextStyle(
                fontSize: 12,
                color: _progress?.error != null ? scheme.error : theme.hintColor,
              ),
            ),
          ] else if (_progress?.error != null)
            Text(_progress!.error!, style: TextStyle(color: scheme.error))
          else if (upToDate)
            Row(
              children: [
                Icon(Icons.verified, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 8),
                const Text('Estás en la última versión.'),
              ],
            )
          else if (hasUpdate)
            Row(
              children: [
                Icon(Icons.info_outline, color: scheme.tertiary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.downloadSize != null
                        ? 'Nueva versión disponible (${_fmtBytes(c.downloadSize!)}).'
                        : 'Nueva versión disponible.',
                  ),
                ),
              ],
            )
          else if (c.localVersion == null)
            Row(
              children: [
                Icon(Icons.download_for_offline, color: scheme.primary, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('yt-dlp no instalado. Descargar ahora.')),
              ],
            ),
          if (widget.hasActiveDownloads &&
              (hasUpdate || c.localVersion == null) &&
              !_downloading &&
              !_installed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hay descargas activas. Reemplazar el ejecutable puede fallar mientras yt-dlp esté corriendo.',
                      style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }

    final c2 = _check;
    final canDownload = !_checking &&
        !_downloading &&
        !_installed &&
        c2 != null &&
        c2.error == null &&
        c2.downloadUrl != null &&
        (c2.hasUpdate || c2.localVersion == null);

    return AlertDialog(
      title: const Text('Actualizar yt-dlp'),
      content: SizedBox(width: 440, child: content),
      actions: [
        if (!_checking && !_downloading && !_installed)
          TextButton(
            onPressed: _runCheck,
            child: const Text('Re-verificar'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, _installed),
          child: Text(_installed ? 'Listo' : 'Cerrar'),
        ),
        if (canDownload)
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download, size: 16),
            label: Text(c2.localVersion == null ? 'Descargar' : 'Actualizar'),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: TextStyle(color: theme.hintColor, fontSize: 13)),
        ),
        Expanded(
          child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_downward,
                size: 28, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 14),
          Text('Listo para descargar',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            'Pega una URL arriba o usa la extensión del navegador',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
