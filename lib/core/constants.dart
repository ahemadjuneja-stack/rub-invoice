/// App-wide constants that only the business owner knows.
///
/// Ruby Key (the web admin panel in /ruby-key-admin) and the lock
/// screens read these values, so everything stays in one place.
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

  /// WhatsApp deep link for a support phone number ('' -> null).
  static String? supportWhatsAppUrl() {
    if (supportWhatsApp.trim().isEmpty) return null;
    return 'https://wa.me/${supportWhatsApp.trim()}';
  }

  /// Prefilled Gmail compose link for support.
  static String supportMailUrl(String subject) {
    return 'mailto:$supportEmail?subject=${Uri.encodeComponent(subject)}';
  }
}
