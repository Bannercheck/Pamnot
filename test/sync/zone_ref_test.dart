import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/features/sync/zone_ref.dart';

void main() {
  test('forList / localListId / parse / toString: personal, list-work, shared:_abc:list-okul gidiş dönüş', () {
    expect(ZoneRef.personal.isShared, isFalse);
    expect(ZoneRef.personal.localListId, isNull);
    expect(ZoneRef.personal.toString(), 'personal');
    expect(ZoneRef.parse('personal'), ZoneRef.personal);

    final work = ZoneRef.forList('work');
    expect(work, const ZoneRef.private('list-work'));
    expect(work.isShared, isFalse);
    expect(work.localListId, 'work');
    expect(work.toString(), 'list-work');
    expect(ZoneRef.parse('list-work'), work);

    final okul = ZoneRef.forList('shared:_abc:okul');
    expect(okul, const ZoneRef.shared('_abc', 'list-okul'));
    expect(okul.isShared, isTrue);
    expect(okul.owner, '_abc');
    expect(okul.localListId, 'shared:_abc:okul');
    expect(okul.toString(), 'shared:_abc:list-okul');
    expect(ZoneRef.parse('shared:_abc:list-okul'), okul);
    expect(ZoneRef.parse(okul.toString())!.localListId, 'shared:_abc:okul');

    // The list with the id "personal" lives in its own zone, not in "personal".
    expect(ZoneRef.forList('personal').toString(), 'list-personal');
    expect(ZoneRef.forList('personal'), isNot(ZoneRef.personal));
    expect(ZoneRef.forList('work').hashCode, work.hashCode);

    expect(ZoneRef.isSharedListId('shared:_abc:okul'), isTrue);
    expect(ZoneRef.isSharedListId('shared:_abc'), isFalse);
    expect(ZoneRef.isSharedListId('work'), isFalse);

    expect(recordKey(RecordType.task, 'a1'), 'task:a1');
    expect(recordKey(RecordType.list, 'shared:_abc:okul'), 'list:shared:_abc:okul');
  });

  test('RF2: parse geçersizleri reddeder: "", "list-", "shared:x", "shared::list-a", "../x", 300 karakter', () {
    for (final s in [
      '',
      'list-',
      'shared:x',
      'shared::list-a',
      'shared:x:list-',
      'shared:x:personal',
      'shared:a:b:list-c',
      '../x',
      'list-../x',
      'list-a/b',
      'list-a b',
      'Personal',
      'list-${'a' * 295}',
    ]) {
      expect(ZoneRef.parse(s), isNull, reason: s);
    }
    expect(ZoneRef.parse('list-${'a' * 200}'), isNotNull);
  });
}
