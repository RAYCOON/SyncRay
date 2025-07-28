# Konfigurationsreferenz

## Struktur der Konfigurationsdatei

SyncRay verwendet eine JSON-Konfigurationsdatei (`sync-config.json`) zur Definition von Datenbankverbindungen und Synchronisierungsregeln.

## Datenbankkonfiguration

### Verbindungseigenschaften

```json
{
  "databases": {
    "verbindungsname": {
      "server": "servername",
      "database": "datenbankname",
      "auth": "windows|sql",
      "user": "benutzername",      // Nur für SQL-Auth
      "password": "passwort"        // Nur für SQL-Auth
    }
  }
}
```

### Authentifizierungstypen

**Windows-Authentifizierung**
```json
{
  "server": "MEINSERVER\\SQLEXPRESS",
  "database": "MeineDatenbank",
  "auth": "windows"
}
```

**SQL Server-Authentifizierung**
```json
{
  "server": "meinserver.database.windows.net,1433",
  "database": "MeineDatenbank",
  "auth": "sql",
  "user": "meinbenutzer",
  "password": "meinpasswort"
}
```

## Tabellen-Synchronisierungseinstellungen

### Basiskonfiguration

```json
{
  "syncTables": [{
    "sourceTable": "Tabellenname",
    "matchOn": ["PrimärschlüsselFeld"]
  }]
}
```

### Erweiterte Konfiguration

```json
{
  "syncTables": [{
    "sourceTable": "Benutzer",
    "targetTable": "Benutzer_Archiv",
    "matchOn": ["BenutzerID", "FirmenID"],
    "ignoreColumns": ["LetzteÄnderung", "GeändertVon"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "preserveIdentity": false,
    "exportWhere": "IstAktiv = 1 AND ErstelltAm > '2024-01-01'"
  }]
}
```

### Tabellenparameter

| Parameter | Typ | Standard | Beschreibung |
|-----------|-----|----------|--------------|
| `sourceTable` | string | erforderlich | Name der Quelltabelle |
| `targetTable` | string | sourceTable | Name der Zieltabelle (falls abweichend) |
| `matchOn` | array | auto (PK) | Felder für Datensatzabgleich |
| `ignoreColumns` | array | [] | Zu ignorierende Spalten beim Vergleich |
| `allowInserts` | boolean | true | INSERT-Operationen erlauben |
| `allowUpdates` | boolean | true | UPDATE-Operationen erlauben |
| `allowDeletes` | boolean | false | DELETE-Operationen erlauben |
| `preserveIdentity` | boolean | false | IDENTITY_INSERT verwenden |
| `exportWhere` | string | null | WHERE-Klausel für Filterung |
| `replaceMode` | boolean | false | Alle Datensätze löschen vor dem Einfügen |

## Globale Einstellungen

```json
{
  "exportPath": "./sync-data",
  "defaultDryRun": true,
  "batchSize": 1000
}
```

| Einstellung | Typ | Standard | Beschreibung |
|-------------|-----|----------|--------------|
| `exportPath` | string | "./sync-data" | Verzeichnis für Exportdateien |
| `defaultDryRun` | boolean | true | Immer Dry-Run als Standard |
| `batchSize` | integer | 1000 | Datensätze pro Batch (zukünftige Verwendung) |

## Best Practices

### matchOn-Felder
- **Immer explizit angeben** für Klarheit
- Müssen Datensätze eindeutig identifizieren
- Zusammengesetzte Schlüssel möglich: `["Feld1", "Feld2"]`
- Primärschlüssel wird automatisch erkannt, wenn nicht angegeben

### Verwendung von ignoreColumns
- Für Zeitstempel-Spalten verwenden
- Für berechnete Spalten verwenden
- Für Identity-Spalten verwenden (wenn nicht beibehalten)

### Export-Filterung
- `exportWhere` für Synchronisierung von Teilmengen verwenden
- WHERE-Klausel-Syntax zuerst in SQL testen
- Performance-Auswirkungen bei großen Tabellen beachten

### Sicherheit
- Niemals Passwörter in Git committen
- Umgebungsvariablen für sensible Daten verwenden
- Integrierte Authentifizierung bevorzugen, wo möglich

## Konfigurationsbeispiele

### Einfache Spiegelung
```json
{
  "syncTables": [{
    "sourceTable": "Produkte",
    "matchOn": ["ProduktID"],
    "allowDeletes": true
  }]
}
```

### Archivierungsmuster
```json
{
  "syncTables": [{
    "sourceTable": "Bestellungen",
    "targetTable": "Bestellungen_Archiv",
    "matchOn": ["BestellID"],
    "allowInserts": true,
    "allowUpdates": false,
    "allowDeletes": false,
    "exportWhere": "BestellDatum < DATEADD(year, -1, GETDATE())"
  }]
}
```

