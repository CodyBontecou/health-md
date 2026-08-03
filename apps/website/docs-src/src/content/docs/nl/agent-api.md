---
title: "Loopback-query-API"
description: "Roep de lokale Health.md-routes met versiebeheer aan voor queries, bewijs, verversing, gereedheid, meetwaarden en persistente taken via HTTP of de laag-niveau-opdracht healthmd agent."
---

Health.md voor Mac biedt onder `/v1/agent/` een lokale API met versiebeheer. Deze verwerkt queries op versleutelde context, bewijsbundels, gegevensophaling van de iPhone met een bereik per verzoek, gereedheid en persistente ophaaltaken.

De API bindt op poort `17645` aan loopback. Alleen gevalideerde IPv4- en IPv6-loopbackpeers worden geaccepteerd.

<div class="callout">
<strong>Stel deze poort niet bloot.</strong>
<p style="margin-top:6px;">Er is geen bearer-token, aanroeperregistratie, toegangsprofiel of toestemmingsdatabase. Bereikbaarheid via loopback is de volledige autorisatiegrens. Elk lokaal proces kan verzoeken indienen terwijl Health.md geopend is.</p>
</div>

## Routes

| Methode | Route | Doel |
|---|---|---|
| `GET` | `/v1/agent/capabilities` | Schema's met versiebeheer, ondersteunde bereiken en paginagrenzen weergeven |
| `GET` | `/v1/agent/metrics` | Canonieke opvraagbare meetwaarde-ID's, categorieën, eenheden en vereisten teruggeven |
| `GET` | `/v1/agent/readiness` | Gereedheid van de versleutelde context en actuele iPhone teruggeven, met vervolgstappen |
| `POST` | `/v1/agent/query` | Eén afgebakende pagina van een getypeerde query uitvoeren |
| `POST` | `/v1/agent/evidence` | Eén afgebakende pagina van een feitelijke bewijsbundel afleiden |
| `POST` | `/v1/agent/refresh` | Een expliciet bereik van de iPhone ophalen en in versleutelde Mac-context plaatsen |
| `GET` | `/v1/agent/jobs/{id}` | Een persistente lokale ophaaltaak bekijken |
| `POST` | `/v1/agent/jobs/{id}/resume` | Het onveranderlijke ophaalverzoek hervatten |
| `POST` | `/v1/agent/jobs/{id}/cancel` | Expliciete annulering aanvragen |

De voormalige routes `/v1/agent/profiles` en `/v1/agent/activity/query` geven `410 removed_endpoint` terug.

De backend voor rechtstreekse iPhone-toegang host deze HTTP-routes niet. De zelfstandige opdracht `healthmd` gebruikt deze backend voor canonieke extractie en exports. `healthmd mcp serve` implementeert via iPhone-queryprotocol v3 rechtstreeks tools voor nieuwe getypeerde queries, bewijs, de meetwaardecatalogus, gereedheid, visualisaties en persistente exports. Koppeling en MCP gebruiken dezelfde identiteit van het uitvoerbare bestand. Verversing en de versleutelde Mac-context zijn specifiek voor deze HTTP-API.

## Gebruik bij voorkeur de CLI-adapter

De laag-niveau-CLI laat de hoofdtekst van verzoeken ongewijzigd en verwerkt transportfouten op loopback:

```bash
healthmd agent capabilities
healthmd agent query --input query-body.json
healthmd agent query --input - < query-body.json
healthmd agent evidence --input evidence-body.json
healthmd agent refresh --input refresh-body.json
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

Gebruik voor een kleine hoofdtekst `--json JSON` in plaats van `--input`. De CLI maakt de aangeleverde JSON voor deze opdrachten niet ongemerkt ruimer of smaller.

Gebruik voor gewone workflows opdrachten op hoger niveau, zoals `healthmd query`, `healthmd sleep sessions` of `healthmd compare`. Deze valideren selecties en stellen de getypeerde bewerking voor je samen.

## Hoofdtekst van een query

`POST /v1/agent/query` accepteert op het hoogste niveau alleen `request` en het optionele `detail_level`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Onbekende velden in de wrapper worden afgewezen. Het contract voor queryverzoeken definieert meetwaarden, bronnen, datums, de bewerking en paginabesturing. `detail_level` is `summary` of `lossless`.

Het antwoord is `healthmd.query_response` v1. Het bevat getypeerde items, dekking, bewijs, bronbeschrijvingen, beperkingen en eventueel `next_cursor`.

Bekijk een volledig synthetisch antwoord in [`agent-query-response.json`](/docs/reference/generated/automation/agent-query-response.json).

## Verdergaan met een cursor

Stuur voor de volgende pagina hetzelfde semantische verzoek en plaats de teruggegeven cursor in `page.cursor`:

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "metric_series"
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144,
      "cursor": "OPAQUE_CURSOR_FROM_PRIOR_RESPONSE"
    }
  },
  "detail_level": "summary"
}
```

