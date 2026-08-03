---
title: "Recepten voor getypeerde queries"
description: "Voer nieuwe of gecachte Health.md-query's uit voor meetwaarden, slaap, training, work-outs, dekking, periodevergelijkingen en bewijs, met expliciete paginering en ontbrekende gegevens."
---

De CLI-opdrachten op hoog niveau zetten veelvoorkomende vragen over gezondheidsgegevens om in vaste, getypeerde querybewerkingen. Standaard halen ze de gevraagde iPhone-gegevens op, bevragen ze de versleutelde context op de Mac en geven ze JSON met versiebeheer, bewijs en dekking terug.

Gebruik in plaats daarvan [canonieke extractie](/nl/docs/cli-extract/) als je volledige dagen volgens `healthmd.health_data` of bronrecords nodig hebt.

## Gereedheid controleren en meetwaarden vinden

```bash
healthmd doctor
healthmd metrics list
healthmd metrics list --category Sleep
```

De meetwaardecatalogus geeft canonieke ID's, weergavenamen, categorieën, eenheden en beschikbaarheidsvereisten terug. De catalogus beweert niet dat HealthKit-toegang voor een meetwaarde is verleend.

Kopieer ID's uit de catalogus in plaats van ze te raden.

## Reeksen meetwaarden opvragen

```bash
healthmd query \
  --metric sleep_total \
  --metric sleep_deep \
  --from 2026-07-01 --to 2026-07-14 \
  --all-pages
```

Categorieën worden uitgebreid aan de hand van de huidige catalogus:

```bash
healthmd query --category Sleep --yesterday
healthmd query --category Heart --last 30 --all-pages
```

Meerdere flags voor meetwaarden en categorieën worden gecombineerd. Bij een nieuwe gegevensophaling stuurt Health.md de uitgebreide selectie naar de iPhone zonder opgeslagen exportinstellingen te wijzigen.

Het antwoord gebruikt een envelop volgens `healthmd.cli_metric_query` v1. Diagnostiek van de gegevensophaling blijft naast het geneste getypeerde queryantwoord staan.

## Nieuw, uit de cache of met hergebruikte dekking

Nieuwe gegevens ophalen is de standaard:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Hiermee vraagt Health.md het exacte bereik op bij de verbonden iPhone, legt bijgewerkte versleutelde eigenaarsdagen vast en bevraagt deze daarna.

De cachemodus maakt geen verbinding met de iPhone:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Gebruik de cachemodus alleen voor offline analyse als het opgeslagen vastleggingstijdstip en de dekking volstaan.

`--reuse-covered` controleert eerst de versleutelde dekking van samenvattingen:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Health.md slaat de gegevensophaling alleen over als elke gevraagde meetwaarde en dag volledige, compatibele samenvattingsdekking heeft. Verliesvrije verzoeken en nieuw berekende bewerkingen voor slaapsessies gebruiken deze verkorte route niet.

## Voltooiingsvelden begrijpen

Antwoorden op nieuwe query's maken onderscheid tussen drie begrippen:

| Veld | Beantwoorde vraag |
|---|---|
| `requested_scope_status` | Is elke gevraagde meetwaarde, bron, provider en eigenaarsdag tijdens deze gegevensophaling voltooid? |
| `corpus_status` | Hebben andere vertakkingen in het vastgelegde corpus waarschuwingen, overgeslagen onderdelen of fouten gemeld? |
| `unrelated_skips` | Welke overgeslagen of niet-ondersteunde vertakkingen vielen buiten het gevraagde bereik? |

Een volledig voltooid gevraagd bereik kan samengaan met niet-gerelateerde overgeslagen onderdelen in het corpus. Health.md behoudt beide feiten. Het verlaagt het gevraagde resultaat niet ten onrechte en verbergt de corpusdiagnostiek evenmin.

Bij nieuw werk tellen voor voltooiing alleen blobs mee die zijn vervangen nadat de verversing begon. Verouderde cachewaarden kunnen een mislukt verzoek niet alsnog laten slagen.

## Door resultaten bladeren

Zonder `--all-pages` geeft de opdracht één afgebakende pagina terug. Controleer `next_cursor`:

```bash
healthmd query --category Activity --last 365 --output activity-page-1.json
jq '.query.next_cursor' activity-page-1.json
```

Een cursor die niet null is, betekent dat er meer resultaten zijn. De buitenste status op hoog niveau blijft `partial_success` totdat de volledige doorloop is voltooid.

Automatische doorloop volgt ondoorzichtige cursors en controleert op herhaling:

```bash
healthmd query --category Activity --last 365 \
  --all-pages --output activity-all-pages.json
```

Het antwoord bewaart de eerste `healthmd.query_response` onder `query`, latere antwoorden met versiebeheer onder `pages` en een `healthmd.cli_query_receipt` v1. Dat ontvangstbewijs bevat aantallen pagina's, items, feiten en bewijsstukken, plus de eindstatus van de doorloop.

