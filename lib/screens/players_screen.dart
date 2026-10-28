import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/players_provider.dart';
import '../providers/tablet_layout_provider.dart';
import '../models/player.dart';
import '../widgets/player_dialog.dart';
import 'player_stats_screen.dart';
import 'sync_screen.dart';
import '../utils/layout.dart';

/// Player management screen: the primary profile plus all other players, with
/// add, edit, delete, stats, and sync actions.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

/// What the pane beside the player list is showing about the player in it.
enum _PaneView { stats, sync }

class _PlayersScreenState extends State<PlayersScreen> {
  /// The player the pane beside the list belongs to. Only ever set on a tablet,
  /// where a player opens next to the list instead of over it.
  Player? _selected;

  /// Which of the two things the pane shows about them. One at a time: both
  /// are a screen's worth on their own.
  _PaneView _view = _PaneView.stats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final syncFab = FloatingActionButton.extended(
      heroTag: 'sync',
      onPressed: () => _openSync(context, null),
      backgroundColor: cs.secondary,
      foregroundColor: cs.onSecondary,
      icon: const Icon(Icons.sync_rounded),
      label: Text(l.syncProfile),
    );
    final addFab = FloatingActionButton.extended(
      heroTag: 'addPlayer',
      onPressed: () => _addPlayer(context),
      icon: const Icon(Icons.person_add),
      label: Text(l.addPlayer),
    );

    // Reserve enough bottom space so the floating action button(s) never
    // overlap the last list items: button height + spacing between stacked
    // buttons + the FAB's own bottom margin + the device's safe area inset.
    const fabHeight = 48.0;
    // Matches _OtherPlayerTile's Card bottom margin, so the gap between the
    // FABs and between the last player card and the FABs is consistent with
    // the gap between player cards.
    const fabSpacing = 6.0;
    const fabMargin = 16.0;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final fabReservedHeight =
        (fabHeight * 2) + fabSpacing + fabMargin + bottomInset;

