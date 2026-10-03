---
title: "Problemen met Health.md oplossen"
description: "Onderzoek lege exports, ontbrekende slaap, onbereikbare telefoons, planning, mappen, deelresultaten en time-outs."
---

Begin met één apparaat, één dag, één categorie en één bestemming. Publiceer geen gezondheidsdata, routes, klinische documenten, tokens, koppelcodes of private paden.

## Lege data

Bevestig de waarde in Apple Health of Health Connect, controleer toestemming en exporteer één categorie voor één dag. Onderscheid `complete_empty`, geen toestemming, niet ondersteund, overgeslagen, gedeeltelijk en mislukt. Afwezig is niet nul.

## Slaap ontbreekt bij Vandaag

Slaap hoort bij de dag waarop de nacht begon. Exporteer dinsdagochtend **Gisteren** of maandag en dinsdag. Zie [Slaapdatums](/nl/docs/sleep-date-attribution/).

## Bestanden en planning

Controleer vault, maptoegang, submap, sjabloon en profiel. iOS-achtergrondwerk en WorkManager gebruiken streeftijden, geen universele garantie. Ontgrendel en gebruik herstel.

## CLI-time-out

Een time-out annuleert geen geaccepteerde job:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Controleer status, ontbrekende dagen, dekking, `next_cursor`, versie en beperkingen voordat je volledigheid claimt. `--allow-partial` wijzigt alleen afsluitbeleid.

<div class="related"><a href="/nl/docs/cli-jobs/"><span>Jobs</span>Hervatten en annuleren.</a><a href="/nl/docs/release-status/"><span>Versies</span>Compatibiliteit.</a></div>
