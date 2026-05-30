import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/download_options.dart';
import '../models/video_info.dart';

class YtdlpException implements Exception {
  final String message;
  final String? stderr;
  YtdlpException(this.message, [this.stderr]);
  @override
  String toString() => 'YtdlpException: $message${stderr != null ? "\n$stderr" : ""}';
}

class DownloadHandle {
  final Stream<DownloadProgress> stream;
  final bool canPause;
  final void Function() pause;
  final void Function() resume;
  final void Function() cancel;
  DownloadHandle({
    required this.stream,
    required this.pause,
    required this.resume,
    required this.cancel,
    this.canPause = true,
  });
}

class YtdlpService {
  String? _binary;
  String? _ffmpegDir;
  // Cache de detección de runtime JS. yt-dlp >= 2026 necesita un runtime
  // (node/deno/bun) para resolver el "n challenge" de YouTube — sin esto
  // muchos videos devuelven solo storyboards.
  bool? _hasNode;

  /// Directorio donde vive el ejecutable de la app — para resolver binarios
  /// portables (Windows: yt-dlp.exe + ffmpeg/) que viajan junto al .exe.
  static String appDir() {
    return File(Platform.resolvedExecutable).parent.path;
  }

  /// En Windows guardamos yt-dlp.exe en %APPDATA%\ytdlinux\bin para poder
  /// actualizarlo (la carpeta de la app suele ser read-only o requiere admin).
  /// En primer arranque copiamos el yt-dlp.exe bundleado allí.
  static String windowsBinDir() {
    final appData = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE'] ?? ''}\\AppData\\Roaming';
    return '$appData\\ytdlinux\\bin';
  }

  /// Limpia el cache de binarios para que el próximo llamado re-resuelva.
  /// Usado después de actualizar yt-dlp.
  void resetBinaryCache() {
    _binary = null;
  }

  String _resolveBinary() {
    if (_binary != null) return _binary!;
    final env = Platform.environment['YTDLINUX_YTDLP'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return _binary = env;
    }
    if (Platform.isWindows) {
      // Preferencia: %APPDATA%\ytdlinux\bin\yt-dlp.exe (actualizable).
      // Fallback: bundle junto al .exe (primer arranque, antes de copiar).
      final updatable = '${windowsBinDir()}\\yt-dlp.exe';
      if (File(updatable).existsSync()) return _binary = updatable;
      final bundled = '${appDir()}\\yt-dlp.exe';
      if (File(bundled).existsSync()) return _binary = bundled;
      return _binary = 'yt-dlp.exe';
    }
    final home = Platform.environment['HOME'];
    if (home != null) {
      final local = '$home/.local/bin/yt-dlp';
      if (File(local).existsSync()) return _binary = local;
    }
    return _binary = 'yt-dlp';
  }

  String get binary => _resolveBinary();

  /// Devuelve directorio con ffmpeg.exe en Windows (bundleado junto al .exe).
  /// En Linux devuelve null — usamos ffmpeg del sistema.
  String? _resolveFfmpegDir() {
    if (_ffmpegDir != null) return _ffmpegDir;
    if (!Platform.isWindows) return null;
    // 1) ffmpeg.exe directo al lado del runner
    final beside = '${appDir()}\\ffmpeg.exe';
    if (File(beside).existsSync()) return _ffmpegDir = appDir();
    // 2) subcarpeta ffmpeg/bin/ffmpeg.exe (layout zip oficial)
    final subBin = '${appDir()}\\ffmpeg\\bin\\ffmpeg.exe';
    if (File(subBin).existsSync()) return _ffmpegDir = '${appDir()}\\ffmpeg\\bin';
    final subDirect = '${appDir()}\\ffmpeg\\ffmpeg.exe';
    if (File(subDirect).existsSync()) return _ffmpegDir = '${appDir()}\\ffmpeg';
    return null;
  }

  Future<bool> _nodeAvailable() async {
    if (_hasNode != null) return _hasNode!;
    try {
      final r = await Process.run('node', ['--version'], runInShell: false);
      return _hasNode = r.exitCode == 0;
    } catch (_) {
      return _hasNode = false;
    }
  }

