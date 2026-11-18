import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Local 4-digit PIN (app lock). The PIN is never stored - only a
/// salted SHA-256 hash. Used for daily unlock; OTP verification comes
/// from Firebase once it is configured (see docs/FIREBASE_SETUP.md).
class PinService {
  PinService._();
  static final PinService instance = PinService._();
  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';

  Future<bool> get hasPin async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getString(_kHash) ?? '').isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final sp = await SharedPreferences.getInstance();
    final salt = const Uuid().v4();
    final hash = _hash(salt, pin);
    await sp.setString(_kSalt, salt);
    await sp.setString(_kHash, hash);
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
    return _hash(salt, pin) == stored;
  }

  String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}
