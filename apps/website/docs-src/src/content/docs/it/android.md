---
title: App Android
description: Configura Health.md per Android, esporta i dati di Health Connect in Markdown, Obsidian Bases, JSON e CSV, scegli le cartelle tramite Storage Access Framework, pianifica le esportazioni e automatizza con Tasker o adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Da Health Connect a file privati</p>
  <p>Health.md per Android legge i dati di Health Connect sul dispositivo e scrive file Markdown, Obsidian Bases, JSON o CSV nelle cartelle che scegli. Nessun account Health.md, nessun cloud per i dati sanitari e nessun abbonamento.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Scarica da Google Play</a>
    <a class="docs-button-secondary" href="/it/docs/export/">Leggi la documentazione sull'esportazione</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>metriche di Health Connect selezionabili</span></div>
<div><strong>4</strong><span>formati di esportazione</span></div>
<div><strong>10</strong><span>azioni gratuite di esportazione manuale</span></div>
<div><strong>0</strong><span>account cloud Health.md richiesti</span></div>
</div>

## Cosa fa l'app Android

Health.md per Android trasforma Health Connect in un diario sanitario locale. Scegli le metriche che ti interessano, visualizza l'anteprima del risultato, quindi esporta file ordinati in una cartella locale, in un vault di Obsidian, nella cartella di un servizio sincronizzato o in qualsiasi provider di documenti Android che conceda l'accesso in scrittura.

<div class="options">
  <div class="option"><strong>Origine Health Connect</strong><p>Legge attività, sonno, cuore, parametri vitali, misurazioni corporee, nutrizione, allenamenti e altre categorie tramite le API di Health Connect sul dispositivo Android.</p></div>
  <div class="option"><strong>Output nativo per Obsidian</strong><p>Scrive note giornaliere, YAML/frontmatter, note compatibili con Obsidian Bases, singole voci e JSON compatibile con il plugin Health.md per Obsidian.</p></div>
  <div class="option"><strong>Archiviazione nativa di Android</strong><p>Utilizza Storage Access Framework per consentirti di scegliere le cartelle rese disponibili dall'archiviazione locale, da Obsidian, Google Drive, OneDrive, Syncthing o da un altro provider.</p></div>
</div>

## Requisiti

- Android 9 / API 28 o versioni successive.
- Un dispositivo o emulatore compatibile con Health Connect.
- Dati di Health Connect provenienti da app Android, dispositivi indossabili o servizi che scrivono in Health Connect.
- Una cartella o un provider di documenti che consenta l'accesso in scrittura per le esportazioni.

## Prima esportazione

1. Installa Health.md da Google Play.
2. Apri la configurazione di **Health Connect** e concedi l'accesso solo alle categorie che vuoi esportare con Health.md.
3. Scegli la destinazione dell'esportazione tramite il selettore di cartelle di Android.
4. Scegli i formati: Markdown, Obsidian Bases, JSON, CSV o qualsiasi combinazione.
5. Seleziona le metriche e l'intervallo di date.
6. Visualizza l'anteprima del risultato.
7. Tocca Esporta e verifica i file generati nella cartella o nel vault.

Il piano gratuito include 10 azioni di esportazione manuale, così puoi provare le autorizzazioni, l'accesso alle cartelle, i formati e il tuo flusso di lavoro con Obsidian prima di sbloccare le esportazioni illimitate.

## Destinazioni su Android

Android non utilizza la destinazione iPhone → Mac sulla rete locale. Si affida invece a Storage Access Framework di Android.

| Destinazione | Stato su Android |
|---|---|
| Cartella locale sul dispositivo | Supportata tramite il selettore di cartelle |
| Vault di Obsidian | Supportato quando la cartella del vault è resa disponibile al selettore di Android |
| Google Drive, OneDrive, Syncthing, Obsidian Sync e provider simili | Supportati quando il provider rende disponibili cartelle scrivibili |
| Destinazione iPhone/Mac sulla rete locale | Specifica delle piattaforme Apple; non utilizzata da Android |

Se un provider non rende disponibili cartelle scrivibili tramite il selettore di Android, Health.md non può scrivervi direttamente in modo sicuro. Scegli una cartella del provider che conceda un accesso persistente in scrittura oppure esporta localmente e sincronizza con lo strumento che preferisci.

## Formati

L'app Android condivide gli stessi obiettivi di utilizzo di file semplici dell'app Apple:

| Formato | Utilizzalo per |
|---|---|
| Markdown | Riepiloghi sanitari giornalieri leggibili, modelli e note |
| Obsidian Bases | Note basate sul frontmatter che possono essere interrogate nelle viste database di Obsidian |
| JSON | Payload giornalieri strutturati per script, dashboard, notebook e il plugin Health.md per Obsidian |
| CSV | Fogli di calcolo e flussi di lavoro di analisi |

Le esportazioni JSON di Android sono progettate per essere compatibili con le visualizzazioni di Health.md in Obsidian. Le esportazioni Markdown e Obsidian Bases utilizzano lo stesso flusso di lavoro basato sul frontmatter descritto nella [guida ai formati](/it/docs/format/).

