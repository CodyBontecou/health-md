---
title: "Mac-synchronisatie"
description: "Gebruik de macOS-app als lokale bestemming. De iPhone legt HealthKit-gegevens en instellingen vast; de Mac maakt en schrijft daarna de gevraagde bestanden."
---

## Wat Mac-synchronisatie is
<p>Met Mac-synchronisatie kan je Mac exports maken zonder zelf HealthKit uit te lezen. De iPhone blijft de gezaghebbende bron voor Apple Health-gegevens. Hij legt de geselecteerde dagelijkse gegevens en een exacte momentopname van de instellingen vast en draagt de taak daarna over aan de Mac. De Mac gebruikt de gedeelde exporters om paden te plannen, de gevraagde formaten te maken en de bestanden naar de gekozen bestemmingsmap te schrijven.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Exportproces met Mac-synchronisatie">
    <span><strong>iPhone</strong>Legt HealthKit-gegevens en een momentopname van de actieve instellingen vast.</span>
    <span><strong>Lokaal netwerk</strong>Draagt de taak met versiebeheer over aan de Mac-app in de buurt.</span>
    <span><strong>Mac</strong>Maakt de geselecteerde formaten en schrijft ze naar de gekozen map.</span>
    <span><strong>Kluis</strong>De uiteindelijke export komt in Obsidian, iCloud Drive of een andere lokale map.</span>
  </div>
</div>

## Inschakelen
<ol>
<li>Installeer en open de macOS-app.</li>
<li>Kies op de Mac een bestemmingsmap, zodat Health.md schrijftoegang heeft.</li>
<li>Open op de iPhone het tabblad Synchronisatie en schakel de Mac-verbinding in.</li>
<li>Ga terug naar het tabblad Exporteren op de iPhone, kies <em>Verbonden Mac</em>, configureer de export en tik op Exporteren.</li>
</ol>

## Wat wordt overgedragen
<ul>
<li>Een exportverzoek met versiebeheer waarin het datumbereik en de actieve instellingen staan</li>
<li>Voortgangs- en capaciteitsberichten terwijl de iPhone HealthKit-gegevens vastlegt</li>
<li>Afgebakende frames met checksumvalidatie, met de vastgelegde dagelijkse gegevens en exacte momentopname van de instellingen voor taken die bestanden schrijven</li>
<li>Een gestructureerd resultaat voor voltooiing, gedeeltelijke voltooiing, mislukking, afwijzing of onbeschikbaarheid</li>
</ul>
<p>Er is geen account of externe cloud voor gezondheidsgegevens nodig. Synchronisatie in de buurt gebruikt versleutelde Multipeer Connectivity. Manual IP en Tailscale gebruiken gekoppeld, versleuteld Network.framework-transport. Beide apparaten moeten elkaar kunnen bereiken en de iPhone blijft HealthKit uitlezen.</p>

## Wanneer je dit gebruikt
<div class="options">
<div class="option"><strong>Kluis alleen op de Mac</strong><p>Als je Obsidian-kluis alleen op de Mac staat, is dit de directe route van HealthKit op de iPhone naar bestanden op de Mac.</p></div>
<div class="option"><strong>Omvangrijke historische aanvullingen</strong><p>Bewaar de uiteindelijke bestanden op een schijf van de Mac terwijl de iPhone HealthKit uitleest en de exportconfiguratie levert.</p></div>
<div class="option"><strong>Lokale archiefworkflows</strong><p>Schrijf rechtstreeks naar mappen waarvan op macOS reservekopieën worden gemaakt of die daar onder versiebeheer staan of worden geïndexeerd.</p></div>
</div>

<div class="callout">
<strong>Lokaal netwerk vereist.</strong>
<p style="margin-top:6px;">Beide apparaten moeten in de buurt zijn en het lokale netwerk mogen gebruiken. Een iPhone die alleen een mobiele verbinding heeft, kan geen Mac-bestemming vinden. Als de gereedheidsstatus aangeeft dat de Mac aandacht nodig heeft, open dan de Mac-app opnieuw en selecteer de bestemmingsmap nogmaals.</p>
</div>

## Mac-synchronisatie en Direct CLI-toegang staan los van elkaar

Mac-synchronisatie koppelt de iPhone met de Health.md-app op de Mac voor exports naar een bestemming en versleutelde agentcontext. Direct CLI-toegang koppelt de iPhone via een afzonderlijk vertrouwensdomein met een opdrachtregelinstallatie. De rechtstreekse modus kan zonder de Mac-app onbewerkte gegevens of gegenereerde bestanden exporteren, maar kan de versleutelde queryindex of MCP van de Mac niet gebruiken.

Lees [CLI rechtstreeks naar de iPhone](/nl/docs/cli-direct/) voordat je de afzonderlijke iPhone-instelling inschakelt.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/macos/"><span>Desktop</span>macOS-app: Exporteren, Schema en Geschiedenis op de Mac.</a>
  <a href="/nl/docs/scheduling/"><span>Werkwijze</span>Planning: automatiseer terugkerende exports.</a>
  <a href="/nl/docs/cli-direct/"><span>Afzonderlijk vertrouwen</span>CLI rechtstreeks naar de iPhone: koppel een CLI zonder werk via de Mac-app te sturen.</a>
  <a href="/nl/docs/reference/connected-mac-iphone-protocol/"><span>Protocol</span>Referentie voor verbonden Mac en iPhone: mogelijkheden, afgebakende overdracht en resultaten.</a>
</div>
