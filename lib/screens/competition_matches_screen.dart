import 'dart:async';

import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/competition_single_result_contract.dart';

import '../services/competition_match_catalog.dart';
import '../services/b74_doubles_session.dart';
import '../services/competition_sync_contract.dart';
import 'competition_single_screen.dart';
import 'competition_doubles_screen.dart';
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
  late Future<List<CompetitionDoublesSummary>> _doubles;
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

  void _reload() {
    final catalog = CompetitionMatchCatalog();
    _matches = catalog.load();
    _doubles = catalog.loadDoubles();
  }

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
    body: FutureBuilder<List<Object>>(
      future: Future.wait<Object>([_matches, _doubles]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Wedstrijden laden mislukt: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = snapshot.data![0] as List<CompetitionMatchSummary>;
        final doubles = snapshot.data![1] as List<CompetitionDoublesSummary>;
        if (matches.isEmpty && doubles.isEmpty) {
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
            if (doubles.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Ontvangen koppels 701',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              for (final match in doubles)
                FutureBuilder<B74DoublesSession?>(
                  key: ValueKey('doubles-result-${match.gameId}'),
                  future: B74DoublesSession.load(match.gameId),
                  builder: (context, resultSnapshot) {
                    final session = resultSnapshot.data;
                    final engine = session?.engine;
                    final winner = engine?.winner;
                    final finished = winner != null;
                    final score = engine == null
                        ? ''
                        : '${engine.legsWon[0]}–${engine.legsWon[1]}';
                    return FutureBuilder<Map<String, Object?>?>(
                      future: DbHelper.instance.competitionDoublesResult(match.gameId),
                      builder: (context, syncSnapshot) {
                        final synced = syncSnapshot.data?['status'] == 'archived';
                        final syncLabel = synced
                            ? 'Gesynchroniseerd'
                            : 'Wacht op synchronisatie';
                        return Card(
                      color: finished
                          ? Colors.green.withValues(alpha: 0.14)
                          : null,
                      child: ListTile(
                        key: ValueKey('doubles-${match.gameId}'),
                        title: Text(
                          'Koppel ${match.slot} — ${match.homeTeam} vs ${match.awayTeam}'
                          '${finished ? '  •  $score' : ''}',
                        ),
                        subtitle: Text(
                          '${match.homePlayers.join(' + ')}  vs  ${match.awayPlayers.join(' + ')}\n'
                          '701 · Best of ${match.bestOf} · Revisie ${match.revision}'
                          '${finished ? '\nGespeeld · Winnaar: ${winner == 0 ? match.homeTeam : match.awayTeam} · $syncLabel' : (match.started ? ' · Gestart' : ' · Ontvangen')}'
                          '${resultSnapshot.hasError ? '\nUitslag laden mislukt' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          finished
                              ? (synced ? Icons.cloud_done : Icons.cloud_upload_outlined)
                              : Icons.chevron_right,
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  CompetitionDoublesScreen(match: match),
                            ),
                          );
                          if (context.mounted) {
                            (context as Element).markNeedsBuild();
                          }
                        },
                      ),
                    );
                      },
                    );
                  },
                ),
            ],
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
