---
title: "Meine Einrichtung teilen"
description: "Prüfe den entwicklungsinternen v2-Profiltransfer ohne Gesundheitsdaten, Zugangsdaten, Käufe oder Gerätevertrauen."
---

<div class="availability preview"><strong>Entwicklungsvorschau · nicht releasequalifiziert</strong><p>Der v2-Vertrag bleibt bis zum Abschluss der Geräte- und Barrierefreiheitstests vorkanonisch und geplant. Nicht produktiv darauf verlassen.</p></div>

Share My Setup bündelt ein oder mehrere Profile. Übertragen werden Metriken, Formate, Benennung, Organisation und Zielabsicht. Niemals enthalten sind Gesundheitsdaten, Tokens, konkrete Ordnerrechte, Kopplungen, Käufe, Verlauf oder Jobs.

1. Auf der Quelle **Einstellungen → Share My Setup** öffnen und v2-Datei exportieren.
2. Auf dem Ziel öffnen und jedes Profil prüfen.
3. **Hinzufügen** oder **Ersetzen** wählen.
4. Ordner, API samt Zugangsdaten oder Mac lokal neu binden.
5. Anwenden und kleinen Testexport ausführen.

Die Transaktion ist atomar und bietet einmaliges **Rückgängig**. Importierte Profile bleiben bis zur Zielbindung gesperrt; Zeitpläne sind deaktiviert. Der aktuelle Entwicklungsstand erzeugt nur `healthmd.shared_setup` v2; v1 wird abgelehnt.

<div class="related"><a href="/de/docs/export-profiles/"><span>Profile</span>Eingefrorene Einstellungen.</a><a href="/de/docs/guides/platform-features/"><span>Status</span>Plattform-QA.</a></div>
