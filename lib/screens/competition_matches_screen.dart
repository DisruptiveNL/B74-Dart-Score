import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _reload();
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
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text('Single ${single.slot}'),
                subtitle: Text(
                  '${match.home}: ${single.homePlayer}${_bond(single.homeBond)}\n'
                  'VS\n${match.away}: ${single.awayPlayer}${_bond(single.awayBond)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CompetitionSingleScreen(match: match, single: single),
                  ),
                ),
              ),
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
