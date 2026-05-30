import 'package:cached_network_image/cached_network_image.dart' hide DownloadProgress;
import 'package:flutter/material.dart';

import '../models/download_options.dart';
import '../models/video_info.dart';

class DownloadRow extends StatefulWidget {
  final VideoInfo info;
  final DownloadProgress? progress;
  final String? error;
  final bool done;
  final bool paused;
  final bool queued;
  final String qualityTag;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onDismiss;

  const DownloadRow({
    super.key,
    required this.info,
    required this.qualityTag,
    this.progress,
    this.error,
    this.done = false,
    this.paused = false,
    this.queued = false,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onOpenFolder,
    this.onDismiss,
  });

  @override
  State<DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends State<DownloadRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _maybeAnimate();
  }

  @override
  void didUpdateWidget(covariant DownloadRow old) {
    super.didUpdateWidget(old);
    _maybeAnimate();
  }

  void _maybeAnimate() {
    final shouldRun = _active && !widget.paused;
    if (shouldRun && !_shimmer.isAnimating) {
      _shimmer.repeat();
    } else if (!shouldRun && _shimmer.isAnimating) {
      _shimmer.stop();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  bool get _active => widget.error == null && !widget.done && !widget.queued;

  Color _accentForState(ColorScheme s) {
    if (widget.error != null) return s.error;
    if (widget.done) return Colors.green.shade600;
    if (widget.paused) return Colors.orange.shade700;
    if (widget.queued) return s.outline;
    return s.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = (widget.progress?.percent ?? 0).clamp(0.0, 100.0);
    final pctFraction = pct > 0 ? pct / 100 : null;
    final accent = _accentForState(scheme);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Rail vertical accent al lado izquierdo de la fila — da presencia.
            Container(
              width: 3,
              height: 102,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: _active && !widget.paused
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            _Thumb(
              info: widget.info,
              qualityTag: widget.qualityTag,
              accent: scheme.primary,
              progressFraction: pctFraction ?? (widget.done ? 1.0 : 0.0),
              active: _active && !widget.paused,
              done: widget.done,
              error: widget.error != null,
              paused: widget.paused,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusBadge(
                        active: _active,
                        paused: widget.paused,
                        done: widget.done,
                        error: widget.error,
                        queued: widget.queued,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.info.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (widget.info.partial && widget.info.uploader == null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            valueColor: AlwaysStoppedAnimation(scheme.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Analizando metadatos…',
                          style:
                              TextStyle(fontSize: 13, color: theme.hintColor),
                        ),
                      ],
                    )
                  else
                    Text(
                      [
                        if (widget.info.uploader != null) widget.info.uploader,
                        if (widget.info.duration != null)
                          widget.info.durationLabel,
                      ].whereType<String>().join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: theme.hintColor),
                    ),
                  const SizedBox(height: 10),
                  _ProgressBar(
                    fraction: pctFraction ?? (widget.done ? 1.0 : 0.0),
                    error: widget.error != null,
                    done: widget.done,
                    paused: widget.paused,
                    indeterminate: _active && !widget.paused && pctFraction == null,
                    shimmer: _shimmer,
                  ),
                  const SizedBox(height: 6),
                  _StatusLine(
                    progress: widget.progress,
                    error: widget.error,
                    done: widget.done,
                    paused: widget.paused,
                    queued: widget.queued,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Actions(
              done: widget.done,
              error: widget.error,
              active: _active,
              paused: widget.paused,
              queued: widget.queued,
              onPause: widget.onPause,
              onResume: widget.onResume,
              onCancel: widget.onCancel,
              onOpenFolder: widget.onOpenFolder,
              onDismiss: widget.onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final VideoInfo info;
  final String qualityTag;
  final Color accent;
  final double progressFraction;
  final bool active;
  final bool done;
  final bool error;
  final bool paused;

  const _Thumb({
    required this.info,
    required this.qualityTag,
    required this.accent,
    required this.progressFraction,
    required this.active,
    required this.done,
    required this.error,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      height: 102,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen
            if (info.thumbnail != null)
              CachedNetworkImage(
                imageUrl: info.thumbnail!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder: (c, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (c, u, e) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.movie_outlined,
                      size: 32, color: theme.hintColor),
                ),
              )
            else
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.movie_outlined,
                    size: 32, color: theme.hintColor),
              ),
            // Gradiente inferior para legibilidad de chips
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.55, 1],
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              ),
            ),
            // Quality tag bottom-left
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  qualityTag,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            // Duración bottom-right
            if (info.duration != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    info.durationLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            // Overlay porcentaje grande cuando está descargando
            if (active && progressFraction > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${(progressFraction * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            // Overlay grande de estado terminal (done / error / paused)
            if (done || error || paused)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.green.shade600
                            : error
                                ? theme.colorScheme.error
                                : Colors.orange.shade700,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        done
                            ? Icons.check
                            : error
                                ? Icons.close
                                : Icons.pause,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;
  final bool paused;
  final bool done;
  final String? error;
  final bool queued;
  const _StatusBadge({
    required this.active,
    required this.paused,
    required this.done,
    required this.error,
    this.queued = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (queued) {
      return Icon(Icons.schedule, size: 16, color: scheme.outline);
    }
    if (paused) {
      return Icon(Icons.pause_circle_filled, size: 16, color: Colors.orange.shade700);
    }
    if (done) {
      return Icon(Icons.check_circle, size: 16, color: Colors.green.shade600);
    }
    if (error != null) {
      return Icon(Icons.error_outline, size: 16, color: scheme.error);
    }
    if (active) {
      return _PulseDot(color: scheme.primary);
    }
    return const SizedBox(width: 10, height: 10);
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.4 + 0.6 * t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * t),
                blurRadius: 4 + 4 * t,
                spreadRadius: t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double fraction;
  final bool error;
  final bool done;
  final bool paused;
  final bool indeterminate;
  final AnimationController shimmer;
  const _ProgressBar({
    required this.fraction,
    required this.error,
    required this.done,
    required this.paused,
    required this.indeterminate,
    required this.shimmer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = error
        ? scheme.error
        : done
            ? Colors.green.shade600
            : paused
                ? Colors.orange.shade700
                : scheme.primary;
    return SizedBox(
      height: 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.5),
        child: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            final fill = (fraction.clamp(0.0, 1.0)) * w;
            return Stack(
              children: [
                Container(color: scheme.surfaceContainerHighest),
                if (indeterminate)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: shimmer,
                      builder: (_, _) {
                        final t = shimmer.value;
                        final pos = -0.4 + 1.4 * t;
                        return Stack(
                          children: [
                            Positioned(
                              left: pos * w,
                              child: Container(
                                width: 0.4 * w,
                                height: 7,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      color.withValues(alpha: 0),
                                      color.withValues(alpha: 0.7),
                                      color.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                else
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: fill,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withValues(alpha: 0.85)],
                      ),
                    ),
                    child: (!error && !done && !paused && fill > 0)
                        ? ClipRect(
                            child: AnimatedBuilder(
                              animation: shimmer,
                              builder: (_, _) {
                                final t = shimmer.value;
                                final shWidth = fill * 0.35;
                                final left = -shWidth + t * (fill + shWidth);
                                return Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned(
                                      left: left,
                                      top: 0,
                                      bottom: 0,
                                      width: shWidth,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withValues(alpha: 0),
                                              Colors.white.withValues(alpha: 0.4),
                                              Colors.white.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final DownloadProgress? progress;
  final String? error;
  final bool done;
  final bool paused;
  final bool queued;
  const _StatusLine({
    this.progress,
    this.error,
    required this.done,
    required this.paused,
    this.queued = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (queued) {
      return Text(
        'En cola',
        style: TextStyle(
          fontSize: 12,
          color: theme.hintColor,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    if (error != null) {
      return Text(
        error!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.error),
      );
    }
    if (done) {
      return Text(
        'Completado',
        style: TextStyle(
          fontSize: 12,
          color: Colors.green.shade600,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    if (paused) {
      final pct = (progress?.percent ?? 0).clamp(0, 100).toStringAsFixed(1);
      return Text(
        'Pausado en $pct%',
        style: TextStyle(
          fontSize: 12,
          color: Colors.orange.shade700,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    final p = progress;
    if (p == null) {
      return Text('Iniciando…',
          style: TextStyle(fontSize: 12, color: theme.hintColor));
    }
    final pct = p.percent.clamp(0, 100).toStringAsFixed(1);
    final phaseLabel = switch (p.phase) {
      'downloading' => 'Bajando',
      'post' => 'Post-proceso',
      _ => 'Trabajando',
    };
    final parts = <String>[
      '$phaseLabel ${p.percent > 0 ? "$pct%" : ""}'.trim(),
      if (p.speed != null) p.speed!,
      if (p.eta != null) 'ETA ${p.eta}',
      if (p.totalSize != null) p.totalSize!,
    ];
    return Text(
      parts.join('  •  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: theme.hintColor),
    );
  }
}

class _Actions extends StatelessWidget {
  final bool done;
  final String? error;
  final bool active;
  final bool paused;
  final bool queued;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onDismiss;

  const _Actions({
    required this.done,
    required this.error,
    required this.active,
    required this.paused,
    this.queued = false,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onOpenFolder,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (queued && onCancel != null)
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: 'Quitar de la cola',
            onPressed: onCancel,
          ),
        if (active && !paused && onPause != null)
          IconButton(
            icon: const Icon(Icons.pause, size: 22),
            tooltip: 'Pausar',
            onPressed: onPause,
          ),
        if (active && paused && onResume != null)
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 22),
            tooltip: 'Reanudar',
            onPressed: onResume,
          ),
        if (active && onCancel != null)
          IconButton(
            icon: const Icon(Icons.stop, size: 22),
            tooltip: 'Cancelar',
            onPressed: onCancel,
          ),
        if (done && onOpenFolder != null)
          IconButton(
            icon: const Icon(Icons.folder_open, size: 22),
            tooltip: 'Abrir carpeta',
            onPressed: onOpenFolder,
          ),
        if ((done || error != null) && onDismiss != null)
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: 'Quitar',
            onPressed: onDismiss,
          ),
      ],
    );
  }
}
