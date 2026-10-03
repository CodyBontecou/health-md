---
title: "Date del sonno e note giornaliere"
description: "Perché il sonno notturno appartiene alla data di inizio e quale intervallo esportare al mattino."
---

Health.md assegna una sessione alla data in cui è **iniziata**. Dormire da lunedì 23:45 a martedì 7:30 appartiene al riepilogo di lunedì. Apple e Android condividono la regola, anche se Health Connect mostra il giorno del risveglio.

| Obiettivo | Esporta |
|---|---|
| Sonno della notte il martedì mattina | **Ieri** (lunedì) |
| Attività del martedì | **Oggi** |
| Entrambi | Lunedì e martedì |

I riepiloghi tengono unita la notte. I record canonici mantengono inizio e fine originali e appartengono al giorno iniziale; Health.md non inventa due metà. Per vere sessioni usa `healthmd_sleep_sessions`.

Daily Note Injection e API Endpoint seguono la stessa attribuzione. Se la fonte sincronizza tardi, riesporta il giorno iniziale. Al momento non esiste un’opzione per spostare i riepiloghi alla data di risveglio.

<div class="related"><a href="/it/docs/scheduling/"><span>Automazione</span>Includi Ieri al mattino.</a><a href="/it/docs/troubleshooting/"><span>Aiuto</span>Dati vuoti o tardivi.</a></div>
