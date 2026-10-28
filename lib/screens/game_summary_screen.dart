import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../providers/game_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/game_labels.dart';
import '../utils/throw_stats.dart';
import '../widgets/final_ranking_card.dart';
import '../widgets/game_info_card.dart';
import '../widgets/rematch_button.dart';
import '../widgets/summary_body.dart';
import '../widgets/summary_player_card.dart';
import '../widgets/throw_log_card.dart';
import '../utils/player_label.dart';
import 'game_screen.dart';

/// Width the exported result card is laid out at, whatever the screen showing
/// it happens to be. A phone's worth of column, so the image reads the same
/// wherever it was made.
const double kExportCardWidth = 500;

/// Identifies the card the image is taken of, for tests that check what ends up
/// in it. It is in the tree only while an image is being made.
const Key kExportCardKey = Key('summary-export-card');

/// Post-game summary for X01: winner, per-player/team stats and throw history,
/// with options to save or share the result card as an image.
class GameSummaryScreen extends StatefulWidget {
  const GameSummaryScreen({super.key});

  @override
  State<GameSummaryScreen> createState() => _GameSummaryScreenState();
}

class _GameSummaryScreenState extends State<GameSummaryScreen> {
  final _cardKey = GlobalKey();

  /// The share button itself, because iPadOS anchors the share sheet to a
  /// rectangle on screen and refuses the call without one.
  final _shareKey = GlobalKey();

  bool _saving = false;

