# B74 Dart Competition Platform — Architectuurprincipes o.a. berichtenverkeer

**Document-ID:** B74-ARCH-MSG-001  
**Versie:** 1.2 
**Datum:** 2026-11-06  
**Status:** Vastgestelde ontwerpuitgangspunten voor verdere ontwikkeling  
**Toepassing:** B74 Competition Dashboard, B74 Dart Score, B74 Live Receiver en toekomstige B74 Online Live-integraties

## Algemene principes
> **REMOVE verwijdert uitsluitend gegevens die bij de specifieke wedstrijd horen.**

> **RETAIN archiveert een specifieke wedstrijd met behoud van alle wedstrijdgerelateerdebrongegevens en statistische bijdragen. De wedstrijd verdwijnt uitsluitend uit actieve overzichten. Een latere REMOVE vereist een nieuwe expliciete beheerdersautorisatie.**

## B74-ARCH-SCOPE-001 — Productspecialisatie met herbruikbare kern

**Besluit (2026-11-06):** B74 Dart Score ondersteunt uitsluitend wedstrijdonderdelen die door B74 Competition Dashboard zijn aangemaakt en via het bestaande beveiligde protocol zijn uitgegeven. Dart Score biedt geen zelfstandige lokale spel-, trainings- of wedstrijdstart aan. Cricket en andere zelfstandige lokale spellen worden in C1B12 na inventarisatie verwijderd. Een losse Single 501 of andere X01-wedstrijd rechtstreeks op de tablet starten valt eveneens buiten scope.

### Verantwoordelijkheden

- **Competition Dashboard:** wedstrijdorganisatie, reglement en wedstrijdsnapshot, opstellingen, uitgifte van wedstrijdopdrachten, resultaatontvangst en administratieve afsluiting.
- **Dart Score:** valideert de ontvangen opdracht, voert het toegewezen wedstrijdonderdeel uit, registreert beurten/legs/resultaten/statistieken duurzaam lokaal en synchroniseert via het bestaande protocol. Offline verder spelen en later herstellen blijven ondersteund.
- **Live Receiver:** beveiligde, read-only weergave van toegestane actuele score- en statistiekgegevens; start of beheert geen wedstrijden.
- **B74 Online Live (later):** uitsluitend de afzonderlijk vastgestelde publieke read-only gegevens; geen wedstrijdbeheer of interne protocolfunctie.

### Verplichte ontwerpafspraken

1. **Startautorisatie op domeinniveau:** geen nieuwe score-sessie zonder geldige, aan een Dashboard-wedstrijd gekoppelde opdracht. Alleen UI-knoppen verbergen is onvoldoende; validatie moet ook in de aanmaak-/verwerkingsroute gelden.
2. **Generieke kern behouden:** X01-rekenregels, in/out, checkouts, starters, rotatie, correcties, statistiekverwerking en andere daadwerkelijk gedeelde componenten blijven herbruikbaar waar functioneel nodig. Niet vooruit bouwen aan een nieuwe lokale spelmodus.
3. **Geen nieuwe transportlaag:** opdracht, resultaat, ACK, revisies, retry en beveiliging volgen B74-ARCH-MSG-001 R01–R12. Offline opslag is geen zelfstandige wedstrijdorganisatie.
4. **Gegevens zorgvuldig migreren:** inventariseer lokale speldata, schema's, referenties en statistische bijdragen vóór verwijdering; kies bewust voor behoud, migratie of expliciet geautoriseerde opschoning. Geen stilzwijgend dataverlies.
5. **Gecontroleerde verwijdering:** verwijder spel-specifieke UI en niet langer benodigde code pas na afhankelijkheidsanalyse; behoud competitieflows en Live TV.
6. **Toekomstige uitbreiding is een nieuw besluit:** een losse spelmodus, trainingsapp of Cricket-ondersteuning mag later op de herbruikbare kern worden ontwikkeld, maar maakt geen deel uit van de huidige B74 Dart Score-scope.
7. **Acceptatie:** geen zelfstandige start mogelijk; alle geldige Dashboard-opdrachten blijven speelbaar, ook bij wifi-uitval/herstart; resultaten en statistieken blijven correct; regressie- en fysieke integratietests zijn groen.

