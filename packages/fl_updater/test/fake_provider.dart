import 'dart:async';

import 'package:fl_updater/fl_updater.dart';

/// Test double: [fetched] is returned by [fetch] (and becomes [active]),
/// [active] is returned by [current]. Set [fetchError] to make [fetch] throw.
class FakeProvider implements FlUpdaterConfigProvider {
  FakeProvider({this.fetched, this.active, this.fetchError, bool push = false})
      : _controller = push ? StreamController<void>.broadcast() : null;

  String? fetched;
  String? active;
  Object? fetchError;
  int fetchCount = 0;
  final StreamController<void>? _controller;

  @override
  Future<String?> fetch(
      {Duration minimumFetchInterval = const Duration(hours: 1)}) async {
    fetchCount++;
    if (fetchError != null) throw fetchError!;
    active = fetched;
    return fetched;
  }

  @override
  Future<String?> current() async => active;

  @override
  Stream<void>? get changes => _controller?.stream;

  void emitChange() => _controller!.add(null);
}
