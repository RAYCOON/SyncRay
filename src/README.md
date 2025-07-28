# Sync Tools - Database Table Synchronization / Einfache Tabellen-Synchronisation

> **Note**: This README is in German. For English documentation, see the main [README.md](../README.md) in the project root.

## Übersicht

Zwei Skripte für den Export und Import von Datenbanktabellen:
- `sync-export.ps1` - Exportiert Tabellen aus einer Quelldatenbank
- `sync-import.ps1` - Importiert/synchronisiert Tabellen in eine Zieldatenbank mit INSERT/UPDATE/DELETE Support

## Quick Start

⚠️ **Wichtig**: Vor der ersten Verwendung die Validierung testen:
```powershell
# Testet die Konfiguration ohne Datenexport
pwsh sync-export.ps1 -From prod -Tables NonExistentTable
```

1. **Konfiguration anpassen** (`sync-config.json`):
   ```json
   {
     "databases": {
       "prod": { 
         "server": "DTW0180-SQL0001\\TST_SQL_TS",
         "database": "TestStelleNAE",
         "auth": "windows"
       },
       "dev": { 
         "server": "yoynmedbserver.database.windows.net,1433",
         "database": "TestStelleNAE",
         "auth": "sql",
         "user": "eessi_login",
         "password": "xxx"
       }
     },
     "syncTables": [
       {
         "sourceTable": "RulesTestCases",
         "matchOn": ["RTC_RSN"],
         "ignoreColumns": [],
         "allowDeletes": true
       }
     ]
   }
   ```

2. **Alle Tabellen exportieren**:
   ```powershell
   # Windows PowerShell
   .\sync-export.ps1 -From prod
   
   # macOS/Linux mit PowerShell Core
   pwsh sync-export.ps1 -From prod
   ```

3. **Änderungen analysieren** (Dry-Run):
   ```powershell
   # Windows
   .\sync-import.ps1 -To dev
   
   # macOS/Linux
   pwsh sync-import.ps1 -To dev
   ```

4. **Änderungen ausführen**:
   ```powershell
   # Windows
   .\sync-import.ps1 -To dev -Execute
   
   # macOS/Linux
   pwsh sync-import.ps1 -To dev -Execute
   ```
   
   Bei `-Execute` erscheint eine Sicherheitsabfrage mit Details zu den Änderungen.
   Nach Ausführung wird eine Statistik angezeigt.

## Konfiguration - sync-config.json

### Struktur der Konfigurationsdatei

```json
{
  "databases": {
    "prod": {
      "server": "DTW0180-SQL0001\\TST_SQL_TS",
      "database": "TestStelleNAE",
      "auth": "windows"
    },
    "dev": {
      "server": "yoynmedbserver.database.windows.net,1433",
      "database": "TestStelleNAE",
      "auth": "sql",
      "user": "eessi_login",
      "password": "xxx"
    }
  },
  
  "syncTables": [ 
    {
      "sourceTable": "RulesTestCases",
      "targetTable": "RulesTestCases_New",
      "matchOn": ["RTC_RSN"],
      "ignoreColumns": ["LastModified"],
      "allowDeletes": true,
      "preserveIdentity": false
    }
  ],
  
  "exportPath": "./sync-data",
  "defaultDryRun": true,
  "batchSize": 1000
}
```

### Datenbank-Konfiguration
- **server**: SQL Server Name (bei Named Instances mit doppeltem Backslash: `SERVER\\INSTANCE`)
- **database**: Datenbankname
- **auth**: Authentication-Typ (`windows` oder `sql`)
- **user/password**: Nur bei SQL-Authentifizierung erforderlich

### Tabellen-Einstellungen (syncTables)
- **sourceTable**: Name der Tabelle in der Quelldatenbank
- **targetTable**: Name der Tabelle in der Zieldatenbank (optional - wenn leer, wird sourceTable verwendet)
- **matchOn**: Array von Feldern für den Abgleich (nicht nur Primary Key!)
  - **WICHTIG**: Wenn leer, wird automatisch der Primary Key verwendet
  - **EMPFEHLUNG**: Immer explizit angeben für Klarheit und Zuverlässigkeit
  - Die Felder müssen eindeutige Datensätze identifizieren (keine Duplikate!)
- **ignoreColumns**: Array von Spalten die beim Vergleich ignoriert werden (z.B. Timestamps)
- **allowInserts**: Neue Zeilen einfügen erlauben (`true`/`false`, default: `true`)
- **allowUpdates**: Bestehende Zeilen aktualisieren erlauben (`true`/`false`, default: `true`)
- **allowDeletes**: Löschungen erlauben (`true`/`false`, default: `false`)
- **preserveIdentity**: IDENTITY_INSERT aktivieren für Identity-Spalten (`true`/`false`)
- **exportWhere**: WHERE-Klausel für den Export (optional, filtert Quelldaten)

### Globale Einstellungen
- **exportPath**: Verzeichnis für Export-Dateien (relativ zum Skript)
- **defaultDryRun**: Standardverhalten (immer `true` empfohlen)
- **batchSize**: Anzahl Zeilen pro Batch (für große Tabellen)

