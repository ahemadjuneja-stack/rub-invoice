import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/package_info_helper.dart';
import '../../services/update_service.dart';
import '../../widgets/widgets.dart';
import '../backup/backup_screen.dart';
import '../settings/subscription_screen.dart';
import '../sync/sync_status_screen.dart';

/// One place for everything app-related: subscription, cloud sync,
/// backup & restore, updates and about. The main menu stays clean with
/// only billing-related options - all the "app ka saaman" lives here.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await PackageInfoHelper.version();
    if (!mounted) return;
    setState(() => _version = v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RubyAppBar(title: 'Settings', subtitle: 'App, updates & data safety'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          SectionHeader('Subscription'),
          const SizedBox(height: 6),
          _card(ListTile(
            leading: const Icon(Icons.workspace_premium_outlined, color: Ruby.ruby, size: 22),
            title: const Text('Subscription',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Ruby.ink)),
            subtitle: const Text('1 year free for new users - plans coming soon',
                style: TextStyle(fontSize: 12, color: Ruby.muted)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ruby.rubyLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'COMING SOON',
                style: TextStyle(
                    fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: Ruby.ruby),
              ),
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
            },
          )),
          const SizedBox(height: 16),
          SectionHeader('Data & Sync'),
          const SizedBox(height: 6),
          _card(Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.cloud_sync_outlined, color: Ruby.ruby, size: 20),
                title: const Text('Cloud Sync Status',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Ruby.ink)),
                subtitle: const Text('Firebase sync across your devices',
                    style: TextStyle(fontSize: 12, color: Ruby.muted)),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncStatusScreen()));
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: const Icon(Icons.backup_outlined, color: Ruby.ruby, size: 20),
                title: const Text('Backup & Restore',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Ruby.ink)),
                subtitle: const Text('Keep a copy of your shop data',
                    style: TextStyle(fontSize: 12, color: Ruby.muted)),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen()));
                },
              ),
            ],
          )),
          const SizedBox(height: 16),
          SectionHeader('App'),
          const SizedBox(height: 6),
          _card(Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.system_update_outlined, color: Ruby.ruby, size: 20),
                title: const Text('Check Updates',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Ruby.ink)),
                subtitle: Text(
                  _version.isEmpty ? 'Checking version...' : 'Installed version $_version',
                  style: const TextStyle(fontSize: 12, color: Ruby.muted),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: _checkUpdates,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, color: Ruby.ruby, size: 20),
                title: const Text('About',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Ruby.ink)),
                subtitle: const Text('Ruby Invoice - offline-first billing',
                    style: TextStyle(fontSize: 12, color: Ruby.muted)),
                trailing: const Icon(Icons.chevron_right, size: 18, color: Ruby.faint),
                onTap: _about,
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _card(Widget child) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Ruby.line),
      ),
      child: child,
    );
  }

  // ---------------- updates ----------------

  Future<void> _checkUpdates() async {
    try {
      if (UpdateService.instance.readyPath.value != null) {
        _showUpdateDialog(tag: UpdateService.instance.latestTag ?? '');
        return;
      }
      final (has, tag) = await UpdateService.instance.check();
      if (!mounted) return;
      if (has) {
        unawaited(UpdateService.instance.downloadApk());
        _showUpdateDialog(tag: tag);
      } else {
        showSnack(context, 'You are on the latest version');
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Could not check updates (offline?)', error: true);
    }
  }

  /// Same ruby-styled update popup as the home screen, compact for
  /// manual checks from Settings.
  void _showUpdateDialog({required String tag}) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Ruby.rubyLight,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child:
                        const Icon(Icons.rocket_launch_outlined, color: Ruby.ruby, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New update available',
                          style: TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.w800, color: Ruby.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ruby Invoice v$tag',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700, color: Ruby.ruby),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String?>(
                valueListenable: UpdateService.instance.readyPath,
                builder: (context, path, _) {
                  if (path != null) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Ruby.ruby, size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Download complete - ready to install',
                                style: TextStyle(fontSize: 13.5, height: 1.4, color: Ruby.muted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: () => UpdateService.instance.install(),
                            icon: const Icon(Icons.install_mobile, size: 20),
                            label: const Text('Install now'),
                          ),
                        ),
                      ],
                    );
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: UpdateService.instance.downloading,
                    builder: (context, busy, _) => ValueListenableBuilder<double>(
                      valueListenable: UpdateService.instance.downloadProgress,
                      builder: (context, p, _) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Downloading the new version in background...',
                              style: TextStyle(fontSize: 13, height: 1.45, color: Ruby.muted),
                            ),
                            const SizedBox(height: 14),
                            RubyShimmerProgress(value: p <= 0 ? null : p),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  busy ? 'Downloading update...' : 'Starting download...',
                                  style: const TextStyle(fontSize: 12, color: Ruby.faint),
                                ),
                                const Spacer(),
                                if (p > 0)
                                  Text(
                                    '${(p * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: Ruby.ruby),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: Ruby.faint),
                  SizedBox(width: 5),
                  Text(
                    'Your data stays safe during updates',
                    style: TextStyle(fontSize: 11, color: Ruby.faint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- about ----------------

  Future<void> _about() async {
    final v = await PackageInfoHelper.version();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ruby Invoice', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Version $v\n\nOffline-first billing with exact paise-level ledger math, '
          'inventory auto-fill and Firebase sync across your devices.',
          style: const TextStyle(fontSize: 13.5, height: 1.5, color: Ruby.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
