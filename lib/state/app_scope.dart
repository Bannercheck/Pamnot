import 'package:flutter/widgets.dart';

import 'app_controller.dart';

/// Gives the widget tree the [AppController]. Widgets name the slices they
/// read, and only rebuild when one of those slices changes:
///
///     final app = AppScope.of(context, {Slice.tasks});
class AppScope extends StatefulWidget {
  const AppScope({super.key, required this.controller, required this.child});

  final AppController controller;
  final Widget child;

  /// Subscribes to [slices]; pass none to read without rebuilding (e.g. in
  /// callbacks).
  static AppController of(BuildContext context, [Set<Slice> slices = const {}]) {
    if (slices.isEmpty) {
      return context.getInheritedWidgetOfExactType<_AppModel>()!.controller;
    }
    late _AppModel model;
    for (final s in slices) {
      model = InheritedModel.inheritFrom<_AppModel>(context, aspect: s)!;
    }
    return model.controller;
  }

  @override
  State<AppScope> createState() => _AppScopeState();
}

class _AppScopeState extends State<AppScope> {
  late Map<Slice, int> _revs = widget.controller.revisions;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() => _revs = widget.controller.revisions);

  @override
  Widget build(BuildContext context) =>
      _AppModel(controller: widget.controller, revs: _revs, child: widget.child);
}

class _AppModel extends InheritedModel<Slice> {
  const _AppModel({required this.controller, required this.revs, required super.child});

  final AppController controller;
  final Map<Slice, int> revs;

  @override
  bool updateShouldNotify(_AppModel old) => true;

  @override
  bool updateShouldNotifyDependent(_AppModel old, Set<Slice> deps) =>
      deps.any((s) => old.revs[s] != revs[s]);
}