## Beispiele

### Nur bestimmte Tabellen
```powershell
.\sync-export.ps1 -From prod -Tables "RulesTestCases,SedBPCVs"
.\sync-import.ps1 -To test -Tables "RulesTestCases"
```

### Automatisierung
```powershell
# sync-daily.ps1
.\sync-export.ps1 -From prod
.\sync-import.ps1 -To dev -Execute

# Oder mit PowerShell Core auf macOS/Linux
pwsh -File sync-export.ps1 -From prod
pwsh -File sync-import.ps1 -To dev -Execute
```

### Navigation ins Verzeichnis
```powershell
# Windows
cd BuildScripts\pwrsh\sync-tools
.\sync-export.ps1 -From prod

# macOS/Linux
cd BuildScripts/pwrsh/sync-tools
pwsh sync-export.ps1 -From prod
```

## Matching-Beispiele

### Standard (gleiche Tabellennamen)
```json
{
  "sourceTable": "Users",
  "matchOn": ["UserID"]
}
```

### Unterschiedliche Tabellennamen
```json
{
  "sourceTable": "RulesTestCases_New",
  "targetTable": "RulesTestCases",
  "matchOn": ["RTC_RSN"]
}
```

### Mehrere Felder für Matching
```json
{
  "sourceTable": "StandardTestCasesPayloads",
  "matchOn": ["SedName", "SedVersion"],
  "ignoreColumns": ["LastModified"]
}
```

### Nur neue Daten hinzufügen (Read-Only Sync)
```json
{
  "sourceTable": "LogEntries",
  "allowInserts": true,
  "allowUpdates": false,
  "allowDeletes": false,
  "matchOn": ["LogID"]
}
```

### Nur Updates erlauben (keine neuen Daten)
```json
{
  "sourceTable": "Customers",
  "allowInserts": false,
  "allowUpdates": true,
  "allowDeletes": false,
  "matchOn": ["CustomerID"]
}
```

### Export mit Filter (WHERE-Klausel)
```json
{
  "sourceTable": "Orders",
  "targetTable": "Orders_Archive",
  "exportWhere": "OrderDate >= '2024-01-01' AND Status = 'Completed'",
  "matchOn": ["OrderID"],
  "allowDeletes": false
}
```

### Nur aktive Datensätze synchronisieren
```json
{
  "sourceTable": "RulesTestCases",
  "exportWhere": "inaktiv = 0",
  "matchOn": ["RTC_RSN"],
  "allowDeletes": true
}
```

## Features

- **Automatische Änderungserkennung**: Vergleicht Quell- und Zieldaten automatisch
- **INSERT/UPDATE/DELETE Support**: Vollständige Synchronisation möglich
- **Dry-Run Modus**: Zeigt Änderungen ohne Ausführung (Standard)
- **Sicherheitsabfrage**: Bei -Execute wird immer nach Bestätigung gefragt
- **Transaktionale Sicherheit**: Alle Änderungen pro Tabelle in einer Transaktion
- **Fehlerbehandlung**: Automatischer Rollback bei Fehlern
- **Statistik**: Zeigt nach Ausführung eine Zusammenfassung
- **Flexible Konfiguration**: Unterschiedliche Tabellennamen, Matching-Felder etc.
- **Umfassende Validierung**:
  - Prüft Datenbankverbindungen und Berechtigungen
  - Validiert Tabellen-Existenz
  - Überprüft matchOn-Felder auf Existenz und Eindeutigkeit
  - Testet WHERE-Klauseln auf Syntax-Fehler
  - Warnt bei fehlenden oder ignorierten Spalten
- **Automatische Primary Key Erkennung**: Wenn matchOn nicht angegeben

## Wichtige Hinweise

### matchOn-Felder
- Die matchOn-Felder müssen **eindeutige Datensätze** identifizieren
- Bei Duplikaten schlägt die Validierung fehl (verhindert falsche Updates/Deletes)
- Wenn nicht angegeben: Automatische Primary Key Verwendung
- **Best Practice**: Immer explizit angeben für Klarheit

### Validierung
- Läuft **automatisch vor jedem Export/Import**
- Bei Fehlern wird die Ausführung abgebrochen
- Zeigt detaillierte Fehlermeldungen mit Beispielen
- Unterscheidet zwischen Fehlern (Stopp) und Warnungen (Fortsetzung)

### Identity-Spalten
- Bei `preserveIdentity: true` wird IDENTITY_INSERT verwendet
- Identity-Spalten sollten in `ignoreColumns` aufgeführt werden, wenn sie nicht synchronisiert werden sollen
- Achtung: Bei automatischer PK-Erkennung können Probleme auftreten

## Dateien

- `sync-config.json` - Zentrale Konfiguration
- `sync-data/` - Export-Verzeichnis (wird automatisch erstellt)
- `*.json` - Export-Dateien pro Tabelle
- `sync-validation.ps1` - Validierungsfunktionen (wird automatisch geladen)