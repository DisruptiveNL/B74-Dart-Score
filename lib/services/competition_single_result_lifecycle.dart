/// Lifecycle of one competition single's result.
///
/// Archiving is only allowed after the receiving dashboard acknowledges
/// the exact submitted result. A transport attempt is not an acknowledgement.
enum CompetitionSingleResultStatus {
  notStarted,
  inProgress,
  completed,
  sending,
  archived,
}

/// Pure transition rules, independent of UI and transport.
class CompetitionSingleResultLifecycle {
  const CompetitionSingleResultLifecycle._();

  static bool canEdit(CompetitionSingleResultStatus status) =>
      status == CompetitionSingleResultStatus.inProgress ||
      status == CompetitionSingleResultStatus.completed;

  static bool canSend(CompetitionSingleResultStatus status) =>
      status == CompetitionSingleResultStatus.completed;

  static bool canStart(CompetitionSingleResultStatus status) =>
      status == CompetitionSingleResultStatus.notStarted;

  static CompetitionSingleResultStatus transition(
    CompetitionSingleResultStatus current,
    CompetitionSingleResultStatus next,
  ) {
    if (current == next) return current;
    final allowed = switch (current) {
      CompetitionSingleResultStatus.notStarted =>
        next == CompetitionSingleResultStatus.inProgress,
      CompetitionSingleResultStatus.inProgress =>
        next == CompetitionSingleResultStatus.completed,
      CompetitionSingleResultStatus.completed =>
        next == CompetitionSingleResultStatus.sending ||
            next == CompetitionSingleResultStatus.inProgress,
      CompetitionSingleResultStatus.sending =>
        next == CompetitionSingleResultStatus.archived ||
            next == CompetitionSingleResultStatus.completed,
      CompetitionSingleResultStatus.archived => false,
    };
    if (!allowed) {
      throw StateError(
        'Ongeldige single-resultaattransitie: $current -> $next',
      );
    }
    return next;
  }

  /// Idempotent receive-side identity: a retry of the same result must not
  /// create a second single result in the dashboard.
  static String resultKey(String matchId, int singleSlot) {
    if (matchId.trim().isEmpty || singleSlot < 1 || singleSlot > 4) {
      throw ArgumentError('Ongeldige wedstrijd of single-slot');
    }
    return '$matchId:single:$singleSlot';
  }
}
