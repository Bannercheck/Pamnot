import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

KeyValueStore createStore() => FileStore();

/// One JSON file per key in the app support directory. Writes go to a
/// temporary file first and are renamed into place, so a crash mid-write
/// never leaves a half-written document behind.
class FileStore implements KeyValueStore {
  FileStore({Directory? directory}) : _fixed = directory;

  final Directory? _fixed;
  Directory? _dir;

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final base = _fixed ?? Directory('${(await getApplicationSupportDirectory()).path}/pamuk');
    await base.create(recursive: true);
    return _dir = base;
  }

  @override
  Future<String?> read(String key) async {
    final f = File('${(await _directory()).path}/$key.json');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    final dir = await _directory();
    final tmp = File('${dir.path}/$key.json.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename('${dir.path}/$key.json');
  }

  @override
  Future<void> delete(String key) async {
    final f = File('${(await _directory()).path}/$key.json');
    if (await f.exists()) await f.delete();
  }
}
