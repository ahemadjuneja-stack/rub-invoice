import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/live_ui_service.dart';

/// Full-screen maintenance gate. Ruby Key flips `maintenance_mode` in
/// `app_config/live_ui` and every phone shows THIS screen on the next
/// open (or immediately - the config is a live listener).
///
/// SAFETY: the owner's admin Gmail always passes through, and a
/// signed-in user can always "Check again" once the flag is off. The
/// gate never blocks access to CLOUD data - it is a UI screen only;
/// billing data keeps syncing in the background once the flag is off.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, required this.onBypass});

  /// Called when the user is allowed through (admin account).
  final VoidCallback onBypass;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _checking = false;

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    try {
      // The live listener already carries the newest value; a tiny wait
      // lets a just-flipped flag land, then re-evaluate.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final stillOn = LiveUiService.instance.config.value.maintenanceMode;
      if (!stillOn) widget.onBypass();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportUrl = AppConstants.supportWhatsAppUrl();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Ruby.rubyLight,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.engineering_outlined,
                      color: Ruby.ruby, size: 44),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Quick maintenance',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Ruby.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We are making Ruby Invoice even better.\n'
                  'Your bills and data are completely safe in the cloud '
                  '- they were saved as you made them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5, height: 1.45, color: Ruby.muted),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Ruby.ruby,
                      minimumSize: const Size.fromHeight(46)),
                  onPressed: _checking ? null : _checkAgain,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Check again'),
                ),
                if (supportUrl != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () async {
                      try {
                        await launchUrl(Uri.parse(supportUrl),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    child: const Text('Contact support',
                        style: TextStyle(color: Ruby.ruby)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
