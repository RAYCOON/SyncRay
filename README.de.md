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

### Neu: Zentraler SyncRay-Befehl

Der einfachste Weg, SyncRay zu verwenden, ist über das zentrale `syncray.ps1`-Skript:

```powershell
# Export aus Produktion
./src/syncray.ps1 -From production

# Import in Entwicklung (Vorschau)
./src/syncray.ps1 -To development

# Direkte Synchronisierung von Produktion zu Entwicklung
./src/syncray.ps1 -From production -To development

# Datenqualität analysieren
./src/syncray.ps1 -From production -Analyze

# Hilfe anzeigen
./src/syncray.ps1 -Help
```

### Einrichtungsanleitung

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

3. **SyncRay verwenden**:

   **Option A: Mit zentralem Skript (empfohlen)**
   ```powershell
   # Daten exportieren
   ./src/syncray.ps1 -From prod
   
   # Daten importieren (Vorschau)
   ./src/syncray.ps1 -To dev
   
   # Direkte Synchronisierung
   ./src/syncray.ps1 -From prod -To dev -Execute
   ```

   **Option B: Mit einzelnen Skripten**
   ```powershell
   # Export
   ./src/sync-export.ps1 -From prod
   
   # Import (Vorschau)
   ./src/sync-import.ps1 -To dev
   
   # Import (ausführen)
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

## Befehlsreferenz

### syncray.ps1 (Zentrales Tool)

Der Haupteinstiegspunkt für alle SyncRay-Operationen. Bestimmt automatisch die Operation basierend auf den Parametern.

**Parameter:**
- `-From <string>`: Quelldatenbank (löst Export-Modus aus)
- `-To <string>`: Zieldatenbank (löst Import-Modus aus)
- `-From <string> -To <string>`: Beide (löst Sync-Modus aus)
- `-Analyze`: Datenqualität analysieren ohne zu exportieren
- `-Validate`: Konfiguration validieren ohne Verarbeitung
- `-Execute`: Änderungen anwenden (für Import-/Sync-Modi)
- `-SkipOnDuplicates`: Tabellen mit doppelten Datensätzen überspringen
- `-CreateReports`: CSV-Berichte für Probleme erstellen
- `-ReportPath <string>`: Benutzerdefinierter Pfad für CSV-Berichte
- `-CsvDelimiter <string>`: CSV-Trennzeichen
- `-ShowSQL`: SQL-Anweisungen für Debugging anzeigen
- `-Help`: Hilfeinformationen anzeigen

**Beispiele:**
```powershell
# Export-Modus
./src/syncray.ps1 -From production

# Import-Modus (Vorschau)
./src/syncray.ps1 -To development

# Sync-Modus (direkte Übertragung)
./src/syncray.ps1 -From production -To development -Execute

# Analyse-Modus
./src/syncray.ps1 -From production -Analyze
```

### sync-export.ps1

Exportiert Daten aus der Quelldatenbank in JSON-Dateien.

**Parameter:**
- `-From <string>` (erforderlich): Quelldatenbank-Schlüssel aus Konfiguration
- `-ConfigFile <string>`: Pfad zur Konfigurationsdatei (Standard: sync-config.json)
- `-Tables <string>`: Kommagetrennte Liste spezifischer zu exportierender Tabellen
- `-Analyze`: Analysiert Datenqualität und erstellt Berichte ohne zu exportieren
- `-Validate`: Validiert Konfiguration und Daten ohne Export oder Berichte
- `-SkipOnDuplicates`: Überspringt automatisch Tabellen mit doppelten Datensätzen
- `-CreateReports`: Erstellt CSV-Berichte für Datenqualitätsprobleme
- `-ReportPath <string>`: Benutzerdefinierter Pfad für CSV-Berichte
- `-CsvDelimiter <string>`: CSV-Trennzeichen (Standard: kulturspezifisch)
- `-ShowSQL`: Zeigt SQL-Anweisungen und detaillierte Debug-Informationen

**Verwendungsbeispiele:**
```powershell
# Standard-Export
./src/sync-export.ps1 -From prod

# Export mit Problemberichten
./src/sync-export.ps1 -From prod -CreateReports

# Nur Datenqualität analysieren
./src/sync-export.ps1 -From prod -Analyze

# Spezifische Tabellen mit SQL-Debug-Ausgabe exportieren
./src/sync-export.ps1 -From prod -Tables "Users,Orders" -ShowSQL
```

### sync-import.ps1

Importiert Daten aus JSON-Dateien in die Zieldatenbank.

**Parameter:**
- `-To <string>` (erforderlich): Zieldatenbank-Schlüssel aus Konfiguration
- `-ConfigFile <string>`: Pfad zur Konfigurationsdatei (Standard: sync-config.json)
- `-Tables <string>`: Kommagetrennte Liste spezifischer zu importierender Tabellen
- `-Execute`: Änderungen anwenden (Standard ist Dry-Run)
- `-ShowSQL`: SQL-Anweisungen für Debugging anzeigen

**Duplikatbehandlung (Neu):**
Wenn beim Import-Validierung Duplikate erkannt werden, bietet das Tool interaktive Optionen:
1. **Detaillierte Duplikate anzeigen** - Zeigt alle doppelten Datensätze mit ihren Daten
2. **Duplikate automatisch entfernen** - Entfernt Duplikate und behält den Datensatz mit dem niedrigsten Primärschlüssel
3. **Operation abbrechen** - Import abbrechen

## Sicherheitsfunktionen

- **Validierung zuerst**: Umfassende Vorabprüfungen vor jeder Operation
- **Dry-Run als Standard**: Immer Vorschau der Änderungen vor der Ausführung
- **Sicherheitsbestätigung**: Explizite Bestätigung für Ausführung erforderlich
- **Transaktions-Rollback**: Automatisches Rollback bei Fehlern
- **Duplikatserkennung**: Stellt sicher, dass matchOn-Felder eindeutige Datensätze identifizieren
- **Sichere Duplikatentfernung**: Interaktive Bestätigung mit Transaktionsschutz

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