---
title: "Condividi la mia configurazione"
description: "Esamina il trasferimento profili v2 solo di sviluppo, senza dati sanitari, credenziali, acquisti o fiducia del dispositivo."
---

<div class="availability preview"><strong>Anteprima di sviluppo · non qualificata per il rilascio</strong><p>Il contratto v2 resta pre-canonico e pianificato fino ai test di interoperabilità e accessibilità su dispositivi. Non usarlo in produzione.</p></div>

Share My Setup raccoglie uno o più profili. Trasferisce metriche, formati, nomi, organizzazione e intento della destinazione. Non include mai salute, token, accesso reale alle cartelle, associazioni, acquisti, cronologia o job.

1. Sulla sorgente apri **Impostazioni → Share My Setup** ed esporta v2.
2. Apri sul target e rivedi ogni profilo.
3. Scegli **Aggiungi** o **Sostituisci**.
4. Ricollega localmente cartella, API con credenziali o Mac.
5. Applica e prova una piccola esportazione.

La transazione è atomica e offre un solo **Annulla**. I profili restano bloccati finché la destinazione non è collegata; le pianificazioni arrivano disattivate. Il codice di sviluppo corrente scrive solo `healthmd.shared_setup` v2; v1 viene rifiutato.

<div class="related"><a href="/it/docs/export-profiles/"><span>Profili</span>Impostazioni congelate.</a><a href="/it/docs/guides/platform-features/"><span>Stato</span>Qualificazione.</a></div>
