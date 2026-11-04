import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/boards_controller.dart';
import 'package:pamnot/boards/cloud/cloud_api.dart';
import 'package:pamnot/boards/cloud/cloud_scope.dart';
import 'package:pamnot/boards/cloud/cloud_service.dart';
import 'package:pamnot/boards/cloud/collab_settings.dart';
import 'package:pamnot/boards/cloud/invite.dart';
import 'package:pamnot/boards/cloud/setup_wizard.dart';
import 'package:pamnot/boards/cloud/share_sheet.dart';
import 'package:pamnot/boards/connection.dart';
import 'package:pamnot/boards/model/board_doc.dart';
import 'package:pamnot/boards/model/board_item.dart';
import 'package:pamnot/boards/sync/backend.dart';
import 'package:pamnot/data/store.dart';
import 'package:pamnot/l10n/strings.dart';
import 'package:pamnot/state/app_controller.dart';
import 'package:pamnot/state/app_scope.dart';

import 'fakes.dart';

const url = 'https://abcdefghijklmnopqrst.supabase.co';
const host = 'abcdefghijklmnopqrst.supabase.co';
const key = 'sb_publishable_AbCdEf123456';
const boardId = '11111111-1111-4111-8111-111111111111';

Widget app(CloudService cloud, Widget home, {AppController? controller}) {
  Widget w = MaterialApp(
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );
  if (controller != null) w = AppScope(controller: controller, child: w);
  return CloudScope(service: cloud, child: w);
}

/// A page with one button that runs [action] with a context under the app.
Widget launcher(Future<void> Function(BuildContext context) action) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(onPressed: () => unawaited(action(context)), child: const Text('open')),
        ),
      ),
    );

class Harness {
  Harness({bool connected = false, String serverUrl = url}) {
    store = MemoryStore();
    if (connected) {
      store.data[CloudService.docKey] = jsonEncode({'url': serverUrl, 'key': key, 'name': 'Ayşe', 'colorIndex': 3});
      api.sessions[serverUrl] = 'me';
    }
  }

  late final MemoryStore store;
  final api = FakeCloudApi();
  late final CloudService cloud = CloudService(store: store, api: api, defaultUrl: '', defaultKey: '');
  late final BoardsController boards = BoardsController(store: store, saveDelay: Duration.zero);

  FakeBackend backend() {
    final h = cloud.server?.host ?? host;
    return api.backend(h) as FakeBackend;
  }

  Future<void> start(WidgetTester tester) async {
    await boards.load();
    await cloud.start();
    cloud.attach(boards, connections: (b, c) => _Sync(b, c));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await boards.flush();
    boards.dispose();
  }
}

/// Stands in for BoardSync: an uploading board becomes shared at once.
class _Sync implements BoardConnection {
  _Sync(this.board, this.controller) {
    scheduleMicrotask(() {
      if (_closed) return;
      final d = board.doc;
      if (d.state == BoardState.uploading) {
        d.state = BoardState.shared;
        d.clearDirty();
        controller.stateChanged(d);
      }
      _state.value = const SyncState(SyncStatus.synced);
    });
  }

  final OpenBoard board;
  final BoardsController controller;
  bool _closed = false;
  final _state = ValueNotifier(const SyncState(SyncStatus.sending));
  final _peers = ValueNotifier<List<Peer>>(const [
    Peer(key: 'node-b', userId: 'mert', name: 'Mert', colorIndex: 2),
  ]);
  final _cursors = ValueNotifier<Map<String, PeerCursor>>(const {});

  @override
  ValueListenable<SyncState> get state => _state;
  @override
  ValueListenable<List<Peer>> get peers => _peers;
  @override
  ValueListenable<Map<String, PeerCursor>> get cursors => _cursors;
  @override
  void sendCursor(Offset? canvasPosition, {bool pointer = true}) {}
  @override
  void setActivity({required String view, String? editing}) {}
  @override
  void kick() {}
  @override
  Future<void> retry() async {}
  @override
  Future<void> close() async => _closed = true;
}

