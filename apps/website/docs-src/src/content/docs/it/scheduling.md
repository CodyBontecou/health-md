---
title: "Programmare le esportazioni di Apple Health e risolvere le esecuzioni mancate"
description: "Verifica le esportazioni programmate, la finestra dei giorni completi e il recupero. iOS non garantisce l’ora; Riprova nella cronologia usa le impostazioni attuali."
---

Questa pagina descrive la programmazione su iPhone. Android ha autorizzazioni in background e requisiti di acquisto diversi; consulta [Automazione Android](/it/docs/android/).

## Verifica la prima esportazione programmata

1. Attiva il profilo previsto. Controlla metriche, formati, dettaglio dei dati, modalità di scrittura e destinazione. Esporta manualmente un giorno completo e verifica il file o il risultato dell’endpoint prima di automatizzare.
2. Apri Programmazione e Configura o Gestisci programmazione. Attivala, scegli Giornaliera, Settimanale o Personalizzata, imposta l’ora e inizia con un giorno completo di retrospettiva. Consenti le notifiche per i promemoria locali di recupero.
3. Controlla attivazione, prossima esecuzione e ultimo risultato. Dopo un tentativo, verifica cronologia e destinazione effettiva; una data prevista o una notifica non dimostra una scrittura.
4. Controlla date, unità, copertura e dati mancanti. Un file salvato da solo non dimostra un’acquisizione completa.

Su Apple, una richiesta programmata che esporta almeno una data condivide le cinque azioni gratuite con le esportazioni manuali e le altre azioni conteggiate. Full Access elimina il limite condiviso. Consulta [Sblocco e acquisti](/it/docs/paywall/).

## Comprendi la finestra dei giorni completi

Le frequenze giornaliera, settimanale e personalizzata possono avere una retrospettiva. La personalizzata si ripete ogni N giorni, settimane o mesi dalla data iniziale. Ogni nuova esecuzione riesporta l’intera finestra configurata, anche date già esportate. Tre giorni comprendono ieri e i due giorni precedenti; un ritardo mantiene il riferimento al giorno programmato.

L’aggiornamento di oggi è indipendente e non sostituisce questa finestra. Controlla percorsi e modalità di scrittura prima di sovrapporre esportazioni; istantanee giornaliere ripetute non sono nuove misurazioni.

## Scegli il recupero corretto

- **Recupero programmato in sospeso:** sblocca l’iPhone, apri Health.md e controlla il tentativo. Conserva date esatte non risolte, impostazioni salvate e destinazione. I giorni completati restano completati; il recupero non amplia la retrospettiva.
- **Riprova dalla cronologia:** avvia una nuova esecuzione per l’intervallo con impostazioni e destinazione attuali e crea una nuova riga. Controlla prima la configurazione attiva. Non riprende il tentativo congelato.
- **Destinazione modificata o non disponibile:** ripristina l’accesso o verifica il profilo in sospeso. Un vecchio recupero API su iPhone non deve adottare silenziosamente un altro endpoint o credenziale. Non avviare nuovi tentativi ripetuti mentre l’originale è irrisolto.

Consulta [Profili di esportazione](/it/docs/export-profiles/) per recupero, identità e destinazioni.

## Cosa garantisce iOS e cosa no

L’ora è un obiettivo, non una fine garantita. iOS controlla l’esecuzione in background e il blocco può impedire letture HealthKit. Richieste e notifiche silenziose non aggirano questa protezione.

I promemoria locali richiedono il permesso per le notifiche e non garantiscono la consegna all’ora prevista. Se ne ricevi uno, sblocca il dispositivo e aprilo per tentare il recupero. Altrimenti apri Health.md e controlla richieste e cronologia. Verifica il risultato invece di dedurre il successo da un avviso o dal tempo trascorso.

## Controllo programmatico
<p>Puoi attivare o disattivare la programmazione da Comandi Rapidi usando l'intento <em>Attiva o disattiva l'esportazione programmata</em>. <a href="/it/docs/shortcuts/">Consulta Comandi Rapidi</a> per alcuni esempi.</p>

## Pianificazioni per profilo e annullamento

- Ogni profilo conserva la propria pianificazione, compresa una cadenza personalizzata; cambiare profilo attivo non reindirizza un’altra pianificazione.
- Un avviso di collisione compare quando i profili potrebbero scrivere gli stessi percorsi generati nella stessa destinazione. Verificalo prima di attivare pianificazioni concorrenti; Health.md non modifica silenziosamente alcun profilo.
- Interrompere o Annullare termina solo il tentativo corrente. Le date completate restano tali, le altre possono essere riprovate e la pianificazione resta attiva.
- Ogni riga della cronologia resta legata al profilo di esecuzione e all’etichetta privata della destinazione effettiva.

Gestisci impostazioni congelate e destinazione in [Profili di esportazione](/it/docs/export-profiles/).

## Contenuti correlati

<div class="related">
  <a href="/it/docs/export-profiles/"><span>Profili</span>Gestisci pianificazioni e destinazioni indipendenti.</a>
  <a href="/it/docs/export/"><span>Manuale</span>Esportazione — per intervalli di date occasionali.</a>
  <a href="/it/docs/shortcuts/"><span>Automatizza</span>Comandi Rapidi — attiva o disattiva la programmazione tramite automazioni.</a>
  <a href="/it/docs/sync/"><span>Tra dispositivi</span>Sincronizzazione con il Mac — programma anche sul Mac.</a>
</div>
