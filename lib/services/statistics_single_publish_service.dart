import 'dart:async';

import 'statistics_single_publish_coordinator.dart';

/// Local, non-network statistics reconciliation. Independent of Dashboard.
/// Delivery requires a separately approved server-side REMOVE protocol.
class StatisticsSinglePublishService {
  StatisticsSinglePublishService({
    StatisticsSinglePublishCoordinator? coordinator,
    Duration interval = const Duration(seconds: 12),
  }) : _coordinator = coordinator ?? StatisticsSinglePublishCoordinator(),
       _interval = interval;

  final StatisticsSinglePublishCoordinator _coordinator;
  final Duration _interval;
  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(_interval, (_) => unawaited(_reconcile()));
    unawaited(_reconcile());
  }

  Future<void> _reconcile() async {
    try {
      await _coordinator.reconcileOnce();
    } catch (_) {
      // Retry on the next interval; never interfere with scoring.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}

final statisticsSinglePublishService = StatisticsSinglePublishService();