**Uitvoering:** C1B12 na functionele afronding van C1B11; geen grote refactoring combineren met nog lopende reglementswijzigingen.

---

## 1. Kernbesluit

> **Eén transportlaag → één protocol → meerdere berichttypen → wedstrijdspecifieke verwerking.**

De bestaande, werkende communicatie voor **singles 501** is de technische basis voor andere wedstrijdtypen. Bij toevoeging van **koppels 701** en later **biergame 1001** veranderen we primair de **berichtinhoud en wedstrijdspecifieke verwerking**, niet de transportinfrastructuur.

**Metafoor:** de pijpleiding en infrastructuur liggen al; verschillende vloeistoffen mogen door dezelfde leidingen. We leggen geen nieuwe leidingen aan voor elk wedstrijdtype.

## 2. Doel en scope

Dit document borgt ontwerpkeuzes zodat nieuwe functies consistent, onderhoudbaar en veilig worden toegevoegd. De eerste toepassing is **C1B4.5: wedstrijdopdracht heen, uitslag terug voor koppels 701**.

Huidige operationele scope: maximaal **twee wedstrijdbanen**, elk met een scoretablet en read-only TV-scorebord. De Samsung S25 draait het Competition Dashboard en verzorgt de lokale hotspot. De publieke B74 Online Live-weergave heeft een eigen beperkte publicatiescope en is **geen vervanging** voor het beveiligde interne berichtenverkeer.

## 3. Verplichte ontwerpregels

### R01 — Hergebruik de bestaande transportlaag

- Gebruik de bestaande verbindingen, services, beveiliging, routering en foutafhandeling van singles 501.
- Introduceer **geen** nieuwe HTTP-endpoints, sockets, synchronisatiekanalen of parallelle transportservices enkel omdat een ander wedstrijdtype wordt toegevoegd.
- Afwijken mag uitsluitend na een aantoonbare technische beperking en een expliciete ontwerpbeslissing.

### R02 — Behoud het bestaande protocol

- Hergebruik de bestaande berichtafhandeling, authenticatie, sessiebeheer, ACK-afhandeling, retries en foutcodes voor zover aanwezig.
- Definieer geen tweede ACK- of retry-protocol voor koppels 701.
- Het transport behandelt de payload als berichtinhoud; wedstrijdregels horen niet thuis in de transportlaag.

### R03 — Onderscheid berichttype en wedstrijdtype

- **Berichttype** beschrijft de handeling, bijvoorbeeld `match_assignment` of `match_result`.
- **Wedstrijdtype** beschrijft de inhoud, bijvoorbeeld `singles_501`, `doubles_701` of `beer_game_1001`.
- Gebruik de bestaande naamgeving en bericht-envelop waar mogelijk. De namen hierboven zijn **conceptueel**, geen opdracht om bestaande veldnamen te wijzigen.
- Routeer op expliciete, gevalideerde kenmerken; leid het wedstrijdtype niet impliciet af uit een score of aantal spelers.

### R04 — Wedstrijdspecifieke logica blijft gescheiden

- Singles 501, koppels 701 en biergame 1001 hebben ieder eigen validatie, scorelogica en resultaatopbouw.
- De generieke berichteninfrastructuur kent geen regels voor legs, starters, spelersrotatie, checkouts of gemiddelden.
- Voorkom dat toevoeging van 701 bestaande singles-code onnodig wijzigt.

### R05 — Compatibiliteit gaat vóór refactoring

- **Werkende singles 501-functionaliteit blijft functioneel ongewijzigd.**
- Kies bij voorkeur een kleine, uitbreidende wijziging boven een brede herstructurering.
- Refactor alleen wanneer er een concrete noodzaak, aantoonbare winst en passende regressietests zijn.
- Houd rekening met berichten die al zijn opgeslagen of onderweg zijn en met tijdelijke versieverschillen tussen S25 en tablet.

