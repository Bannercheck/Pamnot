import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_controller.dart';
import '../../state/app_scope.dart';
import '../tasks/habits_view.dart';

/// Habits, opened from the Matrix screen's ⋯ menu (they used to be a
/// segment of the Track tab).
class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context, {Slice.habits, Slice.settings});
    final s = S.of(context);
    final pad = MediaQuery.sizeOf(context).width >= 560 ? 28.0 : 16.0;
    return Scaffold(
      appBar: AppBar(title: Text(s.habits)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'habits-fab',
        onPressed: () => showHabitEditor(context, app, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(s.newHabit),
      ),
      body: CustomScrollView(
        slivers: [
          HabitsSliver(app: app, padding: pad),
          // Room for the button over the last card.
          SliverToBoxAdapter(child: SizedBox(height: 96 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}
