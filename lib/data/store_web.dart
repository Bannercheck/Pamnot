import 'package:shared_preferences/shared_preferences.dart';

import 'store.dart';

KeyValueStore createStore() => _PrefsStore();

class _PrefsStore implements KeyValueStore {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString('pamnot.$key');

  @override
  Future<void> write(String key, String value) async =>
      (await _prefs).setString('pamnot.$key', value);

  @override
  Future<void> delete(String key) async => (await _prefs).remove('pamnot.$key');
}
