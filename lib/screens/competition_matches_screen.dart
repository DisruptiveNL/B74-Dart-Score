import 'dart:async';

import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/competition_single_result_contract.dart';

import '../services/competition_match_catalog.dart';
import '../services/competition_sync_contract.dart';
import 'competition_single_screen.dart';
import 'competition_receive_screen.dart';

/// Imported competition matches. Scoring integration follows in Patch 02E.
class CompetitionMatchesScreen extends StatefulWidget {
  const CompetitionMatchesScreen({super.key});

  @override
  State<CompetitionMatchesScreen> createState() =>
      _CompetitionMatchesScreenState();
}

class _CompetitionMatchesScreenState extends State<CompetitionMatchesScreen> {
  late Future<List<CompetitionMatchSummary>> _matches;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _reload();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(_reload);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reload() => _matches = CompetitionMatchCatalog().load();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Competities & Toernooien'),
      actions: [
        IconButton(
          tooltip: 'Wedstrijden ontvangen',
          icon: const Icon(Icons.wifi_tethering),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CompetitionReceiveScreen(),
              ),
            );
            if (mounted) setState(_reload);
          },
        ),
        IconButton(
          tooltip: 'Vernieuwen',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(_reload),
        ),
        // Reserveer de rechterbovenhoek voor de permanente B74-indicator.
        // Deze staat in de Navigator-overlay (Patch D).
        const SizedBox(width: 56),
      ],
    ),
    body: FutureBuilder<List<CompetitionMatchSummary>>(
      future: _matches,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Wedstrijden laden mislukt: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = snapshot.data!;
        if (matches.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nog geen competitiewedstrijden ontvangen.\n'
                'Synchroniseer eerst vanuit Competition Dashboard.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'DOGD',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            for (final match in matches) _MatchCard(match: match),
          ],
        );
      },
    ),
  );
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});
  final CompetitionMatchSummary match;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${match.home}  –  ${match.away}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '501 / Best of ${match.rules['bestOf']}  •  '
            '${_startLabel(match.rules['startPolicy'] as String)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final single in match.singles)
            FutureBuilder<Map<String, Object?>?>(
              future: DbHelper.instance.competitionSingleResult(
                match.id,
                single.slot,
              ),
              builder: (context, snapshot) {
                final row = snapshot.data;
                Map<String, dynamic>? result;
                if (row?['payload'] is String) {
                  try {
                    result = CompetitionSingleResultContract.decode(
                      row!['payload'] as String,
                    );
                  } catch (_) {
                    /* Keep the list usable if a row is malformed. */
                  }
                }
                final finished = result != null;
                final archived = row?['status'] == 'archived';
                final winner = result?['winnerPlayerId'] == single.homeId
                    ? single.homePlayer
                    : single.awayPlayer;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  color: finished ? Colors.green.withValues(alpha: 0.14) : null,
                  child: ListTile(
                    title: Text(
                      'Single ${single.slot}${finished ? '  •  ${result['homeLegs']}–${result['awayLegs']}' : ''}',
                    ),
                    subtitle: Text(
                      '${match.home}: ${single.homePlayer}${_bond(single.homeBond)}\n'
                      'VS\n${match.away}: ${single.awayPlayer}${_bond(single.awayBond)}'
                      '${finished ? '\nWinnaar: $winner  •  ${archived ? 'Gesynchroniseerd' : 'Wacht op synchronisatie'}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      finished
                          ? (archived
                                ? Icons.cloud_done
                                : Icons.cloud_upload_outlined)
                          : Icons.chevron_right,
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CompetitionSingleScreen(
                            match: match,
                            single: single,
                          ),
                        ),
                      );
                      if (context.mounted) {
                        (context as Element).markNeedsBuild();
                      }
                    },
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );

  static String _bond(String? bond) =>
      bond == null || bond.trim().isEmpty ? '' : ' ($bond)';

  static String _startLabel(String policy) => switch (policy) {
    CompetitionX01Rules.bull => 'Bullstart',
    CompetitionX01Rules.fixedHome => 'Thuis begint',
    _ => 'Uit begint',
  };
}
