---
title: "Map en kluis"
description: "Kies waar je Markdown-bestanden worden opgeslagen en geef de submap voor exports een naam. De kluis kan elke iOS-map zijn: Obsidian, Bestanden, iCloud Drive en externe bestandsproviders werken allemaal."
---

## Wat 'kluis' hier betekent
<p>De app gebruikt <em>kluis</em> als algemene naam voor de map die je hebt gekozen, ook als je Obsidian niet gebruikt. Gebruik je Obsidian wel, kies dan de hoofdmap van je Obsidian-kluis. Anders kun je elke map kiezen, bijvoorbeeld <code>Documents/Health</code> in iCloud Drive of een map onder Op mijn iPhone.</p>

## Hoe de mapkiezer werkt
<p>Als je op de kluisrij tikt, opent de standaarddocumentkiezer van iOS (<code>UIDocumentPickerViewController</code>). Nadat je een map kiest, geeft iOS een <em>security-scoped URL</em> terug. Met deze blijvende verwijzing kan de app de map ook na opnieuw openen blijven gebruiken zonder nogmaals om toegang te vragen. De app bewaart de verwijzing als bladwijzer in <code>UserDefaults</code>.</p>

## Naam van de submap
<p>Nadat je de kluis hebt gekozen, vraagt de app om de naam van de submap voor exports. De standaardwaarde is <code>Health</code>. De gekozen naam wordt het voorvoegsel van het pad naar elk geëxporteerd bestand:</p>

<div class="doc-diagram folder-tree" aria-label="Voorbeeld van een Health.md-exportmap">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← de naam die je in Health.md instelt</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Je kunt de submap later wijzigen via <em>Instellingen → Obsidian-kluis</em>. Bestaande bestanden worden niet verplaatst.</p>

## Gedrag met andere apps
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Kies de hoofdmap van de Obsidian-kluis. Stel de submap bijvoorbeeld in op <code>Health</code>, zodat de exports als map in de boomstructuur van je kluis verschijnen.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Kies een map in iCloud Drive. De bestanden worden automatisch met al je Apple-apparaten gesynchroniseerd.</p></div>
<div class="option"><strong>Op mijn iPhone</strong><p>Kies een map die je in Bestanden → Op mijn iPhone hebt aangemaakt. Deze blijft lokaal en wordt niet gesynchroniseerd.</p></div>
<div class="option"><strong>Externe providers</strong><p>Dropbox, Google Drive, Working Copy en andere providers die in de app Bestanden beschikbaar zijn, werken op dezelfde manier.</p></div>
</div>

<div class="callout">
<strong>Bijzonderheid van iOS.</strong>
<p style="margin-top:6px;">Als iOS de security-scoped bladwijzer intrekt, mislukken exports. Dit komt zelden voor en gebeurt meestal alleen als de onderliggende map is verwijderd of verplaatst. Kies de kluis dan opnieuw via <em>Instellingen</em>.</p>
</div>

## Een gekozen map veilig vervangen of verplaatsen

Wanneer een opgeslagen bladwijzer naar een ander pad wordt herleid, koppelt Health.md de map automatisch opnieuw als de blijvende identiteit bevestigt dat het om dezelfde map gaat. De app kan ook een succesvol opgeloste beveiligde bladwijzer accepteren wanneer noch de opgeslagen noch de opgeloste map blijvende identiteit biedt, wat vaak voorkomt bij cloudproviders. Alleen een vergelijkbaar pad geldt nooit als bewijs. De geschiedenis blijft het privacyvriendelijke bestemmingslabel tonen dat elke uitvoering gebruikte.

Selecteer de map opnieuw als deze is verwijderd, toegang is ingetrokken, blijvende identiteiten botsen of slechts één kant identiteit biedt en de verplaatsing niet kan worden geverifieerd. Health.md schrijft niet naar een dubbelzinnige bestemming. Omdat elk [exportprofiel](/nl/docs/export-profiles/) een eigen bestemming heeft, controleer of selecteer je de betrokken map opnieuw voor elk profiel.

## Gerelateerde documentatie

<div class="related">
  <a href="/nl/docs/export-profiles/"><span>Profielen</span>Beheer maptoegang en bestemmingen per profiel.</a>
  <a href="/nl/docs/onboarding/"><span>Vorige stap</span>Onboarding: hier kies je de kluis voor het eerst.</a>
  <a href="/nl/docs/export/"><span>Volgende stap</span>Voer een export uit naar je nieuwe kluis.</a>
  <a href="/nl/docs/format/"><span>Aanpassen</span>Formaataanpassing: bepaal hoe de bestanden in de submap worden geschreven.</a>
</div>