Automatische doorloop heeft een totale grens voor pagina's en bytes. Wordt die bereikt, verklein dan de datum- of meetwaardeselectie of gebruik de [laag-niveau-API](/nl/docs/agent-api/) om handmatig te pagineren.

## Voortgang en tabeluitvoer

Schrijf fasen zonder gezondheidsgegevens en paginavoortgang als JSONL naar stderr:

```bash
healthmd query --category Sleep --last 90 \
  --all-pages --progress-json --output sleep.json \
  2> sleep-progress.jsonl
```

JSON is de volledige uitvoer. De tabelmodus is een optionele TSV-weergave met informatieverlies voor iemand die in een terminal werkt:

```bash
healthmd query --metric resting_heart_rate --last 30 --format table
```

De voettekst van de tabel behoudt notities over dekking, bron, beperkingen, voltooiing en niet-gerelateerde overgeslagen onderdelen. Gebruik geen tabeluitvoer als een script exacte getypeerde waarden of bewijs nodig heeft.

## Slaapsessies

Slaapfasen uit Apple Health kunnen over middernacht lopen en elkaar per bron overlappen. De slaapopdracht bouwt stabiele sessies in plaats van elke eigenaarsdag als één numeriek totaal te behandelen.

```bash
healthmd sleep sessions --last-nights 14
healthmd sleep sessions --last-nights 14 --include-naps
healthmd sleep sessions --last-nights 14 \
  --window first:4h --physiology-metric heart_rate
```

Exacte datums en selectie van de volledige geschiedenis zijn ook beschikbaar:

```bash
healthmd sleep sessions \
  --from 2026-07-01 --to 2026-07-14 \
  --window first:3h --all-pages

healthmd sleep sessions --all --all-pages
```

Elke sessie kan het volgende melden:

- een stabiele sessie-identiteit;
- de eigenaarsdatum en lokale tijdzone;
- exacte lokale en UTC-tijdstempels voor begin en einde;
- de classificatie als nachtslaap of dutje;
- geselecteerde totalen per slaapfase;
- waargenomen en niet-bijgehouden duur;
- volledigheid en uitsluitingen;
- een vast venster ten opzichte van de sessie;
- dekking van fysiologische gegevens op aangrenzende dagen;
- bronbewijs.

Voor gegevensophaling van sessies vraagt Health.md verliesvrije canonieke slaapfase-intervallen en de volledige canonieke set met slaapfasemeetwaarden op. De app leest maximaal één technische aangrenzende eigenaarsdag voor de grenzen en sluit niet-gerelateerde datums daarna uit van het resultaat.

Overlappende bronnen voor slaapfasen worden ontdubbeld bij de berekening van de totale slaapduur. Alleen geaggregeerde cachecontext krijgt het label `aggregated`; deze claimt geen dekking van waargenomen intervallen. Een vast venster `first:4h` verdeelt een dagelijks totaal nooit over vier uur.

## Work-outs en slaap op elkaar afstemmen

```bash
healthmd training align --last 14
healthmd training align --last 14 --workout running
healthmd training align --last 14 --workout running \
  --sleep-window first:4h \
  --physiology-metric heart_rate \
  --all-pages
```

Voor elke geselecteerde work-out zoekt Health.md de dichtstbijzijnde geschikte slaapsessie ervoor en erna binnen 36 uur. De uitvoer vermeldt:

- stabiele ID's van work-outs en sessies;
- exacte tussenpozen;
- gevraagde slaapvensters;
- aantallen fysiologische metingen;
- dekking van slaapfasen en sessies;
- bewijs en uitsluitingen.

De bewerking is een deterministische afstemming in de tijd. Ze beweert niet dat een work-out een slaapresultaat veroorzaakte of dat slaap de trainingsprestatie veroorzaakte. Health.md leest maximaal twee technische aangrenzende eigenaarsdagen en geeft geen niet-gerelateerde gegevens terug.

## Work-outs weergeven

```bash
healthmd workouts --yesterday
healthmd workouts --last 14 --all-pages
healthmd workouts \
  --from 2026-07-01 --to 2026-07-31 \
  --format table
```

De lijst met work-outs behoudt stabiele identiteiten, exacte tijdstempels, getypeerde details, bewijs en ontbrekende gegevens. Resultaten zijn gesorteerd op begintijdstempel en stabiele work-outidentiteit. Er is geen vaste limiet voor het totale aantal work-outs; paginabesturing begrenst elk antwoord.

## Dekking

Gebruik dekking wanneer de vraag 'Welke gegevens heb ik?' is en niet 'Wat is de waarde?'

```bash
healthmd coverage --category Sleep --last 30
healthmd coverage \
  --metric steps --metric resting_heart_rate \
  --from 2026-01-01 --to 2026-06-30 \
  --all-pages
```

