---
title: "Dati mancanti nell’esportazione Apple Health? Risolvi con Health.md"
description: "Risolvi esportazioni vuote di Apple Health o Health Connect, sonno mancante, dettagli CSV, errori di scrittura e ritardi. Verifica prima un giorno."
---

Se mancano dati in un'esportazione Apple Health o Health Connect, distingui un **problema di lettura** da un **problema di scrittura del file**. Un dato assente non è uno zero misurato.

## Inizia da un giorno verificabile

1. Conferma un valore registrato e la sua data in Apple Health o Health Connect. Attendi la sincronizzazione dell'orologio o dell'app di origine.
2. In Health.md controlla profilo attivo, metrica, date, formato e destinazione. Inizia con una metrica supportata per un giorno concluso.
3. Sblocca il telefono, apri Health.md e usa l'anteprima se disponibile. Poi esporta e verifica risultato e destinazione effettivi. L'anteprima non dimostra che il file sia stato salvato.

Consulta la [prima esportazione iPhone](/it/docs/iphone-first-export/) o la [configurazione Android](/it/docs/android/).

## L'origine contiene dati, ma l'esportazione è vuota

Su iPhone controlla le categorie consentite a Health.md in Apple Health. **HealthKit non rivela se il permesso di lettura è stato negato**. Un risultato vuoto non distingue l'accesso limitato dall'assenza di record corrispondenti. Una richiesta di autorizzazione riuscita non conferma tutte le categorie. Vedi la [documentazione Apple](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Su Android verifica che l'app di origine abbia scritto il record in Health Connect e che Health.md possa leggere quel tipo supportato. Dati visibili solo in un'altra app potrebbero non essere esportabili. Vedi la [lista di controllo Google](https://support.google.com/android/answer/13770384).

Dopo la sincronizzazione o una modifica dei permessi, ricontrolla metrica e data. Non sostituire i valori mancanti con zero.

Se un risultato strutturato riporta `complete_empty`, distinguilo da output non supportato, parziale, saltato o non riuscito. Non dimostra uno zero misurato né rivela una decisione sul permesso di lettura.

## Il sonno della scorsa notte manca da Oggi

Health.md usa una finestra locale del sonno **da mezzogiorno a mezzogiorno** su Apple e Android. Martedì mattina esporta **Ieri** (lunedì), anche per il sonno iniziato dopo mezzanotte di martedì, oppure lunedì e martedì per sonno e attività. Se la fonte sincronizza tardi, ripeti il giorno del diario. Vedi gli [esempi di date](/it/docs/sleep-date-attribution/#sleep-date-examples).

## L'anteprima mostra dati, ma la cartella è vuota

Su iPhone, controlla se il profilo attivo scrive in una cartella locale, Connected Mac o API Endpoint. Per i file verifica cartella, sottocartella, nome e risultato: scritto, saltato o non riuscito. Un file saltato può dipendere dal comportamento di scrittura scelto. Riseleziona una cartella non disponibile e verifica il provider. Vedi [cartelle e vault](/it/docs/folder-vault/) e [profili](/it/docs/export-profiles/).

## Il CSV contiene totali, non le letture attese

Su iPhone, Summary e Detailed Time-Series offrono dettagli diversi. Controlla Data Detail e metriche prima di ampliare le date. I metadati non sono misurazioni di salute. Conserva le unità e distingui totali giornalieri e record di origine. Lossless Health Records ha uno stato di acquisizione separato; un riepilogo non prova l'acquisizione completa. Vedi la [guida a formati e copertura](/it/docs/reference/export-formats/).

## Un'esportazione pianificata non arriva

Le attività iOS e Android WorkManager usano orari obiettivo, senza garantire la consegna. Sblocca il dispositivo, apri Health.md e controlla cronologia e recupero in sospeso prima di avviare un'altra esecuzione. Una notifica non dimostra una scrittura riuscita. Vedi la [pianificazione iPhone](/it/docs/scheduling/) o l'[automazione Android](/it/docs/android/).

## Timeout CLI

Un timeout non annulla un job accettato:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Prima di dichiarare completezza verifica stato, date mancanti, copertura, `next_cursor`, versione e limiti. `--allow-partial` cambia solo la politica d’uscita.

## Chiedi aiuto senza condividere dati di salute

Indica versione dell’app e del sistema, piattaforma, formato e se mancano dati, viene saltato un file o fallisce la scrittura. Oscura le informazioni private nelle schermate e nei log. Non pubblicare valori di salute, percorsi, documenti clinici, token, codici di abbinamento o percorsi privati.

<div class="related"><a href="/it/docs/cli-jobs/"><span>Job</span>Riprendi e annulla.</a><a href="/it/docs/release-status/"><span>Versioni</span>Compatibilità.</a></div>
