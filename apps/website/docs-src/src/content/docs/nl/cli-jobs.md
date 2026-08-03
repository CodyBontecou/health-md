---
title: "Persistente CLI-taken en automatisering"
description: "Automatiseer healthmd veilig met machineleesbare uitvoer, afgebakende wachttijden, persistente taken van zeven dagen, expliciete gedeeltelijke statussen, hervatten en bevestigde annulering."
---

Health.md behandelt verbonden exports en het ophalen van context als persistente taken. De levensduur van de taak staat los van het proces dat de taak startte. Een terminal kan sluiten of een netwerkverbinding kan wegvallen zonder dat voltooide partities verloren gaan.

Deze pagina geldt voor bestandsexports, strikte onbewerkte exports, canonieke extractie en het opnieuw ophalen van versleutelde context, tenzij bij een opdracht een beperktere regel staat.

## De hoofdregel

Een time-out of verbroken verbinding betekent niet dat de taak is geannuleerd.

Start na een onbekende uitkomst geen duplicaat. Bewaar de teruggegeven taak-ID, controleer de status en hervat dezelfde taak.

Export-, onbewerkte en extractietaken gebruiken de levenscyclusopdrachten op het hoogste niveau:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Taken voor het ophalen van versleutelde context gebruiken de lokale agentlevenscyclus:

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
```

## Levensduur van zeven dagen

Een persistente taak heeft een vaste `expires_at`, zeven dagen na het aanmaken. Voortgang verlengt die termijn niet. Beide peers bewaren het onveranderlijke verzoek en voldoende vastgelegde overdrachtsstatus om de taak veilig te hervatten.

Een taak kan het volgende bewaren:

- exacte datums of opgeloste ID's voor de volledige geschiedenis;
- het bereik van meetwaarden, categorieën, bronnen en details;
- binding aan de backend en het gekoppelde apparaat;
- instellingenbeleid;
- het profiel voor onbewerkte gegevens of de extractieselectie;
- de identiteit van de bestandsbestemming;
- de vingerafdruk van het verzoek;
- sessie- en overdrachtsmanifesten;
- de digestketen van partities;
- het voortgangspunt voor vastgelegde partities en bytes;
- bevestiging van voltooiing of annulering.

Bij hervatten kan geen van deze velden opnieuw worden geïnterpreteerd.

## Meer statussen dan alleen actief of voltooid

Een taakantwoord kan deze velden bevatten:

| Veld | Betekenis |
|---|---|
| `durable` | Of de bewerking een herstelbare taakstatus heeft |
| `state` | Huidige status in de persistente levenscyclus |
| `job_id` | Stabiele taak-ID |
| `session_id` | ID van de gebonden overdrachtssessie |
| `paused` | Of dezelfde iPhone opnieuw verbinding moet maken |
| `processed_days` / `total_days` | Logische voortgang in eigenaarsdagen |
| `committed_partitions` | Partities waarvan de ontvanger de blijvende opslag heeft bevestigd |
| `committed_bytes` | Payloadbytes die veilig zijn vastgelegd |
| `fraction_complete` | Voortgangsfractie zonder gezondheidsgegevens |
| `expires_at` | Vast tijdstempel waarop de taak verloopt |

Statusvelden bevatten datums, ID's, aantallen, bytes en veilige fouten. Ze horen geen gezondheidsmetingen te bevatten.

## Een taak starten met een expliciet uitvoerplan

Onbewerkte export:

```bash
healthmd export --iphone --last 30 --raw \
  --output health-month.json
```

Canonieke extractie:

```bash
healthmd extract --category Sleep --last 30 \
  --output sleep-month.json
```

Rechtstreeks gegenereerde bestanden:

```bash
healthmd --backend direct export --last 30 \
  --destination "$HOME/Documents/HealthVault"
```

Kies de definitieve uitvoer of bestemming voordat het verzoek start. Een onbewerkte taak bindt het uitvoergedrag. Een rechtstreekse bestandstaak bindt de exacte hoofdmap van de bestemming aan het onveranderlijke verzoek.

## Hervatten

```bash
healthmd resume JOB_UUID --timeout 300
healthmd resume JOB_UUID --output recovered.json
healthmd resume JOB_UUID --output recovered.json --allow-partial
```

Selecteer voor de rechtstreekse modus dezelfde backend, hetzelfde apparaat, transport, dezelfde poort en iPhone als bij het oorspronkelijke verzoek:

```bash
healthmd --backend direct --device DEVICE_UUID \
  --transport manual-ip --port 17647 \
  resume JOB_UUID --timeout 300 --output recovered.json
