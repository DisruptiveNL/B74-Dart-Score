import '../services/b74_session_manager.dart';
import 'package:flutter/material.dart';

/// UI status only. Never infer trust from a successful LAN probe.
enum B74LinkState { unpaired, connected, offline, expired }

class B74LinkStatus {
  B74LinkStatus._();
  static final ValueNotifier<B74LinkState> state = ValueNotifier<B74LinkState>(
    B74LinkState.unpaired,
  );
}

/// App-wide indicator. The actual authenticated session will drive this
/// notifier in the next integration step; until then it stays grey.
final GlobalKey<NavigatorState> b74NavigatorKey = GlobalKey<NavigatorState>();

class B74LinkIndicator extends StatelessWidget {
  const B74LinkIndicator({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: b74Session,
    builder: (context, _) {
      final state = switch (b74Session.phase) {
        B74ConnectionPhase.connected => B74LinkState.connected,
        B74ConnectionPhase.offline => B74LinkState.offline,
        B74ConnectionPhase.expired => B74LinkState.expired,
        B74ConnectionPhase.unpaired => B74LinkState.unpaired,
      };
      final color = switch (state) {
        B74LinkState.connected => Colors.green,
        B74LinkState.offline => Colors.orange,
        B74LinkState.expired => Colors.red,
        B74LinkState.unpaired => Colors.grey,
      };
      final description = switch (state) {
        B74LinkState.connected => 'Beveiligd gekoppeld en bereikbaar',
        B74LinkState.offline => 'Gekoppeld, tijdelijk offline',
        B74LinkState.expired => 'Koppeling verlopen of verbroken',
        B74LinkState.unpaired => 'Niet gekoppeld',
      };
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 2, right: 4),
          child: Material(
            color: Colors.transparent,
            child: IconButton(
              tooltip: 'B74 verbinding: $description',
              icon: Icon(Icons.link, color: color),
              onPressed: () => showDialog<void>(
                context: b74NavigatorKey.currentContext ?? context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('B74 apparaatverbinding'),
                  content: Text(
                    '$description\n\nDe koppeling is maximaal 48 uur geldig zolang beide app-processen actief blijven. Na herstart opnieuw QR scannen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Sluiten'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Provides a real Overlay ancestor for the indicator's IconButton tooltip.
/// The navigator stays below the indicator, and dialogs use b74NavigatorKey.
class B74LinkOverlay extends StatefulWidget {
  const B74LinkOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<B74LinkOverlay> createState() => _B74LinkOverlayState();
}

class _B74LinkOverlayState extends State<B74LinkOverlay> {
  late final OverlayEntry _appEntry;
  late final OverlayEntry _indicatorEntry;

  @override
  void initState() {
    super.initState();
    _appEntry = OverlayEntry(builder: (context) => widget.child);
    _indicatorEntry = OverlayEntry(
      builder: (context) =>
          const Positioned(top: 0, right: 0, child: B74LinkIndicator()),
    );
  }

  @override
  void didUpdateWidget(covariant B74LinkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _appEntry.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _appEntry.dispose();
    _indicatorEntry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Overlay(initialEntries: [_appEntry, _indicatorEntry]);
}
