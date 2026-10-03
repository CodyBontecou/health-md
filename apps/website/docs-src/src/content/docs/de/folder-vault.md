---
title: "Ordner & Vault"
description: "Wählen Sie den Speicherort Ihrer Markdown-Dateien und benennen Sie den Unterordner für Exporte. Der Vault ist lediglich ein beliebiger iOS-Ordner – Obsidian, Dateien, iCloud Drive und Drittanbieter funktionieren gleichermaßen."
---

## Was „Vault“ hier bedeutet
<p>Die App verwendet <em>Vault</em> unabhängig von Obsidian als allgemeine Bezeichnung für den ausgewählten Ordner. Wenn Sie Obsidian verwenden, wählen Sie das Stammverzeichnis Ihres Obsidian-Vaults. Andernfalls können Sie einen beliebigen Ordner auswählen, etwa <code>Documents/Health</code> in iCloud Drive oder einen Ordner unter „Auf meinem iPhone“.</p>

## Funktionsweise der Auswahl
<p>Wenn Sie auf die Vault-Zeile tippen, öffnet sich die standardmäßige Dokumentauswahl von iOS (<code>UIDocumentPickerViewController</code>). Nach der Ordnerauswahl gibt iOS eine <em>security-scoped URL</em> zurück: eine dauerhafte Zugriffsberechtigung, mit der die App auch nach einem erneuten Start ohne weitere Nachfrage auf den Ordner zugreifen kann. Die App speichert sie als Lesezeichen in <code>UserDefaults</code>.</p>

## Name des Unterordners
<p>Nach der Vault-Auswahl werden Sie aufgefordert, den Unterordner für Exporte zu benennen. Standardmäßig lautet er <code>Health</code>. Ihre Auswahl wird zum Präfix des Pfads jeder exportierten Datei:</p>

<div class="doc-diagram folder-tree" aria-label="Beispiel für die Ordnerstruktur eines Health.md-Exports">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← Ihre Bezeichnung in Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>Sie können den Unterordner später unter <em>Einstellungen → Obsidian-Vault</em> ändern. Vorhandene Dateien werden nicht verschoben.</p>

## Verhalten mit anderen Apps
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Wählen Sie das Stammverzeichnis des Obsidian-Vaults. Legen Sie beispielsweise <code>Health</code> als Unterordner fest, damit die Exporte als Ordner in Ihrer Vault-Struktur erscheinen.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Wählen Sie einen Ordner in iCloud Drive. Dateien werden automatisch mit all Ihren Apple-Geräten synchronisiert.</p></div>
<div class="option"><strong>Auf meinem iPhone</strong><p>Wählen Sie einen Ordner, den Sie unter Dateien → Auf meinem iPhone erstellt haben. Er bleibt ausschließlich lokal und wird nicht synchronisiert.</p></div>
<div class="option"><strong>Drittanbieter</strong><p>Dropbox, Google Drive, Working Copy usw. – alle Anbieter, die sich in die App „Dateien“ integrieren, funktionieren auf dieselbe Weise.</p></div>
</div>

<div class="callout">
<strong>Besonderheit von iOS.</strong>
<p style="margin-top:6px;">Falls iOS das security-scoped-Lesezeichen widerruft – selten und meist nur, wenn der zugrunde liegende Ordner gelöscht oder verschoben wurde –, schlagen Exporte fehl. Wählen Sie den Vault unter <em>Einstellungen</em> erneut aus.</p>
</div>

## Einen ausgewählten Ordner sicher ersetzen oder verschieben

Wird ein gespeichertes Lesezeichen an einem anderen Pfad aufgelöst, bindet Health.md den Ordner automatisch neu, wenn die dauerhafte Identität denselben Ordner bestätigt. Die App kann auch ein erfolgreich aufgelöstes sicherheitsbezogenes Lesezeichen akzeptieren, wenn weder der gespeicherte noch der aufgelöste Ordner eine dauerhafte Identität bereitstellt – das ist bei Cloud-Anbietern üblich. Ein ähnlicher Pfad allein gilt nie als Beweis. Im Exportverlauf bleibt die datenschutzfreundliche Zielbezeichnung jedes Laufs erhalten.

Wähle den Ordner erneut aus, wenn er gelöscht wurde, der Zugriff entzogen ist, dauerhafte Identitäten widersprüchlich sind oder Identitätsnachweise nur auf einer Seite vorliegen und der Wechsel nicht geprüft werden kann. Health.md schreibt nicht an ein mehrdeutiges Ziel. Da jedes [Exportprofil](/de/docs/export-profiles/) ein eigenes Ziel besitzt, prüfe oder wähle den betroffenen Ordner für jedes Profil neu aus.

## Verwandte Themen

<div class="related">
  <a href="/de/docs/export-profiles/"><span>Profile</span>Ordnerzugriff und Ziele pro Profil verwalten.</a>
  <a href="/de/docs/onboarding/"><span>Zurück</span>Einrichtung – dort wählen Sie den Vault zum ersten Mal aus.</a>
  <a href="/de/docs/export/"><span>Weiter</span>Führen Sie einen Export in Ihren neuen Vault aus.</a>
  <a href="/de/docs/format/"><span>Anpassen</span>Formatanpassung – legen Sie fest, wie Dateien im Unterordner geschrieben werden.</a>
</div>
