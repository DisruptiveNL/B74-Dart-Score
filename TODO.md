# B74 Dart Competition Platform — TODO & voortgang

**Bijgewerkt:** 2026-11-12
**Status:** C1B11 reguliere fysieke keten (9/9, MATCH_LOCKED en read-only competitiearchief) geslaagd op 2026-11-11/12; archief-verwijderregressie, overige spelregel-/migratiegevallen en definitieve releasecontrole open. C1B7 Live TV blijft een werkende tussenversie met openstaande beveiligings-/releasetests.

**Leeswijzer:** `[x]` = afgerond binnen de genoemde scope (waar van toepassing door gebruiker als fysiek getest aangegeven); `[ ]` = open of nog onvoldoende bewezen. Bij gedeeltelijke realisatie staat expliciet wat nog ontbreekt. Tests in een tijdelijke database bewijzen geen fysieke end-to-end-keten. **Vinkjes door gebruiker toegevoegd op 2026-11-09 zijn als praktijkbevestiging overgenomen, tenzij zij strijdig zijn met de vastgelegde patchstatus.**

### Actuele gecontroleerde herstelpunten (2026-11-12)
- [x] **Dart Score:** commit `53ece61` gepusht; **1049/1049 tests** geslaagd; starterbevestiging Patch 04B.3C getest.
- [x] **Competition Dashboard:** commit `bf602ae` gepusht op `feature/c1b3-match-types-rules`; working tree schoon; **160/160 tests** geslaagd.
- [x] **Samen:** 1209 geslaagde tests in de laatst gerapporteerde suites; dit zijn geen end-to-end-tests over alle drie apparaten.
- [ ] **Live Receiver:** na C1B11-wijzigingen opnieuw volledige regressie en fysieke ketentest uitvoeren; laatst hier vastgelegde receiver-commit `3f94655`.

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
- [x] 48-uursregistratie daadwerkelijk laten verlopen en controleren dat de receiver nieuwe QR-koppeling vereist.
- [x] Registratie kunnen intrekken en testen dat opnieuw koppelen noodzakelijk is. **Gebruiker markeerde dit getest; receiver-side intrekking staat in de toelichting nog als te realiseren/verifiëren. Status afstemmen en daarna definitief afvinken.**
- [x] Onjuiste of ingetrokken credentials en verlopen QR-token afwijzen, zonder onveilige `ws://`-fallback.
- [ ] TV-adreswijziging (DHCP/IP) onderzoeken; opgeslagen IP kan automatische reconnect beperken.
- [x] Exactheid van gecombineerde Last 3 Visits, First 9 en 3-Dart Average toetsen met bekende testbeurten, inclusief correctie/undo en Double In.
- [ ] Incidentele vertraging van score-updates objectief meten (wijziging, verzending, ontvangst, ACK, rendering) als deze opnieuw optreedt.
- [x] Reconnect na herstart van de **Receiver** en wisseling tussen wedstrijden opnieuw controleren.

### Tests en Git — C1B7 historische tussenversie (2026-11-07)
- [x] Dart Score: `flutter analyze --no-pub` zonder errors (waarschuwingen/info blijven mogelijk).
- [x] Dart Score: `flutter test --no-pub` — **911 tests geslaagd op dat moment**.
- [x] Dart Score: `git diff --check` schoon vóór commit.
- [x] APK geïnstalleerd en op echte tablet/TV getest; build-output niet afzonderlijk in deze TODO vastgelegd.
- [x] Dart Score gepusht: `feature/c1b3-singles-sync`, commit **`f3ea0de`**.
- [x] Live Receiver gepusht: `feature/c1b7-live-receiver`, commit **`3f94655`**.
- [ ] Voor definitieve release: build, tests en volledige integratie-/beveiligingscontrole opnieuw uitvoeren en resultaten vastleggen.

