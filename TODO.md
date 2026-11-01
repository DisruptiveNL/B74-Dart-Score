# B74 Dart Score — TODO

## C1B7 — Live TV (status 2026-11-01)

### Bevestigd werkend op echte apparaten (v0.6a)
- [x] Centrale TV-knop onder **Competities & Toernooien** zichtbaar.
- [x] QR-code scannen vanuit centrale knop en verbinding maken met B74 Live Receiver.
- [x] Verbinding blijft actief bij wisselen tussen wedstrijden.
- [x] TV toont scores direct, zonder rollende cijferanimatie.
- [x] Bestaande TV-statistieken en 180-celebratie behouden.

### Verbeterpunten — eerstvolgende patch
- [ ] **TV-icoontje in wedstrijd is status-only.** Tikken mag de TV-verbinding **niet verbreken**. Laat uitsluitend de daadwerkelijke verbindingsstatus zien. Koppelen, opnieuw koppelen en handmatig verbreken alleen via de centrale TV-bediening onder Competities & Toernooien. Test: tik op het wedstrijdicoon tijdens een actieve verbinding; score-updates blijven doorkomen.
- [ ] **Incidentele vertraging bij score-updates onderzoeken.** Meet tijdstippen van scorewijziging, verzenden, ontvangst, ACK en rendering; stel vast waar vertraging ontstaat. Geen willekeurige wijzigingen in de werkende WSS-verbinding. Test bij opeenvolgende scores, wisselen van wedstrijd en kortstondige netwerkonderbreking.

### C1B7 v0.6b — centrale koppeling voltooien
- [ ] Beveiligde apparaatregistratie op de receiver met **48 uur geldigheid**, gecontroleerd door receiver; geen onbeperkt hergebruik van het tijdelijke QR-koppeltoken.
- [ ] Automatisch opnieuw verbinden na app-herstart of tijdelijke verbindingsuitval, zolang de registratie geldig is.
- [ ] Na verlopen of ingetrokken registratie opnieuw QR-koppeling vereisen.
- [ ] Centrale TV-verbinding gebruiken voor **SINGLE 501**, **KOPPEL 701** en **BIERGAME 1001**.
- [ ] TV-statistieken per context: single per speler, koppel 701 gezamenlijk per koppel, biergame 1001 gezamenlijk per team. **Last 3 Visits**, **First 9 Average** en **3-Dart Average**; geen 'This leg'-statistieken.
- [ ] Bestaande 180-celebratie, directe scoreweergave en WSS-certificaatcontrole behouden.
- [ ] Integratietest op Samsung S25 / scoretablet / Android TV-box; verbinding wisselt tussen wedstrijden zonder opnieuw QR te scannen.

### Release- en Git-controle
- [ ] `flutter analyze --no-pub`, `flutter test --no-pub`, `git diff --check` en Android-build controleren.
- [ ] Op echte apparaten testen voordat wijzigingen als voltooid worden gemarkeerd.
- [ ] Git-commit en push van B74 Dart Score; receiver staat reeds op branch `feature/c1b7-live-receiver`, commit `6bf2cde` op GitHub.

> Scope: C1B7 v0.6a is een werkende tussenstap, **nog niet** de volledige 48-uurskoppeling. Deze TODO bevat waarnemingen uit de praktijk en geplande werkzaamheden; niet-afgevinkte punten zijn nog niet geïmplementeerd.
