# B74 Dart Competition Platform — TODO richting v1.0

**Datum:** 21 november 2026
**Doel:** uitsluitend resterend werk voor een beheerste publieke v1.0.
**Uitgangspunt:** de functionele MVP-keten is door de eigenaar tijdens doorlopende integrale praktijktests als werkend geaccepteerd. Afgeronde functionaliteit en patches worden niet herhaald in deze TODO; Git en releasehistorie zijn daarvoor de bron.

## Vastgestelde scope

- **Statistieken:** individuele wedstrijdprestaties en historische spelerstatistieken **per bondsnummer**, ook als een speler maar één of twee wedstrijden speelt. Geen minimumaantal deelnames.
- **Niet bouwen:** teamstatistieken, teamranglijsten of competitietussenstanden/klassementen.
- **B74 Online Live:** bestaande publieke read-only weergave van **actuele wedstrijdscoreborden**. Geen afzonderlijk ontwikkelpakket en geen uitbreiding met een competitietussenstand.
- **Identiteit:** bondsnummer is de stabiele spelerssleutel; een naamswijziging mag historische prestaties niet opsplitsen. Definieer apart hoe ontbrekende/ongeldige bondsnummers worden behandeld.
- **Statistiekbewaring:** bestaande RETAIN/REMOVE-beheerderskeuze blijft leidend, onafhankelijk van het verdwijnen van een wedstrijd uit actieve overzichten.

## Gegevensbehoud — bestaande echte competitiewedstrijd

In Dart Score staat één echte competitiewedstrijd met daadwerkelijk geregistreerde statistieken. Niet alle wedstrijdonderdelen zijn geregistreerd of afgewerkt. De exacte afsluit- en synchronisatiestatus moet nog worden vastgesteld.

- [ ] Verifieer de Dashboard-back-up en de afsluit-/synchronisatiestatus. Test herstel van de bestaande Dart Score-back-up op een afzonderlijk Android-testtoestel zodra beschikbaar; niet op het productietoestel. De Dart Score-back-up van 18 november is aanwezig en technisch geïnspecteerd; praktisch herstel is nog niet bewezen.
- [ ] Behoud de echte wedstrijd, brongegevens en statistieken bij upgrades, migraties en tests. Geen reset, uninstall met gegevensverlies of verwijdering van deze wedstrijd.
- [ ] Gebruik een afzonderlijke testdatabase of kopie voor destructieve RETAIN/REMOVE-tests; publiceer geen testgegevens naar productie.

## Werkafspraken

- Alleen nog uit te voeren acties hebben een `[ ]`. Voltooide werkzaamheden staan in Git, niet als historische checklist in deze TODO.
- Eerst samenhangend ontwerp en acceptatiecriteria per pakket; vervolgens implementatie, automatische tests en gerichte acceptatie.
- Behoud de geteste lokale competitievoering, bestaande beveiligde transport-/protocolbasis, synchronisatie, duurzame ACK/retry, offline herstel en archief.
- Repareer alleen aangetoonde fouten; geen ongerichte refactoring of herhaling van al geaccepteerde tests.
- **Geen commits of pushes zonder expliciet akkoord.** Bestaande lokale wijzigingen niet overschrijven of ongemerkt meenemen.
- Functionele MVP-acceptatie is niet gelijk aan goedkeuring voor publieke distributie.

---

## Pakket 1 — Wedstrijd- en spelerstatistieken per bondsnummer

**Opleverresultaat:** een speler kan zijn prestaties uit afzonderlijke wedstrijden én zijn totale historische prestaties terugzien, gekoppeld aan het bondsnummer. Geen team- of competitieaggregaties.

### Vertrekpunt volgende sessie

Statistics Library: `main`, commit **`b3a33e1`** (`origin/main`), schone werkboom en gepusht. Laatste volledige lokale regressie: **385/385 geslaagd** (170 unit, 205 integratie, 10 migratie). **Geen Cloudflare-productiedeployment.** D.5.1 (beheerdersregistratie), D.6.1 (beheerdersstatistieken) en D.6.2 (persoonlijke statistieken) zijn in Git geborgd. Dit bewijst nog geen praktijkacceptatie of productiegeschiktheid. Migraties zijn automatisch getest; toepassing op persistente ontwikkel-/productie-D1 afzonderlijk vaststellen. Start met **gegevensbehoud en ontbrekende statistiekdefinities**, daarna gerichte ketenintegratie. Afgeronde implementaties blijven in Git.