## C1B8 — Uniforme Double In-invoer (voorstel)
- [x] Vergelijk de bestaande Single 501 Double In-UI met Koppel 701/Biergame 1001.
- [x] Maak de gebruikersinteractie uniform voor alle X01-speltypen, met behoud van spelregels en bestaande score-engine.
- [x] Punten tellen pas vanaf **en inclusief** de eerste geldige dubbel; eerdere darts tellen wel voor het aantal gegooide darts.
- [x] Zonder geldige dubbel in drie darts: 0 punten, drie darts geregistreerd.
- [x] Tests voor opening op dart 1, 2 en 3, geen opening, bust, checkout, correctie en undo.
- [x] Geen wijzigingen aan werkende TV-transportlaag of TV-layout.

## Licentiebeleid en autorisatie (beleid vastgesteld; implementatie/juridische toets open; nummer nog toe te wijzen)
- [ ] Licentievormen en gebruiksvoorwaarden vaststellen en juridisch laten toetsen vóór publieke uitgifte.
- [x] **Beleidsbesluit:** licentieaanvraag vooraf verplicht; **implementatie aanvraagproces open**. Aanvrager beschrijft type gebruiker, organisatie en beoogde gebruiksscope.
- [ ] **Technisch realiseren:** online/offline aanvraag, beoordeling, goedkeuring en activering; zonder goedkeuring geen gebruik.
- [x] **Beleidsbesluit:** aanvragen worden persoonlijk beoordeeld; **gebruik pas toegestaan na expliciete goedkeuring**.
- [x] **Beleidsbesluit:** gratis licentie voor goedgekeurd niet-commercieel amateurgebruik door spelers, teams en verenigingen, inclusief reguliere competities met contributies of bondsbijdragen zonder winstoogmerk.
- [x] **Beleidsbesluit:** commercieel dartcentrum en commerciële toernooien of toernooien met betaald inschrijfgeld en/of prijzengeld: geen automatische gratis toestemming; afzonderlijke expliciete toestemming en waar van toepassing betaald abonnement.
- [ ] Licentiegegevens, geldigheidsduur, toegestane scope, verlenging, wijziging, intrekking en audittrail ontwerpen.
- [ ] Technische autorisatie/activatie ontwerpen, inclusief offline gedrag, **één activatiecode per baan/app-installatie (één toestel)**, privacy en misbruikpreventie; gebruik op ander toestel vereist afzonderlijke autorisatie.
- [x] **Beleidsbesluit:** onderscheid tussen **downloadrecht** en **gebruiksrecht**; zonder goedgekeurde licentie geen geautoriseerd gebruik.
- [ ] Vaststellen welke apps onder één licentie vallen: Dart Score, Competition Dashboard, Live Receiver en eventueel Online Live.

## C1B10 — APK-distributie en releasebeheer (voorstel)
- [ ] Android-releaseproces inrichten: versienummering, ondertekende releasebuild, veilige opslag van signing key, release notes en terugrolstrategie.
- [ ] Distributie via Google Play onderzoeken; voor Play wordt doorgaans een Android App Bundle (`.aab`) gebruikt, naast eventuele APK's voor directe installatie/test.
- [ ] Vaststellen hoe goedgekeurde gebruikers een release ontvangen en hoe licentiecontrole bij eerste gebruik plaatsvindt.
- [ ] Installatie, updates, migratie en compatibiliteit testen op ondersteunde Android-telefoons, tablets en TV-boxen.
- [ ] Gebruikersdocumentatie en licentieaanvraagprocedure beschikbaar maken.
- [x] **Scopebesluit:** geen iOS/Apple-distributie in de huidige scope.
- [x] **Beleidsbesluit:** geen automatisch support- of onderhoudscontract aan gratis licenties verbinden.

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
- [x] Officiele wedstrijden: verwijderverzoek vanuit Wedstrijdbeheer.
- [x] Opruimlogboek: wedstrijd selecteren, PIN, RETAIN of REMOVE en bevestigen.
- [x] RETAIN blijft selecteerbaar voor latere REMOVE.
- [x] Beveiligde synchronisatie en fysieke end-to-end-test afronden.

