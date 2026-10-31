---
title: "Date del sonno e note giornaliere"
description: "Scegli la data di esportazione del sonno: intervallo da mezzogiorno a mezzogiorno, orari dopo mezzanotte, sonnellini e risultati vuoti."
---

**Inizio della notte** è l'impostazione predefinita su iPhone e Android. Per il sonno della notte precedente, il martedì mattina esporta **lunedì**, normalmente **Ieri**. Il riepilogo del sonno di Health.md usa una finestra locale dalle **12:00 alle 12:00**: da lunedì a mezzogiorno a martedì a mezzogiorno, non il confine di mezzanotte dell’attività.

Scegli **Fine al mattino** nelle impostazioni di esportazione per assegnare ogni sessione di sonno completa alla data in cui termina, nel fuso orario dell'esportazione e senza tagliarla a mezzogiorno. Per la notte di lunedì che termina martedì, esporta **martedì (Oggi)**; anche i sonnellini di martedì appartengono a martedì. Il cambiamento vale per le nuove operazioni; quelle salvate mantengono l'attribuzione accettata.

<div id="sleep-journal-window"></div>

## Perché il sonno compare nella nota di ieri

La finestra mantiene unita una notte tipica, anche se vai a letto dopo mezzanotte. Include il primo mezzogiorno ed esclude quello successivo. Il sonno che attraversa mezzogiorno può contribuire a riepiloghi di giorni adiacenti. I timestamp originali non vengono riscritti per adattarli alla nota.

Entrambe le modalità di attribuzione del sonno sono disponibili su Apple e Android. Metriche, fasi, record di origine e aggregazioni possono ancora differire tra le piattaforme.

<div id="sleep-date-examples"></div>

## Quale data esportare?

**Inizio della notte:** Esempi fittizi in ora locale, non dati sanitari:

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

I riepiloghi di Daily Note Injection e API Endpoint usano l'attribuzione del sonno scelta per l'operazione. Se i dati arrivano in ritardo, riesporta la data corrispondente a quella modalità o controlla il periodo retrospettivo della pianificazione. L'orario in background è un obiettivo, non una garanzia di scrittura riuscita.

<div id="sleep-records-and-queries"></div>

## Riepiloghi, record e query delle sessioni

I record grezzi o canonici mantengono timestamp e regole di appartenenza propri. Non ricostruire sessioni da un totale giornaliero e non sommare gli intervalli come ulteriore sonno.

**Inizio della notte:** Su Apple, l’archivio grezzo assegna i record in base all’ora di inizio originale nel giorno locale, da mezzanotte a mezzanotte. Il riepilogo del sonno, invece, ritaglia gli intervalli nella finestra del diario, da mezzogiorno a mezzogiorno. Una query riuscita sui record grezzi di Sleep Analysis può quindi contenere record del mattino mentre il riepilogo del sonno di quella data è vuoto. Esporta la data precedente del diario e controlla `time_context.calendar_timezone` prima di indagare su un riepilogo mancante. Per esempio, i record del 22 settembre dalle 04:03 alle 11:52 UTC appartengono interamente al riepilogo del 21 settembre in UTC; in Europe/Lisbon, gli ultimi 52 minuti sono successivi al mezzogiorno locale e contribuiscono invece al 22 settembre.

Il sonno suddiviso in fasi non richiede un record esplicito `inBed`: quando manca, i riepiloghi Apple usano l’unione degli intervalli disponibili delle fasi di sonno. L’assenza di dati sul tempo a letto non crea una durata a letto. Una query di riepilogo non riuscita deve comparire in `diagnostics.partial_failures`; una query riuscita senza intervalli idonei rappresenta una valida assenza di dati. La frequenza cardiaca a riposo usa una query separata per giorno di calendario e richiede una vera misurazione della frequenza cardiaca a riposo; le fasi di sonno o il solo permesso di lettura non la forniscono.

`healthmd_sleep_sessions` richiede una configurazione CLI/MCP **Apple Health** supportata. Le query MCP tipizzate Android non sono attualmente supportate. Vedi [capacità per piattaforma](/it/docs/guides/platform-features/) e [MCP](/it/docs/mcp/).

Altre guide: [pianificazione](/it/docs/scheduling/), [risoluzione dei problemi](/it/docs/troubleshooting/) e [formati](/it/docs/format/).
