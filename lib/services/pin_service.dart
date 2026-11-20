import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Local 4-digit PIN (app lock). The PIN is never stored - only a
/// salted SHA-256 hash. Used for daily unlock; OTP verification comes
/// from Firebase once it is configured (see docs/FIREBASE_SETUP.md).
///
/// The same hash is also stored on the user's Firestore document
/// (users/{uid}.pinHash + pinSalt), so a second device signed in with
/// the SAME mobile number can import the PIN and unlock with it.
class PinService {
  PinService._();
  static final PinService instance = PinService._();
  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';

  Future<bool> get hasPin async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getString(_kHash) ?? '').isNotEmpty;
  }

  /// Public, deterministic salted hash used both locally and on the
  /// users/{uid} Firestore document.
  static String hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Creates a new salt for a fresh PIN.
  static String newSalt() => const Uuid().v4();

  Future<void> setPin(String pin) async {
    final sp = await SharedPreferences.getInstance();
    final salt = newSalt();
    await sp.setString(_kSalt, salt);
    await sp.setString(_kHash, hash(salt, pin));
  }

  /// Imports the PIN hash of the account's master record (2nd device).
  /// Returns true if a hash was actually imported.
  Future<bool> importFrom({required String salt, required String hashValue}) async {
    if (salt.isEmpty || hashValue.isEmpty) return false;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSalt, salt);
    await sp.setString(_kHash, hashValue);
    return true;
  }

  Future<({String salt, String hash})> get stored async {
    final sp = await SharedPreferences.getInstance();
    return (
      salt: sp.getString(_kSalt) ?? '',
      hash: sp.getString(_kHash) ?? '',
    );
  }

  Future<void> clearPin() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kSalt);
    await sp.remove(_kHash);
  }

  Future<bool> verify(String pin) async {
    final sp = await SharedPreferences.getInstance();
    final salt = sp.getString(_kSalt) ?? '';
    final stored = sp.getString(_kHash) ?? '';
    if (stored.isEmpty) return true;
    return hash(salt, pin) == stored;
  }
}
