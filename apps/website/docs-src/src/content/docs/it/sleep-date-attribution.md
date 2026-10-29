---
title: "Date del sonno e note giornaliere"
description: "Scegli la data di esportazione del sonno: intervallo da mezzogiorno a mezzogiorno, orari dopo mezzanotte, sonnellini e risultati vuoti."
---

Per il sonno della notte precedente, il martedì mattina esporta **lunedì**, normalmente **Ieri**. Il riepilogo del sonno di Health.md usa una finestra locale dalle **12:00 alle 12:00**: da lunedì a mezzogiorno a martedì a mezzogiorno, non il confine di mezzanotte dell’attività.

<div id="sleep-journal-window"></div>

## Perché il sonno compare nella nota di ieri

La finestra mantiene unita una notte tipica, anche se vai a letto dopo mezzanotte. Include il primo mezzogiorno ed esclude quello successivo. Il sonno che attraversa mezzogiorno può contribuire a riepiloghi di giorni adiacenti. I timestamp originali non vengono riscritti per adattarli alla nota.

Apple e Android condividono questa finestra nei riepiloghi compatibili; metriche, fasi, record e aggregazioni possono differire. Non esiste un’impostazione che sposti il riepilogo alla data del risveglio.

<div id="sleep-date-examples"></div>

## Quale data esportare?

Esempi fittizi in ora locale, non dati sanitari:

| Sonno o attività | Data di esportazione |
| --- | --- |
| Lunedì 23:45 a martedì 07:30 | **Lunedì** |
| Martedì 01:00 a martedì 07:30 | **Lunedì**, non martedì |
| Sonnellino del martedì, 14:00 a 14:30 | **Martedì** |
| Passi e attività del martedì | **Martedì** |
| Notte del lunedì e attività del martedì | **Lunedì e martedì** |

Controlla il fuso locale dell’esportazione. La data del risveglio in un’altra app o la modifica del file non determina il giorno del diario.

<div id="sleep-empty-checks"></div>

## Se la nota prevista è vuota

1. Controlla il giorno del diario e le metriche del sonno selezionate.
2. Lascia sincronizzare orologio o app con Apple Health o Health Connect, poi visualizza l’anteprima ed esporta di nuovo quel giorno.
3. Controlla gli accessi. Su iPhone, un risultato HealthKit vuoto non rivela se la lettura è stata negata. Su Android, la fonte deve aver scritto il record supportato in Health Connect.
4. Verifica destinazione e risultati scritti, ignorati o falliti. L’anteprima non prova che un file sia stato salvato. Un dato assente non è zero.

Daily Note Injection e i riepiloghi API Endpoint usano la stessa finestra. Per dati tardivi, ripeti il giorno o controlla il periodo retrospettivo della pianificazione. L’esecuzione in background non garantisce una scrittura riuscita a un’ora esatta.

<div id="sleep-records-and-queries"></div>

## Riepiloghi, record e query delle sessioni

I record grezzi o canonici mantengono timestamp e regole di appartenenza propri. Non ricostruire sessioni da un totale giornaliero e non sommare gli intervalli come ulteriore sonno.

Su Apple, l’archivio grezzo assegna i record al giorno locale da mezzanotte a mezzanotte in base all’ora iniziale. Il riepilogo del sonno limita invece gli intervalli alla finestra da mezzogiorno a mezzogiorno. Una query Sleep Analysis riuscita può quindi contenere record mattutini mentre il riepilogo di quella data è vuoto. Esporta il giorno precedente e controlla `time_context.calendar_timezone`. Per esempio, i record del 22 settembre dalle 04:03 alle 11:52 UTC appartengono interamente al riepilogo del 21 in UTC; in Europe/Lisbon, gli ultimi 52 minuti sono dopo mezzogiorno locale e contribuiscono al 22.

Le fasi del sonno non richiedono un record esplicito `inBed`: se manca, Apple usa l’unione delle fasi di sonno disponibili, senza inventare una durata a letto. Una query fallita deve comparire in `diagnostics.partial_failures`; una query riuscita senza intervalli validi è un’assenza valida. La frequenza cardiaca a riposo usa una query separata per giorno di calendario e richiede una misurazione reale; le fasi del sonno o il solo permesso di lettura non la forniscono.

`healthmd_sleep_sessions` richiede una configurazione CLI/MCP **Apple Health** supportata. Le query MCP tipizzate Android non sono attualmente supportate. Vedi [capacità per piattaforma](/it/docs/guides/platform-features/) e [MCP](/it/docs/mcp/).

Altre guide: [pianificazione](/it/docs/scheduling/), [risoluzione dei problemi](/it/docs/troubleshooting/) e [formati](/it/docs/format/).