```

Bytes die nog niet zijn vastgelegd, kunnen na een verbroken verbinding worden weggegooid. Vastgelegde partities worden niet opnieuw verstuurd of geïnterpreteerd. De ontvanger accepteert een al vastgelegde partitie alleen als elke onveranderlijke beschrijving overeenkomt.

Een bestandstaak accepteert tijdens hervatten geen andere bestemming. Als de oorspronkelijke hoofdmap is veranderd, weigert Health.md veilig verder te gaan in plaats van naar een andere map te schrijven.

## Annuleren

Gebruik de levenscyclus waarmee de taak is aangemaakt:

```bash
# Export, raw, or extraction
healthmd cancel JOB_UUID

# Encrypted-context acquisition
healthmd agent job cancel JOB_UUID
```

Annulering bestaat uit twee fasen:

1. de CLI legt een blijvend annuleringsverzoek vast en verstuurt dit;
2. de iPhone bevestigt de annulering, waarna deze definitief is.

Als de iPhone niet beschikbaar is, blijft de taak `cancellation_pending`. Open dezelfde iPhone opnieuw en probeer de annulering nogmaals. Meld een taak niet als geannuleerd op basis van alleen de lokale intentie.

Een proces dat Ctrl-C ontvangt, hoort af te sluiten zonder een definitieve annulering te verzinnen. Gebruik de expliciete annuleringsopdracht als je werkelijk wilt annuleren.

## Uitvoerkanalen

Health.md houdt opdrachtresultaten en voortgang gescheiden:

| Kanaal | Inhoud |
|---|---|
| stdout | Opdrachtresultaat of fout als JSON met versiebeheer, of de gevraagde JSON/JSONL-stroom |
| stderr | Gewone koppelingsinstructies, voortgang zonder gezondheidsgegevens, JSONL-ontvangstbewijs bij streaming en gebruikstekst |
| `--output PATH` | Atomair vastgelegde JSON of JSONL met gezondheidsgegevens |
| `OUTPUT.receipt.json` | Extractie-ontvangstbewijs zonder gezondheidsgegevens voor JSONL-bestandsuitvoer |

`--help` is gewone tekst. Argumentfouten vóór uitvoering gebruiken stderr en afsluitcode 2. Zodra een opdracht wordt uitgevoerd, gebruiken runtimefouten machineleesbare JSON.

Voeg stdout en stderr niet samen in een parser voor automatisering.

## Afsluitstatus en gegevensstatus

De afsluitstatus van het proces is slechts één signaal. Verwerk het antwoord voordat je meldt dat de opdracht is geslaagd.

| Resultaat | Standaard afsluitgedrag |
|---|---|
| Volledig geslaagd | Nul |
| Gevraagd bereik volledig leeg | Nul |
| Gevalideerde gedeeltelijke strikte onbewerkte export of extractie | Niet nul |
| Gedeeltelijk met expliciete `--allow-partial` | Nul, maar het antwoord blijft gedeeltelijk |
| Argumentfout | Afsluitcode 2, gewone tekst op stderr |
| Validatie- of transportfout | Niet nul met gestructureerde runtimefout |

`--allow-partial` is acceptatiebeleid en herstelt geen gegevens. Elke ontbrekende dag, mislukte query, elk niet-ondersteund type en elke waarschuwing blijft zichtbaar.

## Paginadoorloop staat los van taakvoltooiing

Antwoorden op getypeerde queries zijn gepagineerd. Een nieuwe ophaaltaak kan voltooid zijn terwijl de query nog een volgende pagina heeft.

Controleer zonder `--all-pages` de waarde van `next_cursor`. Als er een volgende pagina is, meldt de CLI op hoog niveau `partial_success` in plaats van ten onrechte volledige doorloop te claimen.

```bash
healthmd query --category Sleep --last 90 --all-pages
```

`--all-pages` volgt ondoorzichtige cursors, controleert op herhaling en handhaaft een totale grens voor pagina's en bytes. Verklein bij het bereiken van die grens het bereik of gebruik de laag-niveau-API om handmatig te pagineren. Er is geen verborgen limiet op het totale aantal resultaten, maar één aanroep blijft afgebakend.

## Nieuwe gegevens, cachegegevens en hergebruikte dekking

Queryopdrachten op hoog niveau halen standaard nieuwe iPhone-gegevens op:

```bash
healthmd query --metric resting_heart_rate --last 30
```

Gebruik alleen cachegegevens als verouderde context aanvaardbaar is:

```bash
healthmd query --metric resting_heart_rate --last 30 --cached
```

Gebruik `--reuse-covered` om de gegevensophaling alleen over te slaan nadat Health.md voor de gevraagde dagen volledige samenvattingsdekking per meetwaarde heeft vastgesteld:

```bash
healthmd query --metric resting_heart_rate --last 30 --reuse-covered
```

Deze verkorte route geldt niet voor verliesvrije gegevens of nieuw berekende bewerkingen voor slaapsessies. Gegevens van een andere provider of een oudere verouderde blob gelden nooit als bewijs dat dit nieuwe verzoek volledig is voltooid.

## Shellvoorbeeld

Dit voorbeeld bewaart de gezondheidspayload in een beveiligd bestand en toont alleen veilige statusvelden. Het gaat ervan uit dat GNU `timeout` is geïnstalleerd. Andere automatiseringshosts moeten hun eigen procesdeadline instellen.

```bash
#!/usr/bin/env bash
set -euo pipefail

