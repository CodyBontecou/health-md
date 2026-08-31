---
title: "Cartella e vault"
description: "Scegli dove conservare i file Markdown e assegna un nome alla sottocartella in cui verranno scritte le esportazioni. Il vault può essere una qualsiasi cartella iOS: sono supportati Obsidian, File, iCloud Drive e i provider di file di terze parti."
---

## Cosa significa "vault" in questo contesto
<p>L’app usa il termine <em>vault</em> come nome generico per la cartella scelta, indipendentemente dal fatto che si utilizzi effettivamente Obsidian. Se usi Obsidian, seleziona la cartella principale del tuo vault Obsidian. In caso contrario, scegli una cartella qualsiasi, ad esempio <code>Documents/Health</code> in iCloud Drive, una cartella in Su iPhone e così via.</p>

## Come funziona il selettore
<p>Toccando la riga del vault si apre il selettore documenti standard di iOS (<code>UIDocumentPickerViewController</code>). Quando scegli una cartella, iOS restituisce un <em>URL con ambito di sicurezza</em>, ovvero un riferimento persistente che consente all’app di continuare ad accedere alla cartella tra un avvio e l’altro senza chiederti di selezionarla nuovamente. L’app lo salva come segnalibro in <code>UserDefaults</code>.</p>

## Nome della sottocartella
<p>Dopo aver scelto il vault, ti verrà chiesto di assegnare un nome alla sottocartella in cui saranno salvate le esportazioni. Il nome predefinito è <code>Health</code>. Il nome scelto diventa il prefisso del percorso di ogni file esportato:</p>

<div class="doc-diagram folder-tree" aria-label="Esempio di struttura delle cartelle di esportazione di Health.md">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← il nome che assegni in Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Puoi modificare la sottocartella in seguito da <em>Impostazioni → Vault Obsidian</em>. I file esistenti non verranno spostati.</p>

## Comportamento nelle diverse app
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Seleziona la cartella principale del vault Obsidian. Imposta come sottocartella, ad esempio, <code>Health</code>, così le esportazioni appariranno come una cartella nella struttura del vault.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Seleziona una cartella in iCloud Drive. I file verranno sincronizzati automaticamente su tutti i tuoi dispositivi Apple.</p></div>
<div class="option"><strong>Su iPhone</strong><p>Seleziona una cartella che hai creato in File → Su iPhone. Rimarrà solo in locale, senza sincronizzazione.</p></div>
<div class="option"><strong>Provider di terze parti</strong><p>Dropbox, Google Drive, Working Copy e altri servizi: qualsiasi provider disponibile nell’app File funziona allo stesso modo.</p></div>
</div>

<div class="callout">
<strong>Una particolarità di iOS.</strong>
<p style="margin-top:6px;">Se iOS revoca il segnalibro con ambito di sicurezza (un caso raro, che si verifica in genere solo se la cartella sottostante viene eliminata o spostata), le esportazioni inizieranno a non riuscire. Per risolvere il problema, seleziona nuovamente il vault dalle <em>Impostazioni</em>.</p>
</div>

## Sostituire o spostare una cartella in sicurezza

Quando un segnalibro salvato viene risolto in un percorso diverso, Health.md ricollega automaticamente la cartella se l’identità persistente conferma che è la stessa. L’app può anche accettare un segnalibro con ambito di sicurezza risolto correttamente quando né la cartella salvata né quella risolta espone un’identità persistente, situazione comune con i provider cloud. Un percorso simile da solo non è mai una prova. La cronologia continua a mostrare l’etichetta di destinazione rispettosa della privacy usata da ogni esecuzione.

Seleziona di nuovo la cartella se è stata eliminata, l’accesso è stato revocato, le identità persistenti sono in conflitto oppure l’identità è presente su un solo lato e lo spostamento non può essere verificato. Health.md non scrive in una destinazione ambigua. Poiché ogni [profilo di esportazione](/it/docs/export-profiles/) possiede la propria destinazione, verifica o riseleziona la cartella interessata per ogni profilo.

## Contenuti correlati

<div class="related">
  <a href="/it/docs/export-profiles/"><span>Profili</span>Gestisci accesso alle cartelle e destinazioni per profilo.</a>
  <a href="/it/docs/onboarding/"><span>Precedente</span>Configurazione iniziale — dove scegli il vault per la prima volta.</a>
  <a href="/it/docs/export/"><span>Successivo</span>Esegui un’esportazione nel nuovo vault.</a>
  <a href="/it/docs/format/"><span>Personalizza</span>Personalizzazione del formato — come vengono scritti i file nella sottocartella.</a>
</div>