  /// Rasterizes the result card widget to a high-resolution image.
  ///
  /// Waits for the pending frame first: setting [_saving] swaps the export
  /// actions for a spinner, and that frame must be laid out and painted before
  /// the boundary is grabbed.
  Future<ui.Image> _renderCard() async {
    await WidgetsBinding.instance.endOfFrame;
    final ctx = _cardKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      throw StateError('Card widget is not mounted');
    }
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: 3.0);
  }

  /// Renders the result card and saves it to the device photo gallery.
  Future<void> _saveToPhotos() async {
    setState(() => _saving = true);
    try {
      final img = await _renderCard();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Gal.putImageBytes(bytes!.buffer.asUint8List());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.savedToPhotos)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.l10n.error}: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Where the share sheet should point on a tablet.
  ///
  /// On an iPad the sheet is a popover that has to be anchored to something,
  /// and share_plus reports an error rather than opening without an anchor,
  /// which is why sharing did nothing there. Read before the spinner replaces
  /// the button, or there is nothing left to measure.
  Rect? _shareOrigin() {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Renders the result card to a temporary PNG and opens the share sheet.
  Future<void> _shareCard() async {
    final origin = _shareOrigin();
    setState(() => _saving = true);
    final shareSubject = context.l10n.shareSubject;
    try {
      final img = await _renderCard();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final tmp = await getTemporaryDirectory();
      final file = File('${tmp.path}/dartscore_ergebnis.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: shareSubject,
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${context.l10n.error}: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<GameProvider>();
    final states = provider.playerStates;
    final winner = states.firstWhere(
      (s) => s.players.any((p) => p.id == provider.winnerId),
      orElse: () => states.first,
    );
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    // What a leg checked out in the fewest darts the start score allows is
    // called, for the card of whoever managed one.
    final minDarts = minimumDartsForScore[provider.game!.startScore];
    final perfectLabel = minDarts == 9
        ? l.nineDarter
        : l.perfectGameLabel(minDarts ?? 0);

    // Name of every player in the game, keyed by id, for the throw log.
    final throwerNames = {
      for (final s in states)
        for (final p in s.players) p.id: p.label(l),
    };

    // ── The parts, built once and placed twice ───────────────────────────────
    // The screen arranges them for the device it is on; the exported image puts
    // the same parts in one column of its own, so moving something on screen
    // cannot quietly take it out of the picture somebody shares.

    final winnerBanner = Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              size: 52,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.wins(winner.label(l)),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    final infoCard = GameInfoCard(
      rows: [
        (l.gameLabel, l.modeX01Name),
        (
          l.matchFormat,
          provider.game!.placementMode ? l.placementMode : l.standardMode,
        ),
        (
          l.gameMode_,
          l.gameSummaryInfo(
            provider.game!.startScore,
            provider.game!.legs,
            provider.game!.sets,
            placementMode: provider.game!.placementMode,
          ),
        ),
        // A solo game has nobody to be ordered against.
        if (states.length > 1)
          (
            l.startingOrder,
            startingOrderLabel(l, provider.game!.startingOrder),
          ),
      ],
    );

    final rankingCard = provider.game!.placementMode
        ? FinalRankingCard(
            throwsById: {
              for (var i = 0; i < states.length; i++) i: states[i].throws,
            },
            namesById: {
              for (var i = 0; i < states.length; i++) i: states[i].label(l),
            },
            legsWon: {
              for (var i = 0; i < states.length; i++) i: states[i].legsWon,
            },
            placementSum: {
              for (var i = 0; i < states.length; i++) i: states[i].placementSum,
            },
            points: {
              for (var i = 0; i < states.length; i++)
                i: states[i].placementPoints,
            },
          )
        : null;

    final playerCards = [
      for (final s in states)
        SummaryPlayerCard(
          name: s.label(l),
          throws: s.throws,
          // In placement mode every slot checks out every leg, so legs won come
          // from the provider's tally instead of counting checkout visits.
          legsWon: provider.game!.placementMode
              ? s.legsWon
              : legsWonFromThrows(s.throws),
          // A single-set match has no set tally worth showing.
          setsWon: provider.game!.sets > 1 ? s.setsWon : null,
          members: s.isTeam
              ? [
                  for (final p in s.players)
                    (p.label(l), throwsOfPlayer(s.throws, p.id ?? -1)),
                ]
              : const [],
          badge: s.perfectLegs > 0 ? perfectLabel : null,
        ),
    ];

    // Beside the numbers where there are two columns, right under the winner
    // where there is one: it describes the game, not the players, and in a
    // single column it reads as part of the result rather than of the log.
    final twoColumns = SummaryBody.twoColumnsOn(context);

    final summary = SummaryBody(
      header: winnerBanner,
      result: [if (!twoColumns) infoCard, ...playerCards],
      details: [
        if (twoColumns) infoCard,
        ?rankingCard,
        ThrowLogCard(
          throws: provider.allThrows(),
          // Look the thrower up across every slot member: a team slot's
          // `player` is only whoever throws next, so matching on that alone
          // misses the team's other members.
          playerName: (id) => throwerNames[id] ?? '',
          showSet: provider.game!.sets > 1,
        ),
      ],
      actions: [
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(Icons.home_rounded),
          label: Text(l.backToHome),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        RematchButton(
          modeName: l.modeX01Name,
          details: [
            (
              l.matchFormat,
              provider.game!.placementMode ? l.placementMode : l.standardMode,
            ),
            (
              l.gameMode_,
              l.gameSummaryInfo(
                provider.game!.startScore,
                provider.game!.legs,
                provider.game!.sets,
                placementMode: provider.game!.placementMode,
              ),
            ),
            // With handicaps the game defaults say little, so the per-player
            // rows of the summary carry the rules instead.
            if (!provider.game!.hasHandicaps) ...[
              (l.checkIn, checkInLabel(l, provider.game!.gameMode)),
              (l.checkOut, checkOutLabel(l, provider.game!.checkoutMode)),
            ],
          ],
          slots: states
              .map(
                (s) => s.isTeamSlot
                    ? RematchSlot.team(
                        s.label(l),
                        s.players
                            .map(
                              (p) => RematchSlot.player(
                                p.label(l),
                                rules: handicapRulesLabel(
                                  l,
                                  provider.game!,
                                  p.id,
                                ),
                              ),
                            )
                            .toList(),
                      )
                    : RematchSlot.player(
                        s.label(l),
                        rules: handicapRulesLabel(
                          l,
                          provider.game!,
                          s.player.id,
                        ),
                      ),
              )
              .toList(),
          onRematch: () => provider.startRematch(
            provider.game!,
            provider.playerStates.expand((s) => s.players).toList(),
          ),
          destination: (_) => const GameScreen(),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.gameOverview),
        automaticallyImplyLeading: false,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: l.saveToPhotos,
              onPressed: _saveToPhotos,
            ),
            IconButton(
              key: _shareKey,
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: l.share,
              onPressed: _shareCard,
            ),
          ],
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          // The card the image is taken of. It exists only while one is being
          // taken, in the corner and under the screen itself: a boundary has to
          // be laid out and painted to be rasterized, so it cannot simply be
          // built off to the side and hidden.
          if (_saving)
            Positioned(
              key: kExportCardKey,
              left: 0,
              top: 0,
              // A hairline of a box holding a card as tall as the game was
              // long: the card overflows it downwards, unclipped, and the
              // screen is painted over all of it.
              width: kExportCardWidth,
              height: 1,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: kExportCardWidth,
                maxWidth: kExportCardWidth,
                minHeight: 0,
                maxHeight: double.infinity,
                child: MediaQuery(
                  // The image is the same picture wherever it was made, so it
                  // is drawn at one size: neither the text size the reader set
                  // nor the one the system asks for reaches into it, and a card
                  // of a fixed width cannot be overflowed by either.
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: Container(
                      color: cs.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          winnerBanner,
                          const SizedBox(height: 20),
                          infoCard,
                          ?rankingCard,
                          ...playerCards,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: summary,
            ),
          ),
        ],
      ),
    );
  }
}
