import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';

class DeepLinkIntent {
  final String url;
  final String? kind; // 'video' | 'audio'
  final int? height;
  final int? abr;
  final String? codec;
  final String? itag;
  final bool? subs;
  final bool? sponsorBlock;

  DeepLinkIntent({
    required this.url,
    this.kind,
    this.height,
    this.abr,
    this.codec,
    this.itag,
    this.subs,
    this.sponsorBlock,
  });
}

class DeepLinkService {
  static const _channel = MethodChannel('ytdlinux/deeplinks');

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  final _controller = StreamController<DeepLinkIntent>.broadcast();
  bool _channelHandlerInstalled = false;

  Stream<DeepLinkIntent> get intentStream => _controller.stream;

  /// Llamar una sola vez al arrancar. Devuelve el deep link inicial si lo hay.
  /// Las URIs llegadas vía el GApplication primario (otra invocación) llegan
  /// luego por [intentStream].
  Future<DeepLinkIntent?> initial({List<String> launchArgs = const []}) async {
    _installChannelHandler();

    // 1. argv directo (primer arranque con URI en línea de comandos).
    for (final a in launchArgs) {
      if (a.startsWith('ytdlinux:')) {
        try {
          final intent = _extract(Uri.parse(a));
          if (intent != null) return intent;
        } catch (_) {}
      }
    }

    // 2. URIs en cola en el lado nativo (encoladas antes de que registráramos
    // el handler arriba). Las drenamos vía getPending; emitimos las extra a
    // intentStream y devolvemos la primera.
    DeepLinkIntent? first;
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPending');
      if (result != null) {
        for (final raw in result) {
          if (raw is! String) continue;
          try {
            final intent = _extract(Uri.parse(raw));
            if (intent == null) continue;
            if (first == null) {
              first = intent;
            } else {
              _controller.add(intent);
            }
          } catch (_) {}
        }
      }
    } catch (_) {
      // Canal no disponible (modo debug fuera del runner) — ignorar.
    }
    if (first != null) return first;

    // 3. Fallback final: plugin app_links (poco fiable en Linux pero gratis).
    try {
      final uri = await _appLinks.getInitialLink();
      return _extract(uri);
    } catch (_) {
      return null;
    }
  }

  void start() {
    _installChannelHandler();
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen((uri) {
      final intent = _extract(uri);
      if (intent != null) _controller.add(intent);
    }, onError: (_) {});
  }

  void _installChannelHandler() {
    if (_channelHandlerInstalled) return;
    _channelHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final raw = call.arguments;
        if (raw is String) {
          try {
            final intent = _extract(Uri.parse(raw));
            if (intent != null) _controller.add(intent);
          } catch (_) {}
        }
      }
      return null;
    });
  }

  DeepLinkIntent? _extract(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme != 'ytdlinux') return null;
    final q = uri.queryParameters;
    final url = q['url'] ?? q['v'] ?? '';
    String? finalUrl;
    if (url.isNotEmpty) {
      finalUrl = url;
    } else {
      final path = uri.path.replaceAll(RegExp(r'^/+'), '');
      if (path.startsWith('http')) finalUrl = path;
    }
    if (finalUrl == null) return null;
    return DeepLinkIntent(
      url: finalUrl,
      kind: q['kind'],
      height: int.tryParse(q['height'] ?? ''),
      abr: int.tryParse(q['abr'] ?? ''),
      codec: q['codec'],
      itag: q['itag'],
      subs: q['subs'] == '1' ? true : (q['subs'] == '0' ? false : null),
      sponsorBlock: q['sb'] == '1' ? true : (q['sb'] == '0' ? false : null),
    );
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