Volg `next_cursor` totdat dit veld ontbreekt. Cursors zijn geauthenticeerd en gebonden aan het verzoek en de revisie van het versleutelde corpus. Health.md wijst gewijzigde, niet-overeenkomende en verouderde cursors af.

Paginagrenzen beschermen elk verzoek zonder een limiet op de totale geschiedenis of het totale aantal resultaten op te leggen.

## Hoofdtekst voor bewijs

`POST /v1/agent/evidence` gebruikt dezelfde wrapper. De bewerking is `derive_packet`, met een soort bundel en expliciet geselecteerde details.

```json
{
  "request": {
    "schema": "healthmd.query_request",
    "schema_version": 1,
    "metrics": {
      "type": "explicit",
      "metric_ids": ["steps", "resting_heart_rate"]
    },
    "sources": {
      "type": "all_available"
    },
    "dates": {
      "type": "exact",
      "range": {
        "start_date": "2026-07-01",
        "end_date": "2026-07-07"
      }
    },
    "operation": {
      "type": "derive_packet",
      "kind": "doctor_visit",
      "detail_ids": []
    },
    "page": {
      "max_items": 250,
      "max_bytes": 262144
    }
  },
  "detail_level": "summary"
}
```

Het antwoord blijft een gepagineerd queryantwoord en bevat een fragment van `healthmd.evidence_packet` v1. Feiten bevatten getypeerde waarden en bewijs. De bundel vermeldt de beperking dat deze uitsluitend feitelijke waarnemingen bevat.

Bekijk [`agent-evidence-response.json`](/docs/reference/generated/automation/agent-evidence-response.json) voor een volledig synthetisch antwoord.

## Hoofdtekst voor verversing

