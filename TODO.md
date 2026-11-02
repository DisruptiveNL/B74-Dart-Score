# B74 Dart Score — TODO

**Bijgewerkt:** 2026-11-02
**Status:** C1B7 Live TV werkende, gepushte tussenversie; resterende beveiligings- en releasetests staan open.

## C1B7 — Live TV

### Bevestigd op echte apparaten
- [x] Centrale TV-bediening onder **Competities & Toernooien** en QR-koppeling met B74 Live Receiver.
- [x] TV-icoon in Single 501 is status-only; tikken verbreekt de verbinding niet.
- [x] TV-scores direct bijwerken zonder rollende cijferanimatie.
- [x] Single 501, Koppel 701 en Biergame 1001 worden op de TV weergegeven.
- [x] Wisselen naar Koppel 701 en Biergame 1001 werkt met bestaande TV-koppeling.
- [x] Automatisch herverbinden zonder QR na Dart Score-appherstart.
- [x] Automatisch herverbinden zonder QR na tijdelijke wifi-uitval; score-updates hervatten.
- [x] Bestaande WSS-certificaatcontrole, TV-layout en 180-celebratie behouden in implementatie; volledige regressietest van alle effecten blijft relevant.
- [x] TV-statistieken ingericht: Single 501 per speler, Koppel 701 gecombineerd per koppel, Biergame 1001 gecombineerd per team. Last 3 Visits, First 9 Average en 3-Dart Average; geen This Leg. **Exacte statistische juistheid nog afzonderlijk verifiëren.**

### Nog te verifiëren of verbeteren
- [ ] 48-uursregistratie daadwerkelijk laten verlopen en controleren dat de receiver nieuwe QR-koppeling vereist.
- [ ] Registratie kunnen intrekken en testen dat opnieuw koppelen noodzakelijk is; receiver-side intrekking nog te realiseren/verifiëren.
- [ ] Onjuiste of ingetrokken credentials en verlopen QR-token afwijzen, zonder onveilige `ws://`-fallback.
- [ ] TV-adreswijziging (DHCP/IP) onderzoeken; opgeslagen IP kan automatische reconnect beperken.
- [ ] Exactheid van gecombineerde Last 3 Visits, First 9 en 3-Dart Average toetsen met bekende testbeurten, inclusief correctie/undo en Double In.
- [ ] Incidentele vertraging van score-updates objectief meten (wijziging, verzending, ontvangst, ACK, rendering) als deze opnieuw optreedt.
- [ ] Reconnect na herstart van de **Receiver** en wisseling tussen wedstrijden opnieuw controleren.

### Tests en Git — huidige tussenversie
- [x] Dart Score: `flutter analyze --no-pub` zonder errors (waarschuwingen/info blijven mogelijk).
- [x] Dart Score: `flutter test --no-pub` — **911 tests geslaagd**.
- [x] Dart Score: `git diff --check` schoon vóór commit.
- [x] APK geïnstalleerd en op echte tablet/TV getest; build-output niet afzonderlijk in deze TODO vastgelegd.
- [x] Dart Score gepusht: `feature/c1b3-singles-sync`, commit **`f3ea0de`**.
- [x] Live Receiver gepusht: `feature/c1b7-live-receiver`, commit **`3f94655`**.
- [ ] Voor definitieve release: build, tests en volledige integratie-/beveiligingscontrole opnieuw uitvoeren en resultaten vastleggen.

## C1B8 — Uniforme Double In-invoer (voorstel)
- [ ] Vergelijk de bestaande Single 501 Double In-UI met Koppel 701/Biergame 1001.
- [ ] Maak de gebruikersinteractie uniform voor alle X01-speltypen, met behoud van spelregels en bestaande score-engine.
- [ ] Punten tellen pas vanaf **en inclusief** de eerste geldige dubbel; eerdere darts tellen wel voor het aantal gegooide darts.
- [ ] Zonder geldige dubbel in drie darts: 0 punten, drie darts geregistreerd.
- [ ] Tests voor opening op dart 1, 2 en 3, geen opening, bust, checkout, correctie en undo.
- [ ] Geen wijzigingen aan werkende TV-transportlaag of TV-layout.

