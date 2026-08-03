---
title: "App macOS"
description: "Usa Health.md per Mac come destinazione delle esportazioni da iPhone, host locale per CLI e MCP, archivio crittografato del contesto sanitario, visualizzatore della cronologia e gestore della cartella di destinazione."
---

Health.md per Mac svolge due ruoli locali:

1. riceve le attività di esportazione dall’iPhone e scrive i file in una cartella scelta dall’utente;
2. ospita la CLI su loopback, l’API per le query, il contesto sanitario crittografato e l’adattatore MCP usati dagli agenti locali.

Apple Health rimane su iPhone. L’app per Mac non legge direttamente HealthKit.

## Aree principali

<div class="options">
<div class="option"><strong>Sincronizzazione</strong><p>Mostra se il Mac è rilevabile e pronto a ricevere attività di esportazione dall’iPhone.</p></div>
<div class="option"><strong>Cartella di destinazione</strong><p>Archivia un segnalibro con ambito di sicurezza per gli output Markdown, JSON, CSV, Obsidian Bases, aggregati, ZIP e Note giornaliere.</p></div>
<div class="option"><strong>Programmazione</strong><p>Mantiene visibili la programmazione e lo stato di disponibilità sul Mac. I dati HealthKit continuano a essere forniti dall’iPhone.</p></div>
<div class="option"><strong>Cronologia</strong><p>Registra gli esiti delle esportazioni, l’avanzamento persistente, gli errori e il contesto per i nuovi tentativi relativi ai file scritti dal Mac.</p></div>
<div class="option"><strong>Impostazioni</strong><p>Mostra lo stato della destinazione, i controlli di conservazione del contesto crittografato e la configurazione della CLI locale.</p></div>
<div class="option"><strong>Barra dei menu</strong><p>Fornisce accesso rapido allo stato, alle impostazioni e all’app mentre Health.md rimane disponibile localmente.</p></div>
<div class="option"><strong>CLI</strong><p>Installa gli helper inclusi <code>healthmd</code> e <code>healthmd-mcp</code>, copia i prompt di configurazione, installa la skill facoltativa per agenti e mostra i comandi verificati.</p></div>
</div>

## Configurare una destinazione Mac

1. Installa e apri Health.md sul Mac.
2. Scegli una cartella di destinazione sul disco locale, in iCloud Drive o all’interno di un vault Obsidian.
3. Su iPhone, abilita la connettività con il Mac dalla scheda Sincronizzazione.
4. Su iPhone, scegli Mac connesso come destinazione dell’esportazione.
5. Configura l’esportazione e tocca Esporta.

L’iPhone acquisisce i dati HealthKit e l’istantanea delle impostazioni effettive. I dispositivi compatibili trasferiscono partizioni di dimensioni limitate con checksum convalidati. Il Mac usa gli strumenti di esportazione di produzione e scrive i file richiesti.

<div class="callout">
<strong>Limitazione di HealthKit.</strong>
<p style="margin-top:6px;">Il Mac non può interrogare autonomamente Apple Health. Le nuove esportazioni e il contesto per gli agenti richiedono che l’app sull’iPhone connesso sia aperta. Le query crittografate memorizzate nella cache possono essere eseguite senza una nuova connessione all’iPhone quando la copertura archiviata è sufficiente.</p>
</div>

## Configurazione della CLI e degli agenti

Apri l’area **CLI** dell’app per Mac per:

- visualizzare i percorsi esatti degli strumenti firmati inclusi nel bundle dell’app;
- copiare alias o comandi per collegamenti simbolici in `~/.local/bin`;
- copiare un prompt di configurazione assistita da un agente;
- installare la skill facoltativa `healthmd-cli` in una cartella a tua scelta;
- consultare i comandi correnti per stato, diagnostica, estrazione, query, sonno, allenamento, attività, copertura ed esportazione;
- esaminare gli errori comuni relativi allo stato di disponibilità.

L’app non modifica mai i file di avvio della shell né esegue installazioni in una cartella di sistema senza un’azione dell’utente.

