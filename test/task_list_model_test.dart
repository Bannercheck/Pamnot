import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/models/settings.dart';
import 'package:pamnot/models/task.dart';
import 'package:pamnot/models/task_list.dart';

void main() {
  test('TaskList JSON gidiş-dönüş ve hazır listeler', () {
    final d = TaskList.defaults(tr: true);
    expect(d.map((l) => l.id), ['personal', 'work', 'school', 'shopping', 'home']);
    expect(d.map((l) => l.name), ['Kişisel', 'İş', 'Okul', 'Alışveriş', 'Ev']);
    expect(d.every((l) => l.builtIn), isTrue);
    expect(TaskList.fromJson(d[1].toJson()).name, 'İş');
  });

  test('hazır listelerin renk, simge ve sırası; İngilizce adlar', () {
    final d = TaskList.defaults(tr: false);
    expect(d.map((l) => l.name), ['Personal', 'Work', 'School', 'Shopping', 'Home']);
    expect(d.map((l) => l.colorIndex), [3, 4, 5, 1, 2]);
    expect(d.map((l) => l.icon), ['person', 'work', 'school', 'shopping', 'home']);
    expect(d.map((l) => l.order), [0, 1, 2, 3, 4]);
    expect(TaskList.personalId, 'personal');
  });

  test('TaskList toJson anahtarları, fromJson varsayılanları ve copyWith', () {
    const l = TaskList(id: 'x', name: 'Kitap', colorIndex: 6, icon: 'book', order: 7);
    expect(l.toJson(), {'id': 'x', 'name': 'Kitap', 'color': 6, 'icon': 'book', 'order': 7, 'builtIn': false});
    final back = TaskList.fromJson(l.toJson());
    expect((back.id, back.name, back.colorIndex, back.icon, back.order, back.builtIn), ('x', 'Kitap', 6, 'book', 7, false));
    final min = TaskList.fromJson({'id': 'y', 'name': 'Y'});
    expect((min.colorIndex, min.icon, min.order, min.builtIn), (3, 'list', 0, false));
    final c = TaskList.defaults(tr: true).first.copyWith(name: 'Ben', colorIndex: 0, icon: 'star', order: 9);
    expect((c.id, c.name, c.colorIndex, c.icon, c.order, c.builtIn), ('personal', 'Ben', 0, 'star', 9, true));
  });

  test('eski görev JSON\'u: liste personal, kutu plan; yüksek öncelik doNow', () {
    final old = {'id': 'a', 'title': 'x', 'priority': 'high', 'createdAt': '2026-11-01T09:00:00.000'};
    final t = TaskItem.fromJson(old);
    expect((t.listId, t.quadrant, t.order), ('personal', Quadrant.doNow, 0));
    expect(TaskItem.fromJson({...old, 'priority': 'low'}).quadrant, Quadrant.plan);
  });

  test('bilinmeyen quadrant değeri plan olur; yeni alanlar gidiş-dönüşte korunur', () {
    final base = {'id': 'a', 'title': 'x', 'priority': 'normal', 'createdAt': '2026-11-01T09:00:00.000'};
    expect(TaskItem.fromJson({...base, 'quadrant': 'someday'}).quadrant, Quadrant.plan);
    final t = TaskItem(
        id: 'b', title: 'y', createdAt: DateTime(2026, 11, 2), listId: 'work', quadrant: Quadrant.delegate, order: 4);
    final j = t.toJson();
    expect((j['list'], j['quadrant'], j['order']), ('work', 'delegate', 4));
    final back = TaskItem.fromJson(j);
    expect((back.listId, back.quadrant, back.order), ('work', Quadrant.delegate, 4));
    // Stored quadrant wins over the priority fallback.
    expect(TaskItem.fromJson({...base, 'priority': 'high', 'quadrant': 'later'}).quadrant, Quadrant.later);
    final c = t.copyWith(listId: 'home', quadrant: Quadrant.later, order: 1);
    expect((c.listId, c.quadrant, c.order), ('home', Quadrant.later, 1));
    final same = t.copyWith(title: 'z');
    expect((same.listId, same.quadrant, same.order), ('work', Quadrant.delegate, 4));
    final fresh = TaskItem(id: 'c', title: 'n', createdAt: DateTime(2026));
    expect((fresh.listId, fresh.quadrant, fresh.order), ('personal', Quadrant.plan, 0));
  });

  test('AppSettings: lastListId ve voiceAutoSave varsayılanları ve gidiş-dönüş', () {
    const s = AppSettings();
    expect((s.lastListId, s.voiceAutoSave), ('', true));
    final old = AppSettings.fromJson(const {'language': 'tr'});
    expect((old.lastListId, old.voiceAutoSave), ('', true));
    final c = s.copyWith(lastListId: 'work', voiceAutoSave: false);
    expect((c.lastListId, c.voiceAutoSave), ('work', false));
    final j = c.toJson();
    expect((j['lastListId'], j['voiceAutoSave']), ('work', false));
    final back = AppSettings.fromJson(j);
    expect((back.lastListId, back.voiceAutoSave), ('work', false));
    expect(AppSettings.fromJson(const {'voiceAutoSave': 'x'}).voiceAutoSave, isTrue);
    final kept = c.copyWith(seeded: true);
    expect((kept.lastListId, kept.voiceAutoSave), ('work', false));
  });

  test('kutu başlıkları tasarımdaki gibi', () {
    expect(S.tr.quadrantTitle(Quadrant.doNow), 'Önemli · Acil');
    expect(S.tr.quadrantTitle(Quadrant.plan), 'Önemli · Planlı');
    expect(S.tr.quadrantTitle(Quadrant.delegate), 'Acil · Önemsiz');
    expect(S.tr.quadrantTitle(Quadrant.later), 'Sonra · Belki');
    expect(S.en.quadrantTitle(Quadrant.delegate), 'Urgent · Less important');
    expect(S.tr.quadrantHint(Quadrant.doNow), 'Bugün ilgilen');
  });

  test('kutu başlıkları ve ipuçları: kalan çiftler', () {
    expect(S.en.quadrantTitle(Quadrant.doNow), 'Important · Urgent');
    expect(S.en.quadrantTitle(Quadrant.plan), 'Important · Planned');
    expect(S.en.quadrantTitle(Quadrant.later), 'Later · Maybe');
    expect(Quadrant.values.map(S.tr.quadrantHint),
        ['Bugün ilgilen', 'Zamanını belirle', 'Kısa tut ya da paylaş', 'Gerekirse dön']);
    expect(Quadrant.values.map(S.en.quadrantHint),
        ['Deal with it today', 'Give it a time', 'Keep it short or share it', 'Come back if needed']);
  });
}
