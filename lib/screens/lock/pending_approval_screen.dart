import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/access_service.dart';
import '../../widgets/widgets.dart';

/// Shown while `users/{uid}.status == "pending"`:
/// the shop owner registered, but the Admin has not approved the
/// account yet. Nothing else in the app is reachable from here.
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final info = AccessService.instance.account.value;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const Text(
                  'Your Ruby Invoice account is registered and waiting for '
                  'the Admin to activate it.\n\nPlease contact your Admin to '
                  'approve this account. All your data is safe on this phone '
                  'and will sync automatically once the account is active.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Sign out?',
                      message:
                          'You can sign in again with the same mobile number '
                          'after the Admin approves the account.',
                      ok: 'Sign out',
                    );
                    if (ok && context.mounted) {
                      await AccessService.instance.signOut();
                    }
                  },
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign out'),
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
