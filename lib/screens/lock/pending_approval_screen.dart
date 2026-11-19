import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/access_service.dart';
import '../../services/remote_config.dart';
import '../../widgets/widgets.dart';

/// Shown while `users/{uid}.status == "pending"`: the shop owner
/// registered, but the account is not active yet.
///
/// While the remote `auto_approve` flag is ON the screen tries to
/// activate the account by itself (WhatsApp-style server-side switch -
/// docs/REMOTE_CONTROL.md); only when the flag is OFF does the classic
/// "wait for the Admin" flow apply. Nothing else in the app is
/// reachable from here.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _trying = false;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    _tryActivate();
  }

  Future<void> _tryActivate() async {
    if (_trying) return;
    setState(() {
      _trying = true;
      _tried = true;
    });
    await AccessService.instance.selfActivateIfAllowed();
    if (!mounted) return;
    // On success the users/{uid} live listener flips the access state
    // and the AuthGate swaps this screen for the PIN / Home automatically.
    setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = AccessService.instance.account.value;
    final autoOn = RemoteConfigService.instance.config.value.autoApprove;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(markHeight: 64),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF7E0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      size: 54, color: Color(0xFFB8860B)),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Account Pending Approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  autoOn
                      ? 'Auto-approve is ON, so this account activates '
                          'itself in a moment. If this screen stays, check '
                          'your internet and tap "Retry activation".\n\n'
                          'All your data is safe on this phone and will '
                          'sync automatically once the account is active.'
                      : 'Your Ruby Invoice account is registered and '
                          'waiting for the Admin to activate it.\n\n'
                          'Please contact your Admin to approve this '
                          'account. All your data is safe on this phone '
                          'and will sync automatically once the account '
                          'is active.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Ruby.muted,
                  ),
                ),
                const SizedBox(height: 18),
                _infoCard(
                  icon: Icons.storefront_outlined,
                  label: 'Business',
                  value: info?.businessName.isNotEmpty == true
                      ? info!.businessName
                      : '(not set)',
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.phone_outlined,
                  label: 'Mobile number',
                  value: info?.phone ?? '',
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(180, 46),
                    side: const BorderSide(color: Ruby.ruby),
                  ),
                  onPressed: _trying ? null : _tryActivate,
                  icon: _trying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Ruby.ruby))
                      : const Icon(Icons.verified_outlined, size: 20),
                  label: Text(_trying
                      ? 'Activating...'
                      : (_tried ? 'Retry activation' : 'Activate now')),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Sign out?',
                      message:
                          'You can sign in again with the same mobile number '
                          'after the account is approved.',
                      ok: 'Sign out',
                    );
                    if (ok && context.mounted) {
                      await AccessService.instance.signOut();
                    }
                  },
                  child: const Text('Sign out'),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Status refreshes automatically every few seconds.',
                  style: TextStyle(fontSize: 11.5, color: Ruby.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Ruby.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Ruby.ruby),
          const SizedBox(width: 10),
          Text('$label:  ',
              style: const TextStyle(fontSize: 13, color: Ruby.muted)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Ruby.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
