import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Small key/value secret store used by the desktop app.
///
/// macOS Developer ID builds cannot carry the `keychain-access-groups`
/// entitlement without a provisioning profile. To keep notarized distribution
/// launchable, macOS stores values in an app-local encrypted file. Other
/// platforms continue to use flutter_secure_storage.
class SecureValueStore {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _storeFileName = 'secure_values.json';
  static const String _salt = 'LoveACE desktop local secure store v1';
  static final Random _random = Random.secure();

  static bool get _usesLocalEncryptedStore => Platform.isMacOS;

  static Future<void> write({
    required String key,
    required String value,
  }) async {
    if (!_usesLocalEncryptedStore) {
      await _secureStorage.write(key: key, value: value);
      return;
    }

    final store = await _readLocalStore();
    store[key] = _encrypt(value);
    await _writeLocalStore(store);
  }

  static Future<String?> read({required String key}) async {
    if (!_usesLocalEncryptedStore) {
      return _secureStorage.read(key: key);
    }

    final store = await _readLocalStore();
    final encrypted = store[key];
    if (encrypted == null) return null;
    return _decrypt(encrypted);
  }

  static Future<void> delete({required String key}) async {
    if (!_usesLocalEncryptedStore) {
      await _secureStorage.delete(key: key);
      return;
    }

    final store = await _readLocalStore();
    store.remove(key);
    await _writeLocalStore(store);
  }

  static Future<Map<String, String>> readAll() async {
    if (!_usesLocalEncryptedStore) {
      return _secureStorage.readAll();
    }

    final store = await _readLocalStore();
    final values = <String, String>{};
    for (final entry in store.entries) {
      final value = _decrypt(entry.value);
      if (value != null) values[entry.key] = value;
    }
    return values;
  }

  static Future<File> _storeFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, 'secure_store'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, _storeFileName));
  }

  static Future<Map<String, Map<String, String>>> _readLocalStore() async {
    final file = await _storeFile();
    if (!await file.exists()) return <String, Map<String, String>>{};

    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final values = raw['values'] as Map<String, dynamic>? ?? const {};
      return values.map((key, value) {
        final item = value as Map<String, dynamic>;
        return MapEntry(
          key,
          item.map((itemKey, itemValue) => MapEntry(itemKey, '$itemValue')),
        );
      });
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  static Future<void> _writeLocalStore(
    Map<String, Map<String, String>> values,
  ) async {
    final file = await _storeFile();
    final tmp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(encoder.convert({'version': 1, 'values': values}));
    await tmp.rename(file.path);
    try {
      await Process.run('/bin/chmod', ['600', file.path]);
    } catch (_) {
      // Best-effort only. The file still lives inside the user's app support
      // directory and values are encrypted at rest.
    }
  }

  static Map<String, String> _encrypt(String value) {
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(_keyBytes()), 128, nonce, Uint8List(0)),
      );
    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(value)));
    return {'nonce': base64Encode(nonce), 'data': base64Encode(encrypted)};
  }

  static String? _decrypt(Map<String, String> encrypted) {
    try {
      final nonce = base64Decode(encrypted['nonce'] ?? '');
      final data = base64Decode(encrypted['data'] ?? '');
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(_keyBytes()),
            128,
            Uint8List.fromList(nonce),
            Uint8List(0),
          ),
        );
      final decrypted = cipher.process(Uint8List.fromList(data));
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _keyBytes() {
    final material = [
      _salt,
      Platform.operatingSystem,
      Platform.localHostname,
      Platform.environment['USER'] ?? '',
      Platform.environment['HOME'] ?? '',
      'cn.linota.loveace.desktop',
    ].join('|');
    return Uint8List.fromList(sha256.convert(utf8.encode(material)).bytes);
  }
}
