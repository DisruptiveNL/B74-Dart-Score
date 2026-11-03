# B74 Dart Score — TODO

**Bijgewerkt:** 2026-11-03
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

## Licentiebeleid en autorisatie (voorstel; nummer nog toe te wijzen)
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

## C1B11 — Competitiereglement Regulier en Beker (actieve bouwopdracht)

**Status:** functionele afspraken vastgesteld; broncode-inventarisatie en implementatie nog uit te voeren.
**Aanpak:** eerst Dashboard-reglement en wedstrijdsnapshot, daarna Score-verwerking en integratietests. Bestaande werking niet onnodig wijzigen.

### 1. Reglement en opslag
- [ ] Reglement per wedstrijdsoort ondersteunen: **Regulier** en **Beker**.
- [ ] Per wedstrijd precies drie configuratiegroepen: **Singles** (alle vier gelijk), **Koppels** (alle vier gelijk), **Biergame** (één onderdeel).
- [ ] Bij nieuwe wedstrijd de **laatst opgeslagen instellingen als voorstel** invullen; de gebruiker kan deze vóór vastlegging aanpassen.
- [ ] De definitieve instellingen als **onveranderlijke wedstrijdsnapshot** opslaan en meesturen naar Dart Score; latere reglementswijzigingen hebben geen terugwerkende kracht.
- [ ] Bestaande wedstrijden en databaseversies veilig migreren; defaults voor ontbrekende velden expliciet vastleggen.

### 2. Instelbare spelregels
- [ ] Singles: X01 = **301 / 501 / 701**, standaard **501**; Best of **3 / 5 / 7 / 9 / 11**, standaard **5**.
- [ ] Koppels: X01 = **301 / 501 / 701**, standaard **701**; Best of **3 / 5 / 7 / 9 / 11**, standaard **5**.
- [ ] Biergame: X01 = **301 / 501 / 701 / 1001**, standaard **1001**; altijd **één leg**.
- [ ] Per groep onafhankelijk **Straight In / Double In** en **Straight Out / Double Out / Master Out**. Master Out: dubbel, triple of inner bull (50); Double Out: dubbel of inner bull (50).
- [ ] Double In: punten tellen vanaf en inclusief de eerste geldige dubbel; eerdere darts tellen voor het aantal gegooide darts; drie mislukte openingen = 0 punten.
- [ ] Per groep wedstrijdpunten voor winst instelbaar als **positief geheel getal (minimaal 1)**; standaard **1** per gewonnen onderdeel. Geen competitieklassement/ranglijst bouwen.

### 3. Startregeling
- [ ] Per groep afzonderlijk **Thuis begint / Uit begint / Bullstart** instelbaar.
- [ ] Bij Thuis/Uit-start geldt voor Singles respectievelijk Koppels een doorlopende afwisseling van eerste-leg-starters: onderdeel 1 start volgens instelling, 2 tegengesteld, 3 volgens instelling, 4 tegengesteld. Biergame volgt eigen instelling.
- [ ] Bij Bullstart wordt **per afzonderlijk onderdeel** gebulld; bullwinnaar begint leg 1.
- [ ] Binnen een onderdeel wisselt de legstarter automatisch; bij Singles en Koppels kan een **optionele bull voor de beslissende leg** worden ingesteld. Geen extra beslissende-leg-bull bij Biergame.
- [ ] De starter automatisch uit het reglement afleiden; uitsluitend bullwinnaar laten vastleggen wanneer nodig. Bestaande handmatige starterbevestiging per leg vervangen.

### 4. Opstellingen, verzenden en speelvolgorde
- [ ] Vaste sportieve volgorde: **Single 1–4 → Koppel 1–4 → Biergame**. Niet als instelbare volgorde aanbieden.
- [ ] De **vier Singles gezamenlijk** definitief verzenden; Koppels **elk afzonderlijk**; Biergame afzonderlijk.
- [ ] Captain/appbediener mag **alle onderdelen vooraf indelen en verzenden**, ook Biergame vóór afronding van Koppels. Geen onnodige verzendblokkades op basis van spelfase of vertraagde synchronisatie.
- [ ] Voor iedere verzending expliciete waarschuwing/bevestiging: **VERZONDEN = DEFINITIEF**; na verzending geen wijzigingen meer aan die opstelling, ook niet vóór aanvang.
- [ ] Niet-verzonden onderdelen blijven aanpasbaar; toegestane wissels gelden uitsluitend voor toekomstige, niet-verzonden onderdelen. Reeds vervangen spelers keren niet terug; invaller neemt de positie over.
- [ ] Singles gebruiken vier vaste basisspelers; geen wissels tijdens Singles. Reserves en de bestaande regels voor koppelsamenstelling behouden.

### 5. Dummy en wedstrijdresultaten
- [ ] Dummy is een afzonderlijke speler met naam **Dummy**; bij drie echte spelers toegestaan als vierde.
- [ ] Dummy in Singles: reglementair verlies zonder darts of individuele statistieken, met legs **2–0 / 3–0 / 4–0 / 5–0 / 6–0** voor respectievelijk Bo3/5/7/9/11. Alleen teamresultaat telt.
- [ ] Dummy tegenover Dummy: een echte speler van elk team bullt om het reglementaire teampunt; geen individuele statistieken.
- [ ] Dummy in Koppels/Biergame: normale rotatie, per Dummy-beurt **0 punten en 3 darts**; Dummy kan niet uitgooien; team-/koppelgemiddelde wordt hierdoor beïnvloed.
- [ ] Geen wedstrijd aanmaken bij slechts twee echte spelers; geen automatische 9–0.
- [ ] Teamuitslag berekenen met ingestelde puntgewichten; standaard maximaal **9–0**.

### 6. Correctie, afsluiting en testen
- [ ] Correctie/undo maximaal **laatste drie beurten**, uitsluitend zolang het betreffende onderdeel nog loopt; na beëindiging van het onderdeel geen correcties meer.
- [ ] Sportief afgerond bij negen definitieve resultaten; **alleen Dashboard** mag daarna na volledige synchronisatie de wedstrijd administratief afsluiten en vergrendelen.
- [ ] Unit- en regressietests voor alle X01/Bo-combinaties, in/out, startafwisseling, bull, puntweging, Dummy, verzendvergrendeling, wissels, wedstrijdsnapshot en migraties.
- [ ] Integratietests Dashboard → Dart Score → Dashboard en Live Receiver; bestaande WSS/TV-layout/statistieken niet onnodig aanpassen.
- [ ] Op echte Android-apparaten verifiëren, `flutter analyze`, `flutter test`, `git diff --check` en gecontroleerd committen/pushen per afgeronde stap.

### 7. Uitvoering in stappen
- [ ] **Stap 1:** actuele Dashboard- en Dart Score-broncode inventariseren: bestaande modellen, opslag, protocol, schermen en tests.
- [ ] **Stap 2:** reglementmodel, validatie, defaults, migratie en wedstrijdsnapshot in Dashboard.
- [ ] **Stap 3:** reglementscherm en definitieve verzendbevestigingen in Dashboard.
- [ ] **Stap 4:** protocoluitbreiding en Score-engine voor X01, in/out, starters, Bo en Dummy.
- [ ] **Stap 5:** end-to-end-regressie en fysieke tests; documentatie en TODO actualiseren.

## Later — testgegevens gecontroleerd opschonen
- [ ] **Niet nu uitvoeren.** Eerst backup/inventarisatie van wedstrijden, spelers, teams, competities en statistieken; daarna gecontroleerd alle testdata wissen voor een schone start.
