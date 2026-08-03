---
title: "Comandi Rapidi e App Intent"
description: "Otto App Intent consentono di avviare esportazioni, ottenere riepiloghi e attivare o disattivare la programmazione tramite Siri, l'app Comandi Rapidi, i filtri delle modalità Full immersion, le automazioni e qualsiasi altro host compatibile con AppIntent."
---

## Intent disponibili
<div class="options">
<div class="option"><strong>Esporta i dati sanitari di ieri</strong><p>Comando rapido senza parametri. Il modo più veloce per «esportare semplicemente i dati di ieri senza ulteriori interazioni». Usa lo stesso motore dell'esportazione manuale.</p></div>
<div class="option"><strong>Esporta i dati sanitari per una data</strong><p>Un solo parametro <em>Data</em>. L'ora viene ignorata. Utile nelle automazioni basate sul calendario.</p></div>
<div class="option"><strong>Esporta i dati sanitari per un intervallo di date</strong><p>Parametri <em>Data di inizio</em> e <em>Data di fine</em>, entrambe incluse. Utile per recuperare dati pregressi.</p></div>
<div class="option"><strong>Esporta i dati sanitari degli ultimi N giorni</strong><p>Parametro <em>Numero di giorni</em> (1–366). L'intervallo termina ieri. Il valore predefinito è 7. Ideale per automazioni come «ogni domenica, esporta gli ultimi 7 giorni».</p></div>
<div class="option"><strong>Ottieni il riepilogo sanitario per una data</strong><p>Restituisce un'istantanea strutturata — passi, calorie attive, sonno, frequenza cardiaca — senza scrivere nulla nella cartella. Puoi usarla in Comandi Rapidi per passare i valori ad altre app.</p></div>
<div class="option"><strong>Ottieni lo stato dell'ultima esportazione</strong><p>Restituisce la data e l'ora, lo stato di riuscita, il numero di giorni e l'eventuale motivo dell'errore dell'esportazione registrata più recente. Una richiesta effettuata con il dispositivo bloccato rimane in sospeso fino a un nuovo tentativo e, finché è in sospeso, non viene restituita come stato corrente.</p></div>
<div class="option"><strong>Attiva o disattiva l'esportazione programmata</strong><p>Parametro booleano. Consente di sospendere la programmazione, ad esempio durante la modalità Full immersion Vacanza, e di riattivarla in seguito.</p></div>
<div class="option"><strong>Esporta i dati sanitari</strong><p>Esportazione generica: usa l'intervallo di date dell'ultimo stato della finestra modale Esporta nell'app. È usata meno frequentemente; le varianti con intervallo di date sono in genere più chiare.</p></div>
</div>

## Dove trovarli
<p>Apri l'app Comandi Rapidi su iOS o macOS. Tocca il pulsante <em>+</em> per creare un nuovo comando rapido, quindi cerca &quot;Health.md&quot; o uno dei titoli degli intent riportati sopra. Sono disponibili nella categoria <em>Salute</em>.</p>
<p>La maggior parte degli intent usa <code>openAppWhenRun = false</code>, quindi viene eseguita senza interfaccia: l'app non si apre e non compare alcuna schermata. Funzionano con le automazioni, i filtri delle modalità Full immersion, le richieste a “Ehi Siri” e il tasto Azione.</p>

<div class="callout">
<strong>L'esecuzione con il dispositivo bloccato non sblocca HealthKit.</strong>
<p style="margin-top:6px;">Apple protegge i dati di HealthKit mentre iPhone è bloccato e <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">revoca l'accesso alle app circa dieci minuti dopo il blocco</a>. <em>Consenti esecuzione quando bloccato</em> permette a Comandi Rapidi di avviare l'azione, ma non aggira la protezione dei dati di HealthKit. Neppure l'autorizzazione ai contenuti dell'app Health.md in Comandi Rapidi consente di aggirarla.</p>
<p>Se HealthKit non è disponibile, Health.md conserva le date richieste come operazione in sospeso e invia una notifica <em>L'esportazione dei dati sanitari richiede attenzione</em>. Sblocca iPhone, quindi tocca la notifica oppure apri Health.md per riprovare. Non è possibile garantire un'esportazione completamente automatica mentre il telefono rimane bloccato.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Procedura: esportazione giornaliera con conferma
<ol>
<li><strong>Automazione personale</strong> → <em>Ora del giorno</em> → scegli un orario in cui normalmente usi iPhone sbloccato, ad esempio le 8:00.</li>
<li>Intent <em>Esporta i dati sanitari di ieri</em>.</li>
<li>Intent <em>Ottieni lo stato dell'ultima esportazione</em>.</li>
<li><em>Mostra notifica</em> con il risultato.</li>
</ol>
<p><strong>Nota sullo stato in sospeso:</strong> <em>Ottieni lo stato dell'ultima esportazione</em> legge la voce più recente registrata nella cronologia delle esportazioni. Se durante questa esecuzione i dati di HealthKit non erano disponibili perché il dispositivo era bloccato, potrebbe continuare a mostrare l'esportazione precedente finché non riprovi la richiesta in sospeso. La notifica di ripristino di Health.md è il segnale autorevole della presenza di operazioni in sospeso.</p>

## Procedura: recupero occasionale dei dati pregressi
<ol>
<li>Crea un comando rapido.</li>
<li><em>Esporta i dati sanitari per un intervallo di date</em> con inizio = 2024-01-01 e fine = 2024-12-31.</li>
<li>Eseguilo da Comandi Rapidi. Scorre l'intero anno e scrive un file per ogni giorno. Per anni completi potrebbero essere necessari alcuni minuti.</li>
</ol>

## Procedura: sospendere la programmazione durante le vacanze
<ol>
<li><strong>Filtro Full immersion</strong>: quando attivi la modalità Full immersion <em>Vacanza</em>, esegui <em>Attiva o disattiva l'esportazione programmata</em> con Attiva = false.</li>
<li>Quando disattivi la modalità Full immersion, eseguilo di nuovo con Attiva = true.</li>
</ol>

<div class="callout">
<strong>Autorizzazione necessaria.</strong>
<p style="margin-top:6px;">Gli intent ereditano l'autorizzazione a HealthKit e la cartella selezionata nell'app. Restituiscono un errore chiaro se l'app non è stata aperta e configurata almeno una volta su questo dispositivo.</p>
</div>

## Argomenti correlati

<div class="related">
  <a href="/it/docs/scheduling/"><span>Fonte</span>Programmazione — l'equivalente nell'app dell'intent di attivazione o disattivazione.</a>
  <a href="/it/docs/export/"><span>Fonte</span>Esportazione — l'equivalente nell'app degli intent per intervallo di date.</a>
</div>
