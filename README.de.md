# SyncRay

Ein leistungsstarkes PowerShell-basiertes Datenbank-Synchronisierungstool, das nahtlose Datenmigration zwischen SQL Server-Datenbanken mit vollständiger INSERT-, UPDATE- und DELETE-Unterstützung ermöglicht.

![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue)
![SQL Server](https://img.shields.io/badge/SQL%20Server-2012%2B-red)
![License](https://img.shields.io/badge/license-MIT-green)

## Funktionen

- **Vollständige CRUD-Unterstützung**: Synchronisierung von Tabellen mit INSERT-, UPDATE- und DELETE-Operationen
- **Intelligentes Matching**: Flexible Feldabgleiche über Primärschlüssel hinaus
- **Dry-Run-Modus**: Vorschau von Änderungen vor der Ausführung (Standardverhalten)
- **Transaktionssicherheit**: Alle Operationen in Transaktionen mit automatischem Rollback
- **Umfassende Validierung**: Vorabprüfungen für Konfiguration, Tabellen und Berechtigungen
- **Export-Filterung**: WHERE-Klausel-Unterstützung für selektiven Datenexport
- **Identity-Behandlung**: Konfigurierbare IDENTITY_INSERT-Unterstützung
- **Detaillierte Berichterstattung**: Tabellenformatierte Änderungsübersichten und Ausführungsstatistiken

## Anforderungen

- PowerShell 5.0 oder höher
- SQL Server 2012 oder höher
- Entsprechende Datenbankberechtigungen (SELECT, INSERT, UPDATE, DELETE)

## Schnellstart

1. **Repository klonen**
   ```bash
   git clone https://github.com/yourusername/SyncRay.git
   cd SyncRay
   ```

2. **Datenbanken konfigurieren** in `src/sync-config.json`:
   ```json
   {
     "databases": {
       "prod": {
         "server": "PROD-SERVER",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "dev": {
         "server": "DEV-SERVER",
         "database": "DevelopmentDB",
         "auth": "sql",
         "user": "sa",
         "password": "password"
       }
     }
   }
   ```

3. **Daten aus Quelle exportieren**:
   ```powershell
   ./src/sync-export.ps1 -From prod
   ```

4. **Änderungen vorschauen** (Dry-Run):
   ```powershell
   ./src/sync-import.ps1 -To dev
   ```

5. **Änderungen anwenden**:
   ```powershell
   ./src/sync-import.ps1 -To dev -Execute
   ```

## Dokumentation

- [Installationsanleitung](docs/installation.de.md)
- [Konfigurationsreferenz](docs/configuration.de.md)
- [Verwendungsbeispiele](docs/examples.de.md)
- [Fehlerbehebung](docs/troubleshooting.de.md)

## Konfiguration

### Tabellen-Synchronisierungseinstellungen

```json
{
  "syncTables": [{
    "sourceTable": "Users",
    "targetTable": "Users_Archive",
    "matchOn": ["UserID"],
    "ignoreColumns": ["LastModified"],
    "allowInserts": true,
    "allowUpdates": true,
    "allowDeletes": false,
    "exportWhere": "IsActive = 1"
  }]
}
```

### Wichtige Parameter

- **matchOn**: Felder für Datensatzabgleich (erkennt automatisch Primärschlüssel, wenn leer)
- **ignoreColumns**: Spalten, die vom Vergleich ausgeschlossen werden
- **allowInserts/Updates/Deletes**: Steuerung erlaubter Operationen
- **exportWhere**: Quelldaten mit SQL WHERE-Klausel filtern

## Sicherheitsfunktionen

- **Validierung zuerst**: Umfassende Vorabprüfungen vor jeder Operation
- **Dry-Run als Standard**: Immer Vorschau der Änderungen vor der Ausführung
- **Sicherheitsbestätigung**: Explizite Bestätigung für Ausführung erforderlich
- **Transaktions-Rollback**: Automatisches Rollback bei Fehlern
- **Duplikatserkennung**: Stellt sicher, dass matchOn-Felder eindeutige Datensätze identifizieren

## Beispielausgabe

```
=== ÄNDERUNGEN ERKANNT ===

Tabelle                  | Einfügen | Aktualisieren | Löschen
-------------------------------------------------------------
Users                    |      125 |            37 |       5
Orders                   |      450 |             0 |       0
Products                 |        0 |            15 |       2
-------------------------------------------------------------
GESAMT                   |      575 |            52 |       7

WARNUNG: Sie sind dabei, die Datenbank zu modifizieren!

Möchten Sie diese Änderungen ausführen? (ja/nein):
```

## Mitwirken

Beiträge sind willkommen! Bitte zögern Sie nicht, einen Pull Request einzureichen.

## Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe die [LICENSE](LICENSE) Datei für Details.

## Danksagungen

- Erstellt mit PowerShell und SQL Server
- Inspiriert durch den Bedarf an zuverlässiger Datenbanksynchronisierung

---

Entwickelt vom Raycoon Team