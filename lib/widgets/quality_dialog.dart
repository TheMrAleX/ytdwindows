import 'package:cached_network_image/cached_network_image.dart' hide DownloadProgress;
import 'package:flutter/material.dart';

import '../models/download_options.dart';
import '../models/video_info.dart';

class QualityResult {
  final VideoInfo info;
  final DownloadKind kind;

  // Video preset
  final int? maxHeight;
  final bool best;
  // Video exacto
  final VideoFormat? videoFormat;
  final VideoFormat? audioFormat;

  // Audio preset
  final String? audioPresetCodec;
  final String? audioPresetQuality;

  final String container;
  final bool downloadSubtitles;
  final List<String> subtitleLangs;
  final bool embedSubtitles;
  final bool sponsorBlock;
  final bool embedThumbnail;
  final bool embedMetadata;

  QualityResult({
    required this.info,
    required this.kind,
    this.maxHeight,
    this.best = false,
    this.videoFormat,
    this.audioFormat,
    this.audioPresetCodec,
    this.audioPresetQuality,
    required this.container,
    required this.downloadSubtitles,
    required this.subtitleLangs,
    required this.embedSubtitles,
    required this.sponsorBlock,
    required this.embedThumbnail,
    required this.embedMetadata,
  });
}

class _VideoPreset {
  final String label;
  final int? height; // null = best
  final IconData icon;
  const _VideoPreset(this.label, this.height, this.icon);
}

class _AudioPreset {
  final String label;
  final String codec; // mp3, m4a, opus, flac, wav
  final String quality; // 0-10 vbr o "320"
  final String tag;
  const _AudioPreset(this.label, this.codec, this.quality, this.tag);
}

const _videoPresets = <_VideoPreset>[
  _VideoPreset('Mejor calidad', null, Icons.auto_awesome),
  _VideoPreset('4K (2160p)', 2160, Icons.movie_filter),
  _VideoPreset('2K (1440p)', 1440, Icons.movie_filter),
  _VideoPreset('1080p Full HD', 1080, Icons.high_quality),
  _VideoPreset('720p HD', 720, Icons.hd),
  _VideoPreset('480p', 480, Icons.sd),
  _VideoPreset('360p', 360, Icons.sd),
  _VideoPreset('240p', 240, Icons.sd),
  _VideoPreset('144p', 144, Icons.sd),
];

const _audioPresets = <_AudioPreset>[
  _AudioPreset('Mejor audio', 'opus', '0', 'opus'),
  _AudioPreset('MP3 320 kbps', 'mp3', '0', '320k'),
  _AudioPreset('MP3 192 kbps', 'mp3', '5', '192k'),
  _AudioPreset('M4A AAC alta', 'm4a', '0', 'aac'),
  _AudioPreset('OPUS alta', 'opus', '0', 'opus'),
  _AudioPreset('FLAC sin pérdida', 'flac', '0', 'flac'),
  _AudioPreset('WAV', 'wav', '0', 'wav'),
];

class QualityDialog extends StatefulWidget {
  final VideoInfo preview;
  final Future<VideoInfo> infoFuture;
  // Preselección desde extension via deep link.
  final String? initialKind; // 'video' | 'audio'
  final int? initialHeight;
  final int? initialAbr;
  final String? initialCodec;
  final bool? initialSubs;
  final bool? initialSponsorBlock;
  const QualityDialog({
    super.key,
    required this.preview,
    required this.infoFuture,
    this.initialKind,
    this.initialHeight,
    this.initialAbr,
    this.initialCodec,
    this.initialSubs,
    this.initialSponsorBlock,
  });