### R06 — Gebruik stabiele identificatie en revisies

- Elk bericht is te herleiden tot de juiste competitieavond, wedstrijd, wedstrijdonderdeel en afzender.
- Gebruik bestaande identificatievelden en revisieregels als uitgangspunt.
- **Een duplicaat van dezelfde revisie mag geen dubbele verwerking veroorzaken.**
- **Een nieuwere, geldige revisie mag niet onterecht als duplicaat worden weggegooid.**
- Verwerk oudere of conflicterende revisies volgens een expliciete, testbare regel; overschrijf niet stilzwijgend een nieuwere uitslag.

### R07 — Bevestiging betekent duurzaam geaccepteerd

- Een geslaagde netwerkverzending is **niet** hetzelfde als een door het Dashboard verwerkte uitslag.
- Een ACK voor een resultaat betekent pas 'ontvangen' als het bericht geauthenticeerd, gevalideerd en duurzaam verwerkt of veilig voor verwerking vastgelegd is.
- Als de ACK verloren gaat, moet opnieuw aanbieden veilig zijn (idempotente ontvangst).
- Hergebruik hiervoor de bestaande singles-semantiek; verander die niet stilzwijgend.

### R08 — Offline en herstel zijn onderdeel van de functionele eis

- Een bevestigde uitslag mag niet verdwijnen door wegvallende wifi, een app-herstart of een verloren ACK.
- Gebruik de bestaande duurzame opslag en herstel-/retryvoorzieningen. Introduceer geen tweede outbox als de huidige oplossing voldoet.
- Herstart en opnieuw verzenden mogen geen extra uitslagregistraties opleveren.

### R09 — Vertrouw geen ontvangen payload zonder controle

- Behoud bestaande authenticatie en sessie-/afzendercontrole.
- Valideer onder andere wedstrijdidentiteit, type, spelers/teams, legstand, winnaar, revisie en toegestane statusovergangen.
- Een bericht dat technisch geldig is maar inhoudelijk niet klopt, wordt niet als succesvolle uitslag verwerkt.
- Publieke TV- en Online Live-weergaven ontvangen alleen de daarvoor toegestane read-only gegevens.

### R10 — De wedstrijdadministratie is leidend voor de betekenis

- Het Dashboard bepaalt welke wedstrijd en opstelling zijn uitgegeven.
- Dart Score is bron van de daadwerkelijk gespeelde beurten, legs, uitslag en wedstrijdstatistieken.
- Het Dashboard koppelt een ontvangen resultaat aan de bestaande wedstrijdregistratie; het creëert niet stilzwijgend een tweede wedstrijd.
- Voor koppels 701 worden individuele statistieken afgeleid uit de bestaande 701-eventjournal, inclusief geldige correcties.

### R11 — Maak nieuwe wedstrijdtypen goedkoop uitbreidbaar

- Een volgend wedstrijdtype moet bij voorkeur slechts vereisen: een nieuw of uitgebreid contract, specifieke validatie, een resultaatbuilder en een handler/routering.
- Geen nieuw netwerkprotocol of nieuwe infrastructuur per spelsoort.
- Pas generieke abstrahering toe als meerdere concrete implementaties dat rechtvaardigen; bouw geen theoretisch framework vooruit.

### R12 — Test de pijpleiding én de inhoud

- Houd alle bestaande singles 501-tests groen.
- Test contract-serialisatie/deserialisatie, type-routering, validatie, beveiliging en compatibiliteit.
- Test voor 701: wedstrijdopdracht heen, eindresultaat terug, ACK, verloren ACK, retry, dubbele berichten, nieuwere revisie, oudere revisie, offline/herstart en ongeldige payload.
- Voer een echte end-to-end-test uit op Samsung S25 + scoretablet, naast de Flutter-tests.
- Commit pas na expliciet akkoord en geslaagde relevante controles.

