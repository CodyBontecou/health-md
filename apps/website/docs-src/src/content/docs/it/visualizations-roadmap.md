---
title: Visualizzazioni e roadmap
description: Copertura attuale delle visualizzazioni di Health.md per Obsidian e grafici pianificati, organizzati per tipo di dati esportati.
---

Health.md esporta un insieme di dati locale con versione dello schema per Markdown, Obsidian Bases, JSON e CSV. La roadmap delle visualizzazioni riportata di seguito collega questi dati al plugin complementare di visualizzazione per Obsidian: ciò che è già disponibile, ciò che i dati esportati potranno supportare in futuro e le categorie che richiedono grafici generici in grado di interpretare lo schema.

<div class="callout">
<strong>Origine dati.</strong>
<p style="margin-top:6px;">Questa pagina è organizzata in base allo schema di esportazione e al dizionario dati di Health.md: attività, sonno, cuore, parametri vitali, corpo, alimentazione, mindfulness, farmaci, allenamenti, salute riproduttiva, sintomi, udito e metriche relative allo stile di vita e all'ambiente.</p>
</div>

## Override delle unità per visualizzazione

Inserisci `units` in un singolo blocco `health-viz` quando un grafico deve usare un sistema di visualizzazione diverso dalla preferenza globale del plugin:

```health-viz
type: workout-trends
metric: distance
units: imperial
```

Usa `auto` per seguire il sistema di unità dichiarato dall'esportazione, `metric` per visualizzare chilometri, chilogrammi, metri e Celsius, oppure `imperial` per visualizzare miglia, libbre, piedi e Fahrenheit. L'override si applica solo a questa visualizzazione e ha la precedenza sull'impostazione globale Units. Modifica solo i valori visualizzati; i file Health.md esportati restano invariati. Le metriche non convertibili, come passi, BPM, percentuali e calorie, non cambiano.

## Copertura attuale delle visualizzazioni

<div class="reference-stats">
<div><strong>43</strong><span>visualizzazioni attualmente disponibili nel plugin</span></div>
<div><strong>18</strong><span>categorie di dati esportati</span></div>
<div><strong>220+</strong><span>chiavi di esportazione canoniche</span></div>
<div><strong>1</strong><span>livello generico per le metriche ancora da realizzare</span></div>
</div>

## Supporto delle piattaforme per strumento di esportazione

Il supporto delle visualizzazioni dipende dalla disponibilità dei dati di origine sia in Apple HealthKit sia in Android Health Connect oppure dalla loro presenza esclusiva nel contratto di esportazione di Apple HealthKit.

### iOS e Android

Queste visualizzazioni corrispondono ai campi di esportazione condivisi da HealthKit e Health Connect:

| Categoria | Tipi di visualizzazione |
| --- | --- |
| Panoramica | `intro-stats`, `summary-card`, `trend-tile` |
| Attività | `activity-rings`, `vitals-rings`, `bar-chart`, `activity-heatmap`, `step-spiral`, `weekday-average` |
| Cuore | `heart-terrain`, `heart-range`, `hrv-trend` |
| Respirazione e parametri vitali | `oxygen-river`, `oxygen-range`, `breathing-wave` |
| Sonno | `sleep-schedule`, `sleep-quality-bars`, `sleep-architecture`, `sleep-polar` |
| Mobilità | `walking-symmetry`* |
| Allenamenti | `workout-log`, `workout-heart-rate`, `workout-zones`, `workout-trends`, `workout-intervals`, `workout-map` |

Note:

- `walking-symmetry` è supportato solo parzialmente su Android: Android dispone della velocità di camminata, ma non dei dati specifici di Apple relativi all'asimmetria o al doppio appoggio.
- `activity-rings` è supportato solo parzialmente su Android per l'obiettivo In piedi: quando `standHours` non è disponibile, il plugin utilizza una stima ricavata dai passi.
- I grafici dei percorsi e dei campioni degli allenamenti richiedono dati granulari sugli allenamenti e l'autorizzazione o il consenso per l'accesso ai percorsi.

### Solo iOS

