import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/player.dart';

/// How many players the list shows before it has to be expanded.
///
/// Six covers the players most rounds are picked from while leaving the rest of
/// the setup screen reachable without scrolling past a roster. Everyone beyond
/// it is one tap away, not gone.
const int kCollapsedPlayerCount = 6;

/// The block every setup screen uses to pick who is playing: the roster with a
/// checkbox each, the button that adds one, and the star that marks the main
/// profile.
///
/// Shared by all four modes rather than copied into each, so that the order,
/// the star and the collapsing stay one behaviour. [allPlayers] arrives in the
/// order `PlayersProvider` keeps: the main profile first, everyone else
/// alphabetically.
class PlayerSelectSection extends StatefulWidget {
  final List<Player> allPlayers;
  final List<Player> selectedPlayers;
  final void Function(Player player, bool selected) onToggle;
  final VoidCallback onAddPlayer;

  const PlayerSelectSection({
    super.key,
    required this.allPlayers,
    required this.selectedPlayers,
    required this.onToggle,
    required this.onAddPlayer,
  });

  @override
  State<PlayerSelectSection> createState() => _PlayerSelectSectionState();
}

class _PlayerSelectSectionState extends State<PlayerSelectSection> {
  /// Whether the roster is showing in full.
  ///
  /// View state, not app state: it says nothing about the game being set up and
  /// is meant to be forgotten when the screen goes away, so it stays here
  /// rather than in a provider.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    final total = widget.allPlayers.length;
    final hidden = total - kCollapsedPlayerCount;
    final shown = _expanded || hidden <= 0
        ? widget.allPlayers
        : widget.allPlayers.take(kCollapsedPlayerCount).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.players,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onAddPlayer,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: Text(l.addPlayer),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.allPlayers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.noPlayersAvail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              ...shown.map((p) {
                final idx = widget.selectedPlayers.indexWhere(
                  (s) => s.id == p.id,
                );
                final selected = idx >= 0;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                      if (p.isPrimary) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: l.alreadyMainProfile,
                          child: Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: selected ? Text(l.playerN(idx + 1)) : null,
                  value: selected,
                  onChanged: (v) => widget.onToggle(p, v == true),
                );
              }),
              if (hidden > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: Text(
                      _expanded ? l.fewerPlayers : l.morePlayers(hidden),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
