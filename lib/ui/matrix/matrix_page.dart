import 'package:flutter/material.dart';

import '../../models/task_list.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../common/glass.dart';
import '../common/glass_nav_bar.dart';
import 'list_tabs.dart';
import 'quadrant_box.dart';

/// The Matrix tab (design §3.3): the list tabs on a glass strip, then the
/// four boxes of the selected list.
///
/// Phone width (≥ 360 pt) with text at most 130 %: a 2×2 grid of equal boxes
/// whose cards scroll inside each box. Narrower, larger text, or too short
/// for two rows of boxes (a phone on its side): one column, the four boxes
/// under each other, and the page scrolls.
///
/// Keys: `list-tab-<id>`, `list-add`, `box-<quadrant>`, `box-add-<quadrant>`,
/// `matrix-card-<taskId>`, `box-finished-<quadrant>`.
class MatrixPage extends StatelessWidget {
  const MatrixPage({super.key});

  static const _gap = 10.0;

  /// The smallest box height the 2×2 grid accepts (header plus a card).
  static const _minGridBox = 150.0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.tasks, Slice.lists, Slice.settings});
    final listId = app.currentListId;
    final bottom = scrollEndSpace(context);

    Widget box(Quadrant q, {required bool scrollable}) => QuadrantBox(
          key: Key('box-${q.name}'),
          app: app,
          listId: listId,
          quadrant: q,
          scrollable: scrollable,
        );

    return Scaffold(
      body: GlassScope(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, _gap),
                child: ListTabs(app: app),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  // The height check keeps a landscape phone from squeezing
                  // the boxes below their header.
                  final grid = constraints.maxWidth >= 360 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
                      constraints.maxHeight - bottom >= 2 * _minGridBox + _gap;
                  if (grid) {
                    Widget row(Quadrant a, Quadrant b) => Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: box(a, scrollable: true)),
                              const SizedBox(width: _gap),
                              Expanded(child: box(b, scrollable: true)),
                            ],
                          ),
                        );
                    return Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
                      child: Column(
                        children: [
                          row(Quadrant.doNow, Quadrant.plan),
                          const SizedBox(height: _gap),
                          row(Quadrant.delegate, Quadrant.later),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    key: const Key('matrix-scroll'),
                    padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
                    children: [
                      for (final q in Quadrant.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: _gap),
                          child: box(q, scrollable: false),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
