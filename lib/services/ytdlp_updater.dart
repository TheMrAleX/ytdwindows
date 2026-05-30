import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ytdlp_service.dart';

/// Resultado de check contra GitHub Releases de yt-dlp.
class UpdateCheck {
  final String? latestVersion;
  final String? localVersion;
  final String? downloadUrl;
  final int? downloadSize;
  final String? error;

  bool get hasUpdate {
    if (latestVersion == null || localVersion == null) return false;
    return _compare(latestVersion!, localVersion!) > 0;
  }

  bool get upToDate {
    if (latestVersion == null || localVersion == null) return false;
    return _compare(latestVersion!, localVersion!) <= 0;
  }

  const UpdateCheck({
    this.latestVersion,
    this.localVersion,
    this.downloadUrl,
    this.downloadSize,
    this.error,
  });

  /// Compara versiones yt-dlp formato YYYY.MM.DD (o YYYY.MM.DD.PATCH).
  /// Devuelve >0 si a > b, <0 si a < b, 0 si iguales.
  static int _compare(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }
}

/// Progreso de la descarga. [received] y [total] en bytes.
class UpdateDownloadProgress {
  final int received;
  final int? total;
  final bool done;
  final String? error;

  const UpdateDownloadProgress({
    required this.received,
    this.total,
    this.done = false,
    this.error,
  });

  double? get fraction => total != null && total! > 0 ? received / total! : null;
}

class YtdlpUpdater {
  final YtdlpService yt;
  YtdlpUpdater(this.yt);

  static const _releasesUrl =
      'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';

  String _assetName() {
    if (Platform.isWindows) return 'yt-dlp.exe';
    // Linux: en Linux preferimos pip; este updater solo se usa en Windows.
    return 'yt-dlp';
  }

  /// Path donde se instala el binario actualizable.
  String installPath() {
    if (Platform.isWindows) {
      return '${YtdlpService.windowsBinDir()}\\yt-dlp.exe';
    }
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.local/bin/yt-dlp';
  }

  Future<UpdateCheck> check() async {
    String? local;
    try {
      local = await yt.version();
      if (local == 'no disponible') local = null;
    } catch (_) {}

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(_releasesUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'ytdlinux-updater');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close();
      if (res.statusCode != 200) {
        return UpdateCheck(
          localVersion: local,
          error: 'GitHub respondió ${res.statusCode}',
        );
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final assets = (json['assets'] as List?) ?? const [];
      final targetName = _assetName();
      Map<String, dynamic>? match;
      for (final a in assets) {
        if (a is Map<String, dynamic> && a['name'] == targetName) {
          match = a;
          break;
        }
      }
      return UpdateCheck(
        latestVersion: tag.isEmpty ? null : tag,
        localVersion: local,
        downloadUrl: match?['browser_download_url'] as String?,
        downloadSize: (match?['size'] as num?)?.toInt(),
      );
    } catch (e) {
      return UpdateCheck(
        localVersion: local,
        error: 'No se pudo consultar GitHub: $e',
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// Descarga el asset a un archivo temporal y luego lo mueve al destino.
  /// Emite UpdateDownloadProgress hasta done=true o error.
  Stream<UpdateDownloadProgress> download(String url) async* {
    final target = installPath();
    final targetFile = File(target);
    final dir = targetFile.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tmp = File('${targetFile.path}.part');
    if (tmp.existsSync()) {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }

    final controller = StreamController<UpdateDownloadProgress>();
    HttpClient? client;

    Future<void> run() async {
      try {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
        var current = Uri.parse(url);
        HttpClientResponse? res;
        // Manual redirect chain (GitHub asset URLs redirect a S3).
        for (var i = 0; i < 5; i++) {
          final req = await client!.getUrl(current);
          req.headers.set(HttpHeaders.userAgentHeader, 'ytdlinux-updater');
          req.followRedirects = false;
          final r = await req.close();
          if (r.statusCode >= 300 && r.statusCode < 400) {
            final loc = r.headers.value(HttpHeaders.locationHeader);
            if (loc == null) {
              controller.add(UpdateDownloadProgress(
                received: 0,
                error: 'Redirect sin Location',
              ));
              await controller.close();
              return;
            }
            current = Uri.parse(loc);
            await r.drain();
            continue;
          }
          res = r;
          break;
        }
        if (res == null) {
          controller.add(const UpdateDownloadProgress(
            received: 0,
            error: 'Demasiados redirects',
          ));
          await controller.close();
          return;
        }
        if (res.statusCode != 200) {
          controller.add(UpdateDownloadProgress(
            received: 0,
            error: 'HTTP ${res.statusCode}',
          ));
          await controller.close();
          return;
        }

        final total = res.contentLength > 0 ? res.contentLength : null;
        final sink = tmp.openWrite();
        var received = 0;
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          controller.add(UpdateDownloadProgress(received: received, total: total));
        }
        await sink.flush();
        await sink.close();

        // Mover atómico: si el binario está en uso, falla. En Windows hay que
        // intentar borrar/renombrar el viejo primero.
        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (e) {
            controller.add(UpdateDownloadProgress(
              received: received,
              total: total,
              error:
                  'No se pudo reemplazar el archivo (¿app en uso?). Cierra descargas activas e intenta de nuevo.',
            ));
            await controller.close();
            return;
          }
        }
        tmp.renameSync(targetFile.path);

        // En Linux, dar permiso ejecutable.
        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['+x', targetFile.path]);
          } catch (_) {}
        }

        yt.resetBinaryCache();
        controller.add(UpdateDownloadProgress(
          received: received,
          total: total,
          done: true,
        ));
        await controller.close();
      } catch (e) {
        controller.add(UpdateDownloadProgress(received: 0, error: 'Error: $e'));
        await controller.close();
      } finally {
        client?.close(force: true);
      }
    }

    unawaited(run());
    yield* controller.stream;
  }
}