void main() {
  setUp(() {});

  testWidgets('wizard: each step validates before going on, errors point to their step', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    await h.start(tester);
    bool? result;
    await tester.pumpWidget(app(h.cloud, launcher((c) async => result = await showSetupWizard(c))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ortak çalışmayı kur'), findsOneWidget);
    expect(find.text('Adresi kopyala'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('cloud-url')), findsOneWidget);

    // A dashboard URL is understood; a secret key is refused loudly.
    await tester.enterText(find.byKey(const ValueKey('cloud-url')),
        'https://supabase.com/dashboard/project/abcdefghijklmnopqrst/settings/api');
    await tester.pump();
    expect(find.text('Kullanılacak adres: $url'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('cloud-key')), 'sb_secret_abcdefghijklmnop');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bu gizli (secret) anahtar — asla paylaşma!'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-name')), findsNothing);

    // http to a remote host is refused too.
    await tester.enterText(find.byKey(const ValueKey('cloud-url')), 'http://example.com');
    await tester.enterText(find.byKey(const ValueKey('cloud-key')), key);
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.text('Adres https:// ile başlamalı.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cloud-url')), 'abcdefghijklmnopqrst');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-name')), findsOneWidget);

    // Step 5 needs a name.
    await tester.tap(find.byKey(const ValueKey('cloud-connect')));
    await tester.pumpAndSettle();
    expect(find.text('Bir ad yaz.'), findsOneWidget);
    expect(h.api.calls, isEmpty, reason: 'nothing goes out before the fields pass');

    // The SQL was not run: the error says so and leads back to step 2.
    h.api.schemaError = const CloudFailure(CloudProblem.sqlMissing);
    await tester.enterText(find.byKey(const ValueKey('cloud-name')), 'Ayşe');
    await tester.tap(find.byKey(const ValueKey('cloud-connect')));
    await tester.pumpAndSettle();
    expect(find.text('Kurulum SQL’i çalıştırılmamış görünüyor (2. adım).'), findsOneWidget);
    await tester.tap(find.text('2. adıma git'));
    await tester.pumpAndSettle();
    expect(find.text('SQL’i kopyala'), findsOneWidget);
    expect(h.cloud.ready.value, isFalse);

    h.api.schemaError = null;
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('cloud-connect')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hazır 🌸'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(h.cloud.ready.value, isTrue);
    expect(h.cloud.config?.url, url);
    expect(h.cloud.displayName, 'Ayşe');
    await h.finish(tester);
  });

  testWidgets('wizard: a known server goes straight to name and colour', (tester) async {
    final h = Harness();
    h.store.data[CloudService.docKey] = jsonEncode({'url': url, 'key': key, 'name': 'Ayşe', 'colorIndex': 3});
    await h.start(tester);
    expect(h.cloud.ready.value, isFalse, reason: 'saved server, no session');
    await tester.pumpWidget(app(h.cloud, const SetupWizardPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cloud-url')), findsNothing);
    expect(find.text('Sunucu: $host ✓'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-name')), findsOneWidget);
    await h.finish(tester);
  });

  group('join sheet', () {
    final invite = const Invite(url: url, key: key, code: 'K7Q2M9XDAB', title: 'Pano').encode();
    final message = 'Pamnot’ta «Pano» panosuna katıl 🌸\n1. Pamnot’u aç → Takip → Panolar → Davete katıl\n'
        '2. Bu metnin tamamını yapıştır:\n$invite';

    Future<Future<String?> Function()> open(WidgetTester tester, Harness h) async {
      String? result;
      var done = false;
      await tester.pumpWidget(app(
        h.cloud,
        launcher((c) async {
          result = await showJoinSheet(c, boards: h.boards);
          done = true;
        }),
      ));
      return () async {
        expect(done, isTrue, reason: 'sheet closed');
        return result;
      };
    }

    testWidgets('not set up: paste a whole message, preview, name, join', (tester) async {
      final h = Harness();
      await h.start(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': message};
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final result = await open(tester, h);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Davete katıl'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('join-paste')));
      await tester.pumpAndSettle();
      expect(find.text('«Pano» · $host'), findsOneWidget);
      expect(find.text('Bu davet Pamnot’u $host sunucusuna bağlayacak.'), findsOneWidget);
      expect(find.byKey(const ValueKey('join-name')), findsOneWidget);

      h.api.lastBackend = FakeBackend(host: host, user: () => h.api.userId)
        ..onJoin = (code) => code == 'K7Q2M9XDAB' ? const JoinResult(boardId: boardId, title: 'Pano') : null;
      await tester.enterText(find.byKey(const ValueKey('join-name')), 'Mert');
      await tester.tap(find.byKey(const ValueKey('join-go')));
      await tester.pumpAndSettle();

      expect(await result(), boardId);
      expect(h.api.calls, containsAllInOrder(['start $url', 'probe', 'schema', 'signIn Mert', 'profile Mert ${h.cloud.colorIndex}']));
      expect(h.cloud.config?.url, url, reason: 'the invite configured the server');
      final s = h.boards.summary(boardId)!;
      expect(s.title, 'Pano');
      expect(s.state, BoardState.shared);
      expect(s.account, h.cloud.account);
      await h.finish(tester);
    });

    testWidgets('refuses an invite for another server', (tester) async {
      final h = Harness(connected: true, serverUrl: 'https://zyxwvutsrqponmlkjihg.supabase.co');
      await h.start(tester);
      final result = await open(tester, h);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('join-text')), message);
      await tester.pumpAndSettle();
      expect(find.text('Bu davet başka bir sunucuya ait. Önce Ayarlar › Ortak çalışma’dan bağlantıyı kaldır.'), findsOneWidget);
      final go = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Katıl'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(go.onPressed, isNull);
      Navigator.of(tester.element(find.text('Katıl'))).pop();
      await tester.pumpAndSettle();
      expect(await result(), isNull);
      await h.finish(tester);
    });

    testWidgets('text without an invite, wrong code, rate limit and offline are explained', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      expect(h.cloud.ready.value, isTrue);
      final b = h.backend();
      await open(tester, h);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('join-text')), 'selam, davet bu: PMN1.bozuk');
      await tester.pumpAndSettle();
      expect(find.text('Bu metinde bir Pamnot daveti bulamadım.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('join-text')), message);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('join-name')), findsNothing, reason: 'already signed in');
      expect(find.textContaining('sunucusuna bağlayacak'), findsNothing);

      b.onJoin = (_) => null;
      await tester.tap(find.byKey(const ValueKey('join-go')));
      await tester.pumpAndSettle();
      expect(find.text('Bu davet artık geçerli değil. Pano sahibinden yeni davet iste.'), findsOneWidget);

      b.joinError = const RateLimited();
      await tester.tap(find.byKey(const ValueKey('join-go')));
      await tester.pumpAndSettle();
      expect(find.text('Çok fazla deneme; biraz sonra tekrar dene.'), findsOneWidget);

      b.joinError = const BackendUnavailable();
      await tester.tap(find.byKey(const ValueKey('join-go')));
      await tester.pumpAndSettle();
      expect(find.text('İnternet bağlantısı gerekiyor.'), findsOneWidget);
      expect(b.calls.where((c) => c == 'join K7Q2M9XDAB'), hasLength(3));
      await h.finish(tester);
    });
  });

  group('confirmRemoveBoard', () {
    Future<bool?> run(WidgetTester tester, Harness h, String id, Future<void> Function() answer) async {
      bool? result;
      await tester.pumpWidget(app(h.cloud, launcher((c) async => result = await confirmRemoveBoard(c, boards: h.boards, boardId: id))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await answer();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('device-only: confirm deletes, cancel keeps', (tester) async {
      final h = Harness();
      await h.start(tester);
      final id = await h.boards.createBoard(title: 'Yerel pano', colorIndex: 1, template: BoardTemplate.tasks, strings: S.tr);
      var r = await run(tester, h, id, () async {
        expect(find.text('«Yerel pano» bu cihazdan silinecek. Bu geri alınamaz.'), findsOneWidget);
        await tester.tap(find.text('Vazgeç'));
      });
      expect(r, isFalse);
      expect(h.boards.summary(id), isNotNull);
      r = await run(tester, h, id, () => tester.tap(find.text('Sil')));
      expect(r, isTrue);
      expect(h.boards.summary(id), isNull);
      await h.finish(tester);
    });

    testWidgets('member: leaves on the server, then removes the copy', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      await h.boards.addJoined(boardId: boardId, title: 'Ortak', account: h.cloud.account!);
      final b = h.backend()..status = const BoardStatusInfo(ownerId: 'someone-else');
      final r = await run(tester, h, boardId, () async {
        expect(find.textContaining('«Ortak» panosundan ayrılırsın'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Panodan ayrıl'));
      });
      expect(r, isTrue);
      expect(b.calls, ['status $boardId', 'leave $boardId']);
      expect(h.boards.summary(boardId), isNull);
      await h.finish(tester);
    });

    testWidgets('owner: deletes for everyone', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      await h.boards.addJoined(boardId: boardId, title: 'Ortak', account: h.cloud.account!);
      final b = h.backend()..status = const BoardStatusInfo(ownerId: 'me');
      final r = await run(tester, h, boardId, () async {
        expect(find.text('«Ortak» herkes için silinecek. Bu geri alınamaz.'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Herkes için sil'));
      });
      expect(r, isTrue);
      expect(b.calls, ['status $boardId', 'delete $boardId']);
      expect(h.boards.summary(boardId), isNull);
      await h.finish(tester);
    });

    testWidgets('offline: nothing happens and it says why', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      await h.boards.addJoined(boardId: boardId, title: 'Ortak', account: h.cloud.account!);
      h.backend().statusError = const BackendUnavailable();
      final r = await run(tester, h, boardId, () async {});
      expect(r, isFalse);
      expect(find.text('İnternet bağlantısı gerekiyor.'), findsOneWidget);
      expect(h.boards.summary(boardId), isNotNull);
      await h.finish(tester);
    });

    testWidgets('removed in the meantime: only the copy goes', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      await h.boards.addJoined(boardId: boardId, title: 'Ortak', account: h.cloud.account!);
      final b = h.backend()..status = null;
      final r = await run(tester, h, boardId, () => tester.tap(find.widgetWithText(FilledButton, 'Bu cihazdan sil')));
      expect(r, isTrue);
      expect(b.calls, ['status $boardId']);
      expect(h.boards.summary(boardId), isNull);
      await h.finish(tester);
    });

    testWidgets('deleted by the owner: keep a device-only copy', (tester) async {
      final h = Harness(connected: true);
      await h.start(tester);
      await h.boards.addJoined(boardId: boardId, title: 'Ortak', account: h.cloud.account!);
      final ob = (await h.boards.open(boardId))!;
      ob.doc.write('22222222-2222-4222-8222-222222222222', ItemKind.sticky, {F.text: 'not', F.x: 0, F.y: 0}, '000000000000001-00000-0000000000000001');
      ob.doc.state = BoardState.deleted;
      h.boards.stateChanged(ob.doc);
      await h.boards.release(ob);
      expect(h.boards.summary(boardId)?.state, BoardState.deleted);
      final r = await run(tester, h, boardId, () async {
        expect(find.text('Pano sahibi bu panoyu herkes için sildi.'), findsOneWidget);
        await tester.tap(find.text('Kopyasını cihazda sakla'));
      });
      expect(r, isTrue);
      expect(h.boards.summary(boardId), isNull);
      final copy = h.boards.boards.single;
      expect(copy.state, BoardState.local);
      expect(copy.title, 'Ortak');
      expect(copy.canvasCount, 1);
      await h.finish(tester);
    });
  });

  group('share sheet', () {
    testWidgets('not set up: explains, offers setup, invite or later', (tester) async {
      final h = Harness();
      await h.start(tester);
      final id = await h.boards.createBoard(title: 'Yerel', colorIndex: 1, template: BoardTemplate.blank, strings: S.tr);
      await tester.pumpWidget(app(h.cloud, launcher((c) => showShareSheet(c, boards: h.boards, boardId: id))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Ekibinle paylaş'), findsOneWidget);
      expect(find.text('Kurulumu başlat'), findsOneWidget);
      expect(find.text('Şimdilik kalsın'), findsOneWidget);
      await tester.tap(find.text('Davetim var'));
      await tester.pumpAndSettle();
      expect(find.text('Davete katıl'), findsOneWidget, reason: 'the join sheet follows');
      await h.finish(tester);
    });

    testWidgets('device-only board: privacy note, upload, then invite and members', (tester) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = Harness(connected: true);
      await h.start(tester);
      final b = h.backend()
        ..status = const BoardStatusInfo(ownerId: 'me')
        ..memberList = const [
          BoardMember(userId: 'me', role: 'owner', displayName: 'Ayşe', colorIndex: 3),
          BoardMember(userId: 'mert', role: 'editor', displayName: 'Mert', colorIndex: 2),
          BoardMember(userId: 'ilker', role: 'editor', displayName: 'ilker', colorIndex: 4),
        ];
      final id = await h.boards.createBoard(title: 'Lansman', colorIndex: 1, template: BoardTemplate.tasks, strings: S.tr);
      await tester.pumpWidget(app(h.cloud, launcher((c) => showShareSheet(c, boards: h.boards, boardId: id))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Pano sunucuya yüklenecek. Davet metnine sahip olan herkes panoyu görebilir ve düzenleyebilir.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('share-upload')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(h.boards.summary(id)?.state, BoardState.shared);
      expect(b.calls, containsAll(['status $id', 'members $id', 'invite $id']));
      final text = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(text, startsWith('Pamnot’ta «Lansman» panosuna katıl 🌸'));
      final inv = Invite.find(text)!;
      expect(inv.code, 'ABCDEFGHJK');
      expect(inv.url, url);
      expect(inv.title, 'Lansman');
      expect(find.text('Davet metnini kopyala'), findsOneWidget);

      // Members: presence from the connection, (sen), Sahip, Turkish initials.
      expect(find.text('Üyeler'), findsOneWidget);
      expect(find.text(' (sen)', findRichText: true), findsNothing);
      expect(find.textContaining('(sen)', findRichText: true), findsOneWidget);
      expect(find.text('Sahip'), findsOneWidget);
      expect(find.text('Şimdi burada'), findsNWidgets(2), reason: 'self and Mert');
      expect(find.text('Çevrimdışı'), findsOneWidget);
      expect(find.text('İ'), findsOneWidget, reason: 'ilker → İ');

      // Owner: reset the invite.
      await tester.tap(find.text('Daveti yenile'));
      await tester.pumpAndSettle();
      expect(find.text('Eski davet metni artık çalışmaz. Katılmış olanlar panoda kalır.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Daveti yenile'));
      await tester.pumpAndSettle();
      expect(Invite.find(tester.widget<SelectableText>(find.byType(SelectableText)).data!)?.code, 'NEWC0DE123');
      await h.finish(tester);
    });
  });

  group('settings', () {
    testWidgets('off: explains and offers setup or an invite', (tester) async {
      final h = Harness();
      await h.start(tester);
      await tester.pumpWidget(app(h.cloud, const Scaffold(body: CollabSettingsSection())));
      expect(find.text('Kapalı — panoların yalnızca bu cihazda.'), findsOneWidget);
      expect(find.text('Kur'), findsOneWidget);
      expect(find.text('Davetim var'), findsOneWidget);
      await h.finish(tester);
    });

    testWidgets('on: server, name, colour; disconnect counts unsent changes', (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryStore({
        CloudService.docKey: jsonEncode({'url': url, 'key': key, 'name': 'Ayşe', 'colorIndex': 3}),
      });
      final api = FakeCloudApi()..sessions[url] = 'me';
      final controller = AppController(store: store, saveDelay: Duration.zero);
      await controller.boards.load();
      final cloud = CloudService(store: store, api: api, defaultUrl: '', defaultKey: '');
      await cloud.start();
      cloud.attach(controller.boards, connections: (b, c) => LocalConnection());
      await controller.boards.addJoined(boardId: boardId, title: 'Ortak', account: cloud.account!);
      final ob = (await controller.boards.open(boardId))!;
      ob.doc.write('22222222-2222-4222-8222-222222222222', ItemKind.sticky, {F.text: 'gönderilmedi'}, '000000000000001-00000-0000000000000001');
      controller.boards.persist(ob.doc);
      await controller.boards.release(ob);

      await tester.pumpWidget(app(cloud, const Scaffold(body: SingleChildScrollView(child: CollabSettingsSection())), controller: controller));
      expect(find.text('Sunucu: $host ✓'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Ayşe'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('collab-disconnect')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 gönderilmemiş değişiklik kaybolacak.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Bağlantıyı kaldır'));
      await tester.pumpAndSettle();
      expect(cloud.ready.value, isFalse);
      expect(cloud.config, isNull);
      expect(api.calls.last, 'stop signOut');
      expect(controller.boards.summary(boardId), isNull);
      expect(find.text('Kapalı — panoların yalnızca bu cihazda.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await controller.boards.flush();
      controller.dispose();
    });
  });
}
