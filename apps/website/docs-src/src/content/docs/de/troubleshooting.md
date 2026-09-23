---
title: "Health.md-Fehlerbehebung"
description: "Prüfe leere Exporte, fehlenden Schlaf, nicht erreichbare Telefone, Zeitpläne, Ordner, Teilergebnisse und Timeouts."
---

Beginne mit einem Gerät, einem Tag, einer Kategorie und einem Ziel. Veröffentliche keine Gesundheitsdaten, Routen, klinischen Dokumente, Tokens, Kopplungscodes oder privaten Pfade.

## Leere Daten

Wert in Apple Health oder Health Connect bestätigen, Berechtigung prüfen und einen Tag/eine Kategorie exportieren. Unterscheide `complete_empty`, fehlende Berechtigung, nicht unterstützt, übersprungen, teilweise und fehlgeschlagen. Fehlend ist nicht null.

## Schlaf fehlt unter Heute

Schlaf gehört zum Startdatum der Nacht. Exportiere Dienstagmorgen **Gestern** oder Montag und Dienstag. Siehe [Schlafdaten](/de/docs/sleep-date-attribution/).

## Dateien und Zeitpläne

Vault, Ordnerzugriff, Unterordner, Vorlage und Profil prüfen. iOS-Hintergrundarbeit und Android WorkManager liefern Zielzeiten, keine allgemeine Garantie. Gerät entsperren und ausstehende Wiederherstellung nutzen.

## CLI-Timeout

Ein Timeout bricht einen angenommenen Job nicht ab:

```bash
healthmd status --job JOB_UUID
healthmd resume JOB_UUID --timeout 300
```

Vor Vollständigkeitsbehauptungen Status, fehlende Tage, Abdeckung, `next_cursor`, Version und Einschränkungen prüfen. `--allow-partial` ändert nur den Exit-Status.

<div class="related"><a href="/de/docs/cli-jobs/"><span>Jobs</span>Fortsetzen und abbrechen.</a><a href="/de/docs/release-status/"><span>Versionen</span>Kompatibilität.</a></div>