## C1B11 — Competitiereglement Regulier en Beker (actieve bouwopdracht)

**Status (2026-11-12):** reguliere negen-onderdelenketen (4 singles, 4 koppels, biergame), resultaatretour, Dashboard-afsluiting, beveiligde MATCH_LOCKED-ACK en read-only Score-archief fysiek geslaagd. Overige reglementcombinaties, Dummy, migratie, archief-verwijderregressie en releasecontrole blijven open.
**Aanpak:** eerst Dashboard-reglement en wedstrijdsnapshot, daarna Score-verwerking en integratietests. Bestaande werking niet onnodig wijzigen.

### 1. Reglement en opslag
- [x] Reglement per wedstrijdsoort ondersteunen: **Regulier** en **Beker** (Dashboard-scherm fysiek getoond; contracttests aanwezig).
- [x] Per wedstrijd precies drie configuratiegroepen: **Singles** (alle vier gelijk), **Koppels** (alle vier gelijk), **Biergame** (één onderdeel); reglementcontract getest.
- [x] Bij nieuwe wedstrijd de **laatst opgeslagen instellingen als voorstel** invullen; de gebruiker kan deze vóór vastlegging aanpassen. **Door gebruiker als werkend bevestigd**; geautomatiseerde regressietest voor bewaren/heropenen nog wenselijk.
- [ ] De definitieve instellingen als **onveranderlijke wedstrijdsnapshot** opslaan en meesturen naar Dart Score; latere reglementswijzigingen hebben geen terugwerkende kracht. **Deels:** snapshotcontract en verzending geïmplementeerd/getest; onveranderlijkheid na latere reglementswijziging nog expliciet regressietesten.
- [ ] Bestaande wedstrijden en databaseversies veilig migreren; defaults voor ontbrekende velden expliciet vastleggen. **Deels:** Dashboard-migratie van afsluitpunten getest in 04C.1C; overige legacy-wedstrijden en Score-weergave (`TYPE ONBEKEND`) nog onderzoeken.

### 2. Instelbare spelregels
- [x] Singles: X01 = **301 / 501 / 701**, standaard **501**; Best of **3 / 5 / 7 / 9 / 11**, standaard **5**.
- [x] Koppels: X01 = **301 / 501 / 701**, standaard **701**; Best of **3 / 5 / 7 / 9 / 11**, standaard **5**.
- [x] Biergame: X01 = **301 / 501 / 701 / 1001**, standaard **1001**; altijd **één leg**.
- [x] Per groep onafhankelijk **Straight In / Double In** en **Straight Out / Double Out / Master Out**. Master Out: dubbel, triple of inner bull (50); Double Out: dubbel of inner bull (50).
- [x] Double In: punten tellen vanaf en inclusief de eerste geldige dubbel; eerdere darts tellen voor het aantal gegooide darts; drie mislukte openingen = 0 punten.
- [x] Per groep wedstrijdpunten voor winst instelbaar als **positief geheel getal (minimaal 1)**; standaard **1** per gewonnen onderdeel. Gewogen berekening en opslag via 04C.1B/04C.1C/04C.2 getest. Geen competitieklassement/ranglijst bouwen.

