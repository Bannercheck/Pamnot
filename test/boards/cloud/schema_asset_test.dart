import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pamnot/boards/cloud/setup_wizard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled setup SQL is supabase/schema.sql', () async {
    final source = File('supabase/schema.sql').readAsStringSync();
    expect(File(schemaAsset).readAsStringSync(), source, reason: 'copy supabase/schema.sql to $schemaAsset');
    expect(await rootBundle.loadString(schemaAsset), source, reason: 'declared in pubspec flutter.assets');
  });

  test('the SQL has what the app relies on', () {
    final sql = File('supabase/schema.sql').readAsStringSync();
    for (final fn in [
      'pamnot_info()',
      'server_time_ms()',
      'create_board(p_id uuid)',
      'push_items(p_board uuid, p_items jsonb)',
      'join_board(p_code text)',
      'leave_board(p_board uuid)',
      'remove_member(p_board uuid, p_user uuid)',
      'rotate_invite(p_board uuid)',
      'get_invite(p_board uuid)',
      'delete_board(p_board uuid)',
    ]) {
      expect(sql, contains('function public.$fn'), reason: fn);
    }
    expect(sql, contains("jsonb_build_object('schema', 1)"));
    expect(sql, isNot(contains('upsert_items(p_')), reason: 'no client-side upsert RPC');
  });
}
