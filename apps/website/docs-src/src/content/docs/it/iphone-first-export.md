---
title: "Prima esportazione da iPhone"
description: "Autorizza Apple Health, scegli una destinazione in File, visualizza l’anteprima dell’output di Health.md, esegui una piccola prima esportazione da iPhone e verifica i file scritti."
---

Segui questa procedura per produrre un’esportazione piccola e verificabile prima di modificare metriche, formattazione o automazione. Health.md legge esclusivamente le categorie di Apple Health autorizzate da iOS e scrive i file generati nella cartella scelta.

<div class="availability available">
<strong>Disponibile ora · Health.md per iPhone</strong>
<p>Le esportazioni richiedono una prova attiva, un abbonamento o l’accesso Lifetime. Puoi configurare pianificazioni e altre automazioni in seguito.</p>
</div>

## Prima di iniziare

Prima di iniziare, assicurati di avere:

- [Health.md su App Store](https://apps.apple.com/app/health-md/id6757763969), installato su un iPhone con dati di Apple Health
- l’autorizzazione a leggere almeno una categoria di Apple Health
- una cartella scrivibile in File: iCloud Drive, Sul mio iPhone o un vault di Obsidian.

Mantieni le metriche predefinite e il formato Markdown. Seleziona **Ieri** per un intervallo di un giorno.

## 1. Completa la configurazione dell’iPhone

Health.md mostra cinque passaggi di configurazione. Nessuno è bloccante: l’accesso ad Apple Health e la cartella possono essere saltati e sistemati in seguito.

Al primo avvio, tocca **Collega Apple Health**. Autorizza le categorie di dati sanitari desiderate, esamina l’output di esempio, scegli una cartella in File e prosegui fino all’ultimo passaggio.

Dopo la configurazione, l’app si apre su **Archivio**. Se Apple Health o la cartella richiedono un intervento, la scheda **Richiede attenzione** in alto indica cosa correggere.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Apri lo screenshot della configurazione a dimensione intera">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Configurazione di Health.md al passaggio 1 di 5 con tre passaggi elencati e il pulsante per collegare Apple Health." />
  </a>
  <figcaption>La configurazione spiega cosa legge Health.md e dove vanno i file prima di chiedere l’accesso. L'interfaccia di questa schermata resta in inglese.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Apri lo screenshot di Esporta ora a dimensione intera">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Foglio Esporta ora di Health.md con Ieri selezionato, un interruttore per il solo riepilogo dell’intervallo, un riepilogo di un file per un giorno e un pulsante di esportazione." />
  </a>
  <figcaption>Esporta ora mostra cosa verrà scritto prima di iniziare. Anche questa schermata di riferimento mostra l'interfaccia in inglese.</figcaption>
</figure>
</div>

## 2. Scegli una piccola esportazione

Tocca il pulsante rotondo **Esporta ora** accanto alla barra delle schede. Poi:

1. Seleziona **Ieri**.
2. Lascia disattivato **Solo riepilogo dell'intervallo**.
3. Verifica che **Verrà scritto** indichi la tua cartella e circa un file per un giorno.

L’automazione predefinita usa la selezione di metriche predefinita e **Markdown**. Per modificarle, apri **Automazioni**, scegli l’automazione e poi **Metriche** o **Formati**. Aggiungi CSV, JSON o Obsidian Bases dopo che questa esportazione è riuscita. Un intervallo breve rende più facile individuare problemi di autorizzazione, di dati vuoti e di cartella.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/it/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Apri lo screenshot della selezione delle metriche a dimensione intera">
    <img src="/docs/assets/docs/it/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Pagina Metriche di Health.md con il numero di metriche attive, i pulsanti Consigliato, Seleziona tutto e Deseleziona tutto, un campo di ricerca e categorie con i conteggi." />
  </a>
  <figcaption>Il totale delle metriche dipende dalla versione dell’app e dalle autorizzazioni. Questa schermata localizzata mostra 217 metriche attive su 219.</figcaption>
</figure>

## 3. Controlla l’anteprima prima di scrivere

In **Esporta ora**, tocca **Anteprima**. L’anteprima richiede l’accesso ad Apple Health, ma non una cartella scrivibile.

Usa l’anteprima per individuare un problema di autorizzazione di Apple Health prima di provare la cartella.

Verifica che l’anteprima mostri:

- la data richiesta
- i nomi delle metriche e le unità previsti
- valori mancanti o non disponibili invece di falsi zeri
- il formato scelto e la struttura del nome file.

Chiudi l’anteprima e modifica le impostazioni dell’automazione se devi cambiare metriche o formati.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/it/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Apri lo screenshot dell’anteprima a dimensione intera">
    <img src="/docs/assets/docs/it/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Anteprima esportazione di Health.md con la finestra del sonno, la stima di un giorno in Markdown, il periodo di riepilogo, la cartella di destinazione e il nome file generato." />
  </a>
  <figcaption>Questo esempio usa dati sanitari di prova.</figcaption>
</figure>

## 4. Esporta e verifica

Tocca **Esporta ieri**. Se la configurazione è incompleta, Health.md indica cosa manca tra Apple Health e cartella.

Al termine dell’esportazione:

1. Controlla nel risultato i file scritti, saltati o non riusciti. Il giorno compare nel calendario di **Archivio**.
2. Apri l’app File e la cartella scelta.
3. Apri un file generato e verifica che data, unità e frontmatter siano corretti.
4. Conserva i dettagli del risultato se devi indagare su un problema.

Un giorno coperto nel calendario è un riepilogo; tocca il giorno per vedere lo stato di ogni automazione in quella data.

<div class="callout">
<strong>Nessun dato per il giorno scelto?</strong>
<p style="margin-top:6px;">Scegli un giorno con dati di attività o sonno. Poi controlla l’autorizzazione di Apple Health e la selezione delle metriche. Un intervallo vuoto non è un errore di scrittura.</p>
</div>

## Passaggi successivi

<div class="related">
  <a href="/it/docs/metrics/"><span>Scegli i dati</span>Cerca le metriche di Apple Health e modifica le categorie o le autorizzazioni speciali.</a>
  <a href="/it/docs/format/"><span>Definisci l’output</span>Configura formati, date, unità, frontmatter, modelli e nomi file.</a>
  <a href="/it/docs/scheduling/"><span>Automatizza</span>Configura esportazioni programmate ricorrenti dopo aver verificato un’esecuzione manuale.</a>
  <a href="/it/docs/folder-vault/"><span>Correggi una destinazione</span>Comprendi i provider di File, l’accesso alle cartelle e il ripristino.</a>
</div>