### 3. Startregeling
- [x] Per groep afzonderlijk **Thuis begint / Uit begint / Bullstart** instelbaar.
- [x] Bij Thuis/Uit-start geldt voor Singles respectievelijk Koppels een doorlopende afwisseling van eerste-leg-starters: onderdeel 1 start volgens instelling, 2 tegengesteld, 3 volgens instelling, 4 tegengesteld. Biergame volgt eigen instelling.
- [ ] Bij Bullstart wordt **per afzonderlijk onderdeel** gebulld; bullwinnaar begint leg 1.
- [x] Binnen een onderdeel wisselt de legstarter automatisch; bij Singles en Koppels kan een **optionele bull voor de beslissende leg** worden ingesteld. Geen extra beslissende-leg-bull bij Biergame.
- [x] **Definitief besluit 2026-11-07 — Patch 04B.3C (geïmplementeerd en regressiegetest):** vóór **iedere leg** de starter volgens het reglement **voorstellen**, maar de teller mag thuis/uit handmatig kiezen en moet **expliciet bevestigen vóór score-invoer**. Dit vervangt het eerdere besluit om zonder bevestiging automatisch te starten.
- [x] Bij verplichte bull voor een beslissende leg eerst de bullwinnaar vastleggen; die bepaalt de starter. Bevestigde starter duurzaam bewaren, bij herstart niet opnieuw laten bevestigen en na undo/replay correct herstellen.
- [ ] Volledige gecombineerde regressiematrix: leg 1, volgende legs, handmatige afwijking, bull, herstart vóór/na bevestiging, herstart met reeds gegooide beurten, undo en TV-live. **Deels:** starterbevestiging is al regressiegetest; niet alle combinaties/fysieke scenario’s zijn expliciet vastgelegd.

### 4. Opstellingen, verzenden en speelvolgorde
- [x] Vaste sportieve volgorde: **Single 1–4 → Koppel 1–4 → Biergame**. Niet als instelbare volgorde aanbieden.
- [x] De **vier Singles gezamenlijk** definitief verzenden; Koppels **elk afzonderlijk**; Biergame afzonderlijk.
- [x] Captain/appbediener mag **alle onderdelen vooraf indelen en verzenden**, ook Biergame vóór afronding van Koppels. Geen onnodige verzendblokkades op basis van spelfase of vertraagde synchronisatie.
- [x] Voor iedere verzending expliciete waarschuwing/bevestiging: **VERZONDEN = DEFINITIEF**; na verzending geen wijzigingen meer aan die opstelling, ook niet vóór aanvang.
- [x] Niet-verzonden onderdelen blijven aanpasbaar; toegestane wissels gelden uitsluitend voor toekomstige, niet-verzonden onderdelen. Reeds vervangen spelers keren niet terug; invaller neemt de positie over.
- [ ] Singles gebruiken vier vaste basisspelers; geen wissels tijdens Singles. **Deels:** maximaal **8 reserves per team** in Dashboard-databasevalidatie en opstellingsscherm doorgevoerd en getest (04C.1A); complete wissel-/verzendketen nog toetsen.

### 5. Dummy en wedstrijdresultaten
- [ ] Dummy is een afzonderlijke speler met naam **Dummy**; bij drie echte spelers toegestaan als vierde.
- [ ] Dummy in Singles: reglementair verlies zonder darts of individuele statistieken, met legs **2–0 / 3–0 / 4–0 / 5–0 / 6–0** voor respectievelijk Bo3/5/7/9/11. Alleen teamresultaat telt.
- [ ] Dummy tegenover Dummy: een echte speler van elk team bullt om het reglementaire teampunt; geen individuele statistieken.
- [ ] Dummy in Koppels/Biergame: normale rotatie, per Dummy-beurt **0 punten en 3 darts**; Dummy kan niet uitgooien; team-/koppelgemiddelde wordt hierdoor beïnvloed.
- [ ] Geen wedstrijd aanmaken bij slechts twee echte spelers; geen automatische 9–0.
- [x] Teamuitslag berekenen met ingestelde puntgewichten; standaard maximaal **9–0** bij gewicht 1 per onderdeel. Berekening en opslag getest; bij andere gewichten kan de puntensom hoger zijn (04C.1B/04C.2).

