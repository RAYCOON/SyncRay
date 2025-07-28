# Verwendungsbeispiele

## Basis-Synchronisierung

### Vollständige Datenbank-Synchronisierung
Alle konfigurierten Tabellen exportieren und zum Ziel synchronisieren:

```powershell
# Export von Produktion
./src/sync-export.ps1 -From prod

# Änderungen vorschauen (Dry-Run)
./src/sync-import.ps1 -To dev

# Änderungen anwenden
./src/sync-import.ps1 -To dev -Execute
```

### Einzeltabellen-Synchronisierung
Nur bestimmte Tabellen synchronisieren:

```powershell
# Bestimmte Tabellen exportieren
./src/sync-export.ps1 -From prod -Tables "Benutzer,Bestellungen"

# Bestimmte Tabellen importieren
./src/sync-import.ps1 -To dev -Tables "Benutzer" -Execute
```

## Häufige Szenarien

### 1. Entwicklungsdatenbank aktualisieren
Entwicklungsdatenbank mit Produktionsdaten aktualisieren (anonymisiert):

```json
{
  "syncTables": [{
    "sourceTable": "Benutzer",
    "matchOn": ["BenutzerID"],
    "ignoreColumns": ["Passwort", "Email"],
    "allowDeletes": true
  }]
}
```

### 2. Datenarchivierung
Alte Datensätze in Archivdatenbank verschieben:

```json
{
  "syncTables": [{
    "sourceTable": "Bestellungen",
    "targetTable": "Bestellungen_Archiv",
    "matchOn": ["BestellID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false,
    "exportWhere": "BestellDatum < '2023-01-01'"
  }]
}
```

### 3. Teildaten-Synchronisierung
Nur aktive Datensätze synchronisieren:

```json
{
  "syncTables": [{
    "sourceTable": "Kunden",
    "matchOn": ["KundenID"],
    "exportWhere": "IstAktiv = 1 AND Land = 'Deutschland'"
  }]
}
```

### 4. Stammdatenverteilung
Referenzdaten an mehrere Datenbanken verteilen:

```powershell
# Stammdaten einmal exportieren
./src/sync-export.ps1 -From master -Tables "Produkte,Kategorien"

# In mehrere Ziele importieren
./src/sync-import.ps1 -To filiale1 -Execute
./src/sync-import.ps1 -To filiale2 -Execute
./src/sync-import.ps1 -To filiale3 -Execute
```

## Interaktiver Modus

### Verwendung von syncray.ps1 ohne Parameter
Wenn Sie `syncray.ps1` ohne Parameter ausführen, wird der interaktive Modus gestartet:

```powershell
./src/syncray.ps1
```

Interaktive Eingabeaufforderungen führen Sie durch:
1. **Operationsauswahl**: Export, Import, Sync oder Analyze
2. **Datenbankauswahl**: Wählen Sie aus konfigurierten Datenbanken
3. **Tabellenauswahl**: Alle Tabellen oder spezifische Tabellen
4. **Modusauswahl**: Vorschau oder Ausführen
5. **Berichtsoptionen**: CSV-Berichte erstellen (optional)

Beispiel-Interaktion:
```
=== SYNCRAY INTERAKTIVER MODUS ===

Verfügbare Operationen:
1. Export - Daten aus Quelldatenbank exportieren
2. Import - Daten in Zieldatenbank importieren
3. Sync - Direkte Synchronisierung von Quelle zu Ziel
4. Analyze - Nur Datenqualität analysieren

Operation wählen (1-4): 3

Verfügbare Quelldatenbanken:
1. prod
2. dev
3. staging

Quelldatenbank wählen (1-3): 1

Verfügbare Zieldatenbanken:
1. dev
2. staging

Zieldatenbank wählen (1-2): 1

Tabellen synchronisieren:
1. Alle konfigurierten Tabellen
2. Spezifische Tabellen auswählen

Option wählen (1-2): 2

Verfügbare Tabellen:
1. Benutzer
2. Bestellungen
3. Produkte
4. Kategorien

Tabellen wählen (kommagetrennte Nummern): 1,2

Ausführungsmodus:
1. Änderungen anzeigen (Dry-Run)
2. Änderungen ausführen

Modus wählen (1-2): 1
```

## Erweiterte Verwendung

### Zusammengesetzte Schlüssel
Für Tabellen ohne einzelne Primärschlüssel:

```json
{
  "syncTables": [{
    "sourceTable": "BestellDetails",
    "matchOn": ["BestellID", "ProduktID"],
    "allowDeletes": true
  }]
}
```

### Nur-Lesen-Synchronisierung
Nur neue Datensätze hinzufügen, niemals bestehende ändern:

```json
{
  "syncTables": [{
    "sourceTable": "AuditLogs",
    "matchOn": ["LogID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false
  }]
}
```

### Identity-Spalten-Behandlung
Identity-Werte während der Synchronisierung beibehalten:

```json
{
  "syncTables": [{
    "sourceTable": "Produkte",
    "matchOn": ["ProduktID"],
    "preserveIdentity": true,
    "ignoreColumns": []
  }]
}
```

### Replace-Modus Beispiel
Vollständiger Tabellenaustausch (nützlich für Referenzdaten):

```json
{
  "syncTables": [{
    "sourceTable": "Laender",
    "replaceMode": true,
    "preserveIdentity": true
  }, {
    "sourceTable": "Bundeslaender",
    "replaceMode": true,
    "preserveIdentity": true
  }, {
    "sourceTable": "Staedte",
    "replaceMode": true,
    "preserveIdentity": true
  }]
}
```

