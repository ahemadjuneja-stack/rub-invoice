import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/access_service.dart';
import '../../widgets/widgets.dart';

/// Hard lock screen. Shown whenever the access check fails:
///   * expired  -> trial / subscription validity has passed
///   * blocked  -> admin kill-switch (status = "blocked")
///   * deviceLimit -> this phone is not one of the max 2 approved devices
///
/// Spec extras:
///   * blocked    -> "Account Suspended" + WhatsApp support button
///   * expired    -> "Subscription Expired" + contact admin / renew
///                   (structure ready for the Razorpay checkout later)
///   * deviceLimit-> the previous 2 devices are listed and the owner can
///                   remove one right here to free a slot (no admin trip).
/// The app unlocks ITSELF the moment the Firestore listener reports an
/// allowed state again.
class AccessLockedScreen extends StatelessWidget {
  final AccessState reason;
  const AccessLockedScreen({super.key, required this.reason});

  String get _title {
    switch (reason) {
      case AccessState.expired:
        return 'Subscription Expired';
      case AccessState.blocked:
        return 'Account Suspended';
      case AccessState.deviceLimit:
        return 'Device Limit Reached';
      default:
        return 'Access Locked';
    }
  }

  String get _message {
    switch (reason) {
      case AccessState.expired:
        return 'Your subscription validity is over. '
            'Contact the Admin to renew - the app unlocks the moment '
            'validity is extended.\n\n'
            'Your bills, ledger and inventory are safe and will be '
            'available again as soon as the subscription is renewed.';
      case AccessState.blocked:
        return 'Account Suspended - Contact Support.\n\n'
            'The Admin has locked this account. All data remains safely '
            'stored on this device.';
      case AccessState.deviceLimit:
        return 'Device Limit Reached (Max 2 Devices). Remove an old '
            'device to continue - pick one from the list below and it '
            'frees the slot for this phone instantly.';
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

  Future<void> _open(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      if (context.mounted) {
        showSnack(context, 'Could not open the link', error: true);
      }
    }
  }

  /// WhatsApp when the support number is set, otherwise Gmail compose.
  void _contactSupport(BuildContext context, String subject) {
    final wa = AppConstants.supportWhatsAppUrl();
    if (wa != null) {
      _open(wa, context);
    } else {
      _open(AppConstants.supportMailUrl(subject), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ValueListenableBuilder<AccountInfo?>(
              valueListenable: AccessService.instance.account,
              builder: (context, info, _) {
                return Column(
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
                      _deviceList(context, info),
                    const SizedBox(height: 20),
                    // Contact / renew actions (spec).
                    if (reason == AccessState.blocked ||
                        reason == AccessState.expired ||
                        reason == AccessState.deviceLimit)
                      _supportButtons(context),
                    const SizedBox(height: 14),
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
                              'sign in again with the same Gmail once '
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _supportButtons(BuildContext context) {
    final wa = AppConstants.supportWhatsAppUrl();
    return Column(
      children: [
        if (reason == AccessState.expired) ...[
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _contactSupport(context, 'Subscription renew - Ruby Invoice'),
              icon: const Icon(Icons.workspace_premium_outlined, size: 20),
              label: const Text('Renew / Contact Admin',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Online payments (Razorpay) are coming soon - until then '
            'renewal happens through the Admin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, height: 1.4, color: Ruby.faint),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Ruby.ruby),
              ),
              onPressed: () => _contactSupport(
                  context, 'Account support - Ruby Invoice'),
              icon: Icon(wa != null ? Icons.chat_outlined : Icons.mail_outline,
                  size: 20, color: Ruby.ruby),
              label: Text(
                wa != null ? 'WhatsApp Support' : 'Email Support',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ruby),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// The 2 registered devices with their model names and a Remove button
  /// each - self-service from the Device Limit screen (spec).
  Widget _deviceList(BuildContext context, AccountInfo info) {
    final devices = info.registeredDevices;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Ruby.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Ruby.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Devices used: ${devices.length} of ${info.maxDevices}',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Ruby.ink),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < devices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded,
                      size: 17, color: Ruby.ruby),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Device ${i + 1}  -  '
                      '${info.deviceModels[devices[i]] ?? 'Phone'}',
                      style: const TextStyle(fontSize: 12.5, color: Ruby.muted),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Remove device?',
                        message:
                            'Remove ${info.deviceModels[devices[i]] ?? 'this device'} '
                            'from your account? It will stop working until '
                            'you sign in on it again.',
                        ok: 'Remove',
                      );
                      if (ok) {
                        await AccessService.instance.removeDevice(devices[i]);
                      }
                    },
                    icon: const Icon(Icons.delete_outline,
                        size: 15, color: Ruby.ruby),
                    label: const Text('Remove',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Ruby.ruby)),
                  ),
                ],
              ),
            ),
          const Text(
            'After removing one, this phone takes the free slot '
            'automatically within seconds.',
            style: TextStyle(fontSize: 10.5, height: 1.4, color: Ruby.faint),
          ),
        ],
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
