import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../settings/settings_page.dart';

/// Large soft title at the top of each tab, with the settings button.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = S.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 560;
    return SliverToBoxAdapter(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 20, 16, wide ? 20 : 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null)
                      Text(subtitle!, style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    Text(title, style: t.textTheme.headlineMedium),
                  ],
                ),
              ),
              ...actions,
              IconButton(
                tooltip: s.settings,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