### Vastgestelde ontwerpkeuzes

- Zelfregistratie (optie B): geauthenticeerde speler vraagt toegang aan met naam en bondsnummer; beheerder controleert en keurt expliciet goed. E-mail komt uit de geverifieerde identiteit.
- Technische identiteit: issuer + subject; maximaal één registratie per identiteit en één goedgekeurde identiteit per bondsnummer. Meerdere hangende aanvragen voor hetzelfde bondsnummer toegestaan.
- Statussen PENDING, APPROVED, REJECTED, REVOKED. Alleen APPROVED geeft toegang. Intrekking wijzigt geen wedstrijdstatistieken. Geen zelfwijziging van gekoppeld bondsnummer. Zelfregistratie is toegestaan; wijziging van registratie-identiteit of autorisatie, accountoverdracht en herstel uitsluitend via de beheerder.
- Beoogd hergebruik Cloudflare Access met e-mail/OTP; persoonlijke autorisatie server-side. `GET /api/v1/me/statistics` bepaalt zelf het bondsnummer, niet via een clientparameter.
- Een speler kan zonder registratie statistieken opbouwen. Alleen officiële statistische bijdragen tellen; hetzelfde bondsnummer mag meerdere onderdelen spelen, maar maximaal één bijdrage per onderdeel.

### Resterende statistiekdefinities

- [ ] Inventariseer actuele Dart Score- en Dashboard-bronnen en bestaande lokale projectie-/verwijderimplementatie (Git-status verifiëren); hergebruik bestaande gegevens en tests.
- [ ] Bepaal ontbrekende velden en definities: winst/verlies, legs, finishes, speeldatum (niet publicatiedatum), First 9 met exacte teller/noemer, scorecategorieën en onderscheid per onderdeel. Geen ongewogen gemiddelden of verzonnen ontbrekende waarden.
- [ ] Leg behandeling van ongeldige/ontbrekende bondsnummers, historische gegevens en normalisatie vast; nooit op naam alleen samenvoegen.
- [ ] Beslis wanneer gedeeltelijk gespeelde wedstrijden officieel meetellen; ontbrekende onderdelen mogen geen fictieve resultaten of bijdragen opleveren. Huidig publicatiecontract vereist negen afgeronde onderdelen.
- [ ] Realiseer en test uitsluitend ontbrekende contract-, opslag- en aggregatievelden; bestaande Score-tellerlogica ongemoeid laten.

### 7E.17 — Persoonlijke identiteit en toegang (resterende controles)

De implementaties voor registratiebeheer, beheerdersstatistieken en persoonlijke statistieken zijn lokaal getest en in Git geborgd. De nieuwe persoonlijke route is `GET /api/v1/me/statistics`; deze gebruikt een geverifieerde identiteit en het server-side goedgekeurde bondsnummer. De onderstaande punten zijn **nog openstaande beleids-, omgevings- en acceptatiecontroles**, geen opdracht om de bestaande endpoints opnieuw te bouwen.

- [ ] 7E.17.5 Leg bewaartermijnen, privacybeleid, inzage en beheerprocessen voor registratie- en auditgegevens vast; controleer deze vóór productiegebruik.
- [ ] 7E.17.6 Verifieer Cloudflare Access-geschiktheid en actuele plan-/licentielimieten voor de beoogde productie-inrichting; toets e-mailwijzigingen, issuer/audience-scheiding en toegangsbeleid in de werkelijke omgeving.
- [ ] 7E.17.8 Verifieer migratiestatus van persistente lokale ontwikkel-D1 (inclusief benodigde migraties 0005/0006), maak eerst een back-up en controleer gegevensbehoud. Voer gerichte omgevings- en beveiligingsacceptatie uit waar automatische tests niet volstaan; geen destructieve productietests.

### 7E.18–7E.23 — Ketenintegratie en acceptatie

