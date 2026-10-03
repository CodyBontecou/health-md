---
title: "Verbind een agent in 10 minuten"
description: "Verbind de uitgebrachte Health.md Mac MCP-hulp met Codex of Claude, haal één expliciet iPhone-bereik op, voer een afgebakende query uit en controleer de volledigheid veilig."
---

<div class="availability available">
<strong>Nu beschikbaar · Health.md voor Mac</strong>
<p>Deze route gebruikt het ondertekende <code>healthmd-mcp</code>-hulpprogramma dat bij de uitgebrachte Mac-app wordt meegeleverd. Hij gebruikt niet de draagbare CLI-preview, Direct CLI-toegang, een koppel-QR-code of poort 17647.</p>
</div>

Je verbindt een lokale MCP-host, controleert de gereedheid zonder gezondheidswaarden te lezen, vernieuwt expliciet één klein bereik vanaf de iPhone en bevraagt die versleutelde Mac-context. Reken op ongeveer tien minuten wanneer beide apps al geïnstalleerd zijn en op hetzelfde lokale netwerk staan.

## 1. Installeer en open Health.md

[Download Health.md uit de App Store](https://apps.apple.com/us/app/health-md/id6757763969) op zowel de Mac als de iPhone. Open beide apps.

HealthKit blijft op de iPhone. De Mac-app host het ondertekende MCP-hulpprogramma en een versleutelde, wegwerpbare querycontext; hij leest HealthKit niet rechtstreeks uit.

## 2. Verbind iPhone en Mac

1. Laat Health.md op de Mac openstaan.
2. Open op de iPhone **Health.md → Synchronisatie** en schakel de Mac-verbinding in.
3. Houd beide apparaten op hetzelfde bereikbare lokale netwerk en houd Health.md op de iPhone op de voorgrond zolang er vers werk start.
4. Controleer of de Mac-app de bedoelde iPhone-verbinding toont. Zo niet, open dan beide apps opnieuw en bekijk de [gereedheid van Mac-synchronisatie](/nl/docs/sync/).

Dit is de uitgebrachte Mac-verbinding. Voer `healthmd direct pair` niet uit; dat commando hoort bij de aparte draagbare preview.

## 3. Kopieer het pad van het ondertekende hulpprogramma

Open **Health.md voor Mac → CLI** en kopieer het getoonde pad van het MCP-hulpprogramma. Een normale `/Applications`-installatie gebruikt:

```text
/Applications/Health.md.app/Contents/Helpers/healthmd-mcp
```

Gebruik het getoonde pad als de app elders is geïnstalleerd. Configureer het hulpprogramma rechtstreeks: wikkel het niet in een shell en start het niet als interactief commando.

## 4. Configureer Codex of Claude

### Codex

Voeg dit toe aan `~/.codex/config.toml` en vervang zo nodig het pad van het hulpprogramma:

```toml
[mcp_servers.healthmd]
command = "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp"
args = []
startup_timeout_sec = 10
tool_timeout_sec = 1200
default_tools_approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_files]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_resume]
approval_mode = "prompt"

[mcp_servers.healthmd.tools.healthmd_export_job_cancel]
approval_mode = "prompt"
```

Start Codex opnieuw nadat je het bestand hebt opgeslagen.

### Claude Desktop of Claude Code

Voeg deze lokale stdio-vermelding toe aan de MCP-configuratie van Claude Desktop of aan een vertrouwde `.mcp.json` van Claude Code:

```json
{
  "mcpServers": {
    "healthmd": {
      "command": "/Applications/Health.md.app/Contents/Helpers/healthmd-mcp",
      "args": []
    }
  }
}
```

Start Claude Desktop opnieuw, of stel vertrouwen in voor de Claude Code-werkruimte en keur de server goed. Laat goedkeuringsvragen ingeschakeld voor vernieuwings-, export-, hervattings- en annuleringshandelingen.

## 5. Controleer de gereedheid

Roep `healthmd_doctor` aan. Hij leest uitsluitend gezondheidsvrije gereedheid.

Een gereed resultaat bevat deze velden:

```json
{
  "schema": "healthmd.local_readiness",
  "schema_version": 1,
  "status": "ready"
}
```

Het volledige resultaat bevat daarnaast controles en vervolgstappen. Los elke blokkerende controle op voordat je verdergaat. Een verbonden hulpprogramma bewijst **niet** dat de versleutelde context actueel is.

Roep daarna `healthmd_metrics` aan en bevestig de canonieke meetwaarde-ID en eenheid die je wilt opvragen. Deze walkthrough gebruikt `steps` alleen als voorbeeld.

## 6. Vernieuw expliciet één klein bereik

Bepaal de datums die je werkelijk wilt en roep daarna `healthmd_refresh` aan met een exacte, inclusieve periode. Het voorbeeld vraagt één dag samengevatte gegevens op:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "wait_timeout_seconds": 300
}
```

Bekijk de argumenten, keur het ophalen goed en houd beide apps open. De vernieuwing schrijft geen exportbestanden en wijzigt de opgeslagen iPhone-exportinstellingen niet. Bewaar de teruggegeven `job_id` totdat de taak een eindstatus bereikt.

## 7. Voer de eerste afgebakende query uit

Roep na afronding van de vernieuwing `healthmd_metric_chart` aan met dezelfde datums, meetwaarde, bronkeuze en detailniveau:

```json
{
  "dates": {
    "type": "exact",
    "range": {
      "start_date": "2026-07-14",
      "end_date": "2026-07-14"
    }
  },
  "metrics": {
    "type": "explicit",
    "metric_ids": ["steps"]
  },
  "sources": {
    "type": "all_available"
  },
  "detail_level": "summary",
  "all_pages": true
}
```

`all_pages: true` doorloopt ondoorzichtige cursors alleen binnen de geaggregeerde pagina- en byteplafonds van het hulpprogramma. Roep voor slaap `healthmd_sleep_sessions` aan in plaats van canonieke extractie te vervangen.

## 8. Controleer de volledigheid voordat je antwoordt

Beschouw het succes van een tool niet als bewijs van volledige gezondheidsdekking. Controleer alles hieronder:

- de vernieuwing bereikte een geslaagde eindstatus voor exact dezelfde datums, meetwaarden, bronnen en detailniveau;
- het schema en de versie van het antwoord worden herkend;
- de opgevraagde periode en tijdzone kloppen met de vraag;
- elke genoemde waarde behoudt zijn canonieke meetwaarde-ID en eenheid;
- de dekkingsstatus, beschouwde dagen, dagen met waarden en elk ontbrekend interval worden gerapporteerd;
- `complete_empty`, `partial`, `failed`, `unsupported`, `skipped` en `cancelled` worden niet naar nul omgezet;
- de doorloop is voltooid, of elke resterende cursor of geaggregeerd plafond wordt vermeld;
- bewijs- en brondescriptoren en beperkingen blijven aan het antwoord verbonden;
- feitelijke richting wordt niet omgezet in diagnose, behandeladvies, causaliteit of taal over “beter/slechter”.

### Lees gedeeltelijke resultaten zonder bruikbare gegevens weg te gooen

Een getypeerde query kan een geldige `healthmd.query_response` teruggeven terwijl slechts een deel van het opgevraagde bereik is voltooid. De gegenereerde [fixture voor gedeeltelijke query-antwoorden](/docs/reference/generated/automation/agent-query-response-partial.json) behoudt een beschikbaar Stappen-item en rapporteert de mislukte dag apart:

```json
{
  "schema": "healthmd.query_response",
  "schema_version": 1,
  "coverage": {
    "status": "partial",
    "days_considered": 2,
    "days_with_values": 1,
    "missing": [
      {
        "status": "failed",
        "range": {
          "start_date": "2026-03-16",
          "end_date": "2026-03-16"
        }
      }
    ]
  },
  "items": ["one retained typed item"],
  "limitations": ["one or more requested days did not complete"]
}
```

De tekenreeksen binnen `items` en `limitations` hierboven zijn verklarende afkortingen; gebruik de downloadbare gegenereerde fixture voor exacte velden en bewijs. Behoud het behouden item, het mislukte interval, de dekkingstellingen en de beperking samen.

Voeg `status: "partial_success"` niet toe aan `healthmd.query_response`. Die status hoort bij de API-envelope van CLI en export op hoger niveau wanneer ophalen, doorloop of bestandsgeneratie onvolledig is. Een time-out is weer iets anders: het is een onbekende uitkomst van een persistente taak die op taak-ID moet worden gecontroleerd.

Gestructureerde fouten gebruiken `healthmd.query_error` v1 in plaats van een gedeeltelijk antwoord. Bekijk [agent-query-error.json](/docs/reference/generated/automation/agent-query-error.json) voor de gegenereerde productievorm met stabiele code, bericht, herhaalbaarheid en getypeerde details.

## 9. Herstel veilig na een time-out

Een time-out, gesloten host of geannuleerde MCP-wachter annuleert een geaccepteerde vernieuwing niet.

1. Bewaar de teruggegeven `job_id`.
2. Roep `healthmd_job_status` aan met die ID.
3. Als de onveranderlijke taak hervatbaar is, bekijk en keur dan `healthmd_job_resume` goed met dezelfde ID en een eindige wachttijd.
4. Start pas een nieuwe vernieuwing nadat de status aantoont dat geen geaccepteerde taak nog kan voltooien.
5. Gebruik `healthmd_job_cancel` alleen wanneer je de taak daadwerkelijk wilt beëindigen; annuleren is pas definitief na bevestiging door de iPhone.

Probeer nooit blind opnieuw na een onbekende uitkomst. Persistente vernieuwingstaken behouden het geaccepteerde bereik en het vastgelegde voortgangspunt.

## Je bent verbonden

De eerste alleen-lezen-werkstroom is voltooid wanneer doctor gereed is, de expliciete vernieuwing een eindstatus heeft, de afgebakende query volledig is doorlopen en je dekking, bewijs, eenheden en beperkingen hebt gecontroleerd.

Exporten van gegenereerde bestanden zijn een aparte werkstroom die goedkeuring vereist. Het uitgebrachte Mac-tool schrijft naar de map die al in Health.md voor Mac is gekozen; hij accepteert geen willekeurig bestemmingsargument.

<div class="related">
  <a href="/nl/docs/mcp/"><span>Toolcatalogus</span>Bekijk alle uitgebrachte Mac-tools, exacte schema's, MCP Apps, paginering en veiligheidsgrenzen.</a>
  <a href="/nl/docs/configuration/"><span>Andere clients</span>Kies tussen de uitgebrachte Mac-integratie en de duidelijk gemarkeerde draagbare preview.</a>
  <a href="/nl/docs/agent-queries/"><span>Volgende vragen</span>Voer getypeerde workflows uit voor meetwaarden, slaap, work-outs, vergelijkingen, dekking en bewijs.</a>
  <a href="/nl/docs/agents/"><span>Vertrouwensmodel</span>Begrijp versleutelde context, verzoekbereik, bewaartermijn, bewijs en rapportageregels.</a>
</div>