**Hinweis**: Tabellen werden in Konfigurationsreihenfolge verarbeitet. Bei Fremdschlüsselabhängigkeiten, listen Sie Kind-Tabellen vor Eltern-Tabellen auf.

### Umgang mit Duplikaten
Wenn Duplikate während des Imports mit `-Execute` erkannt werden:

```
[WARNUNG] Validierung fehlgeschlagen aufgrund doppelter Datensätze in folgenden Tabellen:
  - Benutzer
  - Bestellungen

Möchten Sie:
1) Detaillierte doppelte Datensätze anzeigen
2) Duplikate automatisch entfernen (behält Datensatz mit niedrigstem Primärschlüssel)
3) Operation abbrechen

Option wählen (1-3): 1

=== Doppelte Datensätze in Benutzer ===
BenutzerID | Email           | Name        | DuplikatGruppe
-----------|-----------------|-------------|---------------
1234       | john@email.com  | John Doe    | 1
5678       | john@email.com  | John D.     | 1
2345       | jane@email.com  | Jane Smith  | 2
6789       | jane@email.com  | J. Smith    | 2

Möchten Sie jetzt:
1) Duplikate automatisch entfernen
2) Operation abbrechen

Option wählen (1-2): 1
```

## Workflow-Beispiele

### Täglicher Synchronisierungs-Workflow
```powershell
# Morgendliches Sync-Skript
$datum = Get-Date -Format "yyyy-MM-dd"
Write-Host "Starte tägliche Synchronisierung für $datum"

# Produktionsdaten exportieren
./src/sync-export.ps1 -From prod

# Aktuelle Entwicklungsdaten sichern (optional)
Invoke-SqlCmd -Query "BACKUP DATABASE DevDB TO DISK='C:\Backups\DevDB_$datum.bak'"

# Zu Entwicklung synchronisieren
./src/sync-import.ps1 -To dev -Execute

Write-Host "Tägliche Synchronisierung abgeschlossen"
```

### Selektive Tabellenaktualisierung
```powershell
# Nur bestimmte Tabellen aktualisieren
$tabellen = @("Benutzer", "Bestellungen", "Produkte")

foreach ($tabelle in $tabellen) {
    Write-Host "Synchronisiere $tabelle..."
    ./src/sync-export.ps1 -From prod -Tables $tabelle
    ./src/sync-import.ps1 -To dev -Tables $tabelle -Execute
}
```

### Validierung vor Synchronisierung
```powershell
# Vor Synchronisierung validieren
./src/sync-export.ps1 -From prod -Tables "NichtExistent"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Validierung erfolgreich, führe Synchronisierung durch"
    ./src/sync-export.ps1 -From prod
    ./src/sync-import.ps1 -To dev -Execute
} else {
    Write-Host "Validierung fehlgeschlagen, Synchronisierung abgebrochen" -ForegroundColor Red
}
```

### Datenqualitätsanalyse
Daten analysieren ohne zu exportieren:

```powershell
# Alle Tabellen analysieren
./src/sync-export.ps1 -From prod -Analyze

# Mit CSV-Berichten analysieren
./src/sync-export.ps1 -From prod -Analyze -CreateReports

# Spezifische Tabellen analysieren
./src/sync-export.ps1 -From prod -Tables "Benutzer,Bestellungen" -Analyze -CreateReports -ReportPath ./berichte
```

Analysebericht enthält:
- Doppelte Datensätze nach matchOn-Feldern
- Tabellen, die übersprungen würden
- Validierungsprobleme
- Zeilenanzahl und Datenvolumen

Beispiel generierte CSV-Berichte:
- `duplicate_issues.csv` - Alle gefundenen doppelten Datensätze
- `skipped_tables.csv` - Tabellen, die übersprungen würden
- `data_quality_summary.csv` - Allgemeine Qualitätsmetriken

## Ausgabebeispiele

### Dry-Run-Ausgabe
```
=== SYNC IMPORT ===
Ziel: dev (DEV-SERVER)
Modus: DRY-RUN

Analysiere Benutzer...
Analysiere Bestellungen...

=== ÄNDERUNGEN ERKANNT ===

Tabelle                  | Einfügen | Aktualisieren | Löschen
-------------------------------------------------------------
Benutzer                 |       15 |            82 |       3
Bestellungen             |      234 |             0 |       0
-------------------------------------------------------------
GESAMT                   |      249 |            82 |       3

[DRY-RUN] Keine Änderungen vorgenommen
Führen Sie mit -Execute aus, um diese Änderungen anzuwenden
```

### Ausführungsausgabe
```
=== SYNC IMPORT ===
Ziel: dev (DEV-SERVER)
Modus: AUSFÜHRUNG

=== ÄNDERUNGEN ERKANNT ===
Tabelle                  | Einfügen | Aktualisieren | Löschen
-------------------------------------------------------------
Benutzer                 |       15 |            82 |       3
-------------------------------------------------------------

WARNUNG: Sie sind dabei, die Datenbank zu modifizieren!

Möchten Sie diese Änderungen ausführen? (ja/nein): ja

=== FÜHRE ÄNDERUNGEN AUS ===

→ Benutzer
  Füge 15 Zeilen ein... [OK]
  Aktualisiere 82 Zeilen... [OK]
  Lösche 3 Zeilen... [OK]
  ✓ Transaktion committed

✓ Alle Änderungen erfolgreich ausgeführt

=== AUSFÜHRUNGSSTATISTIK ===
Tabelle                  | Einfügen | Aktualisieren | Löschen
-------------------------------------------------------------
Benutzer                 |       15 |            82 |       3
-------------------------------------------------------------
GESAMT                   |       15 |            82 |       3
```