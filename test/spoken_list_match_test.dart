import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/core/spoken/list_match.dart';
import 'package:pamnot/models/task_list.dart';

const _gym = TaskList(id: 'gym-1', name: 'Spor salonu');

List<TaskList> _lists(bool tr) => [...TaskList.defaults(tr: tr), _gym];

void main() {
  // (cümle, Türkçe mi) → (listId, başlık)
  const table = <(String, bool, String?, String)>[
    ('alışveriş listesine ekmek ekle', true, 'shopping', 'ekmek'),
    ('ekmek al alışveriş listeme', true, 'shopping', 'ekmek al'),
    ('spor salonu listesine havlu', true, 'gym-1', 'havlu'),
    ('işe toplantı notu', true, 'work', 'işe toplantı notu'),
    ('okula git', true, 'school', 'okula git'),
    ('işe geç kalma', true, 'work', 'işe geç kalma'),
    ('evet tamam', true, null, 'evet tamam'),
    ('işaret koy', true, null, 'işaret koy'),
    ('toplantı işe', true, null, 'toplantı işe'),
    ('alışveriş listesine ekle', true, null, 'alışveriş listesine ekle'),
    ('add milk to the shopping list', false, 'shopping', 'milk'),
    ('milk on my Shopping list', false, 'shopping', 'milk'),
    ('work on the report', false, null, 'work on the report'),
    ('İŞ LİSTESİNE rapor', true, 'work', 'rapor'),
    // ek satırlar
    ('Alışveriş listesine ekmek ekle', true, 'shopping', 'Ekmek'),
    ('Ekmek alışveriş listesine ekle', true, 'shopping', 'Ekmek'),
    ('alışveriş listesine ekle süt', true, 'shopping', 'süt'),
    ('rapor iş listemde', true, 'work', 'rapor'),
    ('eve ekmek götür', true, 'home', 'eve ekmek götür'),
    ('Kişisel listesine yaz günlük', true, 'personal', 'Günlük'),
    ('alışveriş listesi', true, null, 'alışveriş listesi'),
    ('ekmek alışveriş listesine lütfen ekle', true, null, 'ekmek alışveriş listesine lütfen ekle'),
    ('Add milk to the shopping list.', false, 'shopping', 'Milk'),
    ('to the work list send the report', false, 'work', 'send the report'),
    ('add to the shopping list', false, null, 'add to the shopping list'),
    ('shopping list', false, null, 'shopping list'),
    ('go to work', false, null, 'go to work'),
  ];

  for (final (sentence, tr, listId, title) in table) {
    test('${tr ? 'tr' : 'en'}: "$sentence" → ($listId, "$title")', () {
      final r = matchSpokenList(sentence, _lists(tr), turkish: tr);
      expect(r.listId, listId);
      expect(r.title, title);
    });
  }

  test('en uzun liste adı önce denenir', () {
    final lists = [
      const TaskList(id: 'ev', name: 'Ev'),
      const TaskList(id: 'yeni-ev', name: 'Yeni ev'),
    ];
    expect(matchSpokenList('boya al yeni ev listesine', lists, turkish: true),
        (title: 'boya al', listId: 'yeni-ev'));
    expect(matchSpokenList('yeni eve taşın', lists, turkish: true),
        (title: 'yeni eve taşın', listId: 'yeni-ev'));
  });

  test('ad içindeki özel karakterler kalıp olarak yorumlanmaz', () {
    final lists = [const TaskList(id: 'x', name: 'A+B (iş)')];
    expect(matchSpokenList('rapor a+b (iş) listesine', lists, turkish: true),
        (title: 'rapor', listId: 'x'));
    expect(matchSpokenList('rapor aab (iş) listesine', lists, turkish: true).listId, isNull);
  });

  test('boş adlı liste ve boş liste dizisi eşleşmez', () {
    expect(matchSpokenList('listesine süt', [const TaskList(id: 'e', name: ' ')], turkish: true),
        (title: 'listesine süt', listId: null));
    expect(matchSpokenList('süt', const [], turkish: true), (title: 'süt', listId: null));
  });
}