## C1B9 — Licentiebeleid en autorisatie (voorstel)
- [ ] Licentievormen en gebruiksvoorwaarden vaststellen en juridisch laten toetsen vóór publieke uitgifte.
- [ ] **Licentieaanvraag vooraf verplicht:** aanvrager beschrijft type gebruiker, organisatie en beoogde gebruiksscope.
- [ ] Aanvragen worden persoonlijk beoordeeld; **gebruik pas toegestaan na expliciete goedkeuring**.
- [ ] Gratis licentie voor goedgekeurd niet-commercieel amateurgebruik door spelers, teams en verenigingen, inclusief reguliere competities met contributies of bondsbijdragen zonder winstoogmerk.
- [ ] Commercieel dartcentrum en commerciële toernooien of toernooien met betaald inschrijfgeld en/of prijzengeld: geen automatische gratis toestemming; afzonderlijke expliciete toestemming en waar van toepassing betaald abonnement.
- [ ] Licentiegegevens, geldigheidsduur, toegestane scope, verlenging, wijziging, intrekking en audittrail ontwerpen.
- [ ] Technische autorisatie/activatie ontwerpen, inclusief offline gedrag, meerdere apparaten per licentie, privacy en misbruikpreventie.
- [ ] Onderscheid maken tussen **downloadrecht** en **gebruiksrecht**; zonder goedgekeurde licentie geen geautoriseerd gebruik.
- [ ] Vaststellen welke apps onder één licentie vallen: Dart Score, Competition Dashboard, Live Receiver en eventueel Online Live.

## C1B10 — APK-distributie en releasebeheer (voorstel)
- [ ] Android-releaseproces inrichten: versienummering, ondertekende releasebuild, veilige opslag van signing key, release notes en terugrolstrategie.
- [ ] Distributie via Google Play onderzoeken; voor Play wordt doorgaans een Android App Bundle (`.aab`) gebruikt, naast eventuele APK's voor directe installatie/test.
- [ ] Vaststellen hoe goedgekeurde gebruikers een release ontvangen en hoe licentiecontrole bij eerste gebruik plaatsvindt.
- [ ] Installatie, updates, migratie en compatibiliteit testen op ondersteunde Android-telefoons, tablets en TV-boxen.
- [ ] Gebruikersdocumentatie en licentieaanvraagprocedure beschikbaar maken.
- [ ] Geen iOS/Apple-distributie in de huidige scope.
- [ ] Geen automatisch support- of onderhoudscontract aan gratis licenties verbinden.

## Latere productontwikkeling — Dashboard en B74 Online Live
- [ ] Overkoepelende teamstatistieken voor captains, wedstrijdleiding en publiek uitwerken: gemiddelden, resultaten, finishes, 100+/140+/180 en competitieoverzichten.
- [ ] Voor gemiddelden punten en werkelijk gegooide darts gebruiken; geen ongewogen gemiddelde van spelersgemiddelden.
- [ ] Dart Score-statistieken voor de teller ongewijzigd laten, tenzij een afzonderlijk functioneel probleem wordt vastgesteld.
- [ ] B74 Online Live beperkt houden tot afgesproken publieke actuele scorebord- en tussenstandinformatie; uitbreiding van publieke statistieken vereist afzonderlijke scopebeslissing.

---

**Architectuurregel:** B74-ARCH-MSG-001 — één transportlaag, één protocol, meerdere berichttypen, wedstrijdspecifieke verwerking.
**Releasegrens:** een werkende en gepushte tussenversie is niet automatisch een definitief vrijgegeven product.

## C1B9 — Opruimlogboek en beheerdersverwijdering
- [x] Dart Score: databaseondersteuning RETAIN naar REMOVE; 966 tests geslaagd.
- [ ] Officiele wedstrijden: verwijderverzoek vanuit Wedstrijdbeheer.
- [ ] Opruimlogboek: wedstrijd selecteren, PIN, RETAIN of REMOVE en bevestigen.
- [ ] RETAIN blijft selecteerbaar voor latere REMOVE.
- [ ] Beveiligde synchronisatie en fysieke end-to-end-test afronden.

## Competitiereglement — Regulier en Beker
- [ ] Reglement instelbaar maken voor Singles, Koppels en Biergame.
- [ ] Dit ondersteunen voor zowel Reguliere competitie als Beker.
- [ ] Bij aanmaken van een wedstrijd automatisch het toepasselijke reglement overnemen.
- [ ] Overgenomen instellingen bij de wedstrijd vastleggen; latere reglementswijzigingen wijzigen bestaande wedstrijden niet.
- [ ] Regressietests toevoegen.
