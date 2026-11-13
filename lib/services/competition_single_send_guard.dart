/// UI decision for a persisted singles result. Transport owns all status
/// transitions and acknowledgement; the screen never changes the outbox.
enum CompetitionSingleSendAction { send, inProgress, alreadyArchived }

class CompetitionSingleSendGuard {
  const CompetitionSingleSendGuard._();

  static CompetitionSingleSendAction evaluate(Object? status) {
    if (status == 'archived') return CompetitionSingleSendAction.alreadyArchived;
    if (status == 'sending') return CompetitionSingleSendAction.inProgress;
    return CompetitionSingleSendAction.send;
  }
}
