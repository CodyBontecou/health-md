---
title: "Programmazione"
description: "Esegui automaticamente le esportazioni, ogni giorno o ogni settimana, all'ora che preferisci. Utilizza le attività in background di iOS e, come soluzione alternativa quando il dispositivo è bloccato, una notifica locale programmata."
---

## Il pannello Programmazione
<p>Una schermata di stato, non un pannello delle impostazioni. Mostra a colpo d'occhio:</p>
<ul>
<li>Se la programmazione è attiva o disattiva</li>
<li>La prossima esecuzione programmata, se presente</li>
<li>L'esito dell'ultima esecuzione</li>
</ul>
<p>Un unico pulsante — <em>Configura programmazione</em> (o <em>Gestisci programmazione</em>) — apre la vista dettagliata.</p>

## Impostazioni della programmazione
<div class="options">
<div class="option"><strong>Abilita esportazioni programmate</strong><p>Interruttore principale nella parte superiore. Quando è disattivato, non vengono eseguite attività in background né inviate notifiche.</p></div>
<div class="option"><strong>Frequenza</strong><p>Giornaliera, settimanale o mensile. Le esportazioni giornaliere includono i dati di ieri; quelle settimanali i 7 giorni precedenti; quelle mensili i 30 giorni precedenti.</p></div>
<div class="option"><strong>Ora</strong><p>Ora e minuti. iOS la considera un'indicazione, non una garanzia — consulta l'avviso sulle limitazioni qui sotto.</p></div>
</div>

## Cronologia delle esportazioni
<p>L'elenco nella parte inferiore della schermata Programmazione registra ogni esecuzione programmata con il relativo esito. Tocca una riga per visualizzarne i dettagli. Le esecuzioni non riuscite includono un pulsante <em>Riprova</em> che ripete l'esportazione per quello specifico intervallo di date.</p>

## Come funziona realmente la programmazione su iOS
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Flusso alternativo dell'esportazione programmata">
    <span><strong>1. Ora prevista</strong>Health.md chiede a iOS di riattivare l'app in prossimità dell'ora scelta.</span>
    <span><strong>2. Tentativo in background</strong>Se il dispositivo è disponibile, iOS esegue un'attività di aggiornamento in background.</span>
    <span><strong>3. Soluzione alternativa con dispositivo bloccato</strong>Se HealthKit non è disponibile, Health.md invia una notifica.</span>
    <span><strong>4. Tocca per completare</strong>Aprendo la notifica, l'app può leggere HealthKit ed eseguire l'esportazione.</span>
  </div>
</div>

<div class="callout">
<strong>Limitazioni di iOS da conoscere.</strong>
<p style="margin-top:6px;">I dati di HealthKit non sono accessibili mentre il dispositivo è bloccato. Le esportazioni programmate vengono eseguite tramite <code>BGAppRefreshTask</code>, che iOS pianifica in modo opportunistico in base alle modalità di utilizzo: l'ora impostata è un obiettivo, non una garanzia. Come soluzione alternativa, se il dispositivo è bloccato, l'app invia una notifica locale all'ora programmata; toccala per eseguire l'esportazione.</p>
</div>
<ul>
<li>L'ora programmata è approssimativa. iOS potrebbe eseguire l'attività in anticipo, in ritardo oppure saltarla se il dispositivo è spento o disconnesso.</li>
<li>Le esportazioni programmate funzionano al meglio quando l'iPhone viene collegato regolarmente all'alimentazione e sbloccato più o meno alla stessa ora ogni giorno.</li>
<li>Se l'esportazione non riesce perché il dispositivo era bloccato, tocca la notifica: l'esportazione verrà eseguita con accesso a HealthKit.</li>
</ul>

## Controllo programmatico
<p>Puoi attivare o disattivare la programmazione da Comandi Rapidi usando l'intento <em>Attiva o disattiva l'esportazione programmata</em>. <a href="/it/docs/shortcuts/">Consulta Comandi Rapidi</a> per alcuni esempi.</p>

## Contenuti correlati

<div class="related">
  <a href="/it/docs/export/"><span>Manuale</span>Esportazione — per intervalli di date occasionali.</a>
  <a href="/it/docs/shortcuts/"><span>Automatizza</span>Comandi Rapidi — attiva o disattiva la programmazione tramite automazioni.</a>
  <a href="/it/docs/sync/"><span>Tra dispositivi</span>Sincronizzazione con il Mac — programma anche sul Mac.</a>
</div>