### 6. Correctie, afsluiting en testen
- [x] Correctie/undo maximaal **laatste drie beurten**, uitsluitend zolang het betreffende onderdeel nog loopt; na beëindiging van het onderdeel geen correcties meer.
- [x] Sportief afgerond bij negen definitieve resultaten; **alleen Dashboard** mag daarna na volledige synchronisatie de wedstrijd administratief afsluiten en vergrendelen. **Fysiek 2026-11-11:** 9/9 resultaten, eindstand 9–0, beveiligde `MATCH_LOCKED`-ACK en Dashboard-status na herstart bevestigd; overige afwijkende scenario’s blijven in regressieplanning.
- [ ] Unit- en regressietests voor alle X01/Bo-combinaties, in/out, startafwisseling, bull, puntweging, Dummy, verzendvergrendeling, wissels, wedstrijdsnapshot en migraties.
- [ ] Integratietests Dashboard → Dart Score → Dashboard en Live Receiver volledig afronden; **deels:** Dashboard ↔ Score negen-onderdelenretour en MATCH_LOCKED fysiek geslaagd (2026-11-11), Score → TV eerder fysiek bevestigd; volledige gecombineerde TV-/offline-/foutscenario-regressie nog open.
- [ ] Definitieve C1B11-releasecontrole op echte Android-apparaten uitvoeren, inclusief `flutter analyze`, `flutter test`, `git diff --check` en gecontroleerd committen/pushen. **Deels:** eerdere fysieke tests en de actuele Dashboard-/Score-testsuites zijn groen.

### 7. Uitvoering in stappen
- [x] **Stap 1:** actuele Dashboard- en Dart Score-broncode inventariseren: bestaande modellen, opslag, protocol, schermen en tests (broncodeversies van 2026-11-09 voor 04C.3 gebruikt).
- [ ] **Stap 2:** reglementmodel, validatie, defaults, migratie en wedstrijdsnapshot in Dashboard. **Grotendeels gereed:** contracten en migratieonderdelen getest; resterende legacy-/snapshotregressie in §1.
- [ ] **Stap 3:** reglementscherm en definitieve verzendbevestigingen in Dashboard. **Deels:** reglementscherm fysiek bevestigd; alle definitieve verzendbevestigingen nog afzonderlijk nalopen.
- [ ] **Stap 4:** protocoluitbreiding en Score-engine voor X01, in/out, starters, Bo en Dummy. **Deels:** starterbevestiging en diverse regels getest; volledige combinatie-/Dummy-matrix nog open.
- [ ] **Stap 5:** end-to-end-regressie en fysieke tests; documentatie en TODO actualiseren.


## C1B11 — Patchregistratie en eerstvolgende werkzaamheden (2026-11-09)

### Afgerond en vastgelegd
- [x] **04B.3C — Starterbevestiging per leg:** Score-commit `53ece61`, 1049 tests groen; handmatige bevestiging vóór score-invoer, persistente starterstatus en beslissende-leg-bull-regels in regressiescope.
- [x] **04C.1A–C — Dashboard-reglement, 8 reserves, gewogen punten en migratie:** commit `a85ef3b`; 156 tests groen na deze reeks.
- [x] **04C.2 — Negen-resultatenafsluiting:** commit `9db59ea`; 158 tests groen. Test: 8 resultaten blokkeren; 9 afsluiten; puntweging; herhaalde afsluiting; `MATCH_LOCKED`-outbox en persistente uitslag.
- [x] **04C.3A — HTTP-resultaatontvanger, afwijzingspaden:** commit `bf602ae`; 160 tests groen. Onbekende wedstrijd geeft 409 en ongeldige resultaat-ID 400, zonder valse ACK. Flutter-HTTP-testbinding is voor deze lokale servertests correct behandeld; geen productiecode of dependency toegevoegd.

### 04C.3B — succesvolle ontvangst en herstel (historische planning; stand 2026-11-12 hieronder)

**Historische statuscorrectie 2026-11-09:** destijds waren deze taken nog niet aangetoond. **Nieuwe stand 2026-11-12:** reguliere fysieke keten en veilige afsluiting zijn inmiddels aangetoond; foutinjectie, conflicten, hertransmissie en alle herstartscenario’s niet afzonderlijk bewezen.