output="${HOME}/Private/healthmd/sleep-week.json"
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"

set +e
NO_COLOR=1 TERM=dumb timeout 300 \
  healthmd extract --category Sleep --last 7 --output "$output" \
  </dev/null > /tmp/healthmd-command.json
exit_code=$?
set -e

if [ -s /tmp/healthmd-command.json ]; then
  jq '{status, job_id, error, message}' /tmp/healthmd-command.json
fi

if [ "$exit_code" -ne 0 ]; then
  echo "healthmd did not report complete success" >&2
  exit "$exit_code"
fi
```

Schakel `set -x` niet in rond een opdracht die mogelijk gezondheids-JSON streamt of gevoelige paden bevat.

## Gedrag van agents na een onbekende uitkomst

Een agent of planner hoort deze volgorde te volgen:

1. Lees de gestructureerde fout en taak-ID.
2. Voer lokaal `status --job` uit.
3. Controleer of de taak is gepauzeerd, definitief, verlopen of op bevestiging wacht.
4. Open dezelfde iPhone opnieuw als nieuw werk of een bevestiging nodig is.
5. Hervat de bestaande taak met dezelfde backend en hetzelfde apparaat.
6. Start pas een nieuwe taak als de eerdere uitkomst bekend is of het verlopen ervan expliciet is aanvaard.

Een muterende bewerking blind opnieuw proberen kan bronwerk dupliceren, ook als het vastleggen van bestanden zelf idempotent is.

## Veelvoorkomende machineleesbare fouten

| Code | Betekenis | Veilige reactie |
|---|---|---|
| `timed_out` | De opdracht stopte met wachten voordat de taak was voltooid | Bekijk de teruggegeven taak en hervat deze |
| `job_not_found` | Er bestaat geen lokaal persistent record voor die ID | Controleer de backend en statusmap voordat je opnieuw begint |
| `job_expired` | De vaste termijn van zeven dagen is verstreken | Leg het hiaat vast en maak zo nodig een nieuw verzoek |
| `direct_export_paused` | Voor rechtstreeks werk is de gekoppelde iPhone opnieuw nodig | Open de iPhone opnieuw en hervat de taak |
| `direct_cancellation_pending` | De lokale annuleringsintentie is niet door de iPhone bevestigd | Open de iPhone opnieuw en probeer de annulering nogmaals |
| `invalid_direct_raw_response` | Strikte validatie van de onbewerkte uitvoer is mislukt | Gebruik de uitvoer niet |
| `invalid_direct_file_receipt` | Het bestandsmanifest of ontvangstbewijs van de vastlegging heeft de validatie niet doorstaan | Herstel bestanden niet en voeg er niet handmatig aan toe |
| `partial_canonical_extraction` | De gevraagde extractie is onvolledig | Bekijk het ontvangstbewijs; accepteer gedeeltelijke uitvoer alleen bewust |
| `unvalidated_response_too_large` | Eén resultaat kan binnen de huidige validatiegrenzen niet beschikbaar worden gesteld | Verklein het bereik of gebruik een geschikte uitvoermodus |
| `stale_cursor` | De versleutelde context is gewijzigd nadat de paginacursor is uitgegeven | Start die query opnieuw op het huidige corpus |

## Voortgang zonder payloadlogboeken

Gebruik `--progress-json` voor fasen en paginadoorloop van query's op hoog niveau:

```bash
healthmd query --category Sleep --last 30 \
  --all-pages --progress-json --output result.json \
  2> progress.jsonl
```

JSONL-voortgang kan de fase, het aantal pagina's en items, datums en veilige diagnostiek bevatten. Gezondheidswaarden horen er niet in te staan. Houd het bestand gescheiden van het eindresultaat en pas er desondanks een passend bewaarbeleid op toe.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/cli/"><span>Configuratie</span>Health.md-CLI: installeren, een backend kiezen en de opdrachtuitvoer begrijpen.</a>
  <a href="/nl/docs/cli-direct/"><span>Rechtstreeks</span>CLI rechtstreeks naar de iPhone: koppeling, beperkte achtergrondtijd, expliciete bestemming en vertrouwd hervatten.</a>
  <a href="/nl/docs/agent-queries/"><span>Paginering</span>Recepten voor getypeerde queries: nieuwe en gecachte modi, paginadoorloop, dekking en ontvangstbewijzen.</a>
  <a href="/nl/docs/reference/generated/cli/exit-codes/"><span>Gegenereerd contract</span>CLI-afsluitcodes: vanuit productie gegenereerd status- en foutgedrag.</a>
</div>
