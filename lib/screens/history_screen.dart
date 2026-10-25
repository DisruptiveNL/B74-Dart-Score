import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/cricket_game.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../models/shanghai_game.dart';
import '../models/around_the_clock_game.dart';
import '../models/checkout_ladder_game.dart' show CheckoutLadderGame;
import '../providers/cricket_provider.dart';
import '../providers/game_provider.dart';
import '../providers/tablet_layout_provider.dart';
import '../providers/shanghai_provider.dart';
import '../providers/around_the_clock_provider.dart';
import '../providers/checkout_ladder_provider.dart';
import '../utils/game_labels.dart';
import 'cricket_history_summary_screen.dart';
import 'cricket_screen.dart';
import 'game_screen.dart';
import 'history_game_summary_screen.dart';
import 'shanghai_history_summary_screen.dart';
import 'shanghai_screen.dart';
import 'around_the_clock_history_summary_screen.dart';
import 'around_the_clock_screen.dart';
import 'checkout_ladder_history_summary_screen.dart';
import 'checkout_ladder_screen.dart';
import '../utils/layout.dart';
import '../utils/player_label.dart';
import '../widgets/ladder_icon.dart';

enum _ModeFilter { all, x01, cricket, shanghai, aroundTheClock, checkoutLadder }

/// Lists all past games across every mode, split into Open and Finished tabs
/// with per-mode filters. Supports resuming, opening details, and deleting.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<_HistoryEntry>> _future;
  late TabController _tabController;
  List<_HistoryEntry> _entries = [];
  _ModeFilter _openFilter     = _ModeFilter.all;
  _ModeFilter _finishedFilter = _ModeFilter.all;
  /// The finished game the detail pane shows. Only ever set on a tablet, where
  /// a tap opens the game beside the list instead of on top of it.
  _HistoryEntry? _selected;

  _ModeFilter get _currentFilter =>
      _tabController.index == 0 ? _openFilter : _finishedFilter;

  List<_HistoryEntry> get _visibleEntries {
    final isOpen = _tabController.index == 0;
    final tabEntries =
        _entries.where((e) => isOpen ? e.finishedAt == null : e.finishedAt != null).toList();
    final f = _currentFilter;
    if (f == _ModeFilter.all) return tabEntries;
    return tabEntries.where((e) => _matchesFilter(e, f)).toList();
  }

  /// Whether history entry [e] belongs to the selected mode filter [f].
  static bool _matchesFilter(_HistoryEntry e, _ModeFilter f) {
    switch (f) {
      case _ModeFilter.all:           return true;
      case _ModeFilter.x01:           return e.isX01;
      case _ModeFilter.cricket:       return e.isCricket;
      case _ModeFilter.shanghai:      return e.isShanghai;
      case _ModeFilter.aroundTheClock: return e.isAroundTheClock;
      case _ModeFilter.checkoutLadder: return e.isCheckoutLadder;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _reload();
  }

  /// Rebuilds when the Open/Finished tab settles so the action bar updates.
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Loads all games of every mode with their players and returns them as a
  /// single list sorted newest-first.
  Future<List<_HistoryEntry>> _load() async {
    final db      = DbHelper.instance;
    final entries = <_HistoryEntry>[];
    // Resolved once for the whole list instead of once per player per game.
    final byId    = await db.getPlayersById();
    // Same reasoning for the X01 line-ups, which live in their own table.
    final byGame  = await db.getGamePlayerIdsByGame();

    List<Player> resolve(List<int> ids) =>
        [for (final id in ids) if (byId[id] != null) byId[id]!];

    for (final g in await db.getGames()) {
      entries.add(
          _HistoryEntry.x01(g, resolve(byGame[g.id!] ?? const [])));
    }
    for (final g in await db.getCricketGames()) {
      entries.add(_HistoryEntry.cricket(g, resolve(g.playerIds)));
    }
    for (final g in await db.getShanghaiGames()) {
      entries.add(_HistoryEntry.shanghai(g, resolve(g.playerIds)));
    }
    for (final g in await db.getAroundTheClockGames()) {
      entries.add(_HistoryEntry.aroundTheClock(g, resolve(g.playerIds)));
    }
    for (final g in await db.getCheckoutLadderGames()) {
      entries.add(_HistoryEntry.checkoutLadder(g, resolve(g.playerIds)));
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  /// Reloads the history list and refreshes the UI.
  void _reload() {
    final future = _load();
    future.then((loaded) {
      if (mounted) setState(() => _entries = loaded);
    });
    setState(() { _future = future; });
  }

  /// Deletes a single game (snapshotting X01 stats first so lifetime totals are
  /// preserved) and reloads.
  Future<void> _deleteEntry(_HistoryEntry entry) async {
    final db = DbHelper.instance;
    if (entry.isCricket) {
      await db.deleteCricketGame(entry.cricketGame!.id!);
    } else if (entry.isShanghai) {
      await db.deleteShanghaiGame(entry.shanghaiGame!.id!);
    } else if (entry.isAroundTheClock) {
      await db.deleteAroundTheClockGame(entry.aroundTheClockGame!.id!);
    } else if (entry.isCheckoutLadder) {
      await db.deleteCheckoutLadderGame(entry.checkoutLadderGame!.id!);
    } else {
      await db.snapshotGameStats(entry.x01Game!.id!);
      await db.deleteGame(entry.x01Game!.id!);
    }
    _reload();
  }

  /// Confirms and deletes all currently visible entries (current tab + filter),
  /// snapshotting finished X01 stats first, then reloads.
  Future<void> _confirmDeleteVisible(BuildContext context) async {
    final toDelete = _visibleEntries;
    if (toDelete.isEmpty) return;
    final l      = context.l10n;
    final isOpen = _tabController.index == 0;
    final adj    = isOpen ? l.openAdj : l.finishedAdj;
    final mode   = _currentFilter == _ModeFilter.all
        ? ''
        : _currentFilter == _ModeFilter.x01
            ? l.gameModeX01
            : _currentFilter == _ModeFilter.cricket
                ? l.gameModeCricket
                : _currentFilter == _ModeFilter.shanghai
                    ? l.gameModeShanghai
                    : _currentFilter == _ModeFilter.aroundTheClock
                        ? l.gameModeAroundTheClock
                        : l.gameModeCheckoutLadder;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Center(
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: AlertDialog(
          title: Text(l.clearAllTitle),
          content: Text(l.deleteVisibleBody(adj, mode)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.clearAll),
            ),
          ],
        ),
        ),
      ),
    );
    if (confirmed != true) return;

    final db = DbHelper.instance;
    for (final e in toDelete) {
      // Every X01 game, finished or not: the statistics screen counts throws
      // from open games too, so skipping them here would drop those from the
      // lifetime totals. Deleting a single game does the same.
      if (e.isX01) {
        await db.snapshotGameStats(e.x01Game!.id!);
      }
    }
    for (final e in toDelete) {
      if (e.isCricket) {
        await db.deleteCricketGame(e.cricketGame!.id!);
      } else if (e.isShanghai) {
        await db.deleteShanghaiGame(e.shanghaiGame!.id!);
      } else if (e.isAroundTheClock) {
        await db.deleteAroundTheClockGame(e.aroundTheClockGame!.id!);
      } else if (e.isCheckoutLadder) {
        await db.deleteCheckoutLadderGame(e.checkoutLadderGame!.id!);
      } else {
        await db.deleteGame(e.x01Game!.id!);
      }
    }

    setState(() {
      if (isOpen) {
        _openFilter = _ModeFilter.all;
      } else {
        _finishedFilter = _ModeFilter.all;
      }
    });
    _reload();
  }

  /// Resumes an X01 game and opens its play screen, reloading on return.
  Future<void> _resumeX01(BuildContext context, _HistoryEntry entry) async {
    if (entry.players.isEmpty) return;
    final provider = context.read<GameProvider>();
    await provider.resumeGame(entry.x01Game!, entry.players);
    if (context.mounted) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GameScreen()))
          .then((_) => _reload());
    }
  }

  /// Resumes a Cricket game and opens its play screen, reloading on return.
  Future<void> _resumeCricket(BuildContext context, _HistoryEntry entry) async {
    if (entry.players.isEmpty) return;
    final provider = context.read<CricketProvider>();
    await provider.resumeGame(entry.cricketGame!, entry.players);
    if (context.mounted) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CricketScreen()))
          .then((_) => _reload());
    }
  }

  /// Resumes a Shanghai game and opens its play screen, reloading on return.
  Future<void> _resumeShanghai(BuildContext context, _HistoryEntry entry) async {
    if (entry.players.isEmpty) return;
    final provider = context.read<ShanghaiProvider>();
    await provider.resumeGame(entry.shanghaiGame!, entry.players);
    if (context.mounted) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ShanghaiScreen()))
          .then((_) => _reload());
    }
  }

  /// Resumes an Around the Clock game and opens its play screen, reloading on return.
  Future<void> _resumeAroundTheClock(
      BuildContext context, _HistoryEntry entry) async {
    if (entry.players.isEmpty) return;
    final provider = context.read<AroundTheClockProvider>();
    await provider.resumeGame(entry.aroundTheClockGame!, entry.players);
    if (context.mounted) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AroundTheClockScreen()))
          .then((_) => _reload());
    }
  }

  /// Resumes a Checkout Ladder game and opens its play screen, reloading on return.
  Future<void> _resumeCheckoutLadder(
      BuildContext context, _HistoryEntry entry) async {
    if (entry.players.isEmpty) return;
    final provider = context.read<CheckoutLadderProvider>();
    await provider.resumeGame(entry.checkoutLadderGame!, entry.players);
    if (context.mounted) {
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CheckoutLadderScreen()))
          .then((_) => _reload());
    }
  }

  /// The detail view of [e], for the route on a phone and the pane on a tablet.
  Widget _detailFor(_HistoryEntry e, {required bool embedded}) {
    if (e.isCricket) {
      return CricketHistorySummaryScreen(
          game: e.cricketGame!, players: e.players, embedded: embedded);
    }
    if (e.isShanghai) {
      return ShanghaiHistorySummaryScreen(
          game: e.shanghaiGame!, players: e.players, embedded: embedded);
    }
    if (e.isAroundTheClock) {
      return AroundTheClockHistorySummaryScreen(
          game: e.aroundTheClockGame!, players: e.players, embedded: embedded);
    }
    if (e.isCheckoutLadder) {
      return CheckoutLadderHistorySummaryScreen(
          game: e.checkoutLadderGame!, players: e.players, embedded: embedded);
    }
    return HistoryGameSummaryScreen(
        game: e.x01Game!, players: e.players, embedded: embedded);
  }

  /// Opens the detail of [e]: beside the list where there is room for it, on
  /// top of it where there is not.
  void _showSummary(BuildContext context, _HistoryEntry e) {
    if (isTabletLayout(context)) {
      setState(() => _selected = e);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _detailFor(e, embedded: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = isTabletLayout(context);
    // The divider is one setting for the whole app: wherever two panes share a
    // screen, they share the position the player dragged them to.
    final layout = tablet ? context.watch<TabletLayoutProvider>() : null;
    final landscape =
        MediaQuery.sizeOf(context).width >= MediaQuery.sizeOf(context).height;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.historyTitle),
        actions: [
          if (_visibleEntries.isNotEmpty)
            IconButton(
              // Read and hit from further away than a phone is.
              icon: Icon(Icons.delete_sweep_outlined, size: tablet ? 30 : null),
              tooltip: context.l10n.clearAll,
              onPressed: () => _confirmDeleteVisible(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // A tablet reads its tabs from further away, and there is height to
          // spare for them.
          labelStyle: tablet
              ? Theme.of(context).textTheme.titleLarge
              : null,
          unselectedLabelStyle: tablet
              ? Theme.of(context).textTheme.titleLarge
              : null,
          tabs: [
            Tab(
              height: tablet ? 56 : null,
              text: context.l10n.open,
            ),
            Tab(
              height: tablet ? 56 : null,
              text: context.l10n.finished,
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<_HistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data ?? [];
          final open     = entries.where((e) => e.finishedAt == null).toList();
          final finished = entries.where((e) => e.finishedAt != null).toList();

          final finishedList = _TabContent(
            entries: finished,
            isOpenTab: false,
            filter: _finishedFilter,
            onFilterChanged: (f) => setState(() => _finishedFilter = f),
            onDelete: _deleteEntry,
            onResume: (_) {},
            onShowSummary: (e) => _showSummary(context, e),
            selected: _selected,
          );

          // A game the list no longer holds must not stay open beside it.
          final stillThere = _selected != null &&
              finished.any((e) => identical(e, _selected));

          return TabBarView(
            controller: _tabController,
            // A tablet switches tabs from the bar above them. Left swipeable,
            // the page would take every horizontal drag on this tab, including
            // the one that moves the divider it now carries.
            physics: tablet ? const NeverScrollableScrollPhysics() : null,
            children: [
              // Only finished games have anything to show beside the list. An
              // open one is resumed, not read, so its tab keeps the whole
              // width instead of standing next to an empty half.
              _TabContent(
                entries: open,
                isOpenTab: true,
                filter: _openFilter,
                onFilterChanged: (f) => setState(() => _openFilter = f),
                onDelete: _deleteEntry,
                onResume: (e) => e.isCricket
                    ? _resumeCricket(context, e)
                    : e.isShanghai
                        ? _resumeShanghai(context, e)
                        : e.isAroundTheClock
                            ? _resumeAroundTheClock(context, e)
                            : e.isCheckoutLadder
                                ? _resumeCheckoutLadder(context, e)
                                : _resumeX01(context, e),
                onShowSummary: (_) {},
              ),
              // The pane belongs to this tab rather than to the screen. Around
              // the whole TabBarView it would appear and disappear halfway
              // through a swipe, which resizes both pages under the finger.
              if (!tablet)
                finishedList
              else
                SidePaneLayout(
                  side: InputSide.left,
                  fraction:
                      layout!.splitFraction(SplitPane.history, landscape: landscape),
                  minPaneWidth: kMinListPaneWidth,
                  onFractionChanged: (f) =>
                      layout.setSplitFraction(SplitPane.history, f,
                          landscape: landscape),
                  onFractionSettled: () {
                    layout.persistSplitFraction(SplitPane.history,
                        landscape: landscape);
                  },
                  primary: finishedList,
                  secondary: stillThere
                      ? _DetailPane(
                          entry: _selected!,
                          child: _detailFor(_selected!, embedded: true),
                        )
                      : _EmptyDetailPane(message: context.l10n.historyPickGame),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Detail pane ──────────────────────────────────────────────────────────────

/// The right hand pane of the tablet history: the title the pushed route would
/// have carried in its app bar, and the detail below it.
class _DetailPane extends StatelessWidget {
  final _HistoryEntry entry;
  final Widget child;

  const _DetailPane({required this.entry, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            DateFormat('dd.MM.yy  HH:mm').format(entry.createdAt),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// What the detail pane shows while no game is picked.
class _EmptyDetailPane extends StatelessWidget {
  final String message;

  const _EmptyDetailPane({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 40, color: cs.outline),
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

// ── Tab content with chip filter ─────────────────────────────────────────────

/// One history tab (Open or Finished): a per-mode chip filter over a scrollable
/// list of game tiles. Kept alive so its scroll position survives tab switches.
class _TabContent extends StatefulWidget {
  final List<_HistoryEntry> entries;
  final bool isOpenTab;
  final _ModeFilter filter;
  final void Function(_ModeFilter) onFilterChanged;
  final void Function(_HistoryEntry) onDelete;
  final void Function(_HistoryEntry) onResume;
  final void Function(_HistoryEntry) onShowSummary;
  /// The entry whose detail is open beside the list, if any.
  final _HistoryEntry? selected;

  const _TabContent({
    required this.entries,
    required this.isOpenTab,
    required this.filter,
    required this.onFilterChanged,
    required this.onDelete,
    required this.onResume,
    required this.onShowSummary,
    this.selected,
  });

  @override
  State<_TabContent> createState() => _TabContentState();
}

class _TabContentState extends State<_TabContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// The entries matching the active mode filter.
  List<_HistoryEntry> get _filtered {
    if (widget.filter == _ModeFilter.all) return widget.entries;
    return widget.entries
        .where((e) => _HistoryScreenState._matchesFilter(e, widget.filter))
        .toList();
  }

  /// The set of game modes actually present in this tab's entries (used to hide
  /// chips for modes with no games).
  Set<_ModeFilter> get _presentModes {
    final modes = <_ModeFilter>{};
    for (final e in widget.entries) {
      if (e.isCricket) {
        modes.add(_ModeFilter.cricket);
      } else if (e.isShanghai) {
        modes.add(_ModeFilter.shanghai);
      } else if (e.isAroundTheClock) {
        modes.add(_ModeFilter.aroundTheClock);
      } else if (e.isCheckoutLadder) {
        modes.add(_ModeFilter.checkoutLadder);
      } else {
        modes.add(_ModeFilter.x01);
      }
    }
    return modes;
  }

  /// Localized label for a mode-filter chip.
  String _chipLabel(_ModeFilter f, AppLocalizations l) {
    switch (f) {
      case _ModeFilter.all:            return l.filterAll;
      case _ModeFilter.x01:            return l.gameModeX01;
      case _ModeFilter.cricket:        return l.gameModeCricket;
      case _ModeFilter.shanghai:       return l.gameModeShanghai;
      case _ModeFilter.aroundTheClock: return l.gameModeAroundTheClock;
      case _ModeFilter.checkoutLadder: return l.gameModeCheckoutLadder;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l        = context.l10n;
    final cs       = Theme.of(context).colorScheme;
    final present  = _presentModes;
    final filtered = _filtered;

    if (widget.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(l.noHistory),
          ],
        ),
      );
    }

    final chips = [
      _ModeFilter.all, _ModeFilter.x01, _ModeFilter.cricket,
      _ModeFilter.shanghai, _ModeFilter.aroundTheClock,
      _ModeFilter.checkoutLadder,
    ].where((f) => f == _ModeFilter.all || present.contains(f)).toList();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: Column(
          children: [
            if (chips.length > 1)
              _ChipBar(
                filters: chips,
                selected: widget.filter,
                labelOf: (f) => _chipLabel(f, l),
                onSelected: widget.onFilterChanged,
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(l.noHistory))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return _GameTile(
                          entry: e,
                          isSelected: identical(e, widget.selected),
                          onDelete: () => widget.onDelete(e),
                          onResume: widget.isOpenTab
                              ? () => widget.onResume(e)
                              : null,
                          onShowSummary: widget.isOpenTab
                              ? null
                              : () => widget.onShowSummary(e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chip filter bar ───────────────────────────────────────────────────────────

/// A horizontal row of single-select mode filter chips.
class _ChipBar extends StatelessWidget {
  final List<_ModeFilter> filters;
  final _ModeFilter selected;
  final String Function(_ModeFilter) labelOf;
  final void Function(_ModeFilter) onSelected;

  const _ChipBar({
    required this.filters,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            FilterChip(
              label: Text(labelOf(filters[i])),
              selected: filters[i] == selected,
              onSelected: (_) => onSelected(filters[i]),
              showCheckmark: false,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

/// A single history list item wrapping a game of any mode (exactly one of the
/// game fields is non-null) together with its players.
class _HistoryEntry {
  final Game?                x01Game;
  final CricketGame?         cricketGame;
  final ShanghaiGame?        shanghaiGame;
  final AroundTheClockGame?  aroundTheClockGame;
  final CheckoutLadderGame?  checkoutLadderGame;
  final List<Player>         players;

  const _HistoryEntry._({
    this.x01Game,
    this.cricketGame,
    this.shanghaiGame,
    this.aroundTheClockGame,
    this.checkoutLadderGame,
    required this.players,
  });

  factory _HistoryEntry.x01(Game g, List<Player> players) =>
      _HistoryEntry._(x01Game: g, players: players);

  factory _HistoryEntry.cricket(CricketGame g, List<Player> players) =>
      _HistoryEntry._(cricketGame: g, players: players);

  factory _HistoryEntry.shanghai(ShanghaiGame g, List<Player> players) =>
      _HistoryEntry._(shanghaiGame: g, players: players);

  factory _HistoryEntry.aroundTheClock(AroundTheClockGame g, List<Player> players) =>
      _HistoryEntry._(aroundTheClockGame: g, players: players);

  factory _HistoryEntry.checkoutLadder(CheckoutLadderGame g, List<Player> players) =>
      _HistoryEntry._(checkoutLadderGame: g, players: players);

  bool get isCricket        => cricketGame != null;
  bool get isShanghai       => shanghaiGame != null;
  bool get isAroundTheClock => aroundTheClockGame != null;
  bool get isCheckoutLadder => checkoutLadderGame != null;
  bool get isX01            => x01Game != null;

  /// The wrapped game's creation time, regardless of mode.
  DateTime get createdAt {
    if (isCricket) return cricketGame!.createdAt;
    if (isShanghai) return shanghaiGame!.createdAt;
    if (isAroundTheClock) return aroundTheClockGame!.createdAt;
    if (isCheckoutLadder) return checkoutLadderGame!.createdAt;
    return x01Game!.createdAt;
  }

  /// The wrapped game's finish time (null if still open), regardless of mode.
  DateTime? get finishedAt {
    if (isCricket) return cricketGame!.finishedAt;
    if (isShanghai) return shanghaiGame!.finishedAt;
    if (isAroundTheClock) return aroundTheClockGame!.finishedAt;
    if (isCheckoutLadder) return checkoutLadderGame!.finishedAt;
    return x01Game!.finishedAt;
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

/// A list tile for one history entry, showing mode, date, players, and result,
/// with resume (open games) or details (finished games) and delete actions.
class _GameTile extends StatelessWidget {
  final _HistoryEntry entry;
  final VoidCallback onDelete;
  final VoidCallback? onResume;
  final VoidCallback? onShowSummary;
  /// Whether this entry is the one open in the detail pane beside the list.
  final bool isSelected;

  const _GameTile({
    required this.entry,
    required this.onDelete,
    this.onResume,
    this.onShowSummary,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final l           = context.l10n;
    final fmt         = DateFormat('dd.MM.yy  HH:mm');
    final finished    = entry.finishedAt != null;
    final cs          = Theme.of(context).colorScheme;
    final playerNames = entry.players.map((p) => p.label(l)).join(' vs ');

    final subtitle = entry.isCricket
        ? l.cricketGameInfo(
            entry.cricketGame!.variant == CricketVariant.cutThroat
                ? l.cricketVariantCutThroat
                : l.cricketVariantNormal,
          )
        : entry.isShanghai
            ? l.shanghaiGameInfo(shanghaiVariantLabel(l, entry.shanghaiGame!.variant))
            : entry.isAroundTheClock
                ? l.aroundClockGameInfo(
                    aroundTheClockVariantLabel(l, entry.aroundTheClockGame!.variant))
                : entry.isCheckoutLadder
                    ? (entry.checkoutLadderGame!.isRace
                        ? l.checkoutLadderRaceInfo(
                            entry.checkoutLadderGame!.startNumber,
                            entry.checkoutLadderGame!.targetNumber!)
                        : l.checkoutLadderTrainingInfo(
                            entry.checkoutLadderGame!.startNumber))
                    : l.gameSummaryInfo(
                    entry.x01Game!.startScore,
                    entry.x01Game!.legs,
                    entry.x01Game!.sets,
                    placementMode: entry.x01Game!.placementMode,
                  );

    final entryId = entry.x01Game?.id ??
        entry.cricketGame?.id ??
        entry.shanghaiGame?.id ??
        entry.aroundTheClockGame?.id ??
        entry.checkoutLadderGame?.id;
    final entryPrefix = entry.isCricket
        ? 'c'
        : entry.isShanghai
            ? 's'
            : entry.isAroundTheClock
                ? 'a'
                : entry.isCheckoutLadder
                    ? 'l'
                    : 'x';

    return Dismissible(
      key: ValueKey('$entryPrefix$entryId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        // Marked rather than merely highlighted: on a tablet this tile and the
        // pane beside it are the same thing, and nothing else says which.
        color: isSelected ? cs.secondaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onResume ?? onShowSummary,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: finished ? cs.primaryContainer : cs.tertiaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: entry.isCheckoutLadder
                      ? Center(
                          child: LadderIcon(
                            size: 18,
                            color: finished
                                ? cs.onPrimaryContainer
                                : cs.onTertiaryContainer,
                          ),
                        )
                      : Icon(
                        entry.isCricket
                            ? Icons.sports_cricket_rounded
                            : entry.isShanghai
                                ? Icons.layers_rounded
                                : entry.isAroundTheClock
                                    ? Icons.watch_later_outlined
                                    : (finished
                                        ? Icons.check
                                        : Icons.play_arrow_rounded),
                        size: 18,
                        color: finished
                            ? cs.onPrimaryContainer
                            : cs.onTertiaryContainer,
                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playerNames,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              )),
                      Text(
                        fmt.format(entry.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!finished)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.tertiary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l.resume,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onTertiary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