- [ ] 7E.18 Persoonlijke webinterface: registratie/status, eigen wedstrijdhistorie en details, historische totalen per onderdeel; filters alleen indien nodig. Beheerdersinterface voor aanvragen en besluiten (bestaande API hergebruiken). Geen openbare historische spelersstatistieken.
- [ ] 7E.19 Hergebruik duurzame outbox/ACK, retry, revisies en offline herstel voor publicatie; toets ontbrekende ketenscenario’s.
- [ ] 7E.20 Dart Score-publicatie integreren: rechtstreeks beveiligd naar Statistics Library, expliciete aanbieding na afsluiting volgens vastgesteld beleid; testdivisie en Dummy uitsluiten; echte wedstrijd beschermen.
- [ ] 7E.21 Dashboard RETAIN/REMOVE koppelen aan Statistics Library: RETAIN bewaart bijdragen; REMOVE uitsluitend betreffende wedstrijd met nieuwe bevoegde autorisatie waar vereist. Hergebruik bestaande verwijderketen en bevestigingen; test end-to-end.
- [ ] 7E.22 Cloudflare-productieconfiguratie, D1-migraties, secrets, toegangsbeleid, privacy, back-up en herstel voorbereiden en uitsluitend na expliciet akkoord uitrollen.
- [ ] 7E.23 Vergelijk persoonlijke resultaten met bekende wedstrijden en databasequeries, inclusief sporadische deelname, correcties, ontbrekende gegevens en RETAIN/REMOVE. Gebruik de echte gedeeltelijke wedstrijd uitsluitend read-only als referentie totdat het publicatiebeleid is vastgesteld. Leg pakketacceptatie vast.

**Klaar wanneer:** prestaties per wedstrijd en persoonlijke historie per bondsnummer aantoonbaar correct zijn, ook bij sporadische deelname.

---

## Pakket 2 — Licentieplatform en activatie

**Opleverresultaat:** Android-apps zijn openbaar te downloaden, maar gebruik is alleen mogelijk na persoonlijke, expliciete goedkeuring door Ben van der Veen.

### Ontwerp en beleid
- [ ] Werk de reeds gekozen licentievoorwaarden uit en laat deze vóór publicatie juridisch toetsen: gratis na goedkeuring voor niet-commercieel amateur-/verenigingsgebruik; commercieel gebruik uitsluitend na afzonderlijke toestemming/afspraak.
- [ ] Leg per app en installatie de licentiescope vast voor Competition Dashboard, Dart Score en Live Receiver; bepaal of Online Live onderdeel van de bijbehorende goedkeuring is.
- [ ] Ontwerp aanvraag, persoonlijke beoordeling, goedkeuring/weigering, uitgifte, verlenging en audittrail met organisatie, beoogd gebruik en aantal banen/installaties.
- [ ] Ontwerp installatie-/apparaatgebonden activatie, toestelwissel, herinstallatie, verloop en intrekking, met bescherming tegen kopiëren van activaties.
- [ ] Leg het offline beleid en herstelgedrag vast: goedgekeurde lokale competitievoering mag niet afhankelijk worden van voortdurend internet; specificeer veilig gedrag bij verlopen/ingetrokken licenties.
- [ ] Werk privacy, beveiliging van licentiegegevens en herstel bij apparaatverlies uit.

### Realisatie en acceptatie
- [ ] Bouw aanvraag, beheerdersgoedkeuring, licentie-uitgifte en verificatie bij eerste gebruik.
- [ ] Integreer activatie in de betrokken Android-apps zonder de lokale Score-/TV-/Dashboard-keten te verstoren.
- [ ] Test goedkeuring, weigering, tweede toestel, herinstallatie, offline gebruik, verloop, intrekking en herstel.

**Klaar wanneer:** ongeautoriseerd gebruik wordt geblokkeerd en een goedgekeurde wedstrijd offline kan doorgaan volgens het vastgestelde beleid.

---

## Pakket 3 — Release, distributie en documentatie (C1B10)

**Opleverresultaat:** reproduceerbare, veilig te installeren en te actualiseren Android-releases voor de beoogde apparaten.