Dekking geeft het gevraagde en beschikbare bereik, het aantal bekeken dagen, dagen met waarden en ontbrekende intervallen met een status terug. Aangrenzende intervallen met dezelfde status en reden kunnen zonder betekenisverlies worden samengevoegd.

Een dag zonder overeenkomende waarnemingen kan `complete_empty` zijn. Een dag die nooit is gesynchroniseerd heeft een andere status. Geen van beide wordt nul.

## Exacte perioden vergelijken

De CLI raadt nooit of een meetwaarde moet worden opgeteld, gemiddeld, geminimaliseerd, gemaximaliseerd of geteld, of dat de laatste waarde moet worden gekozen. Geef naast elke meetwaarde-ID de aggregatie op:

```bash
healthmd compare \
  --metric steps:sum \
  --metric resting_heart_rate:average \
  --first-from 2026-07-01 --first-to 2026-07-07 \
  --second-from 2026-07-08 --second-to 2026-07-14
```

Ondersteunde aggregaties zijn:

- `sum`
- `average`
- `minimum`
- `maximum`
- `latest`
- `count`
- `duration_sum`

Niet-overeenkomende eenheden of typen leveren een fout op en worden niet ongemerkt gecombineerd. Een ontbrekende periode heeft geen aggregatiewaarde. Als de uitgangswaarde van de eerste periode nul is, bevat het resultaat wel een absolute verandering maar geen procentuele verandering. Ook wordt `zero_baseline` als beperking vermeld.

De richting is feitelijk: `increased`, `decreased`, `unchanged` of `not_comparable`. Dit betekent nooit beter of slechter.

## Bewijsbundels voor training

```bash
healthmd evidence training \
  --category Sleep \
  --metric resting_heart_rate \
  --last 14 \
  --all-pages
```

Vraag alleen specifieke details over work-outs op als je ze nodig hebt:

```bash
healthmd evidence training \
  --category Sleep \
  --workout-detail distance \
  --workout-detail duration \
  --last 14 --all-pages
```

Als je details van work-outs selecteert, vraagt Health.md voor dat verzoek het benodigde verliesvrije bereik op. De bundel bevat feitelijke waarden, dekking, bronbeschrijvingen, bewijslocators en beperkingen.

Bundel-ID's zijn deterministische SHA-256-digests van de semantische inhoud. Als je dezelfde bundel later opnieuw maakt, blijft de semantische ID gelijk, ook als de generatiemetadata verandert.

Soorten bewijsbundels in contract v1 zijn onder meer `daily_wellness`, `training` en `doctor_visit`. De gemaksopdracht op hoog niveau biedt momenteel de trainingsbundel. Gebruik de laag-niveau-API voor exacte verzoekteksten.

## Datumeigendom en tijdzone

Querydatums zijn `owner_date`-waarden uit de compacte context. Elke dag behoudt ook het exacte halfopen UTC-interval en de tijdens de vastlegging gebruikte IANA-kalendertijdzone.

Slaapsessies behouden lokale tijdstempels en datums die over middernacht lopen. Technische uitlezingen van aangrenzende dagen zorgen dat een sessie een grens van een eigenaarsdag kan overschrijden zonder gegevens te verplaatsen op basis van de huidige tijdzone van de Mac.

Vermeld bij een datumgevoelige vraag aan een agent de bedoelde eigenaarsdatums en controleer de teruggegeven tijdzone. Ga niet uit van de tijdzone van de computer.

## Verberg ontbrekende gegevens niet in een agentantwoord

Een veilige samenvatting behoudt:

- de meetwaarde-ID en canonieke eenheid;
- het datumbereik en de tijdzone;
- de modus voor nieuwe gegevens, cachegegevens of hergebruikte dekking;
- de status van het gevraagde bereik en de corpusstatus;
- de voltooiing van de paginadoorloop;
- bewijsverwijzingen of de digest van de bron;
- volledig lege en ontbrekende intervallen;
- waarschuwingen, beperkingen en niet-gerelateerde overgeslagen onderdelen.

Middel mislukte dagen niet weg, behandel afwezigheid niet als nul en beschrijf een afstemming in de tijd niet als oorzakelijk verband.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/agents/"><span>Architectuur</span>Lokale agents en gezondheidscontext: configuratie, versleuteling, verzoekbereik, bewijs en bewaren.</a>
  <a href="/nl/docs/mcp/"><span>MCP</span>Lokaal MCP-hulpprogramma: getypeerde equivalenten voor queries, slaap, afstemming, work-outs, dekking, vergelijkingen en bewijs.</a>
  <a href="/nl/docs/agent-api/"><span>Onbewerkte contracten</span>Loopback-query-API: exacte verzoeken, antwoorden van één pagina, verversing en taakroutes.</a>
  <a href="/nl/docs/reference/evidence-packets/"><span>Referentie</span>Compacte queries en bewijsbundels: getypeerde waarden, cursors, bewerkingen, dekking en ID's.</a>
</div>