Visualizzazioni di Stato d'animo / umore di HealthKit:

- `mood-trend` / `state-of-mind`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

Visualizzazioni del catalogo dei farmaci e degli eventi di assunzione:

- `medication-overview` / `medications` / `medication-adherence`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status` / `per-medication-dose-status`
- `medication-adherence-trend` / `medication-daily-adherence-trend`
- `medication-recent-dose-events` / `medication-dose-events`

Android Health Connect non rende disponibili record equivalenti a Stato d'animo di HealthKit né record del catalogo dei farmaci o degli eventi di assunzione nello stile di HealthKit.

### Solo Android

Il registro attuale delle visualizzazioni del plugin per Obsidian non ne include nessuna. Android esporta dati nativi, come risorse PHR/FHIR, allenamenti pianificati e intensità dell'attività, ma nessuna visualizzazione attuale usa ancora questi campi.

<span id="visualization-screenshot-gallery"></span>

## Catalogo delle visualizzazioni

Ogni elemento rimanda alla variante pubblica corrispondente nella [galleria delle visualizzazioni di Health.md](/visualizations/). Questi link utilizzano la variante `theme-colors`, affinché la documentazione rimanga veloce e stabile senza incorporare in questa pagina ogni strumento di rendering.

### Riepilogo e panoramica

- [Statistiche introduttive](/visualizations/overview-trends/intro-stats/theme-colors/) — `intro-stats`
- [Scheda di riepilogo](/visualizations/overview-trends/summary-card/theme-colors/) — `summary-card`
- [Riquadro delle tendenze](/visualizations/overview-trends/trend-tile/theme-colors/) — `trend-tile`

### Attività

- [Anelli attività](/visualizations/activity-fitness/activity-rings/theme-colors/) — `activity-rings`
- [Grafico a barre](/visualizations/activity-fitness/bar-chart/theme-colors/) — `bar-chart`
- [Mappa di calore dell'attività](/visualizations/activity-fitness/activity-heatmap/theme-colors/) — `activity-heatmap`
- [Spirale dei passi](/visualizations/activity-fitness/step-spiral/theme-colors/) — `step-spiral`
- [Media per giorno della settimana](/visualizations/activity-fitness/weekday-average/theme-colors/) — `weekday-average`

### Cuore

- [Profilo del battito cardiaco](/visualizations/heart-health/heart-terrain/theme-colors/) — `heart-terrain`
- [Intervallo della frequenza cardiaca](/visualizations/heart-health/heart-range/theme-colors/) — `heart-range`
- [Andamento HRV](/visualizations/heart-health/hrv-trend/theme-colors/) — `hrv-trend`

### Respirazione, ossigeno e parametri vitali

- [Flusso dell'ossigeno](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/) — `oxygen-river`
- [Intervallo dell'ossigeno](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/) — `oxygen-range`
- [Onda respiratoria](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/) — `breathing-wave`
- [Anelli dei parametri vitali](/visualizations/activity-fitness/vitals-rings/theme-colors/) — `vitals-rings`

### Sonno

- [Programma del sonno](/visualizations/sleep-analysis/sleep-schedule/theme-colors/) — `sleep-schedule`
- [Barre della qualità del sonno](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/) — `sleep-quality-bars`
- [Architettura del sonno](/visualizations/sleep-analysis/sleep-architecture/theme-colors/) — `sleep-architecture`
- [Grafico polare del sonno](/visualizations/sleep-analysis/sleep-polar/theme-colors/) — `sleep-polar`

### Mindfulness e umore

- [Andamento dell'umore](/visualizations/mindfulness-mood/mood-trend/theme-colors/) — `mood-trend`
- [Mappa di calore del calendario dell'umore](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/) — `mood-calendar-heatmap`
- [Grafico a dispersione umore × sonno](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/) — `mood-sleep-scatter`
- [Cronologia giornaliera dell'umore](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/) — `mood-day-timeline`
- [Umore per associazione](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/) — `mood-association-breakdown`
- [Nuvola di etichette dell'umore](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/) — `mood-label-cloud`
- [Volatilità dell'umore](/visualizations/mindfulness-mood/mood-volatility/theme-colors/) — `mood-volatility`
- [Umore quotidiano e momentaneo](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/) — `mood-kind-split`
- [Orologio circadiano dell'umore](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/) — `mood-circadian-clock`
- [Riquadro recupero + stato mentale](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/) — `mood-recovery-tile`
- [Matrice delle associazioni dell'umore](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/) — `mood-association-matrix`

### Farmaci

- [Panoramica dei farmaci](/visualizations/medication-adherence/medication-overview/theme-colors/) — `medication-overview`
- [Inventario dei farmaci](/visualizations/medication-adherence/medication-inventory/theme-colors/) — `medication-inventory`
- [Riepilogo dell'aderenza terapeutica](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/) — `medication-adherence-summary`
- [Stato delle dosi dei farmaci](/visualizations/medication-adherence/medication-dose-status/theme-colors/) — `medication-dose-status`
- [Andamento dell'aderenza terapeutica](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/) — `medication-adherence-trend`
- [Eventi di assunzione recenti](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/) — `medication-recent-dose-events`

### Mobilità, andatura e tecnica di corsa

- [Simmetria della camminata](/visualizations/mobility-gait/walking-symmetry/theme-colors/) — `walking-symmetry`

### Allenamenti

- [Registro degli allenamenti](/visualizations/workout-analytics/workout-log/theme-colors/) — `workout-log`
- [Frequenza cardiaca durante gli allenamenti](/visualizations/workout-analytics/workout-heart-rate/theme-colors/) — `workout-heart-rate`
- [Zone di allenamento](/visualizations/workout-analytics/workout-zones/theme-colors/) — `workout-zones`
- [Andamento degli allenamenti](/visualizations/workout-analytics/workout-trends/theme-colors/) — `workout-trends`
- [Intervalli degli allenamenti](/visualizations/workout-analytics/workout-intervals/theme-colors/) — `workout-intervals`
- [Mappa degli allenamenti](/visualizations/workout-analytics/workout-map/theme-colors/) — `workout-map`

## Roadmap dell'infrastruttura di base

La lacuna principale del prodotto non consiste in un singolo grafico mancante. È necessario un livello generico per le metriche, in grado di interpretare lo schema, che consenta di rappresentare qualsiasi campo esportato da Health.md senza dover creare un parser e uno strumento di rendering personalizzati per ogni metrica.

### Disponibile

- Rilevamento della compatibilità dello schema per esportazioni giornaliere, file precedenti, aggregazioni e file del dizionario dati.
- Caricamento da JSON, CSV, Markdown e Obsidian Bases.
- Riconoscimento delle aggregazioni, affinché i riepiloghi settimanali, mensili e annuali non alterino i grafici giornalieri.
- Navigazione dai punti del grafico al file Health.md di origine che ha fornito i dati.

### Pianificato

- **Sistema generico di accesso alle metriche in grado di interpretare lo schema** — lettura di `_healthmd_data_dictionary.json` per etichette, unità, categorie, regole di aggregazione e alias.
- **Andamento generico delle metriche** — grafico a linee/area per qualsiasi chiave numerica esportata.
- **Barre generiche delle metriche** — barre giornaliere/settimanali/mensili generalizzate con linee degli obiettivi e delle soglie.
- **Mappa di calore generica del calendario** — qualsiasi metrica numerica giornaliera rappresentata come griglia del calendario.
- **Rapporto sulla copertura delle visualizzazioni** — mostrare i campi presenti in un vault e quelli coperti da visualizzazioni dedicate.

---

## Riepilogo e panoramica

### Disponibile

- [`intro-stats`](/visualizations/overview-trends/intro-stats/theme-colors/) — riepilogo dell’insieme di dati con totali, medie, sonno e parametri vitali.
- [`summary-card`](/visualizations/overview-trends/summary-card/theme-colors/) — scheda KPI in stile Apple con sparkline e confronto con il periodo precedente.
- [`trend-tile`](/visualizations/overview-trends/trend-tile/theme-colors/) — scheda delle tendenze che confronta il periodo attuale con quello precedente.

### Pianificato

- Dashboard generata automaticamente in base ai campi presenti nella cartella Health.md selezionata.
- Dashboard della copertura dello schema per categoria di dati.
- Schede riepilogative delle correlazioni, come sonno e umore, HRV e allenamenti, sintomi e farmaci oppure alcol e sonno.

---

## Attività

Health.md esporta passi, energia attiva, energia basale, tempo di esercizio, tempo in piedi, piani di scale saliti, distanza percorsa camminando/correndo, ciclismo, nuoto, attività su sedia a rotelle, distanza nello sci alpino, tempo di movimento, sforzo fisico e VO₂ max.

### Disponibile

- [`activity-rings`](/visualizations/activity-fitness/activity-rings/theme-colors/)
- [`vitals-rings`](/visualizations/activity-fitness/vitals-rings/theme-colors/)
- [`bar-chart`](/visualizations/activity-fitness/bar-chart/theme-colors/)
- [`activity-heatmap`](/visualizations/activity-fitness/activity-heatmap/theme-colors/)
- [`step-spiral`](/visualizations/activity-fitness/step-spiral/theme-colors/)
- [`weekday-average`](/visualizations/activity-fitness/weekday-average/theme-colors/)

### Pianificato

- Dashboard del carico di attività per passi, calorie, esercizio, ore in piedi e sforzo fisico.
- Andamento del VO₂ max.
- Grafico della costanza degli obiettivi Movimento / Esercizio / In piedi.
- Grafico della distribuzione delle distanze tra camminata/corsa, ciclismo, nuoto, sedia a rotelle e sport sulla neve.
- Grafico della distanza a nuoto e delle bracciate.
- Grafico della distanza e delle spinte su sedia a rotelle.

---

## Sonno

Health.md esporta durata totale del sonno, ora di coricamento, ora del risveglio, durata delle fasi profonda/REM/centrale/veglia/a letto e intervalli granulari delle fasi del sonno.

### Disponibile

- [`sleep-schedule`](/visualizations/sleep-analysis/sleep-schedule/theme-colors/)
- [`sleep-quality-bars`](/visualizations/sleep-analysis/sleep-quality-bars/theme-colors/)
- [`sleep-architecture`](/visualizations/sleep-analysis/sleep-architecture/theme-colors/)
- [`sleep-polar`](/visualizations/sleep-analysis/sleep-polar/theme-colors/)

### Pianificato

- Debito di sonno e punteggio di regolarità.
- Andamento del rapporto tra le fasi del sonno.
- Mappa di calore della regolarità degli orari di coricamento e risveglio.
- Dashboard del recupero con sonno, HRV e frequenza cardiaca a riposo.

---

## Cuore

Health.md esporta frequenza cardiaca a riposo, frequenza cardiaca durante la camminata, frequenza cardiaca media/minima/massima, HRV, campioni della frequenza cardiaca, campioni HRV, recupero della frequenza cardiaca e carico di fibrillazione atriale.

### Disponibile

- [`heart-terrain`](/visualizations/heart-health/heart-terrain/theme-colors/)
- [`heart-range`](/visualizations/heart-health/heart-range/theme-colors/)
- [`hrv-trend`](/visualizations/heart-health/hrv-trend/theme-colors/)

### Pianificato

- Andamento della frequenza cardiaca a riposo.
- Andamento della frequenza cardiaca durante la camminata.
- Andamento del recupero della frequenza cardiaca.
- Grafico del carico di fibrillazione atriale.
- Riquadro del recupero con HRV e frequenza cardiaca a riposo.
- Profilo circadiano della frequenza cardiaca per ora del giorno.

---

## Respirazione e ossigeno

Health.md esporta valori medi/minimi/massimi dell'ossigeno nel sangue, campioni dell'ossigeno nel sangue, valori medi/minimi/massimi della frequenza respiratoria e campioni della frequenza respiratoria.

### Disponibile

- [`oxygen-river`](/visualizations/respiratory-oxygen/oxygen-river/theme-colors/)
- [`oxygen-range`](/visualizations/respiratory-oxygen/oxygen-range/theme-colors/)
- [`breathing-wave`](/visualizations/respiratory-oxygen/breathing-wave/theme-colors/)

### Pianificato

- Grafico dedicato dell'intervallo respiratorio.
- Grafico degli episodi di desaturazione dell'ossigeno.
- Dashboard respiratoria notturna che combini fasi del sonno, ossigeno e frequenza respiratoria.

---

## Parametri vitali

Health.md esporta temperatura corporea, pressione arteriosa, glicemia, temperatura corporea basale, temperatura del polso, attività elettrodermica, capacità vitale forzata, FEV1, picco di flusso espiratorio e utilizzo dell'inalatore.

### Disponibile

- Copertura parziale tramite schede di riepilogo e grafici giornalieri generici.

### Pianificato

- Grafico dell'intervallo della pressione arteriosa sistolica/diastolica con fasce di soglia.
- Grafico dell'intervallo glicemico.
- Andamento della temperatura corporea, basale e del polso.
- Riquadro della temperatura del polso per recupero/malattia.
- Dashboard della funzione respiratoria per FVC, FEV1, picco di flusso e utilizzo dell'inalatore.
- Andamento dell'attività elettrodermica / stress.

---

## Misure corporee

Health.md esporta peso, altezza, BMI, percentuale di grasso corporeo, massa magra e circonferenza vita.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata alla composizione corporea.

### Pianificato

- Dashboard della composizione corporea.
- Andamento del peso con media mobile e linea dell'obiettivo.
- Andamento del BMI con fasce delle categorie.
- Grafico del grasso corporeo rispetto alla massa magra.
- Andamento della circonferenza vita.

---

## Mobilità, andatura e tecnica di corsa

Health.md esporta velocità di camminata, lunghezza del passo, doppio appoggio, asimmetria della camminata, velocità di salita/discesa delle scale, cammino di sei minuti, stabilità della camminata, velocità di corsa, lunghezza della falcata, tempo di contatto con il suolo, oscillazione verticale e potenza di corsa.

### Disponibile

- [`walking-symmetry`](/visualizations/mobility-gait/walking-symmetry/theme-colors/)

### Pianificato

- Dashboard dell'andatura.
- Indicatore della stabilità della camminata.
- Andamento del cammino di sei minuti.
- Grafico della velocità di salita/discesa delle scale.
- Dashboard della tecnica di corsa per velocità, falcata, contatto con il suolo, oscillazione verticale e potenza.

---

## Allenamenti

Health.md esporta numero di allenamenti, minuti, calorie, distanza, tipi di allenamento, statistiche della frequenza cardiaca, metriche tecniche di corsa/ciclismo, potenza, altitudine, giri, frazioni, punti del percorso, zone di frequenza cardiaca e campioni delle serie temporali degli allenamenti.

### Disponibile

- [`workout-log`](/visualizations/workout-analytics/workout-log/theme-colors/)
- [`workout-heart-rate`](/visualizations/workout-analytics/workout-heart-rate/theme-colors/)
- [`workout-zones`](/visualizations/workout-analytics/workout-zones/theme-colors/)
- [`workout-trends`](/visualizations/workout-analytics/workout-trends/theme-colors/)
- [`workout-intervals`](/visualizations/workout-analytics/workout-intervals/theme-colors/)
- [`workout-map`](/visualizations/workout-analytics/workout-map/theme-colors/)

### Pianificato

- Mappa di calore del calendario degli allenamenti.
- Grafico del carico di allenamento basato su durata e intensità.
- Distribuzione settimanale degli allenamenti per tipo.
- Andamento del passo e della velocità per tipo di allenamento.
- Andamento del dislivello positivo/negativo.
- Piccoli multipli per il confronto dei percorsi.
- Curva di potenza / migliori prestazioni.
- Dashboard della tecnica di corsa e delle prestazioni ciclistiche.

---

## Mindfulness e umore

Health.md esporta minuti di mindfulness, sessioni di mindfulness, registrazioni di Stato d'animo, valenza media, umore quotidiano, emozioni momentanee, etichette e associazioni.

### Disponibile

- [`mood-trend`](/visualizations/mindfulness-mood/mood-trend/theme-colors/)
- [`mood-calendar-heatmap`](/visualizations/mindfulness-mood/mood-calendar-heatmap/theme-colors/)
- [`mood-sleep-scatter`](/visualizations/mindfulness-mood/mood-sleep-scatter/theme-colors/)
- [`mood-day-timeline`](/visualizations/mindfulness-mood/mood-day-timeline/theme-colors/)
- [`mood-association-breakdown`](/visualizations/mindfulness-mood/mood-association-breakdown/theme-colors/)
- [`mood-label-cloud`](/visualizations/mindfulness-mood/mood-label-cloud/theme-colors/)
- [`mood-volatility`](/visualizations/mindfulness-mood/mood-volatility/theme-colors/)
- [`mood-kind-split`](/visualizations/mindfulness-mood/mood-kind-split/theme-colors/)
- [`mood-circadian-clock`](/visualizations/mindfulness-mood/mood-circadian-clock/theme-colors/)
- [`mood-recovery-tile`](/visualizations/mindfulness-mood/mood-recovery-tile/theme-colors/)
- [`mood-association-matrix`](/visualizations/mindfulness-mood/mood-association-matrix/theme-colors/)

### Pianificato

- Andamento dei minuti di mindfulness.
- Serie/calendario delle sessioni di mindfulness.
- Umore e aderenza terapeutica.
- Umore in relazione ad alimentazione, alcol e caffeina.
- Cronologia delle etichette dell'umore.

---

## Farmaci

Health.md esporta inventario dei farmaci, conteggi di farmaci attivi/archiviati, numero di eventi di assunzione, conteggi delle dosi assunte/saltate, dettagli dei farmaci, metadati RxNorm/di codifica, quantità delle dosi, tipo di programma, date pianificate/di inizio/di fine, stati e metadati.

### Disponibile

- [`medication-overview`](/visualizations/medication-adherence/medication-overview/theme-colors/)
- [`medication-inventory`](/visualizations/medication-adherence/medication-inventory/theme-colors/)
- [`medication-adherence-summary`](/visualizations/medication-adherence/medication-adherence-summary/theme-colors/)
- [`medication-dose-status`](/visualizations/medication-adherence/medication-dose-status/theme-colors/)
- [`medication-adherence-trend`](/visualizations/medication-adherence/medication-adherence-trend/theme-colors/)
- [`medication-recent-dose-events`](/visualizations/medication-adherence/medication-recent-dose-events/theme-colors/)

### Pianificato

- Cronologia del programma dei farmaci.
- Mappa di calore del calendario dell'aderenza terapeutica.
- Grafico dei ritardi nell'assunzione dei farmaci, con confronto tra orario programmato e orario effettivo.
- Andamento della quantità delle dosi.
- Viste delle correlazioni tra farmaci e sintomi/umore.
- Pannello dei dettagli RxNorm / di codifica.

---

## Alimentazione

Health.md esporta calorie alimentari, proteine, carboidrati, grassi, grassi saturi, grassi monoinsaturi, grassi polinsaturi, fibre, zuccheri, sodio, colesterolo, acqua e caffeina.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata all'alimentazione.

### Pianificato

- Dashboard dell'alimentazione.
- Grafico della ripartizione dei macronutrienti.
- Grafico delle calorie assunte rispetto alle calorie attive.
- Andamento dell'idratazione.
- Grafico della quantità giornaliera / degli orari di assunzione della caffeina.
- Grafici delle soglie di zuccheri e sodio.
- Avanzamento verso gli obiettivi di fibre e proteine.

---

## Vitamine e minerali

Health.md esporta vitamine A, B6, B12, C, D, E, K, tiamina, riboflavina, niacina, folati, biotina, acido pantotenico, calcio, ferro, potassio, magnesio, fosforo, zinco, selenio, rame, manganese, cromo, molibdeno, cloruro e iodio.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata ai micronutrienti.

### Pianificato

- Mappa di calore dei micronutrienti.
- Griglia di avanzamento rispetto ai valori giornalieri raccomandati.
- Dashboard dell'andamento delle vitamine.
- Dashboard dell'andamento dei minerali.
- Pannello di segnalazione di carenze/eccessi.
- Punteggio di completezza nutrizionale.

---

## Udito

Health.md esporta il livello audio delle cuffie e il livello sonoro ambientale.

### Disponibile

- Solo copertura parziale a livello di riepilogo.

### Pianificato

- Andamento dell'esposizione sonora.
- Calendario dei giorni rumorosi.
- Fasce delle soglie di esposizione sicura.
- Riepilogo settimanale dell'esposizione.

---

## Salute riproduttiva e monitoraggio del ciclo

Health.md esporta flusso mestruale, attività sessuale, risultato del test di ovulazione, qualità del muco cervicale e sanguinamento intermestruale.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata alla salute riproduttiva.

### Pianificato

- Calendario del ciclo.
- Mappa di calore del flusso mestruale.
- Cronologia dei segnali di fertilità.
- Sovrapposizione dei sintomi del ciclo che combini salute riproduttiva, sintomi, umore e sonno.
- Cronologia dello spotting / sanguinamento intermestruale.

---

## Sintomi

Health.md esporta i conteggi giornalieri dei sintomi relativi a mal di testa, affaticamento, nausea, vertigini, cambiamenti dell'umore, cambiamenti del sonno, cambiamenti dell'appetito, vampate di calore, brividi, febbre, dolore lombare, gonfiore, stitichezza, diarrea, bruciore di stomaco, tosse, mal di gola, naso che cola, respiro affannoso, dolore toracico, battito saltato, battito accelerato, acne, pelle secca, perdita di capelli, vuoti di memoria, sudorazione notturna, vomito, crampi addominali, dolore al seno, dolore pelvico, dolori muscolari, svenimento, perdita dell'olfatto, perdita del gusto, respiro sibilante, congestione dei seni paranasali, incontinenza urinaria e secchezza vaginale.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata ai sintomi.

### Pianificato

- Mappa di calore del calendario dei sintomi.
- Classifica della frequenza dei sintomi.
- Matrice di co-occorrenza dei sintomi.
- Cronologia delle riacutizzazioni.
- Esploratore delle correlazioni dei sintomi.
- Dashboard dei sintomi raggruppati per apparato corporeo.

---

## Altri dati sanitari, sullo stile di vita e sull'ambiente

Health.md esporta esposizione ai raggi UV, tempo trascorso alla luce del giorno, cadute, tasso alcolemico, bevande alcoliche, somministrazione di insulina, lavaggio dei denti, lavaggio delle mani, temperatura dell'acqua e profondità subacquea.

### Disponibile

- Non è ancora disponibile una visualizzazione dedicata allo stile di vita e all'ambiente.

### Pianificato

- Calendario della luce diurna / dei raggi UV.
- Cronologia delle cadute.
- Grafico dell'alcol rispetto a sonno / HRV.
- Andamento della somministrazione di insulina.
- Serie del lavaggio dei denti e delle mani.
- Grafico della temperatura dell'acqua / profondità subacquea.

---

## Ordine di priorità

1. Infrastruttura generica per le metriche in grado di interpretare lo schema.
2. Visualizzazioni generiche per andamento, barre e mappa di calore del calendario.
3. Suite dei parametri vitali: pressione arteriosa, glicemia, temperatura e funzione respiratoria.
4. Dashboard della composizione corporea.
5. Dashboard dell'alimentazione.
6. Mappa di calore, classifica e viste delle correlazioni dei sintomi.
7. Calendario del ciclo / della salute riproduttiva.
8. Mappa di calore dei micronutrienti e griglia RDA.
9. Dashboard ampliata della mobilità e della tecnica di corsa.
10. Grafici dell'udito e dello stile di vita/ambiente.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Ultimo aggiornamento: 25 giugno 2026</p>