Een verversing haalt alleen een expliciet bereik op. De hoofdtekst accepteert datums, meetwaarden, bronnen, een detailniveau en een eindige wachttijd:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-01",
      "end_date": "2026-07-07"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["sleep_total"]
  },
  "sources": {
    "type": "explicit",
    "source_ids": ["apple_health"],
    "provider_ids": []
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

De Mac valideert het bereik aan de hand van de huidige catalogi en zet het om in een onveranderlijke canonieke selectie. De iPhone leest alleen de geselecteerde gewone HealthKit-typen. Instellingen per verzoek wijzigen de opgeslagen exportvoorkeuren op de iPhone niet.

Verversing gebruikt een afzonderlijke overdrachtsmodus `encrypted_context`:

- er worden geen exportbestanden geschreven;
- er wordt geen tegoed voor bestandsexports verbruikt;
- de overdracht gebruikt afgebakende partities die kunnen worden hervat;
- de Mac legt elke deterministische compacte eigenaarsdag vast voordat hij de ontvangst bevestigt;
- het exacte verzoek blijft bij de persistente taak opgeslagen.

Een bereik dat alleen providers bevat, vereist geen uitlezing van Apple Health. Systeemeigen geschiedenis van providers blijft systeemeigen providerbewijs en wordt niet omgezet in synthetische Apple Health-meetwaarden.

## Selectie van alle beschikbare gegevens

Selecties voor meetwaarden en datums kunnen `all_available` gebruiken:

```json
{
  "dates": {"type": "all_available"},
  "metrics": {"type": "all_available"},
  "sources": {"type": "all_available"},
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

De iPhone bepaalt het oudste beschikbare geselecteerde Apple Health-record en elke kalenderdag van de bron tot en met vandaag. Gegevensophaling bij providers volgt de systeemeigen geschiedeniscursors van die provider. De opgeloste ID's worden vóór de overdracht vastgezet, zodat hervatten het verzoek niet kan verschuiven.

Er is geen vaste limiet op datums of resultaten. Partities, pagina's, ontsleuteling per dag, schijfruimte en eindige wachttijden begrenzen het gebruik van middelen.

## Persistente ophaaltaken

Het wachten op een verversing kan verlopen terwijl de taak doorgaat. Het antwoord bevat een taak-ID en veilige voortgangsinformatie.

```bash
healthmd agent job status JOB_UUID
healthmd agent job resume JOB_UUID --timeout 300
healthmd agent job cancel JOB_UUID
```

De taak verloopt zeven dagen nadat deze is aangemaakt. Hervatten hergebruikt hetzelfde verzoek, dezelfde Mac en iPhone, hetzelfde bronbereik en hetzelfde vastgelegde voortgangspunt.

Annulering is pas definitief nadat de iPhone dit heeft bevestigd. Als de iPhone niet beschikbaar is, kan de taak in de status 'annulering in behandeling' blijven staan.

## Rechtstreekse HTTP-aanroepen

De CLI heeft de voorkeur, maar lokale software kan HTTP ook rechtstreeks aanroepen:

```bash
curl --fail-with-body --max-time 5 \
  http://127.0.0.1:17645/v1/agent/readiness

curl --fail-with-body --max-time 30 \
  -H 'Content-Type: application/json' \
  --data @query-body.json \
  http://127.0.0.1:17645/v1/agent/query
```

De listener handhaaft grenzen voor headers en JSON-hoofdteksten, een expliciete methode en expliciet contenttype, ontvangstdeadlines en eindig verzoekgedrag.

Houd rechtstreekse HTTP-clients op dezelfde Mac. Voeg geen LAN-binding, proxy, tunnel of externe HTTP-MCP-wrapper toe.

## Getypeerde waarden en ontbrekende gegevens

Queryresultaten behouden hun type en eenheid. Waarden kunnen hoeveelheden, duren, tellingen, tekenreeksen, categorieën, Booleaanse waarden, tijdstempels, kalenderdatums, geneste arrays of onbekende toekomstige getypeerde waarden zijn.

Ontbrekende statussen omvatten volledig leeg, gedeeltelijk, mislukt, niet ondersteund, overgeslagen, geannuleerd, niet aangevraagd, verouderd niet beschikbaar, afgeschermd en niet gesynchroniseerd. Verwerkers mogen deze statussen niet naar nul omzetten.

Dekking bevat het gevraagde en beschikbare bereik, het aantal bekeken dagen, dagen met waarden en gecomprimeerde ontbrekende intervallen met een status.

## Foutafhandeling

Fouten gebruiken `healthmd.query_error` v1 met een stabiele code, een bericht, informatie over opnieuw proberen en getypeerde details. Er zijn afzonderlijke fouten voor:

- ongeldige paginabesturing;
- onjuist gevormde of gemanipuleerde cursors;
- een cursor die niet bij de query past;
- een verouderde corpusrevisie;
- een ongeldig datumbereik;
- validatie van meetwaarden of bronnen;
- niet-overeenkomende eenheden of aggregaties;
- een niet-ondersteunde bewerking;
- schending van het bewijsbereik;
- gereedheid van de iPhone of versleutelde opslag;
- de status van een persistente taak.

Probeer een verversing na een onbekende uitkomst niet zonder controle opnieuw. Bekijk eerst de taakstatus.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/agents/"><span>Overzicht</span>Lokale agents en gezondheidscontext: configuratie, versleutelde opslag, bereik en rapportageregels.</a>
  <a href="/nl/docs/agent-queries/"><span>Hoog niveau</span>Recepten voor getypeerde queries: gevalideerde opdrachten voor veelvoorkomende vragen over meetwaarden, slaap, work-outs en bewijs.</a>
  <a href="/nl/docs/mcp/"><span>Tools</span>Lokale MCP-server: stdio-configuratie, getypeerde tools, paginering en sandboxgrenzen.</a>
  <a href="/nl/docs/reference/api-and-cli/"><span>Referentie</span>API- en CLI-contract: export, extractie, queries, directe backend en operationele grenzen.</a>
  <a href="/nl/docs/reference/evidence-packets/"><span>Datacontracten</span>Compacte queries en bewijsbundels: typen, cursors, bewerkingen en deterministische bundel-ID's.</a>
</div>
