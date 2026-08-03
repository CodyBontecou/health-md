---
title: "macOS-app"
description: "Gebruik Health.md voor Mac als iPhone-exportbestemming, lokale CLI- en MCP-host, versleutelde opslag voor gezondheidscontext, geschiedenisweergave en beheerder van de bestemmingsmap."
---

Health.md voor Mac heeft twee lokale taken:

1. de app ontvangt exporttaken van de iPhone en schrijft bestanden naar een map die je kiest;
2. de app host de loopback-CLI, query-API, versleutelde gezondheidscontext en MCP-adapter voor lokale agents.

Apple Health blijft op de iPhone. De Mac-app leest HealthKit niet rechtstreeks uit.

## Belangrijkste onderdelen

<div class="options">
<div class="option"><strong>Synchronisatie</strong><p>Toont of de Mac vindbaar en gereed is voor exporttaken vanaf de iPhone.</p></div>
<div class="option"><strong>Bestemmingsmap</strong><p>Bewaart een security-scoped bladwijzer voor uitvoer in Markdown, JSON, CSV en Bases, plus periodeoverzichten, ZIP-bestanden en dagelijkse notities.</p></div>
<div class="option"><strong>Schema</strong><p>Toont de planning en gereedheid aan de Mac-kant. De iPhone blijft de HealthKit-gegevens leveren.</p></div>
<div class="option"><strong>Geschiedenis</strong><p>Houdt exportresultaten, persistente voortgang, fouten en informatie voor nieuwe pogingen bij voor bestanden die op de Mac worden geschreven.</p></div>
<div class="option"><strong>Instellingen</strong><p>Toont de status van de bestemming, bewaarbeheer voor versleutelde context en de lokale CLI-configuratie.</p></div>
<div class="option"><strong>Menubalk</strong><p>Geeft snel toegang tot status, instellingen en de app terwijl Health.md lokaal beschikbaar blijft.</p></div>
<div class="option"><strong>CLI</strong><p>Installeert de gebundelde hulpprogramma's <code>healthmd</code> en <code>healthmd-mcp</code>, kopieert configuratieprompts, installeert de optionele agentskill en toont geteste opdrachten.</p></div>
</div>

## Een Mac-bestemming instellen

1. Installeer en open Health.md op de Mac.
2. Kies een bestemmingsmap op de lokale schijf, in iCloud Drive of in een Obsidian-kluis.
3. Schakel op de iPhone de Mac-verbinding in via het tabblad Synchronisatie.
4. Kies op de iPhone Verbonden Mac als exportbestemming.
5. Configureer de export en tik op Exporteren.

De iPhone legt de HealthKit-gegevens en een momentopname van de actieve instellingen vast. Huidige peers dragen afgebakende partities over die met checksums zijn gevalideerd. De Mac gebruikt de productie-exporters en schrijft de gevraagde bestanden.

<div class="callout">
<strong>Beperking van HealthKit.</strong>
<p style="margin-top:6px;">De Mac kan Apple Health niet zelfstandig opvragen. Voor nieuwe exports en nieuwe agentcontext moet de verbonden iPhone-app geopend zijn. Gecachte queries op versleutelde context kunnen zonder nieuwe iPhone-verbinding worden uitgevoerd als de opgeslagen dekking volstaat.</p>
</div>

## CLI en agents configureren

Open het onderdeel **CLI** in de Mac-app om:

- de exacte paden van de ondertekende hulpprogramma's in deze appbundel te bekijken;
- aliassen of opdrachten voor symbolische koppelingen in `~/.local/bin` te kopiëren;
- een configuratieprompt voor een agent te kopiëren;
- de optionele skill `healthmd-cli` te installeren in een map die je kiest;
- opdrachten voor status, doctor, extractie, queries, slaap, training, work-outs, dekking en export te bekijken;
- veelvoorkomende gereedheidsfouten te controleren.