- [x] Geldige **Single 501**, **Koppel 701** en **Biergame 1001** via de echte ontvangstservice verwerken en duurzaam opslaan; 9/9 fysiek terugontvangen en na Dashboard-herstart aanwezig.
- [ ] ACK uitsluitend na succesvolle databaseverwerking; geen ACK bij transactiefout.
- [ ] Exact dezelfde resultaat-ID/payload opnieuw aanbieden: idempotent gedrag, geen dubbele resultaten of statistieken.
- [ ] Verloren ACK en herhaalde verzending na wifi-uitval/reconnect: geen verlies of dubbeltelling.
- [ ] Conflicterende payload bij bestaande resultaat-ID expliciet afwijzen of volgens vastgelegd contract afhandelen.
- [ ] Resultaten en ontvangststatus na Dashboard-/Score-herstart behouden. **Deels:** Dashboard-afsluiting/ACK na herstart bevestigd en Score-archief na herstart zichtbaar; volledige afzonderlijke ontvangst-/retry-matrix nog open.
- [x] Volledige reguliere keten van 9 resultaten via synchronisatie tot Dashboard-afsluiting en `MATCH_LOCKED`-verwerking fysiek aangetoond (Steady – Testteam, 9–0, 2026-11-11). Dit dekt niet alle fout-/offlinevarianten.
- [ ] Testresultaten, analyzer en Git-status vastleggen; afzonderlijke patch committen/pushen na groen resultaat.

### Aandachtspunten voor afronding C1B11
- [x] **Gebruiker bevestigt:** laatst gebruikte reglementinstellingen komen bij nieuwe wedstrijd terug. **Aanvullend:** regressietest voor opslaan/heropenen kan nog worden toegevoegd.
- [ ] Snapshot blijft ongewijzigd na aanpassen van het bronreglement; oudere databases migreren correct.
- [ ] Alle speltypen en combinaties (X01, Bo, in/out, bull, Dummy, wissels) end-to-end verifiëren.
- [ ] Definitieve verzendbevestiging en vergrendeling per Singles-/Koppels-/Biergame-opstelling fysiek nalopen.
- [ ] Verwijder-/correctieregels na beëindiging van een onderdeel expliciet testen; niet verwarren met het kunnen corrigeren van de laatste beurt tijdens een lopend onderdeel.
- [ ] **C1B12 pas starten nadat C1B11 functioneel is afgerond** en de test-/migratierisico's zijn beoordeeld.


### Afstemming van gebruikersvinkjes (2026-11-09)
- [ ] **C1B7 registratie-intrekking:** gebruiker geeft aan getest; verifiëren of receiver-side intrekking daadwerkelijk is geïmplementeerd, zodat het tegenstrijdige restpunt kan verdwijnen.
- [x] **C1B11 §6 reguliere negen-onderdelen-retourketen:** op 2026-11-11 fysiek bevestigd; volledige fout-/offline-/TV-regressie blijft apart open.
- [ ] **C1B11 04C.3B:** reguliere ontvangst en 9/9-MATCH_LOCKED-keten fysiek bevestigd; resterende fout-/retry-/conflictgevallen afzonderlijk bewijzen.
- [ ] **C1B11 overige gebruikersvinkjes:** bij de volgende fysieke testronde eventueel testdatum, apparaat en scenario toevoegen voor traceerbaarheid.


## Fysieke keten en competitiearchief — 2026-11-11/12 (C1B11)

