import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/layout.dart';
import '../utils/visit_darts.dart';
import '../widgets/stat_row.dart';
import '../widgets/visit_darts_row.dart';

/// One visit as the live info lists it: its darts and what they brought in,
/// marks, points or hits depending on the mode.
typedef VisitSummary = ({List<VisitDart> darts, String yield});

/// What the live info of a slot shows: the name, the last visits and the
/// statistics the mode cares about.
typedef ModeLiveInfo = ({
  String title,
  String? subtitle,
  List<VisitSummary> recentVisits,
  List<(String label, String value)> stats,
  int visitSlots,
});

/// Live info for one slot of Cricket, Shanghai, Around the Clock or the
/// Checkout Ladder: the last three visits as dart chips, then the handful of
/// numbers that describe the slot in that mode. The X01 screen has its own,
/// richer page; this one is shared by the other modes, which differ only in
/// what [data] puts on it.
///
/// Rebuilds from [listenable], the mode's provider, so a bot's visit or the
/// turn moving on shows while the page is open.
class ModeLiveInfoScreen extends StatelessWidget {
  final Listenable listenable;
  final ModeLiveInfo Function(BuildContext context) data;

  const ModeLiveInfoScreen({
    super.key,
    required this.listenable,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final info  = data(context);
        final theme = Theme.of(context);
        final l     = context.l10n;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(info.title),
                if (info.subtitle != null)
                  Text(info.subtitle!,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: contentPadding(context, top: 12, bottom: 24, innerH: 16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.lastVisits,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      if (info.recentVisits.isEmpty)
                        Text(l.noVisitsYet,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant))
                      else
                        for (final v in info.recentVisits)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: VisitDartsRow(
                                        darts: v.darts, slots: info.visitSlots),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(v.yield,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.statistics,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      for (final (label, value) in info.stats)
                        StatRow(label: label, value: value),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