De app wijzigt nooit shell-opstartbestanden en installeert niets in een systeemmap zonder dat jij daarvoor een actie uitvoert.

Begin met:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

Lees [Health.md-CLI](/nl/docs/cli/) voor backendselectie en [Lokale agents](/nl/docs/agents/) voor de queryarchitectuur.

## Versleutelde gezondheidscontext

Nieuwe query- en bewijsverzoeken gebruiken een afzonderlijke modus voor het ophalen van context. De iPhone leest exact het gevraagde bereik van meetwaarden, bronnen, datums en details. Er worden geen exportbestanden gemaakt en opgeslagen exportvoorkeuren veranderen niet.

De Mac bewaart elke compacte eigenaarsdag in een afzonderlijk geauthenticeerde AES-256-GCM-blob. Een willekeurige versleutelingssleutel staat in een sleutelhangeritem dat alleen op dit apparaat en na ontgrendeling beschikbaar is. Bestandsnamen zijn willekeurig en onthullen geen datums of namen van meetwaarden.

Instellingen toont het aantal versleutelde eigenaarsdagen en het datumbereik. Twee afzonderlijke acties beheren het bewaren:

- **Oudere context verwijderen** verwijdert eigenaarsdagen van vóór de gekozen grens;
- **Alle versleutelde context verwijderen** verwijdert alle contextbestanden en de speciale sleutel in de sleutelhanger.

Het verwijderen van context verwijdert nooit Apple Health-gegevens, exportbestanden, bladwijzers voor Mac-bestemmingen of inloggegevens van verbonden providers.

## Grens van de loopback-API

De Mac-app luistert op `127.0.0.1` en `::1` via poort `17645` naar lokale routes voor status, export, queries, bewijs, verversing en persistente taken.

Er is geen bearer-token of agentregistratie. Elk lokaal proces kan de API aanroepen terwijl de app geopend is. Stel de poort nooit bloot en gebruik geen proxy of tunnel naar een andere computer.

Het gesandboxte hulpprogramma `healthmd-mcp` accepteert alleen canonieke HTTP-loopbackeindpunten. De tools bieden geen shell, willekeurige bestanden, SQL, URL-ophaalacties, resources, prompts, rootmappen of sampling.

## Direct CLI-toegang staat los van de Mac-app

De iPhone-instelling **Direct CLI-toegang** maakt een afzonderlijke vertrouwensrelatie tussen een CLI die rechtstreekse toegang ondersteunt en de iPhone. Daarmee kan de CLI voor onbewerkte exports, canonieke extractie, gegenereerde bestanden, status, hervatten en annuleren buiten de Mac-app om werken.

De rechtstreekse modus gebruikt de versleutelde querycontext van de Mac-app niet. De platformonafhankelijke opdracht `healthmd mcp serve` voert in plaats daarvan nieuwe getypeerde queries rechtstreeks uit op de iPhone-app op de voorgrond, met dezelfde identiteit van het uitvoerbare bestand als bij de koppeling. Lees [CLI rechtstreeks naar de iPhone](/nl/docs/cli-direct/) voor koppeling en platformondersteuning.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/sync/"><span>Bestemming</span>Mac-synchronisatie: koppel iPhone en Mac voor lokale bestandsexports.</a>
  <a href="/nl/docs/cli/"><span>Terminal</span>Health.md-CLI: installeer hulpprogramma's, selecteer een backend en voer opdrachten uit.</a>
  <a href="/nl/docs/agents/"><span>Lokale context</span>Agents: afgebakende gegevensophaling, versleutelde opslag, bewijs en bewaren.</a>
  <a href="/nl/docs/mcp/"><span>Tools</span>Lokale MCP-server: configuratie, toolcatalogus en sandboxgrenzen.</a>
  <a href="/nl/docs/scheduling/"><span>Werkwijze</span>Planning: automatiseer terugkerende exports.</a>
</div>
