import '../services/remote_config.dart';

/// App-wide constants that only the business owner knows.
///
/// Ruby Key (the web admin panel in /ruby-key-admin) and the lock
/// screens read these values, so everything stays in one place.
///
/// GOVERNANCE: before changing ANY user-visible string in this app,
/// read /GOVERNANCE.md at the repo root (BINDING for every developer
/// and every automated tool, forever). User-facing text must never
/// name the underlying platforms or infrastructure.
///
/// REMOTE CONTROL: supportMobile below is the OFFLINE FALLBACK. The
/// live value comes from the Firestore document `config/app`
/// (`support_mobile` field) - editable from the Ruby Key panel's
/// Remote Control card - so the number can be changed without an
/// app update.
class AppConstants {
  AppConstants._();

  /// The ONLY Gmail that may open Ruby Key (the admin panel).
  /// Any other Gmail that signs in there is signed out immediately.
  static const String adminEmail = 'Ahemadjuneja@gmail.com';

  /// Support contact shown on the lock screens (blocked / expired /
  /// device limit). Keep the full international format WITHOUT '+' and
  /// without spaces, e.g. '919876543210' for +91 98765 43210.
  /// When this is empty the lock screens show the Gmail button instead.
  static const String supportWhatsApp = '';

  /// Support email (used as the fallback button on lock screens).
  static const String supportEmail = 'ahemadjuneja@gmail.com';

  /// WhatsApp deep link for the support phone number ('' -> null).
  /// Remote config (config/app -> support_mobile) wins; the compile
  /// time constant is only the fallback when Firestore has no value.
  /// A bare 10-digit Indian number is accepted and prefixed with 91.
  static String? supportWhatsAppUrl() {
    String mobile = '';
    try {
      mobile = RemoteConfigService.instance.config.value.supportMobile;
    } catch (_) {
      // Remote config not ready (tests / early boot) - use the constant.
    }
    if (mobile.trim().isEmpty) mobile = supportWhatsApp;
    final digits = mobile.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final full = digits.length == 10 ? '91$digits' : digits;
    return 'https://wa.me/$full';
  }

  /// Prefilled Gmail compose link for support.
  static String supportMailUrl(String subject) {
    return 'mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}';
  }
}
