import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/sync_service.dart';

/// Small reusable widgets shared across screens.

/// AppBar with the Ruby Invoice brand chip - a white rounded tile
/// holding the origami "R" - before the title. Used on every screen so
/// the Ruby mark is always visible, in a crisp white-on-ruby treatment
/// that matches the app icon identity.
class RubyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  const RubyAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(
              'assets/icon/logo_r.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFF3B7BC),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String text;
  final Color color;
  const SectionHeader(this.text, {super.key, this.color = Ruby.muted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: color,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Ruby.faint),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Ruby.ink)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Ruby.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String ok = 'Confirm',
  bool dangerous = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Text(message, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Ruby.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(80, 42),
            backgroundColor: dangerous ? Colors.red : Ruby.ruby,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Live sync indicator for the home app bar: cloud_off / spinner /
/// cloud_done. Tap to force a sync. Shows nothing while Firebase is
/// not configured (pure offline mode).
class SyncChip extends StatelessWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = SyncService.instance;
    if (!svc.fbReady) return const SizedBox.shrink();
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: svc.status,
      builder: (context, status, _) {
        late final Widget icon;
        String tip = 'Sync';
        switch (status) {
          case SyncStatus.offline:
            icon = const Icon(Icons.cloud_off_outlined, size: 20, color: Colors.white70);
            tip = 'Signed out';
            break;
          case SyncStatus.syncing:
            icon = const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            );
            tip = 'Syncing...';
            break;
          case SyncStatus.synced:
            icon = const Icon(Icons.cloud_done_outlined, size: 20, color: Colors.white);
            tip = 'Synced';
            break;
          case SyncStatus.error:
            icon = const Icon(Icons.cloud_off, size: 20, color: Color(0xFFFFC1C6));
            tip = 'Sync error - tap to retry';
            break;
        }
        return IconButton(
          tooltip: tip,
          icon: icon,
          onPressed: () async {
            await svc.syncNow();
          },
        );
      },
    );
  }
}

Future<void> showSnack(BuildContext context, String message, {bool error = false}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// RUBY INVOICE brand lockup: origami R mark + RUBY wordmark + INVOICE
/// tagline. Matches the printed brand identity (assets/icon/logo_r.png).
class BrandMark extends StatelessWidget {
  final double markHeight;
  final bool onDark;
  const BrandMark({super.key, this.markHeight = 76, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final wordColor = onDark ? Colors.white : const Color(0xFF3A3A3A);
    final tagColor = onDark ? Colors.white70 : const Color(0xFF9E9E9E);
    final lineColor = onDark ? Colors.white24 : const Color(0xFFD0D0D0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/icon/logo_r.png',
            height: markHeight, filterQuality: FilterQuality.high),
        SizedBox(height: markHeight * 0.15),
        Text(
          'RUBY',
          style: TextStyle(
            fontSize: markHeight * 0.26,
            fontWeight: FontWeight.w800,
            letterSpacing: markHeight * 0.11,
            color: wordColor,
          ),
        ),
        SizedBox(height: markHeight * 0.08),
        SizedBox(
          width: markHeight * 1.15,
          child: Divider(height: 1, thickness: 1, color: lineColor),
        ),
        SizedBox(height: markHeight * 0.08),
        Text(
          'INVOICE',
          style: TextStyle(
            fontSize: markHeight * 0.115,
            fontWeight: FontWeight.w500,
            letterSpacing: markHeight * 0.055,
            color: tagColor,
          ),
        ),
      ],
    );
  }
}

/// Ruby-brand rounded loading line with an animated shine: a small
/// bright ruby highlight pulses and glides at the leading edge of the
/// fill while the download runs. [value] is 0..1; pass null for an
/// indeterminate sweep (e.g. while the download is starting).
class RubyShimmerProgress extends StatefulWidget {
  const RubyShimmerProgress({
    super.key,
    required this.value,
    this.height = 8,
  });

  final double? value;
  final double height;

  @override
  State<RubyShimmerProgress> createState() => _RubyShimmerProgressState();
}

class _RubyShimmerProgressState extends State<RubyShimmerProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, _) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _RubyShimmerPainter(value: widget.value, t: _ctl.value),
          ),
        ),
      ),
    );
  }
}

class _RubyShimmerPainter extends CustomPainter {
  _RubyShimmerPainter({required this.value, required this.t});

  final double? value;
  final double t; // looping 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;

    // Track.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)),
      Paint()..color = Ruby.rubyLight,
    );

    final v = value;
    if (v == null) {
      // Indeterminate: one soft ruby band sweeping across the track.
      final bandW = size.width * 0.4;
      final x = -bandW + (size.width + bandW * 2) * t;
      final rect = Rect.fromLTWH(x, 0, bandW, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        Paint()
          ..shader = LinearGradient(colors: [
            Ruby.ruby.withValues(alpha: 0),
            Ruby.ruby.withValues(alpha: 0.85),
            Ruby.ruby.withValues(alpha: 0),
          ]).createShader(rect),
      );
      return;
    }

    final fill = v.clamp(0.0, 1.0);
    if (fill <= 0) return;
    final w = size.width * fill;

    // Filled part: deep ruby gradient.
    final fillRect = Rect.fromLTWH(0, 0, w, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, Radius.circular(r)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [Ruby.rubyDark, Ruby.ruby],
        ).createShader(fillRect),
    );

    // Shining head at the front edge: a small bright band whose glow
    // pulses (0..1..0) as the fill travels.
    final pulse = t < 0.5 ? t * 2 : (1 - t) * 2;
    final headW = size.height * 1.8;
    final headLeft = w - headW <= 0 ? 0.0 : w - headW;
    final head = Rect.fromLTWH(headLeft, 0, headW, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, Radius.circular(r)),
      Paint()
        ..color = Color.lerp(Ruby.ruby, Colors.white, 0.45 + 0.3 * pulse)!
        ..maskFilter = MaskFilter.blur(BlurStyle.solid, 2.5 + 2.5 * pulse),
    );
  }

  @override
  bool shouldRepaint(covariant _RubyShimmerPainter old) => true;
}