    final listContent = Consumer<PlayersProvider>(
      builder: (context, provider, _) {
        if (provider.players.isEmpty) {
          return Center(child: Text(l.noPlayers));
        }

        final primary = provider.primaryPlayer;
        final others = provider.players.where((p) => !p.isPrimary).toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            // The last card's own bottom margin (_OtherPlayerTile's Card) is
            // consumed by the FAB's reserved height, so add it back once
            // more to leave the same gap above the FAB as between cards.
            fabReservedHeight + (fabSpacing * 2) + 4,
          ),
          children: [
            // ── Primary user card ──────────────────────────────────────
            if (primary != null) ...[
              _PrimaryPlayerCard(
                player: primary,
                onEdit: () => _editPlayer(context, primary),
                onStats: () => _openStats(context, primary),
                onShare: () => _openSync(context, primary),
              ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    l.players,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ],

            // ── Other players ──────────────────────────────────────────
            ...others.map(
              (p) => _OtherPlayerTile(
                player: p,
                onEdit: () => _editPlayer(context, p),
                onStats: () => _openStats(context, p),
                onShare: () => _openSync(context, p),
              ),
            ),
          ],
        );
      },
    );

    final tablet = isTabletLayout(context);

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        addFab,
        const SizedBox(height: fabSpacing),
        syncFab,
      ],
    );

    Widget list = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: listContent,
      ),
    );

    // Both buttons act on the list, so on a tablet they belong over the list
    // and not over the statistics in the pane beside it, which is where the
    // scaffold would float them.
    if (tablet) {
      list = Stack(
        children: [
          Positioned.fill(child: list),
          Positioned(
            right: fabMargin,
            bottom: fabMargin + bottomInset,
            child: buttons,
          ),
        ],
      );
    }

    final layout = tablet ? context.watch<TabletLayoutProvider>() : null;
    final landscape =
        MediaQuery.sizeOf(context).width >= MediaQuery.sizeOf(context).height;
    // A player who was deleted while their stats were open must not stay in
    // the pane beside a list that no longer holds them.
    final selected = context
        .watch<PlayersProvider>()
        .players
        .where((p) => p.id == _selected?.id)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l.playersTitle)),
      body: !tablet
          ? list
          : SidePaneLayout(
              side: InputSide.left,
              fraction: layout!.splitFraction(
                SplitPane.players,
                landscape: landscape,
              ),
              minPaneWidth: kMinListPaneWidth,
              onFractionChanged: (f) => layout.setSplitFraction(
                SplitPane.players,
                f,
                landscape: landscape,
              ),
              onFractionSettled: () {
                layout.persistSplitFraction(
                  SplitPane.players,
                  landscape: landscape,
                );
              },
              primary: list,
              secondary: _view == _PaneView.sync
                  ? _StatsPane(
                      // Keyed by player, so switching to another one starts
                      // their transfer over instead of handing the new name to
                      // a code that is already running.
                      key: ValueKey('sync-${selected?.id}'),
                      title: selected == null
                          ? l.syncTitle
                          : l.syncOf(selected.name),
                      child: SyncScreen(
                        initialPlayer: selected,
                        embedded: true,
                      ),
                    )
                  : selected == null
                  ? _EmptyStatsPane(message: l.playersPickOne)
                  : _StatsPane(
                      title: l.statisticsOf(selected.name),
                      child: PlayerStatsScreen(
                        player: selected,
                        embedded: true,
                      ),
                    ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: tablet ? null : buttons,
    );
  }

  /// Opens the lifetime stats of [player]: beside the list where there is room
  /// for it, on top of it where there is not.
  void _openStats(BuildContext context, Player player) {
    if (isTabletLayout(context)) {
      setState(() {
        _selected = player;
        _view = _PaneView.stats;
      });
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlayerStatsScreen(player: player)),
    );
  }

  /// Opens the device-to-device sync in the pane beside the list where there is
  /// room for it, and on top of it where there is not.
  ///
  /// [player] is whose profile to send, or null for the button over the list,
  /// which is the way in for a device that is about to receive one and has
  /// nobody picked. The pane shows one thing at a time, so this replaces the
  /// statistics rather than standing beside them.
  void _openSync(BuildContext context, Player? player) {
    if (isTabletLayout(context)) {
      setState(() {
        _selected = player;
        _view = _PaneView.sync;
      });
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SyncScreen(initialPlayer: player)),
    );
  }

  /// Opens the create-player dialog, rejecting names that already exist.
  void _addPlayer(BuildContext context) {
    final existing = context
        .read<PlayersProvider>()
        .players
        .map((p) => p.name.toLowerCase())
        .toList();
    showDialog(
      context: context,
      builder: (_) => PlayerDialog(
        existingNames: existing,
        onSave: (name, doubles) {
          final provider = context.read<PlayersProvider>();
          provider
              .addPlayer(name)
              .then(
                (player) => provider.updatePlayer(
                  player.copyWith(favoriteDoubles: doubles),
                ),
              );
        },
      ),
    );
  }

  /// Opens the edit dialog for [player] with options to rename, set the favorite
  /// double, make primary, or delete.
  void _editPlayer(BuildContext context, Player player) {
    final existing = context
        .read<PlayersProvider>()
        .players
        .where((p) => p.id != player.id)
        .map((p) => p.name.toLowerCase())
        .toList();
    showDialog(
      context: context,
      builder: (_) => PlayerDialog(
        initialName: player.name,
        initialDouble: player.favoriteDouble,
        isPrimary: player.isPrimary,
        existingNames: existing,
        onSave: (name, doubles) async {
          await context.read<PlayersProvider>().updatePlayer(
            player.copyWith(name: name, favoriteDoubles: doubles),
          );
        },
        onDelete: () =>
            _confirmDelete(context, context.read<PlayersProvider>(), player),
        onSetPrimary: player.isPrimary
            ? null
            : () => context.read<PlayersProvider>().setPrimary(player),
      ),
    );
  }

  /// Confirms and deletes [player].
  void _confirmDelete(
    BuildContext context,
    PlayersProvider provider,
    Player player,
  ) {
    showDialog(
      context: context,
      builder: (_) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
          child: AlertDialog(
            title: Text(context.l10n.deletePlayerTitle),
            content: Text(context.l10n.deletePlayerConfirm(player.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  provider.deletePlayer(player.id!);
                  Navigator.pop(context);
                },
                child: Text(context.l10n.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Primary player card ───────────────────────────────────────────────────────

// ── Detail pane ──────────────────────────────────────────────────────────────

/// The right hand pane of the tablet player list: the name the pushed route
/// would have carried in its app bar, and the statistics below it.
class _StatsPane extends StatelessWidget {
  final String title;
  final Widget child;

  const _StatsPane({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// What the statistics pane shows while no player is picked.
class _EmptyStatsPane extends StatelessWidget {
  final String message;

  const _EmptyStatsPane({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Highlighted card for the primary player with edit, stats, and sync actions.
class _PrimaryPlayerCard extends StatelessWidget {
  final Player player;
  final VoidCallback onEdit;
  final VoidCallback onStats;
  final VoidCallback onShare;

  const _PrimaryPlayerCard({
    required this.player,
    required this.onEdit,
    required this.onStats,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    return Card(
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
        child: Row(
          children: [
            // Avatar with star badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primary,
                  child: Text(
                    player.name.isNotEmpty ? player.name[0].toUpperCase() : "?",
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primaryContainer, width: 2),
                    ),
                    child: Icon(
                      Icons.star_rounded,
                      size: 11,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Name + label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.myProfile,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    player.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  if (player.favoriteDouble != null)
                    Text(
                      '${l.favDoublesPrefix}${player.favoriteDouble}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            ),
            // Action buttons in a row
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.bar_chart_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                  tooltip: context.l10n.statsTooltip,
                  onPressed: onStats,
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: cs.onPrimaryContainer),
                  tooltip: context.l10n.edit,
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: Icon(Icons.share_rounded, color: cs.onPrimaryContainer),
                  tooltip: context.l10n.sharePlayerTooltip,
                  onPressed: onShare,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Other player tile ─────────────────────────────────────────────────────────

/// List tile for a non-primary player with edit, stats, and sync actions.
class _OtherPlayerTile extends StatelessWidget {
  final Player player;
  final VoidCallback onEdit;
  final VoidCallback onStats;
  final VoidCallback onShare;

  const _OtherPlayerTile({
    required this.player,
    required this.onEdit,
    required this.onStats,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: cs.surfaceContainerHighest,
          child: Text(
            player.name.isNotEmpty ? player.name[0].toUpperCase() : "?",
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          player.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: player.favoriteDouble == null
            ? Text(l.noFavDoubles)
            : Text('${l.favDoublesPrefix}${player.favoriteDouble}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded),
              tooltip: context.l10n.statsTooltip,
              onPressed: onStats,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l.edit,
              onPressed: onEdit,
            ),
            IconButton(
              icon: Icon(Icons.share_rounded, color: cs.primary),
              tooltip: l.sharePlayerTooltip,
              onPressed: onShare,
            ),
          ],
        ),
      ),
    );
  }
}