  @override
  State<QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends State<QualityDialog> with SingleTickerProviderStateMixin {
  late TabController _tab;
  VideoInfo _info = VideoInfo.preview('');
  Object? _infoError;
  bool _loading = true;

  // Video selección
  _VideoPreset _videoPreset = _videoPresets[0];
  VideoFormat? _videoFormat;
  bool _useDetailedVideo = false;
  String _container = 'mp4';

  // Audio selección
  _AudioPreset _audioPreset = _audioPresets[0];
  VideoFormat? _audioFormat;
  bool _useDetailedAudio = false;

  // Extras
  bool _subs = false;
  bool _embedSubs = true;
  bool _sponsor = true;
  bool _embedThumb = true;
  bool _embedMeta = true;
  final Set<String> _selectedLangs = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _info = widget.preview;
    _applyInitial();
    widget.infoFuture.then((info) {
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        // Preselección por defecto: idiomas comunes
        for (final p in ['es', 'en']) {
          if (info.subtitles.any((s) => s.lang.startsWith(p))) {
            _selectedLangs.add(p);
            break;
          }
        }
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _infoError = e;
      });
    });
  }

  void _applyInitial() {
    if (widget.initialSubs != null) _subs = widget.initialSubs!;
    if (widget.initialSponsorBlock != null) _sponsor = widget.initialSponsorBlock!;
    if (widget.initialKind == 'audio') {
      _tab.index = 1;
      // Buscar preset audio que más se acerque
      final wantCodec = widget.initialCodec?.toLowerCase();
      final wantAbr = widget.initialAbr;
      _AudioPreset? best;
      int bestScore = -1;
      for (final p in _audioPresets) {
        int score = 0;
        if (wantCodec != null && p.codec == wantCodec) score += 5;
        if (wantAbr != null && p.tag.contains('${wantAbr}k')) score += 3;
        if (score > bestScore) {
          bestScore = score;
          best = p;
        }
      }
      if (best != null) _audioPreset = best;
    } else if (widget.initialKind == 'video' && widget.initialHeight != null) {
      _tab.index = 0;
      final h = widget.initialHeight!;
      _VideoPreset? closest;
      int closestDiff = 1 << 30;
      for (final p in _videoPresets) {
        if (p.height == null) continue;
        final d = (p.height! - h).abs();
        if (d < closestDiff) {
          closestDiff = d;
          closest = p;
        }
      }
      if (closest != null) _videoPreset = closest;
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(info: _info, loading: _loading, error: _infoError),
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(icon: Icon(Icons.movie_outlined), text: 'Video + Audio'),
                Tab(icon: Icon(Icons.audiotrack), text: 'Solo audio'),
              ],
              onTap: (_) => setState(() {}),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildVideoTab(theme),
                  _buildAudioTab(theme),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildExtras(theme),
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  if (_loading)
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Analizando…', style: theme.textTheme.bodySmall),
                      ],
                    )
                  else if (_infoError != null)
                    Row(
                      children: [
                        Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Análisis falló — usando presets',
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Detectados ${_info.formats.length} formatos',
                      style: theme.textTheme.bodySmall,
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar'),
                    onPressed: _onDownload,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDownload() {
    final isAudio = _tab.index == 1;
    QualityResult result;
    if (isAudio) {
      if (_useDetailedAudio && _audioFormat != null) {
        result = _build(
          kind: DownloadKind.audioOnly,
          audioFormat: _audioFormat,
          audioPresetCodec: _audioPreset.codec,
          audioPresetQuality: _audioPreset.quality,
          container: _audioPreset.codec,
        );
      } else {
        result = _build(
          kind: DownloadKind.audioOnly,
          audioPresetCodec: _audioPreset.codec,
          audioPresetQuality: _audioPreset.quality,
          container: _audioPreset.codec,
        );
      }
    } else {
      if (_useDetailedVideo && _videoFormat != null) {
        result = _build(
          kind: DownloadKind.videoAudio,
          videoFormat: _videoFormat,
          container: _container,
        );
      } else {
        result = _build(
          kind: DownloadKind.videoAudio,
          maxHeight: _videoPreset.height,
          best: _videoPreset.height == null,
          container: _container,
        );
      }
    }
    Navigator.of(context).pop(result);
  }

  QualityResult _build({
    required DownloadKind kind,
    int? maxHeight,
    bool best = false,
    VideoFormat? videoFormat,
    VideoFormat? audioFormat,
    String? audioPresetCodec,
    String? audioPresetQuality,
    required String container,
  }) {
    return QualityResult(
      info: _info,
      kind: kind,
      maxHeight: maxHeight,
      best: best,
      videoFormat: videoFormat,
      audioFormat: audioFormat,
      audioPresetCodec: audioPresetCodec,
      audioPresetQuality: audioPresetQuality,
      container: container,
      downloadSubtitles: _subs,
      subtitleLangs: _selectedLangs.toList(),
      embedSubtitles: _embedSubs,
      sponsorBlock: _sponsor,
      embedThumbnail: _embedThumb,
      embedMetadata: _embedMeta,
    );
  }

  Widget _buildVideoTab(ThemeData theme) {
    final maxH = _info.maxAvailableHeight;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calidad', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._videoPresets.map((p) {
            final unavailable = p.height != null && maxH != null && p.height! > maxH;
            final selected = !_useDetailedVideo && _videoPreset.label == p.label;
            return _PresetTile(
              icon: p.icon,
              title: p.label,
              tag: p.height == null ? 'best' : '${p.height}p',
              hint: unavailable
                  ? 'No disponible — se usará lo mejor cercano (${maxH}p)'
                  : null,
              selected: selected,
              onTap: () => setState(() {
                _useDetailedVideo = false;
                _videoPreset = p;
              }),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Contenedor', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'mp4', label: Text('mp4')),
                  ButtonSegment(value: 'mkv', label: Text('mkv')),
                  ButtonSegment(value: 'webm', label: Text('webm')),
                ],
                selected: {_container},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _container = s.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_loading && _info.formats.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.tune, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Text('Formatos detectados',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${_info.videoFormats.length}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            ..._info.videoFormats.map((f) {
              final selected = _useDetailedVideo && _videoFormat?.formatId == f.formatId;
              return _DetailTile(
                title: '${f.height ?? "?"}p${f.fps != null && f.fps! > 0 ? " ${f.fps!.toStringAsFixed(0)}fps" : ""}',
                tags: _videoTags(f),
                size: f.sizeLabel,
                selected: selected,
                onTap: () => setState(() {
                  _useDetailedVideo = true;
                  _videoFormat = f;
                }),
              );
            }),
          ] else if (_loading) ...[
            _ShimmerHint(),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calidad de audio', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._audioPresets.map((p) {
            final selected = !_useDetailedAudio && _audioPreset.label == p.label;
            return _PresetTile(
              icon: Icons.audiotrack,
              title: p.label,
              tag: p.tag,
              selected: selected,
              onTap: () => setState(() {
                _useDetailedAudio = false;
                _audioPreset = p;
              }),
            );
          }),
          if (!_loading && _info.audioFormats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.tune, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Text('Pistas detectadas', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${_info.audioFormats.length}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            ..._info.audioFormats.map((f) {
              final selected = _useDetailedAudio && _audioFormat?.formatId == f.formatId;
              return _DetailTile(
                title: '${f.abr ?? f.tbr ?? "?"} kbps',
                tags: _audioTags(f),
                size: f.sizeLabel,
                selected: selected,
                onTap: () => setState(() {
                  _useDetailedAudio = true;
                  _audioFormat = f;
                }),
              );
            }),
          ] else if (_loading) ...[
            const SizedBox(height: 16),
            _ShimmerHint(),
          ],
        ],
      ),
    );
  }

  List<String> _videoTags(VideoFormat f) {
    final tags = <String>[];
    if (f.ext != null) tags.add(f.ext!);
    if (f.vcodec != null && f.vcodec != 'none') tags.add(_codecShort(f.vcodec!));
    if (f.fps != null && f.fps! > 0) tags.add('${f.fps!.toStringAsFixed(0)}fps');
    if (f.hasAudio) {
      tags.add('+audio');
    } else {
      tags.add('video-only');
    }
    if (f.formatNote != null && f.formatNote!.toLowerCase().contains('hdr')) {
      tags.add('HDR');
    }
    return tags;
  }

  List<String> _audioTags(VideoFormat f) {
    final tags = <String>[];
    if (f.ext != null) tags.add(f.ext!);
    if (f.acodec != null && f.acodec != 'none') tags.add(_codecShort(f.acodec!));
    if (f.formatNote != null) tags.add(f.formatNote!);
    return tags;
  }

  String _codecShort(String c) {
    final lc = c.toLowerCase();
    if (lc.startsWith('avc') || lc.startsWith('h264')) return 'h264';
    if (lc.startsWith('vp9')) return 'vp9';
    if (lc.startsWith('av01') || lc.startsWith('av1')) return 'av1';
    if (lc.startsWith('opus')) return 'opus';
    if (lc.startsWith('mp4a') || lc.startsWith('aac')) return 'aac';
    if (lc.length > 12) return lc.split('.').first;
    return lc;
  }

  Widget _buildExtras(ThemeData theme) {
    final allLangs = <SubtitleTrack>[
      ..._info.subtitles,
      ..._info.autoSubtitles.where((a) =>
          !_info.subtitles.any((s) => s.lang == a.lang)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text('SponsorBlock'),
                avatar: const Icon(Icons.cut, size: 16),
                selected: _sponsor,
                onSelected: (v) => setState(() => _sponsor = v),
              ),
              FilterChip(
                label: const Text('Subtítulos'),
                avatar: const Icon(Icons.closed_caption, size: 16),
                selected: _subs,
                onSelected: (v) => setState(() => _subs = v),
              ),
              if (_subs && _tab.index == 0)
                FilterChip(
                  label: const Text('Incrustar'),
                  selected: _embedSubs,
                  onSelected: (v) => setState(() => _embedSubs = v),
                ),
              FilterChip(
                label: const Text('Miniatura'),
                avatar: const Icon(Icons.image, size: 16),
                selected: _embedThumb,
                onSelected: (v) => setState(() => _embedThumb = v),
              ),
              FilterChip(
                label: const Text('Metadatos'),
                selected: _embedMeta,
                onSelected: (v) => setState(() => _embedMeta = v),
              ),
            ],
          ),
          if (_subs) ...[
            const SizedBox(height: 6),
            if (allLangs.isEmpty && _loading)
              Text('Buscando idiomas…',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))
            else if (allLangs.isEmpty)
              Text('No hay subtítulos. Se intentará igual.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))
            else
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: allLangs.map((s) {
                    final selected = _selectedLangs.contains(s.lang);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${s.lang}${s.auto ? " (auto)" : ""}'),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _selectedLangs.add(s.lang);
                          } else {
                            _selectedLangs.remove(s.lang);
                          }
                        }),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VideoInfo info;
  final bool loading;
  final Object? error;
  const _Header({required this.info, required this.loading, required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: info.thumbnail != null
              ? CachedNetworkImage(
                  imageUrl: info.thumbnail!,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (c, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (c, u, e) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie, size: 48),
                  ),
                )
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie, size: 48),
                ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.duration != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    info.durationLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                info.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (info.uploader != null)
                Text(
                  info.uploader!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ),
        if (loading)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text('Analizando',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String tag;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;
  const _PresetTile({
    required this.icon,
    required this.title,
    required this.tag,
    this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.dividerColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? theme.colorScheme.primary : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (hint != null)
                      Text(hint!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.tertiary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: selected ? theme.colorScheme.onPrimary : null,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final String title;
  final List<String> tags;
  final String size;
  final bool selected;
  final VoidCallback onTap;
  const _DetailTile({
    required this.title,
    required this.tags,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : theme.dividerColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? theme.colorScheme.primary : theme.hintColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: tags
                          .map((t) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant)),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              if (size.isNotEmpty)
                Text(size,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
