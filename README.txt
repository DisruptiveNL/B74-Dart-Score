B74 C1b2b Patch E — ruimte voor globale verbindingsindicator

VEREIST: werkende Patch D reeds geinstalleerd.

Overschrijf uitsluitend deze twee bestanden in de Dart Score projectroot:
  lib/screens/competition_matches_screen.dart
  lib/screens/competition_receive_screen.dart

Wijzigingen:
- Competities & Toernooien: 56 logical pixels rechts gereserveerd voor globale indicator.
- Wedstrijden ontvangen: dubbele lokale B74LinkIndicator verwijderd; globale indicator blijft.
- Geen wijzigingen aan Patch D, heartbeat, sessie, database of scorelogica.

Controle:
  dart format lib/screens/competition_matches_screen.dart lib/screens/competition_receive_screen.dart
  flutter analyze
  flutter test
  flutter run -d R8YY91N6X3E --debug

Praktijktest: radio opent Wedstrijden ontvangen, vernieuwen werkt, groen kettingicoon opent
rechtstreeks B74 apparaatverbinding op beide schermen, geen overlap.

Nog niet gecompileerd/getest op de gebruikersomgeving.