### Voorbereiding
- [ ] Leg app-identiteiten, versies, ondersteunde apparaten en compatibiliteit vast voor S25, Score-tablets en Android TV-box.
- [ ] Richt ondertekende releasebuilds in; bescherm signing keys en beschrijf herstel en terugrol.
- [ ] Richt Google Play-distributie voor geschikte Android-apps in, inclusief `.aab`, winkelteksten en vereiste verklaringen.
- [ ] Kies en test de distributie- en updateroute voor Live Receiver op Android TV.
- [ ] Test migratie van database, instellingen, wedstrijden, archief, koppelingen en licentiestatus bij upgrades.
- [ ] Maak compacte installatie-, koppel- en licentie-instructies, gebruiksvoorwaarden en release notes.

### Acceptatie en uitgifte
- [ ] Maak definitieve releasekandidaten en voer daarop automatische tests, analyzer en Git-/buildcontroles uit.
- [ ] Controleer nieuwe installatie, update, offline starten, activatie en herstel op de ondersteunde apparaten.
- [ ] Controleer productieconfiguratie en distributie-instellingen vóór publicatie.
- [ ] Vraag expliciete finale vrijgave van de eigenaar voor publicatie.

**Klaar wanneer:** de goedgekeurde Android-apps veilig geïnstalleerd, geactiveerd en bijgewerkt kunnen worden.

---

## Gezamenlijke releaseacceptatie — geen extra bouwpakket

De doorlopende integrale praktijktests van de bestaande wedstrijdketen zijn **functioneel geaccepteerd** en worden niet opnieuw als open bouwtaak opgevoerd. Voor de **definitieve releaseversies** resteert uitsluitend een gerichte vrijgavecontrole:

- [ ] Verifieer risicogericht nog niet aantoonbaar afgedekte foutscenario's (verloren ACK, dubbele/conflicterende berichten, herstart en herstel), zonder reeds bewezen scenario's blind te herhalen.
- [ ] Verifieer RETAIN/REMOVE en de statistische bijdragen per bondsnummer met gerichte databasequeries, inclusief historische en verwijderde wedstrijden.
- [ ] Controleer op de definitieve builds TV-koppeling, credential-verloop/intrekking, reconnect en de publicatie-/intrekkingsgrenzen van Online Live; herstel alleen aantoonbare afwijkingen.
- [ ] Test onafhankelijke Online Live-publicatie tijdens uitsluitend uitval van de TV-verbinding; controleer of de singles-providerlistener actief blijft en herstel alleen een aangetoonde afwijking.
- [ ] Test baan 2 integraal, inclusief onafhankelijke publicatie en gelijktijdig gebruik van beide banen; controleer de huidige hardcoded baan 1 in Dart Score en realiseer uitsluitend de benodigde baantoewijzing.
- [ ] Beoordeel resterende bekende afwijkingen uitsluitend op release-impact (zoals TV-IP-wijziging, incidentele vertraging, Dummy-winnaarlabel en `TYPE ONBEKEND`).
- [ ] Maak vóór productiestart een back-up en inventarisatie; verwijder testgegevens uitsluitend na afzonderlijk expliciet akkoord. Sluit de echte competitiewedstrijd en haar statistieken expliciet uit van opschoning.
- [ ] Leg geteste versies, uitkomsten, bekende beperkingen en definitieve vrijgave vast.

## Uitvoeringsvolgorde

0. **Gegevensbehoud:** resterende back-up-, inventarisatie- en herstelcontroles; geen destructieve tests op productie.
1. **Pakket 1:** resterende statistiekdefinities en broninventarisatie, daarna 7E.19–7E.21 ketenintegratie, 7E.18 webinterfaces, 7E.17 resterende beleids-/omgevingscontroles, 7E.22 productievoorbereiding en 7E.23 gerichte acceptatie. Geen deployment zonder expliciet akkoord.
2. **Pakket 2:** licentieplatform en activatie realiseren.
3. **Pakket 3:** Android-distributie, documentatie en releasekandidaten afronden.
4. **Gezamenlijke releaseacceptatie:** resterende risico's controleren en expliciet vrijgeven.

**Architectuurkaders:** B74-ARCH-MSG-001 v1.1 en B74-ARCH-SCOPE-001. Bestaande Dashboard-gestuurde wedstrijdvoering, lokale duurzaamheid, beveiligde synchronisatie, archief, Live Receiver en Online Live blijven behouden.
