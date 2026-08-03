---
title: "Sincronizzazione Mac"
description: "Usa l’app complementare per macOS come destinazione locale. L’iPhone acquisisce i dati HealthKit e le impostazioni, quindi il Mac genera e scrive i file richiesti."
---

## Che cos’è
<p>Sincronizzazione Mac consente al Mac di produrre esportazioni senza diventare un lettore HealthKit. L’iPhone rimane la fonte attendibile per i dati Apple Health: acquisisce i dati giornalieri selezionati e un’istantanea esatta delle impostazioni, quindi trasferisce l’attività al Mac. Il Mac usa gli strumenti di esportazione condivisi per pianificare i percorsi, generare i formati richiesti e scrivere i file risultanti nella cartella di destinazione scelta.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Flusso di esportazione di Sincronizzazione Mac">
    <span><strong>iPhone</strong>Acquisisce i dati HealthKit e crea un’istantanea delle impostazioni effettive.</span>
    <span><strong>Rete locale</strong>Trasferisce l’attività con controllo di versione all’app sul Mac nelle vicinanze.</span>
    <span><strong>Mac</strong>Genera i formati selezionati e li scrive nella cartella scelta.</span>
    <span><strong>Vault</strong>Obsidian, iCloud Drive o qualsiasi cartella locale riceve l’esportazione finale.</span>
  </div>
</div>

## Come abilitarla
<ol>
<li>Installa e apri l’app per macOS.</li>
<li>Sul Mac, scegli una cartella di destinazione in modo che Health.md disponga dell’accesso in scrittura.</li>
<li>Sull’iPhone, apri il pannello Sincronizzazione e abilita la connettività con il Mac.</li>
<li>Torna al pannello Esportazione sull’iPhone, scegli <em>Mac connesso</em>, configura l’esportazione e tocca Esporta.</li>
</ol>

## Che cosa viene trasferito
<ul>
<li>Una richiesta di esportazione con controllo di versione che descrive l’intervallo di date e le impostazioni effettive</li>
<li>Messaggi relativi allo stato di avanzamento e alle funzionalità mentre l’iPhone acquisisce i dati HealthKit</li>
<li>Frame di dimensioni limitate e con checksum convalidato, contenenti i dati giornalieri acquisiti e l’istantanea esatta delle impostazioni per le operazioni di scrittura dei file</li>
<li>Un risultato strutturato di completamento, completamento parziale, errore, rifiuto o indisponibilità</li>
</ul>
<p>Non sono necessari né un account né un cloud remoto per i dati sanitari. La sincronizzazione nelle vicinanze usa Multipeer Connectivity con crittografia; l’IP manuale/Tailscale usa un trasporto Network.framework abbinato e crittografato. Entrambi i dispositivi devono potersi raggiungere e l’iPhone rimane il lettore HealthKit.</p>

## Quando usarla
<div class="options">
<div class="option"><strong>Vault disponibili solo sul desktop</strong><p>Se il tuo vault Obsidian risiede solo sul Mac, questo è il percorso più diretto dai dati HealthKit dell’iPhone ai file sul Mac.</p></div>
<div class="option"><strong>Recuperi di grandi quantità di dati storici</strong><p>Conserva i file finali su un disco desktop mentre l’iPhone gestisce la lettura di HealthKit e la configurazione dell’esportazione.</p></div>
<div class="option"><strong>Flussi di lavoro per archivi locali</strong><p>Scrivi direttamente nelle cartelle sottoposte a backup, controllo di versione o indicizzazione su macOS.</p></div>
</div>

<div class="callout">
<strong>È necessaria una rete locale.</strong>
<p style="margin-top:6px;">Entrambi i dispositivi devono trovarsi nelle vicinanze ed essere autorizzati a usare la rete locale. Gli iPhone connessi solo alla rete cellulare non possono rilevare un Mac come destinazione. Se lo stato di disponibilità indica che il Mac richiede attenzione, riapri l’app sul Mac e riseleziona la cartella di destinazione.</p>
</div>

## Sincronizzazione Mac e Accesso CLI diretto sono funzionalità separate

Sincronizzazione Mac abbina l’iPhone all’app Health.md per Mac per le esportazioni verso una destinazione e il contesto crittografato dell’agente. Accesso CLI diretto abbina l’iPhone a un’installazione da riga di comando attraverso un dominio di attendibilità separato. La modalità diretta può esportare dati grezzi o file generati senza l’app per Mac, ma non può usare l’indice crittografato delle query sul Mac né MCP.

Consulta [CLI diretta per iPhone](/it/docs/cli-direct/) prima di abilitare l’impostazione separata sull’iPhone.

## Contenuti correlati

<div class="related">
  <a href="/it/docs/macos/"><span>Desktop</span>App per macOS — Esportazione, programmazione e cronologia sul Mac.</a>
  <a href="/it/docs/scheduling/"><span>Flusso di lavoro</span>Programmazione — automatizza le esportazioni ricorrenti.</a>
  <a href="/it/docs/cli-direct/"><span>Attendibilità separata</span>CLI diretta per iPhone — abbina una CLI senza instradare il lavoro attraverso l’app per Mac.</a>
  <a href="/it/docs/reference/connected-mac-iphone-protocol/"><span>Protocollo</span>Riferimento per la connessione Mac–iPhone — funzionalità, richieste, trasferimento limitato e risultati.</a>
</div>
