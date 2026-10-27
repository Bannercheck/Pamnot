import 'store_io.dart' if (dart.library.js_interop) 'store_web.dart' as platform;

/// Where the app keeps its JSON documents. Each key holds one document
/// (notes, tasks, …) so a change rewrites only that document.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Files on iOS, Android, macOS, Windows and Linux; browser storage on web.
  static KeyValueStore platformDefault() => platform.createStore();
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
