---
title: "Prima esportazione da iPhone"
description: "Autorizza Apple Health, scegli una destinazione in File, visualizza l’anteprima dell’output di Health.md, esegui una piccola prima esportazione da iPhone e verifica i file scritti."
---

Segui questa procedura per produrre un’esportazione piccola e verificabile prima di modificare metriche, formattazione o automazione. Health.md legge esclusivamente le categorie di Apple Health autorizzate da iOS e scrive i file generati nella cartella scelta.

<div class="availability available">
<strong>Disponibile ora · Health.md per iPhone</strong>
<p>La prima esportazione rientra nella disponibilità gratuita. L’esportazione programmata e le altre funzionalità a pagamento possono essere configurate in seguito.</p>
</div>

## Prima di iniziare

Occorrono:

- Health.md installato su un iPhone che contiene dati di Apple Health;
- l’autorizzazione a leggere almeno una categoria di Apple Health;
- una destinazione scrivibile in File, come iCloud Drive, Su iPhone o un vault di Obsidian.

Per una prima esecuzione più rapida, mantieni le metriche predefinite e l’output Markdown. Inizia con **Ieri** o con un altro intervallo di un giorno, anziché con tutta la cronologia disponibile.

## 1. Completa la configurazione su iPhone

Al primo avvio, tocca **Avvia configurazione** e completa i sette passaggi iniziali. Autorizza le categorie di dati sanitari desiderate, esamina l’output di esempio, scegli una cartella in File e prosegui fino a **Pronto**. Quando compare il passaggio per lo sblocco, puoi continuare con la disponibilità gratuita.

Se hai già completato la configurazione iniziale, apri il pannello **Esportazione** e verifica che Apple Health e la cartella locale siano pronti. Usa il controllo della cartella per sostituire una destinazione mancante o non accessibile.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Apri a dimensione intera l’immagine della configurazione iniziale">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Schermata iniziale di benvenuto di Health.md al passaggio 1 di 7, con il pulsante Start Setup in inglese." />
  </a>
  <figcaption>Start Setup presenta l’archivio locale, le note programmate e il modello basato sulle cartelle prima di richiedere l’accesso. Il contenuto in primo piano della configurazione iniziale rimane in inglese.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Apri a dimensione intera l’immagine di riferimento in inglese relativa alla configurazione richiesta">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Pannello Export di Health.md in inglese, con Health non connesso, Choose Folder disponibile, Local iPhone Folder selezionato e pulsanti per l’intervallo di date." />
  </a>
  <figcaption>Gli indicatori di stato rendono esplicita la configurazione mancante di Health e della cartella. Questa acquisizione di riferimento del simulatore rimane in inglese e mostra intenzionalmente entrambi i requisiti incompleti.</figcaption>
</figure>
</div>

## 2. Scegli una piccola esportazione

Nel pannello Esportazione:

1. Seleziona **Cartella locale su iPhone** come destinazione.
2. Scegli **Ieri** o un intervallo personalizzato di un giorno.
3. Mantieni la selezione predefinita delle metriche per la prima esecuzione.
4. Mantieni selezionato **Markdown**. Potrai aggiungere CSV, JSON o Obsidian Bases dopo aver verificato il corretto funzionamento del percorso di base.

Un intervallo breve rende più semplici da comprendere i problemi relativi alle autorizzazioni, alle categorie vuote e alla destinazione. Evita inoltre di scambiare una prima richiesta di lunga durata per un’esportazione non riuscita.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/it/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Apri a dimensione intera l’immagine della selezione delle metriche">
    <img src="/docs/assets/docs/it/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Schermata Metriche sanitarie con 217 metriche abilitate su 219, l’interruttore delle metriche standard attivo, il campo di ricerca e le categorie espandibili Sonno, Attività e Cuore." />
  </a>
  <figcaption>Il totale delle metriche dipende dalla versione dell’app installata e dalle autorizzazioni. Questa acquisizione localizzata mostra 217 metriche abilitate su 219 e le metriche standard attive; non è necessario raggiungere questo totale per la prima esportazione.</figcaption>
</figure>

## 3. Visualizza l’anteprima prima della scrittura

Tocca **Anteprima**. L’anteprima richiede l’accesso ad Apple Health, ma non necessita di una cartella locale scrivibile; è quindi utile per distinguere un problema di autorizzazione alla lettura da un problema relativo a File.

Verifica che l’anteprima mostri:

- la data richiesta;
- i nomi e le unità previsti per le metriche;
- valori mancanti o non disponibili indicati esplicitamente, anziché zeri inventati;
- il formato selezionato e la struttura del nome file.

Torna al pannello Esportazione se devi modificare date, metriche o formattazione.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/it/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Apri a dimensione intera l’immagine dell’anteprima dell’esportazione">
    <img src="/docs/assets/docs/it/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Anteprima esportazione di Health.md che mostra la stima di un’esportazione Markdown di un giorno, i periodi di riepilogo, la destinazione e il nome file generato." />
  </a>
  <figcaption>L’anteprima separa l’esame dell’output dalla scrittura. Questa acquisizione deterministica per la documentazione usa dati sanitari di esempio e indica esplicitamente che non è selezionato alcun vault.</figcaption>
</figure>

## 4. Esporta e verifica

Tocca **Esporta dati**. Se la configurazione è incompleta, Health.md indica il requisito mancante relativo a Health o alla cartella, anziché avviare silenziosamente una scrittura parziale.

Al termine:

1. Esamina il risultato nell’app per controllare i file scritti, ignorati o non riusciti.
2. Apri l’app File e raggiungi la cartella selezionata.
3. Apri uno dei file generati e verificane la data, le unità e il frontmatter.
4. Conserva i dettagli del risultato per la risoluzione dei problemi; non presumere che l’operazione sia riuscita solo perché il pulsante è tornato allo stato inattivo.

<div class="callout">
<strong>Nessun dato per il giorno selezionato?</strong>
<p style="margin-top:6px;">Prova un giorno in cui sai che sono presenti dati relativi all’attività o al sonno, quindi verifica l’autorizzazione di Health e la selezione delle metriche. Un intervallo autorizzato ma vuoto è diverso da un errore di trasferimento o scrittura.</p>
</div>

## Passaggi successivi

<div class="related">
  <a href="/it/docs/metrics/"><span>Scegli i dati</span>Cerca le metriche di Apple Health e modifica le categorie o le autorizzazioni speciali.</a>
  <a href="/it/docs/format/"><span>Definisci l’output</span>Configura formati, date, unità, frontmatter, modelli e nomi file.</a>
  <a href="/it/docs/scheduling/"><span>Automatizza</span>Configura esportazioni programmate ricorrenti dopo aver verificato un’esecuzione manuale.</a>
  <a href="/it/docs/folder-vault/"><span>Correggi una destinazione</span>Comprendi i provider di File, l’accesso alle cartelle e il ripristino.</a>
</div>