- [x] **Wedstrijd Steady – Testteam** (`F2C6513F`; volledige ID op apparaat): 4 singles 501, 4 koppels 701 en 1 biergame 1001 gespeeld; Dashboard ontving **9/9** en berekende **9–0**.
- [x] **Definitieve afsluiting:** alleen Dashboard sloot af; `MATCH_LOCKED` veilig aan Dart Score verzonden en beveiligde ACK door Dashboard bevestigd. Na herstart Dashboard bleef `DEFINITIEF AFGESLOTEN · 9–0` met ACK zichtbaar.
- [x] **Competitiearchief Patch 01 op Score-tablet:** keuze **Actief / Afgesloten**; twee afgesloten Steady–Testteam-wedstrijden zichtbaar; alle vier singles, vier koppels en biergame met historische uitslagen aanwezig. Groene, afgeronde onderdelen niet selecteerbaar (read-only).
- [x] **Technische controle Score na Patch 01:** `flutter test --no-pub` **1054 tests geslaagd**; `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` **44 info, geen errors/warnings**; `git diff --check` schoon. Dit is nog **niet gecommit/gepusht** in deze registratie.
- [ ] **Laatste archief-verwijderregressie:** vanuit Dashboard een afzonderlijke, veilig te verwijderen **testwedstrijd** verwijderen; bevestigen dat die niet meer in Score onder **Actief** of **Afgesloten** staat. Bestaande C1B9-verwijderketen was eerder fysiek geslaagd; deze nieuwe archiefweergave nog niet apart gecontroleerd. **Niet** de geslaagde 9–0-referentiewedstrijd verwijderen.
- [ ] **Statistiekkeuze bij verwijderen:** Dashboard-keuze RETAIN versus REMOVE blijft leidend; archief mag geen verwijderde wedstrijd tonen, ongeacht keuze. Test afzonderlijk dat RETAIN statistieken bewaart en REMOVE statistieken verwijdert; geen nieuwe verwijderlogica bouwen.
- [ ] **Legacy-weergave:** tweede afgesloten wedstrijd toont `TYPE ONBEKEND`; oude metadata/migratie onderzoeken zonder gegevens te verliezen.
- [ ] **Commit/push:** na archief-verwijdercontrole TODO en wijzigingen in Score gecontroleerd stagen, committen en pushen; working tree controleren.

## C1B12 — Beperking tot Dashboard-gestuurde wedstrijden en opschonen lokale spellen

**Status:** scopebesluit vastgesteld; inventarisatie en uitvoering nog open. **Planning:** na functionele afronding van C1B11.  
**Architectuurreferentie:** B74-ARCH-SCOPE-001 (zie architectuurprincipes v1.2).

**Definitieve scope:** B74 Dart Score is uitsluitend bedoeld voor het ontvangen, spelen, lokaal duurzaam vastleggen en synchroniseren van wedstrijden die door B74 Competition Dashboard zijn aangemaakt en uitgegeven. Dart Score mag geen zelfstandige wedstrijd of spel starten.

- [ ] Inventariseer alle lokaal startbare spelvormen, waaronder Cricket, losse Single 501, overige X01-spellen, trainings-/oefenmodi en bijbehorende navigatie, afhankelijkheden en tests; verwijder alleen daadwerkelijk aanwezige onderdelen.
- [ ] Verwijder de mogelijkheid om zonder geldige Dashboard-wedstrijdopdracht een spel of wedstrijd aan te maken of te starten; handhaaf validatie ook buiten de UI.
- [ ] Verwijder overbodige lokale spelkeuze, schermen, spelgebonden services, modellen en tests nadat afhankelijkheden zijn onderzocht; voorkom dode code.
- [ ] Behoud de herbruikbare X01-score-engine, configureerbare in/out- en checkoutregels, starters, rotatie, correctie/undo en statistieken die voor Dashboard-wedstrijden nodig zijn.
- [ ] Behoud duurzame lokale wedstrijdopslag, hervatten na app-herstart of netwerkuitval, idempotente synchronisatie, ACK/retry en beveiligde Dashboard-koppeling.
- [ ] Behoud de read-only Live Receiver-koppeling, TV-statistieken en bestaande beveiliging; voorkom ongewenste wijzigingen in de transportlaag.
- [ ] Inventariseer bestaande lokale spelgegevens en databaseverwijzingen; bepaal expliciet of migratie, behoud, archivering of gecontroleerde verwijdering nodig is. Geen impliciet dataverlies.
- [ ] Controleer dat ontvangen Singles, Koppels en Biergame volgens het wedstrijdsnapshot functioneren, ook wanneer tijdelijk offline wordt gescoord.
- [ ] Werk gebruikersinterface, documentatie, tests en eventuele release-/licentieteksten bij zodat geen zelfstandige spelmodus wordt beloofd.
- [ ] Voer unit-, migratie-, regressie- en fysieke end-to-end-tests uit (Dashboard → Dart Score → Dashboard en Live Receiver), inclusief offline/herstart.
- [ ] `flutter analyze --no-pub`, `flutter test --no-pub`, `git diff --check`; pas na expliciet akkoord committen/pushen.

