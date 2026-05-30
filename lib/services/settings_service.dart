import 'dart:convert';
import 'dart:io';

/// Persistencia simple en `~/.config/ytdlinux/settings.json`. Sin deps externas.
class AppSettings {
  /// Navegador para `--cookies-from-browser`. Ej: chrome, firefox, brave, edge,
  /// chromium, opera, vivaldi, safari. Mutuamente exclusivo con [cookiesFile].
  final String? cookiesBrowser;

  /// Archivo `cookies.txt` (formato Netscape) para `--cookies <file>`.
  final String? cookiesFile;

  const AppSettings({this.cookiesBrowser, this.cookiesFile});

  bool get hasCookies =>
      (cookiesBrowser != null && cookiesBrowser!.isNotEmpty) ||
      (cookiesFile != null && cookiesFile!.isNotEmpty);

  AppSettings copyWith({
    String? cookiesBrowser,
    String? cookiesFile,
    bool clearCookies = false,
  }) {
    if (clearCookies) {
      return const AppSettings();
    }
    return AppSettings(
      cookiesBrowser: cookiesBrowser ?? this.cookiesBrowser,
      cookiesFile: cookiesFile ?? this.cookiesFile,
    );
  }

  Map<String, dynamic> toJson() => {
        if (cookiesBrowser != null) 'cookiesBrowser': cookiesBrowser,
        if (cookiesFile != null) 'cookiesFile': cookiesFile,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        cookiesBrowser: (j['cookiesBrowser'] as String?)?.trim().isEmpty == true
            ? null
            : j['cookiesBrowser'] as String?,
        cookiesFile: (j['cookiesFile'] as String?)?.trim().isEmpty == true
            ? null
            : j['cookiesFile'] as String?,
      );
}

class SettingsService {
  File _file() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE'] ?? '.'}\\AppData\\Roaming';
      return File('$appData\\ytdlinux\\settings.json');
    }
    final home = Platform.environment['HOME'] ?? '.';
    return File('$home/.config/ytdlinux/settings.json');
  }

  Future<AppSettings> load() async {
    try {
      final f = _file();
      if (!await f.exists()) return const AppSettings();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const AppSettings();
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return AppSettings.fromJson(j);
    } catch (_) {}
    return const AppSettings();
  }

  Future<void> save(AppSettings s) async {
    try {
      final f = _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(s.toJson()));
    } catch (_) {}
  }
}
