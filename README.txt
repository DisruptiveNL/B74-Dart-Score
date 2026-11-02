B74 C1B7 v0.6b-2 - kandidaatpatch (NIET lokaal gecompileerd)

Bestanden: lib/services/b74_live_tv.dart en lib/screens/competition_doubles_screen.dart

Doel: bestaande WSS TV-socket hergebruiken voor doubles701 en beer1001.
- Na sessie laden/score/correctie/undo: volledige TV-snapshot.
- Teamstatistieken per koppel/team uit correctie-bewuste events.
- First nine en laatste drie teambeurten chronologisch uit journal.
- Reconnect stuurt snapshot van laatst gekoppelde sessie.
- Geen wijziging aan QR, TLS pinning of 48-uursregistratie.

INSTALLATIE: pak ZIP uit in root D:\b74dev\projects\B74-Dart-Score.
Maak vooraf een backup / controleer git diff; overschrijf alleen deze 2 bestanden.

CONTROLE:
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
git diff --check

Geen commit totdat echte apparaat-tests (701, 1001, correctie, undo,
reconnect, terug naar singles) slagen.