**Ontwerpafspraak:** de huidige productscope beperken zonder de technische kern kunstmatig te versmallen. Een toekomstige zelfstandige spelmodus of aparte app vereist een nieuw expliciet scope-/architectuurbesluit; wordt nu niet vooruit gebouwd.

## Later — testgegevens gecontroleerd opschonen
- [ ] **Niet nu uitvoeren.** Eerst backup/inventarisatie van wedstrijden, spelers, teams, competities en statistieken; daarna gecontroleerd alle testdata wissen voor een schone start.

## Historische voortgang sinds TODO-versie (2026-11-06)

- [x] C1B11 Dart Score checkoutregels: `matchRules`-verwerking en stabielere synchronisatietest vastgelegd in commit `16abaf6` op `feature/c1b3-singles-sync`.
- [x] Dart Score: volledige testsuite **990/990 geslaagd** na verwijderen tijdelijke diagnosecode; `git status --short` schoon na push.
- [x] Actuele Dashboard-/Score-broncode opnieuw geïnventariseerd voor Patch 04C.3 (2026-11-09); resterende taken staan expliciet in C1B11 en onderstaande patchregistratie.


## Fysieke integratietest — 2026-11-07 (historische momentopname; C1B11 / C1B7)

- [x] Actuele Dashboard-debugbuild op Samsung S25 (Android 17) geïnstalleerd en gestart.
- [x] Actuele Dart Score-debugbuild op Samsung SM-X135F (Android 16) geïnstalleerd en gestart.
- [x] Live Receiver-debugbuild op Pro14 GD Android TV (Android 14) geïnstalleerd en gestart; EGL schakelt terug naar OpenGLES.
- [x] Dashboard toont afzonderlijke reglementen voor Regulier en Beker, met X01, Best of, check-in/out, starterbeleid en punten.
- [x] Reguliere testwedstrijd Steady–Testteam aangemaakt, code `7F72BC2C`; singlesopstellingen vastgezet bij START SINGLES.
- [x] Dashboard → Score: vier singles overgedragen, ontvangst bevestigd; 501/Bo5, Straight In/Double Out en voorgestelde starter 'Uit begint' zichtbaar.
- [x] Score → Live Receiver: QR/WSS-koppeling en live score-/statistiekweergave op TV praktisch bevestigd.
- [x] Starterafwisseling werkt in praktijk: Jan leg 1, Jair leg 2.
- [x] **Historische afwijking 2026-11-07:** teller kon starter niet wijzigen/bevestigen. **Hersteld in Patch 04B.3C**, commit `53ece61`; regressietests groen. Nieuwe fysieke controle op alle speltypen blijft zinvol.
- [x] **Dashboard-limiet reserves:** maximaal 8 reserves per team in validatie en UI doorgevoerd in 04C.1A. **Let op:** aantal reserves is niet automatisch gelijk aan aantal toegestane wissels; aparte wisselregel en fysieke UI-controle blijven open (§4).
- [ ] Oudere Score-wedstrijden tonen 'TYPE ONBEKEND'; migratie/legacy-weergave apart onderzoeken.
- [x] **Latere opvolging 2026-11-11/12:** reguliere negen onderdelen (inclusief koppels/biergame), resultaatretour, Dashboard-eindafsluiting en MATCH_LOCKED fysiek bevestigd; offline-/foutscenario’s, afwijkende snapshots en exacte TV-statistieken blijven afzonderlijk te toetsen.
- [x] Laatste vóór fysieke test gemelde regressiestand: Dart Score **1049** tests; Dashboard **150** tests; Score analyzer **39 info**, `git diff --check` schoon. Deze aantallen zijn geen nieuwe testuitvoering na 04B.3C.
