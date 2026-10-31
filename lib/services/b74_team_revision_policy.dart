/// C1B4.2B.2 — zuivere beslislogica voor teamwedstrijd-revisies.
/// Geen opslag of netwerk: de ontvangende database moet deze beslissing
/// binnen dezelfde transactie nemen als de daadwerkelijke mutatie.
enum B74TeamRevisionDecision { create, unchanged, replace, reject }

class B74TeamRevisionPolicy {
  static B74TeamRevisionDecision decide({
    required int incomingRevision,
    required String incomingPayload,
    int? storedRevision,
    String? storedPayload,
    required bool hasStarted,
  }) {
    if (incomingRevision < 1 || incomingPayload.isEmpty) {
      return B74TeamRevisionDecision.reject;
    }
    if (storedRevision == null) {
      // Ook een nieuwe wedstrijd moet bij revisie 1 beginnen.
      return !hasStarted && incomingRevision == 1
          ? B74TeamRevisionDecision.create
          : B74TeamRevisionDecision.reject;
    }
    if (storedRevision < 1 || storedPayload == null) {
      return B74TeamRevisionDecision.reject;
    }
    if (incomingRevision < storedRevision) {
      return B74TeamRevisionDecision.reject;
    }
    if (incomingRevision == storedRevision) {
      return incomingPayload == storedPayload
          ? B74TeamRevisionDecision.unchanged
          : B74TeamRevisionDecision.reject;
    }
    // Geen revisies overslaan: voorkomt dat ontbrekende correcties
    // ongemerkt worden geaccepteerd.
    if (incomingRevision != storedRevision + 1 || hasStarted) {
      return B74TeamRevisionDecision.reject;
    }
    return B74TeamRevisionDecision.replace;
  }
}