## Pianificazione e automazione

Le esportazioni programmate richiedono l’acquisto a vita una tantum. Le esportazioni programmate utilizzano un allarme esatto una tantum quando concedi l'accesso ad Allarmi e promemoria di Android, con un'attività persistente di WorkManager come soluzione di riserva. Senza l'accesso agli allarmi esatti, WorkManager diventa il sistema di pianificazione principale, quindi l'ora selezionata è indicativa e non una garanzia assoluta. Health.md registra la cronologia delle esportazioni, può recuperare le date programmate non elaborate e consente di riprovare le esecuzioni non riuscite.

Per Tasker, adb o altri strumenti di automazione, Health.md espone intent broadcast solo espliciti. I chiamanti esterni devono indirizzare direttamente il componente receiver:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Esempi:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

L’automazione usa per impostazione predefinita il profilo attivo con destinazione, formati, metriche, conteggio e cronologia congelati. Un extra `PROFILE` può selezionare un profilo stabile per ID o nome; un riferimento sconosciuto fallisce in sicurezza anziché usare le impostazioni attuali. Anche le esecuzioni pianificate restano legate al profilo. Consulta [Profili di esportazione](/it/docs/export-profiles/).

### Requisiti in background e annullamento pianificato

- Consenti letture Health Connect in background per esportazioni non presidiate; altrimenti apri Health.md.
- Mantieni le notifiche attive per mostrare il lavoro, il servizio in primo piano e gli avvisi di ripristino.
- Concedi Sveglie e promemoria solo per allarmi esatti. Senza accesso, il lavoro è persistente ma l’orario approssimativo.
- Annullare un’esecuzione pianificata ferma solo quel tentativo. Le date completate restano, le altre sono riprovabili e la pianificazione rimane attiva.

## Fonti dei dati sanitari

Health Connect è il percorso locale di esportazione predefinito. L'app Android include anche un'area di configurazione delle fonti dei dati sanitari per ecosistemi come Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar e WHOOP. Quando questi ecosistemi scrivono in Health Connect, Health.md può esportare i relativi record di Health Connect. Le importazioni dirette dai provider cloud richiedono l'autorizzazione del provider e possono prevedere configurazioni aggiuntive o limitazioni di disponibilità.

Google Fit è intenzionalmente escluso dall'elenco dei provider supportati perché Health Connect è il livello preferito da Android per i dati sanitari.

### Passi giornalieri locali esatti

I totali usano i limiti esatti del giorno locale con fuso. Health.md taglia e divide gli intervalli Health Connect alla mezzanotte locale prima dell’aggregazione, evitando spostamenti dovuti a viaggi o ora legale.

## Prezzi e ripristino

- L'app Android include 10 azioni gratuite di esportazione manuale.
- Le esportazioni illimitate e l'automazione programmata si sbloccano con un acquisto una tantum tramite Google Play Billing.
- Non è previsto alcun abbonamento né alcun addebito ricorrente.
- Google Play mostra il prezzo locale aggiornato prima dell'acquisto.
- Ripristina acquisto utilizza l'account Google con cui è stato acquistato Full Access.

Dopo una disconnessione temporanea da Google Play Billing, Health.md si riconnette e aggiorna automaticamente il diritto. Premium non viene rimosso definitivamente; usa Ripristina acquisto solo se l’account resta irrisolto dopo il ritorno della rete.

## Modello di privacy

Health.md per Android privilegia l'archiviazione locale:

- I record di Health Connect vengono letti sul tuo dispositivo Android.
- Le esportazioni vengono scritte direttamente nelle cartelle che scegli.
- Health.md non gestisce un servizio cloud per i dati sanitari.
- Le impostazioni e la cronologia delle esportazioni rimangono sul dispositivo.
- La fatturazione è gestita da Google Play.
- Le cartelle gestite da provider vengono sincronizzate secondo i termini del rispettivo provider.

Per la configurazione locale più rigorosa, esegui esportazioni manuali in una cartella locale del dispositivo e lascia disattivate le esportazioni programmate e la sincronizzazione tramite provider.

## Documentazione correlata

<div class="related">
  <a href="/it/docs/export-profiles/"><span>Profili</span>Salva destinazioni, impostazioni di output, pianificazioni e ID di automazione stabili indipendenti.</a>
  <a href="/it/docs/export/"><span>Esportazione</span>Flusso di esportazione manuale, intervalli di date, anteprime, cronologia e output dei file.</a>
  <a href="/it/docs/metrics/"><span>Metriche</span>Come funzionano la selezione delle metriche e le categorie in Health.md.</a>
  <a href="/it/docs/format/"><span>Formati</span>Markdown, Obsidian Bases, JSON, CSV, unità, nomi dei file e frontmatter.</a>
  <a href="/it/docs/visualizations-roadmap/"><span>Obsidian</span>Come i file JSON e Markdown esportati alimentano le visualizzazioni di Health.md.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Ultimo aggiornamento: 31 agosto 2026</p>
