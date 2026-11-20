import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../widgets/widgets.dart';

/// Legal pages shown inside Menu -> Settings, generated from the real
/// behaviour of this codebase (permissions, Firebase usage, photo
/// handling, device limit, in-app updates) - not generic boilerplate.
enum LegalDoc { privacy, terms }

class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  bool get _isPrivacy => doc == LegalDoc.privacy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RubyAppBar(
        title: _isPrivacy ? 'Privacy Policy' : 'Terms & Conditions',
        subtitle: 'Ruby Invoice',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
            'Last updated: 20 November 2025',
            style: const TextStyle(fontSize: 11.5, color: Ruby.faint),
          ),
          const SizedBox(height: 6),
          for (final s in _sections()) ...[
            const SizedBox(height: 14),
            Text(s.title,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Ruby.ink)),
            const SizedBox(height: 6),
            Text(s.body,
                style: const TextStyle(
                    fontSize: 13, height: 1.55, color: Ruby.muted)),
          ],
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Ruby.fieldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Ruby.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Ruby.ink)),
                const SizedBox(height: 6),
                Text(
                  'Questions about ${_isPrivacy ? 'this policy' : 'these terms'}? '
                  'Email ${AppConstants.supportEmail} or use Settings -> '
                  'Subscription to reach the Admin.',
                  style: const TextStyle(fontSize: 12.5, height: 1.5, color: Ruby.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_Sec> _sections() {
    if (_isPrivacy) {
      return const [
        _Sec('1. What this app is',
            'Ruby Invoice is an offline-first billing app for shops. Bills, '
            'customers, the ledger (jama/udhar), inventory and purchase '
            'invoices are stored FIRST on your phone (local SQLite '
            'database). When you sign in with Google, the same data syncs '
            'to your own private Firebase account so your two devices stay '
            'identical.'),
        _Sec('2. Information we collect',
            'a) Account details you enter at registration: shop/business '
            'name, owner name, 10-digit mobile number, city, address and '
            'optional GST number. Your Gmail address and basic profile '
            'come from Google Sign-In and are used as your login.\n\n'
            'b) Business data you create: customers, bills and bill items, '
            'payments and ledger entries, inventory items, purchase '
            'invoices and their notes/amounts.\n\n'
            'c) Photos you attach: billty (transport receipt) photos, '
            'payment-proof (UPI screenshot) images and purchase-bill '
            'photos. They are compressed to 300 KB or less before upload.\n\n'
            'd) Technical identifiers: a random device ID and your device '
            'model name, used ONLY to manage the maximum-2-devices limit '
            'and to keep your login secure.'),
        _Sec('3. Where your data lives',
            'Locally on the phone in the app private storage. In the cloud, '
            'under your personal account only: Firestore path '
            'shops/{your-uid} and Storage path shops/{your-uid}/photos. '
            'Firebase security rules make your data readable and writable '
            'ONLY by your own login. The Admin can see and change ONLY '
            'account-management fields (status, plan, validity, device '
            'list) - never your bills, customers or ledger.'),
        _Sec('4. Photo retention (45-day billty rule)',
            'Billty (transport receipt) photos are kept for 45 days and '
            'delete themselves automatically from the phone after that. '
            'When a synced photo passes 45 days it is also removed from '
            'cloud storage by the next device that runs the cleanup, so '
            'the 45-day rule holds everywhere. Payment-proof and purchase '
            'photos stay until you delete the record or uninstall.'),
        _Sec('5. Permissions we use and why',
            'Internet & network state - sign-in, sync and update checks.\n'
            'Camera - capture billty and purchase-bill photos (only when '
            'you tap the camera button).\n'
            'Photos / gallery - attach a payment-proof screenshot or '
            'business logo (only when you tap the gallery button).\n'
            'Install packages - the in-app updater installs new Ruby '
            'Invoice versions you approve.\n'
            'No location, no contacts reading, no microphone, no ads.'),
        _Sec('6. Sharing and selling',
            'We do NOT sell your data and we do NOT show ads. Data leaves '
            'the app only when: (a) you sync it to your own Firebase '
            'account, (b) you share a bill, billty or report through the '
            'Android share sheet (WhatsApp etc.) - that share is done by '
            'you, (c) you back up or export files yourself.'),
        _Sec('7. Account control',
            'Your account status (trial / active / suspended), validity '
            'and the 2-device list are managed by the Admin through the '
            'Ruby Key panel. If an account is suspended or expires, the '
            'app locks itself but your local data stays safe on the '
            'phone. You can delete your cloud data by asking the Admin, '
            'and uninstalling the app removes all local data.'),
        _Sec('8. Children and security',
            'Ruby Invoice is a business tool and is not directed at '
            'children. Data in transit is encrypted (HTTPS/TLS by Firebase '
            'SDKs) and access is protected by Google authentication and '
            'per-user security rules.'),
      ];
    }
    return const [
      _Sec('1. The service',
          'Ruby Invoice provides offline-first billing, ledger and '
          'inventory tools for shops, with optional cloud sync between a '
          'maximum of two devices per account. The app is provided by the '
          'Ruby Invoice team ("we", "Admin").'),
      _Sec('2. Your account',
          'You sign in with your own Gmail (Google handles the '
          'authentication; we never see your Google password). You are '
          'responsible for the accuracy of the business details you '
          'enter and for keeping your Quick PIN secret. One account may '
          'be used on a maximum of 2 devices; you can remove a device '
          'from the Device Limit screen or the Admin can reset it.'),
      _Sec('3. Trial, subscription and fair use',
          'New accounts start with a FREE 7-day trial. After the trial, '
          'continued use requires an active subscription set by the '
          'Admin (online payments through Razorpay are planned). The '
          'Admin may extend, expire or suspend an account. Misuse - '
          'trying to break the device limit, attacking the service or '
          'other users, or storing unlawful content - can lead to '
          'suspension.'),
      _Sec('4. Your data',
          'Your bills, ledger, inventory and photos remain YOUR property. '
          'We store them only to provide the service (sync between your '
          'devices). You can export/backup your data from Settings -> '
          'Backup & Restore at any time. If the service is discontinued, '
          'your local copy always stays with you.'),
      _Sec('5. Updates',
          'Ruby Invoice updates itself through in-app update checks '
          '(APK from official GitHub releases). Installing an update is '
          'always your choice; critical fixes may be recommended.'),
      _Sec('6. Availability and support',
          'The app works offline; cloud sync needs internet. We aim for '
          'reliable service but do not guarantee uninterrupted cloud '
          'availability. Support: ${AppConstants.supportEmail} or '
          'WhatsApp support from the lock screen when provided.'),
      _Sec('7. Limitation of liability',
          'To the maximum extent permitted by Indian law, we are not '
          'liable for indirect damages or for data loss caused by device '
          'failure, uninstallation or third-party services (Google, '
          'Firebase). Keep regular backups from Settings -> Backup & '
          'Restore.'),
      _Sec('8. Changes and governing law',
          'These terms may be updated inside the app; continued use '
          'means you accept the current version. They are governed by '
          'the laws of India.'),
    ];
  }
}

class _Sec {
  final String title;
  final String body;
  const _Sec(this.title, this.body);
}