  /// Inserta `--js-runtimes node` cuando node esté disponible. Necesario
  /// para que yt-dlp resuelva el JS challenge de YouTube en builds recientes.
  Future<void> _maybeAddJsRuntime(List<String> args) async {
    if (await _nodeAvailable()) {
      args.addAll(['--js-runtimes', 'node']);
    }
  }

  Future<bool> isAvailable() async {
    try {
      final r = await Process.run(binary, ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String> version() async {
    try {
      final r = await Process.run(binary, ['--version']);
      return (r.stdout as String).trim();
    } catch (_) {
      return 'no disponible';
    }
  }

  /// Devuelve true si la versión parece anterior a 2025-01.
  /// Formato versión yt-dlp: YYYY.MM.DD
  bool isLikelyOutdated(String v) {
    final m = RegExp(r'^(\d{4})\.(\d{1,2})').firstMatch(v);
    if (m == null) return false;
    final year = int.tryParse(m.group(1) ?? '') ?? 0;
    return year < 2025;
  }

  Future<VideoInfo> fetchInfo(
    String url, {
    String? cookiesBrowser,
    String? cookiesFile,
  }) async {
    if (url.trim().isEmpty) {
      throw YtdlpException('URL vacía');
    }
    try {
      final args = <String>[
        '-J',
        '--no-playlist',
        '--no-warnings',
        '--skip-download',
        '--ignore-no-formats-error',
      ];
      await _maybeAddJsRuntime(args);
      if (cookiesBrowser != null && cookiesBrowser.isNotEmpty) {
        args.addAll(['--cookies-from-browser', cookiesBrowser]);
      } else if (cookiesFile != null && cookiesFile.isNotEmpty) {
        args.addAll(['--cookies', cookiesFile]);
      }
      args.addAll(['--', url]);
      final result = await Process.run(
        binary,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        final err = (result.stderr as String).trim();
        throw YtdlpException(_friendlyError(err), err);
      }
      final out = (result.stdout as String).trim();
      if (out.isEmpty) throw YtdlpException('yt-dlp no devolvió datos');
      final json = jsonDecode(out);
      if (json is! Map<String, dynamic>) {
        throw YtdlpException('Respuesta inesperada de yt-dlp');
      }
      return VideoInfo.fromJson(json);
    } on YtdlpException {
      rethrow;
    } on FormatException catch (e) {
      throw YtdlpException('JSON inválido de yt-dlp: ${e.message}');
    } on ProcessException catch (e) {
      throw YtdlpException('No se pudo ejecutar yt-dlp: ${e.message}');
    } catch (e) {
      throw YtdlpException('Error inesperado: $e');
    }
  }

  DownloadHandle download(DownloadOptions opts) {
    final controller = StreamController<DownloadProgress>();
    Process? proc;

    Future<void> run() async {
      try {
        final args = await _buildArgs(opts);
        // En Windows usamos detachedWithStdio para evitar que aparezca una
        // ventana de consola al spawnear yt-dlp.exe (subsistema CONSOLE).
        // En Linux usamos normal porque necesitamos SIGSTOP/SIGCONT/SIGTERM.
        final mode = Platform.isWindows
            ? ProcessStartMode.detachedWithStdio
            : ProcessStartMode.normal;
        proc = await Process.start(binary, args, runInShell: false, mode: mode);

        proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          final p = _parseProgress(line);
          if (p != null) controller.add(p);
        }, onError: (e) {
          controller.add(DownloadProgress(percent: -1, phase: 'stdout error', raw: e.toString()));
        });

        final errBuf = StringBuffer();
        proc!.stderr.transform(utf8.decoder).listen((data) {
          errBuf.write(data);
          for (final line in const LineSplitter().convert(data)) {
            if (line.trim().isEmpty) continue;
            controller.add(DownloadProgress(percent: -1, phase: 'log', raw: line));
          }
        });

        final code = await proc!.exitCode;
        if (code == 0) {
          controller.add(DownloadProgress(percent: 100, phase: 'done'));
          await controller.close();
        } else {
          controller.addError(YtdlpException(
            _friendlyError(errBuf.toString()),
            errBuf.toString(),
          ));
          await controller.close();
        }
      } on ProcessException catch (e) {
        controller.addError(YtdlpException('No se pudo iniciar yt-dlp: ${e.message}'));
        await controller.close();
      } catch (e) {
        controller.addError(YtdlpException('Error en descarga: $e'));
        await controller.close();
      }
    }

    void killTerm() {
      try {
        // Windows no entiende SIGTERM; kill() default mapea a TerminateProcess.
        proc?.kill(Platform.isWindows ? ProcessSignal.sigkill : ProcessSignal.sigterm);
      } catch (_) {}
    }

    controller.onCancel = () async => killTerm();

    run();

    return DownloadHandle(
      stream: controller.stream,
      canPause: !Platform.isWindows,
      pause: () {
        if (Platform.isWindows) return; // no SIGSTOP en Windows.
        try {
          proc?.kill(ProcessSignal.sigstop);
        } catch (_) {}
      },
      resume: () {
        if (Platform.isWindows) return;
        try {
          proc?.kill(ProcessSignal.sigcont);
        } catch (_) {}
      },
      cancel: killTerm,
    );
  }

  String _buildVideoSelector(DownloadOptions o) {
    if (o.videoFormat != null) {
      final v = o.videoFormat!;
      if (v.hasAudio) return v.formatId;
      if (o.audioFormat != null) return '${v.formatId}+${o.audioFormat!.formatId}';
      return '${v.formatId}+ba/b';
    }
    if (o.best || o.maxHeight == null) {
      return 'bv*+ba/b';
    }
    final h = o.maxHeight!;
    return 'bv*[height<=$h]+ba/b/b[height<=$h]/b';
  }

  String _buildAudioSelector(DownloadOptions o) {
    if (o.audioFormat != null) return o.audioFormat!.formatId;
    return 'ba/b';
  }

  Future<List<String>> _buildArgs(DownloadOptions o) async {
    final sep = Platform.isWindows ? '\\' : '/';
    final args = <String>[
      '--newline',
      '--no-playlist',
      '--ignore-no-formats-error',
      '--progress',
      '--progress-template',
      'PROG|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s|%(info.title)s',
      '-o',
      '${o.outputDir}$sep%(title)s [%(id)s].%(ext)s',
    ];
    final ffmpegDir = _resolveFfmpegDir();
    if (ffmpegDir != null) {
      args.addAll(['--ffmpeg-location', ffmpegDir]);
    }
    await _maybeAddJsRuntime(args);

    if (o.kind == DownloadKind.audioOnly) {
      args.addAll(['-x', '-f', _buildAudioSelector(o)]);
      final codec = o.audioPresetCodec ?? 'mp3';
      args.addAll(['--audio-format', codec]);
      final q = o.audioPresetQuality ?? '0';
      args.addAll(['--audio-quality', q]);
    } else {
      args.addAll([
        '-f',
        _buildVideoSelector(o),
        '--merge-output-format',
        o.container,
      ]);
    }

    if (o.embedThumbnail) args.add('--embed-thumbnail');
    if (o.embedMetadata) args.add('--embed-metadata');

    if (o.downloadSubtitles && o.subtitleLangs.isNotEmpty) {
      args.addAll([
        '--write-subs',
        '--write-auto-subs',
        '--sub-langs',
        o.subtitleLangs.join(','),
        '--sub-format',
        'srt/best',
        '--convert-subs',
        'srt',
      ]);
      if (o.embedSubtitles && o.kind == DownloadKind.videoAudio) {
        args.add('--embed-subs');
      }
    }

    if (o.sponsorBlock && o.sponsorBlockCategories.isNotEmpty) {
      args.addAll([
        '--sponsorblock-remove',
        o.sponsorBlockCategories.join(','),
      ]);
    }

    // Auth: --cookies-from-browser tiene prioridad sobre --cookies file.
    if (o.cookiesBrowser != null && o.cookiesBrowser!.isNotEmpty) {
      args.addAll(['--cookies-from-browser', o.cookiesBrowser!]);
    } else if (o.cookiesFile != null && o.cookiesFile!.isNotEmpty) {
      args.addAll(['--cookies', o.cookiesFile!]);
    }

    args.addAll(['--', o.info.webpageUrl]);
    return args;
  }

  DownloadProgress? _parseProgress(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('PROG|')) {
      final parts = t.split('|');
      if (parts.length >= 5) {
        final pctStr = parts[1].trim().replaceAll('%', '').replaceAll('NA', '');
        final pct = double.tryParse(pctStr);
        return DownloadProgress(
          percent: pct ?? 0,
          speed: parts[2].trim() == 'NA' ? null : parts[2].trim(),
          eta: parts[3].trim() == 'NA' ? null : parts[3].trim(),
          totalSize: parts[4].trim() == 'NA' ? null : parts[4].trim(),
          phase: 'downloading',
          raw: line,
          destinationTitle: parts.length >= 6 ? parts[5].trim() : null,
        );
      }
    }
    if (t.startsWith('[Merger]') ||
        t.startsWith('[ExtractAudio]') ||
        t.startsWith('[EmbedSubtitle]') ||
        t.startsWith('[Metadata]') ||
        t.startsWith('[ThumbnailsConvertor]') ||
        t.startsWith('[SponsorBlock]') ||
        t.startsWith('[ModifyChapters]') ||
        t.startsWith('[FixupM3u8]') ||
        t.startsWith('[download] Destination')) {
      return DownloadProgress(percent: -1, phase: 'post', raw: t);
    }
    return DownloadProgress(percent: -1, phase: 'log', raw: t);
  }