Per iniziare:

```bash
healthmd doctor
healthmd metrics list --category Sleep
healthmd extract --category Sleep --yesterday --output sleep.json
healthmd query --category Sleep --yesterday
```

Consulta [CLI di Health.md](/it/docs/cli/) per la selezione del backend e [Agenti locali](/it/docs/agents/) per l’architettura delle query.

## Contesto sanitario crittografato

Le nuove richieste di query e dati di riscontro usano una modalità dedicata di acquisizione del contesto. L’iPhone legge esattamente la metrica, la fonte, la data e l’ambito di dettaglio richiesti. Non crea file di esportazione né modifica le preferenze di esportazione salvate.

Il Mac archivia ogni giornata compatta attribuita al titolare in un blocco AES-256-GCM autenticato in modo indipendente. Una voce del Portachiavi utilizzabile solo su questo dispositivo e quando è sbloccato conserva la chiave di crittografia casuale. I nomi dei file sono casuali e non rivelano date o nomi di metriche.

Le Impostazioni mostrano il numero di giornate crittografate attribuite al titolare e l’intervallo di date. Due azioni indipendenti controllano la conservazione:

- **Elimina contesto meno recente** rimuove le giornate attribuite al titolare strettamente precedenti al limite scelto;
- **Elimina tutto il contesto crittografato** rimuove tutti i file di contesto e la chiave dedicata del Portachiavi.

La conservazione del contesto non elimina mai i dati di Apple Health, i file di esportazione, i segnalibri delle destinazioni Mac o le credenziali dei provider connessi.

## Limite dell’API su loopback

L’app per Mac rimane in ascolto su `127.0.0.1` e `::1` alla porta `17645` per le route locali relative a stato, esportazione, query, dati di riscontro, aggiornamento e attività persistenti.

Non sono presenti token bearer né registrazioni degli agenti. Qualsiasi processo locale può chiamare l’API mentre l’app è aperta. Non esporre, inoltrare tramite proxy o incanalare mai la porta verso un altro computer.

L’helper `healthmd-mcp`, eseguito in un ambiente isolato, accetta esclusivamente endpoint HTTP loopback canonici e fornisce strumenti senza shell, file arbitrari, SQL, recupero di URL, risorse, prompt, radici o campionamento.

## L’accesso diretto dalla CLI è separato

L’impostazione **Accesso diretto dalla CLI** dell’iPhone crea una relazione di attendibilità separata tra una CLI compatibile con l’accesso diretto e l’iPhone. Può ignorare l’app per Mac per l’esportazione di dati non elaborati, l’estrazione canonica, i file generati, lo stato, la ripresa e l’annullamento.

La modalità diretta non usa il contesto crittografato delle query dell’app per Mac. Il comando multipiattaforma `healthmd mcp serve` esegue invece nuove query tipizzate direttamente sull’iPhone in primo piano, usando la stessa identità dell’eseguibile impiegata per l’abbinamento. Consulta [CLI diretta per iPhone](/it/docs/cli-direct/) per informazioni sull’abbinamento e sul supporto delle piattaforme.

## Contenuti correlati

<div class="related">
  <a href="/it/docs/sync/"><span>Destinazione</span>Sincronizzazione con il Mac: abbina iPhone e Mac per esportare file localmente.</a>
  <a href="/it/docs/cli/"><span>Terminale</span>CLI di Health.md: installa gli strumenti, seleziona un backend ed esegui i comandi.</a>
  <a href="/it/docs/agents/"><span>Contesto locale</span>Agenti: acquisizione con ambito definito, archiviazione crittografata, dati di riscontro e conservazione.</a>
  <a href="/it/docs/mcp/"><span>Strumenti</span>Server MCP locale: configurazione, catalogo degli strumenti e limiti della sandbox.</a>
  <a href="/it/docs/scheduling/"><span>Flusso di lavoro</span>Programmazione: automatizza le esportazioni ricorrenti.</a>
</div>
