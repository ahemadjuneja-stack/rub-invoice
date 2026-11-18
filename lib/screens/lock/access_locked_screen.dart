import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/access_service.dart';
import '../../widgets/widgets.dart';

/// Hard lock screen. Shown whenever the access check fails:
///   * expired  -> subscription expiryDate has passed
///   * blocked  -> admin kill-switch (status = "blocked")
///   * deviceLimit -> this phone is not one of the max 2 approved devices
/// The app is unreachable until the Admin fixes the account.
class AccessLockedScreen extends StatelessWidget {
  final AccessState reason;
  const AccessLockedScreen({super.key, required this.reason});

  String get _title {
    switch (reason) {
      case AccessState.expired:
        return 'Subscription Expired';
      case AccessState.blocked:
        return 'Access Locked by Admin';
      case AccessState.deviceLimit:
        return 'Device Not Authorized';
      default:
        return 'Access Locked';
    }
  }

  String get _message {
    switch (reason) {
      case AccessState.expired:
        return 'Your Ruby Invoice subscription has expired. '
            'Please contact your Admin to renew it.\n\n'
            'Your bills, ledger and inventory are safe and will be '
            'available again as soon as the subscription is renewed.';
      case AccessState.blocked:
        return 'The Admin has locked this account. '
            'Please contact your Admin for details.\n\n'
            'All data remains safely stored on this device.';
      case AccessState.deviceLimit:
        return 'This device is not authorized. A Ruby Invoice account '
            'can be used on a maximum of 2 devices.\n\n'
            'To use billing on this phone, remove an old device from your '
            'account (Admin -> Firestore -> registeredDevices) or contact '
            'your Admin.';
      default:
        return 'This account cannot be used right now. '
            'Please contact your Admin.';
    }
  }

  IconData get _icon {
    switch (reason) {
      case AccessState.expired:
        return Icons.event_busy_rounded;
      case AccessState.deviceLimit:
        return Icons.phonelink_off_rounded;
      default:
        return Icons.lock_rounded;
    }
  }

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
                    color: Ruby.rubyLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 54, color: Ruby.ruby),
                ),
                const SizedBox(height: 22),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ruby,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Ruby.muted,
                  ),
                ),
                const SizedBox(height: 18),
                if (info != null && reason == AccessState.expired)
                  _infoCard(
                    icon: Icons.storefront_outlined,
                    label: 'Business',
                    value: info.businessName,
                  ),
                if (info != null && reason == AccessState.deviceLimit)
                  _infoCard(
                    icon: Icons.devices_other,
                    label: 'Devices used',
                    value:
                        '${info.registeredDevices.length} of ${info.maxDevices}',
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
                          'Sign out of Ruby Invoice on this device? You can '
                          'sign in again with the same mobile number once '
                          'the account is fixed.',
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
                  'Access is re-checked automatically - the app unlocks '
                  'itself the moment the Admin renews or approves it.',
                  textAlign: TextAlign.center,
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
