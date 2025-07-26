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