### Teilsynchronisierung
```json
{
  "syncTables": [{
    "sourceTable": "Kunden",
    "matchOn": ["KundenID"],
    "ignoreColumns": ["LetzterLogin", "SessionToken"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IstAktiv = 1"
  }]
}
```

### Replace-Modus (Vollständiger Tabellenaustausch)
```json
{
  "syncTables": [{
    "sourceTable": "Referenzdaten",
    "replaceMode": true,
    "preserveIdentity": true
  }]
}
```

Wenn `replaceMode` aktiviert ist:
- Alle vorhandenen Datensätze in der Zieltabelle werden gelöscht
- Alle Datensätze aus dem Export werden eingefügt
- Keine UPDATE oder einzelnen DELETE Operationen werden durchgeführt
- matchOn-Felder sind nicht erforderlich (und werden ignoriert)
- Duplikatsprüfung wird übersprungen
- Wird in einer Transaktion für Sicherheit ausgeführt

**Wichtig**: Reihenfolge ist wichtig bei Tabellen mit Fremdschlüsselbeziehungen:
```json
{
  "syncTables": [
    { "sourceTable": "BestellDetails", "replaceMode": true },
    { "sourceTable": "Bestellungen", "replaceMode": true },
    { "sourceTable": "Kunden", "replaceMode": true }
  ]
}
```

## Validierung

Vor jeder Operation validiert SyncRay:
- Datenbankverbindung
- Tabellenexistenz
- Spaltenexistenz für matchOn-Felder
- Eindeutigkeit der matchOn-Felder (übersprungen bei replaceMode)
- WHERE-Klausel-Syntax
- Benutzerberechtigungen

Nur Validierung ausführen:
```powershell
./src/sync-export.ps1 -From source -Validate
```

Dies führt alle Prüfungen durch, ohne Daten zu exportieren.

## Befehlszeilenparameter

### syncray.ps1 (Haupteinstiegspunkt)

| Parameter | Typ | Beschreibung |
|-----------|-----|--------------|
| `-From` | string | Quelldatenbank-Schlüssel (löst Export-Modus aus) |
| `-To` | string | Zieldatenbank-Schlüssel (löst Import-Modus aus) |
| `-Interactive` | switch | Interaktiver Modus mit Eingabeaufforderungen |
| `-Analyze` | switch | Datenqualität analysieren ohne Export |
| `-Validate` | switch | Nur Konfiguration validieren |
| `-Execute` | switch | Änderungen anwenden (für Import/Sync) |
| `-Tables` | string | Kommagetrennte Liste von Tabellen |
| `-SkipOnDuplicates` | switch | Tabellen mit Duplikaten überspringen |
| `-CreateReports` | switch | CSV-Berichte erstellen |
| `-ReportPath` | string | Benutzerdefiniertes Berichtsverzeichnis |
| `-CsvDelimiter` | string | CSV-Trennzeichen |
| `-ShowSQL` | switch | SQL-Anweisungen anzeigen |
| `-Help` | switch | Hilfeinformationen anzeigen |

### sync-export.ps1

| Parameter | Typ | Beschreibung |
|-----------|-----|--------------|
| `-From` | string | **Erforderlich** - Quelldatenbank-Schlüssel |
| `-ConfigFile` | string | Konfigurationsdateipfad |
| `-Tables` | string | Spezifische zu exportierende Tabellen |
| `-Analyze` | switch | Nur analysieren, kein Export |
| `-Validate` | switch | Nur validieren |
| `-SkipOnDuplicates` | switch | Doppelte Tabellen überspringen |
| `-CreateReports` | switch | Qualitätsberichte erstellen |
| `-ReportPath` | string | Berichtsausgabeverzeichnis |
| `-CsvDelimiter` | string | CSV-Trennzeichen |
| `-ShowSQL` | switch | Debug-SQL-Ausgabe |

### sync-import.ps1

| Parameter | Typ | Beschreibung |
|-----------|-----|--------------|
| `-To` | string | **Erforderlich** - Zieldatenbank-Schlüssel |
| `-ConfigFile` | string | Konfigurationsdateipfad |
| `-Tables` | string | Spezifische zu importierende Tabellen |
| `-Execute` | switch | Änderungen anwenden (Standard: Vorschau) |
| `-ShowSQL` | switch | Debug-SQL-Ausgabe |

**Hinweis**: Import bietet interaktive Duplikatbereinigung, wenn Duplikate im Execute-Modus erkannt werden.