  String _friendlyError(String stderr) {
    final s = stderr.toLowerCase();
    if (s.contains('private video')) return 'Video privado.';
    if (s.contains('members-only') || s.contains('members only')) {
      return 'Video solo para miembros del canal.';
    }
    if (s.contains('removed by the uploader') || s.contains('this video has been removed')) {
      return 'Video eliminado por el autor.';
    }
    if (s.contains('terminated') || s.contains('terms of service')) {
      return 'Cuenta del canal terminada.';
    }
    if (s.contains('not available in your country') || s.contains('blocked in your country')) {
      return 'Video bloqueado en tu país.';
    }
    if (s.contains('http error 403')) return 'YouTube bloqueó la solicitud (403). Reintentar.';
    if (s.contains('http error 429')) return 'Demasiadas peticiones (429). Esperar y reintentar.';
    if (s.contains('http error 404') || s.contains('not found')) {
      return 'Video no encontrado (404).';
    }
    if (s.contains('video unavailable') || s.contains('unavailable')) {
      return 'Video no disponible.';
    }
    if (s.contains('sign in') || s.contains('login required') || s.contains('confirm your age')) {
      return 'Requiere inicio de sesión o verificación de edad.';
    }
    // Word-boundary match para evitar falsos positivos con manage/package/storage
    // que aparecen en errores de cookies y otros stderr no relacionados.
    final ageRe = RegExp(
      r'\b(age[- ]?restrict|age[- ]?gate|age[- ]?verif|inappropriate for some users)',
      caseSensitive: false,
    );
    if (ageRe.hasMatch(stderr)) return 'Video con restricción de edad.';
    if (s.contains('is not a valid url') || s.contains('unsupported url')) {
      return 'URL no soportada o inválida.';
    }
    if (s.contains('no video formats') || s.contains('no playable')) {
      return 'No hay formatos descargables disponibles.';
    }
    if (s.contains('live event will begin') || s.contains('premiere')) {
      return 'Es un live/premiere que aún no comenzó.';
    }
    if (s.contains('network') || s.contains('connection') || s.contains('resolve host') || s.contains('timed out') || s.contains('timeout')) {
      return 'Error de red. Revisa tu conexión.';
    }
    if (s.contains('ffmpeg')) return 'Falta ffmpeg o falló al procesar.';
    if (s.contains('requested format is not available')) {
      return 'Formato exacto no disponible. Se usará el más cercano.';
    }
    if (stderr.trim().isEmpty) return 'Error desconocido en yt-dlp';
    final firstLine = stderr.trim().split('\n').last.trim();
    if (firstLine.length > 200) return '${firstLine.substring(0, 200)}…';
    return firstLine;
  }
}
