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

## Validierung

Vor jeder Operation validiert SyncRay:
- Datenbankverbindung
- Tabellenexistenz
- Spaltenexistenz für matchOn-Felder
- Eindeutigkeit der matchOn-Felder
- WHERE-Klausel-Syntax
- Benutzerberechtigungen

Nur Validierung ausführen:
```powershell
./src/sync-export.ps1 -From source -Tables Tabellenname
```

Dies führt alle Prüfungen durch, ohne Daten zu exportieren.