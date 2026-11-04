import 'package:flutter/widgets.dart';

import 'cloud_service.dart';

/// Gives the widget tree the [CloudService]; dependents rebuild when it
/// changes (ready, server, name, colour). Put it above MaterialApp so sheets
/// and routes see it:
///
///     runApp(CloudScope(service: cloud, child: PamnotApp(controller: controller)));
class CloudScope extends InheritedNotifier<CloudService> {
  const CloudScope({super.key, required CloudService service, required super.child}) : super(notifier: service);

  CloudService get service => notifier!;

  /// The service, subscribing [context] to its changes.
  static CloudService of(BuildContext context) {
    final s = maybeOf(context);
    assert(s != null, 'No CloudScope above this widget');
    return s!;
  }

  static CloudService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CloudScope>()?.notifier;

  /// The service without subscribing (for callbacks).
  static CloudService? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CloudScope>()?.notifier;
}