## 4. Logische architectuur

```text
B74 Competition Dashboard (S25)
  ├─ Wedstrijdspecifieke opdrachtbuilder (501 / 701 / 1001)
  ├─ Bestaande generieke bericht-/transportlaag  ⇄  Bestaande generieke bericht-/transportlaag
  └─ Wedstrijdspecifieke resultaatontvanger          ├─ Wedstrijdspecifieke opdrachtverwerker
                                                    └─ Wedstrijdspecifieke resultaatbuilder
                                                       B74 Dart Score (tablet)

             ÉÉN BEVEILIGD TRANSPORT + ÉÉN BESTAAND PROTOCOL
               verschillende berichttypen en payloads
```

**Heen:** Dashboard → wedstrijdopdracht → Dart Score.  
**Terug:** Dart Score → definitief resultaat → Dashboard → bestaande wedstrijdregistratie.  
**Bevestiging:** Dashboard → bestaande protocol-ACK → Dart Score.

## 5. Toepassing op C1B4.5 (koppels 701)

1. Inventariseer de **werkende singles 501-route** van opdracht, resultaat, beveiliging, opslag en ACK.
2. Hergebruik die route zonder protocol- of infrastructuurwijziging.
3. Voeg uitsluitend de benodigde 701-payload, builder, validatie en routering toe.
4. Koppel de 701-uitslag en individuele statistieken aan het bestaande wedstrijdonderdeel.
5. Hergebruik bestaande retry- en revisieregels; test expliciet verloren ACK en gecorrigeerde uitslagen.
6. Controleer beide applicaties met `flutter analyze --no-pub` en `flutter test --no-pub` en voer een S25/tablet-proef uit.
7. **Geen Git-commit zonder expliciet akkoord.**

## 6. Niet doen (anti-patronen)

- Een afzonderlijke '701-transportservice' naast de singles-transportservice bouwen.
- Een tweede ACK-, retry- of offline-opslagmechanisme introduceren zonder noodzaak.
- Wedstrijdregels in netwerkcode verwerken.
- Bestaande singles-berichten onnodig incompatibel maken.
- Een uitslag als verwerkt markeren zodra alleen de verzending is gelukt.
- Een gewijzigde uitslagrevisie als gewoon duplicaat negeren.
- De publieke read-only scorebordroute gebruiken als intern beveiligd wedstrijdprotocol.
- Grote refactorings combineren met de toevoeging van één nieuw wedstrijdtype.

## 7. Afwijkingsprocedure

Een uitzondering op deze regels vereist vóór implementatie:

1. De concrete beperking in de bestaande oplossing.
2. Waarom uitbreiding van de bestaande route onvoldoende is.
3. De alternatieven en hun gevolgen voor compatibiliteit, beveiliging en beheer.
4. De regressie- en migratieaanpak.
5. Expliciete goedkeuring van de voorgestelde afwijking.

## 8. Definitie van gereed voor een nieuw wedstrijdtype

- [ ] Opdracht gebruikt de bestaande beveiligde route.
- [ ] Resultaat gebruikt de bestaande beveiligde retourroute.
- [ ] Bestaande protocolsemantiek, ACK en retry zijn behouden.
- [ ] Berichttype en wedstrijdtype worden expliciet gevalideerd.
- [ ] Ontvangst is idempotent; revisies worden correct afgehandeld.
- [ ] Offline/herstart en verloren ACK zijn getest.
- [ ] Wedstrijdspecifieke regels en statistieken zijn correct.
- [ ] Singles 501-regressietests blijven groen.
- [ ] Dashboard- en Dart Score-tests zijn groen.
- [ ] Praktijktest op S25 en scoretablet is geslaagd.
- [ ] Commit alleen na expliciet akkoord.

---

**Leidende ontwerpzin:** *Hergebruik wat goed werkt. Verander de inhoud, niet de pijpleiding.*
