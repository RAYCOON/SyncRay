# Installationsanleitung

## Voraussetzungen

### PowerShell
- Windows: PowerShell 5.0+ (in Windows 10 enthalten)
- macOS/Linux: PowerShell Core 6.0+ ([Download](https://github.com/PowerShell/PowerShell))

### SQL Server Anforderungen
- SQL Server 2012 oder höher
- SQL Server-Authentifizierung oder Windows-Authentifizierung
- Netzwerkzugriff auf SQL Server-Instanzen

### Erforderliche Berechtigungen
- SELECT auf Quelltabellen
- SELECT, INSERT, UPDATE, DELETE auf Zieltabellen
- VIEW DEFINITION für Schema-Informationen

## Installationsschritte

### 1. Klonen oder Herunterladen

```bash
# Von GitHub klonen
git clone https://github.com/yourusername/SyncRay.git
cd SyncRay

# Oder ZIP herunterladen und entpacken
```

### 2. Datenbankverbindungen konfigurieren

1. Beispielkonfiguration kopieren:
   ```bash
   cp src/sync-config.example.json src/sync-config.json
   ```

2. `src/sync-config.json` mit Ihren Datenbankdetails bearbeiten:
   ```json
   {
     "databases": {
       "source": {
         "server": "SERVER1\\INSTANCE",
         "database": "ProductionDB",
         "auth": "windows"
       },
       "target": {
         "server": "SERVER2",
         "database": "TestDB",
         "auth": "sql",
         "user": "sa",
         "password": "ihr-passwort"
       }
     }
   }
   ```

### 3. Verbindung testen

Führen Sie die Validierung aus, um Ihre Konfiguration zu testen:

```powershell
# Windows
.\src\sync-export.ps1 -From source -Tables NichtExistierendeTabelle

# macOS/Linux
pwsh src/sync-export.ps1 -From source -Tables NichtExistierendeTabelle
```

Dies validiert Ihre Verbindung ohne Daten zu exportieren.

## Plattformspezifische Hinweise

### Windows
- PowerShell oder PowerShell ISE verwenden
- Windows-Authentifizierung funktioniert standardmäßig
- Backslash für benannte Instanzen verwenden: `SERVER\INSTANCE`

### macOS/Linux
- PowerShell Core zuerst installieren
- `pwsh`-Befehl anstelle von `powershell` verwenden
- SQL-Authentifizierung empfohlen
- Schrägstrich für Pfade: `./src/sync-export.ps1`

### Docker-Container
- Sicherstellen, dass Container-Ports verfügbar sind
- Container-Name oder IP als Server verwenden
- SQL-Authentifizierung erforderlich

## Fehlerbehebung

### Verbindungsprobleme
- SQL Server-Erreichbarkeit prüfen: `Test-NetConnection -ComputerName servername -Port 1433`
- Firewall-Regeln überprüfen
- SQL Server Browser-Dienst für benannte Instanzen prüfen
- IP-Adresse statt Hostname versuchen

### Berechtigungsfehler
- Sicherstellen, dass Benutzer erforderliche Datenbankberechtigungen hat
- Für Windows-Auth, PowerShell als entsprechender Benutzer ausführen
- SQL Server-Fehlerprotokolle für detaillierte Meldungen prüfen

### PowerShell-Ausführungsrichtlinie
Falls Skripte nicht ausgeführt werden:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Nächste Schritte

Nach erfolgreicher Installation:
1. [Konfigurationsreferenz](configuration.de.md) durchsehen
2. [Verwendungsbeispiele](examples.de.md) ausprobieren
3. Tabellen-Synchronisierungsregeln einrichten