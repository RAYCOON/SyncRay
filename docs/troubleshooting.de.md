# Fehlerbehebung

## Häufige Probleme und Lösungen

### Verbindungsfehler

#### "Kann keine Verbindung zu SQL Server herstellen"
**Symptome**: Verbindungs-Timeout oder Server nicht gefunden

**Lösungen**:
1. Servernamen und Instanz überprüfen
   ```powershell
   Test-NetConnection -ComputerName servername -Port 1433
   ```
2. SQL Server Browser-Dienst für benannte Instanzen prüfen
3. IP-Adresse statt Hostname verwenden
4. Firewall erlaubt SQL Server-Port (Standard 1433) prüfen

#### "Anmeldung für Benutzer fehlgeschlagen"
**Symptome**: Authentifizierungsfehler

**Lösungen**:
1. Für SQL-Auth: Benutzername/Passwort überprüfen
2. Für Windows-Auth: Berechtigungen des aktuellen Benutzers prüfen
3. Sicherstellen, dass SQL Server gemischten Modus erlaubt
4. Benutzer hat Datenbankzugriff prüfen

### Validierungsfehler

#### "Tabelle in Datenbank nicht gefunden"
**Ursache**: Tabelle existiert nicht in Quell-/Zieldatenbank

**Lösung**: 
- Tabellennamen und Groß-/Kleinschreibung überprüfen
- Prüfen, ob Benutzer VIEW DEFINITION-Berechtigung hat
- Sicherstellen, dass richtige Datenbank angegeben ist

#### "Match-Felder nicht gefunden"
**Ursache**: Angegebene matchOn-Spalten existieren nicht

**Lösung**:
- Spaltennamen in Konfiguration prüfen
- matchOn entfernen, um automatisch Primärschlüssel zu verwenden
- Spaltenexistenz überprüfen mit:
  ```sql
  SELECT COLUMN_NAME 
  FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_NAME = 'IhreTabelle'
  ```

#### "matchOn-Felder erzeugen Duplikate"
**Ursache**: Die matchOn-Felder identifizieren Datensätze nicht eindeutig

**Lösung**:
- Weitere Felder zum matchOn-Array hinzufügen
- Primärschlüssel-Spalten verwenden
- Auf doppelte Daten prüfen:
  ```sql
  SELECT Feld1, Feld2, COUNT(*) 
  FROM IhreTabelle 
  GROUP BY Feld1, Feld2 
  HAVING COUNT(*) > 1
  ```

**Beim Export**:
- Sie werden gefragt, ob Sie fortfahren oder überspringen möchten, wenn Duplikate gefunden werden
- Bei Fortsetzung werden Duplikate nach matchOn-Feldern gruppiert
- Nur ein Datensatz pro eindeutiger Kombination wird exportiert
- Verwenden Sie `-SkipOnDuplicates` um Tabellen mit Duplikaten automatisch zu überspringen

**Beim Import** (Neue Funktion):
Wenn Duplikate in der Zieldatenbank während der Validierung erkannt werden:
- Das Tool zeigt Ihnen, welche Tabellen Duplikate haben
- Sie erhalten drei interaktive Optionen:
  1. **Detaillierte Duplikate anzeigen** - Alle doppelten Daten anzeigen
  2. **Duplikate automatisch entfernen** - Sichere Entfernung, behält niedrigsten Primärschlüssel
  3. **Operation abbrechen** - Import abbrechen

Beispiel-Interaktion:
```
[WARNUNG] Validierung fehlgeschlagen aufgrund doppelter Datensätze in folgenden Tabellen:
  - Users
  - Orders

Möchten Sie:
1) Detaillierte Duplikate anzeigen
2) Duplikate automatisch entfernen (behält Datensatz mit niedrigstem Primärschlüssel)
3) Operation abbrechen

Option wählen (1-3): 2

Entferne Duplikate aus Users...
[OK] Erfolgreich 5 doppelte Datensätze gelöscht

Entferne Duplikate aus Orders...
[OK] Erfolgreich 3 doppelte Datensätze gelöscht

[OK] Alle Duplikate erfolgreich entfernt
Validierung wird erneut ausgeführt...
[OK] Validierung erfolgreich
```

Die Duplikatentfernung:
- Wird in einer Transaktion ausgeführt (automatisches Rollback bei Fehler)
- Behält den Datensatz mit dem niedrigsten Primärschlüsselwert
- Validiert nach Bereinigung erneut für Erfolgssicherung
- Zeigt detaillierten Fortschritt für jede Tabelle

### Ausführungsfehler

#### "IDENTITY_INSERT ist auf OFF gesetzt"
**Ursache**: Versuch, Identity-Werte ohne Berechtigung einzufügen

**Lösung**:
1. `preserveIdentity: true` in Konfiguration setzen
2. Oder Identity-Spalte zu `ignoreColumns` hinzufügen
3. Sicherstellen, dass Benutzer ALTER-Berechtigung auf Tabelle hat

#### "String- oder Binärdaten würden abgeschnitten"
**Ursache**: Daten zu groß für Zielspalte

**Lösung**:
- Spaltengrößen zwischen Quelle und Ziel vergleichen
- Zielspalte vergrößern
- Spalte zu ignoreColumns hinzufügen, wenn nicht benötigt

#### "Transaktion zurückgerollt"
**Ursache**: Fehler während der Ausführung

**Lösung**:
- Fehlermeldung auf spezifisches Problem prüfen
- Sicherstellen, dass alle Constraints erfüllt sind
- Auf Trigger prüfen, die stören könnten
- Fremdschlüsselbeziehungen überprüfen

### Performance-Probleme

#### Langsamer Export
**Symptome**: Export dauert sehr lange

**Lösungen**:
1. exportWhere verwenden, um Daten zu begrenzen
2. Nur spezifische Tabellen exportieren
3. Auf fehlende Indizes prüfen
4. SQL Server-Performance überwachen

#### Speicherprobleme
**Symptome**: Speicherfehler

**Lösungen**:
1. Weniger Tabellen auf einmal verarbeiten
2. exportWhere verwenden, um Datenvolumen zu reduzieren
3. PowerShell-Speicherlimit erhöhen:
   ```powershell
   $PSVersionTable.PSVersion
   # Bei Windows PowerShell, PowerShell Core erwägen
   ```

### Konfigurationsprobleme

#### "Konfigurationsdatei nicht gefunden"
**Lösung**:
```bash
cp src/sync-config.example.json src/sync-config.json
```

#### "Keine matchOn-Felder angegeben und Primärschlüsselspalten werden ignoriert"
**Ursache**: Primärschlüssel ist in ignoreColumns, aber kein matchOn angegeben

**Lösung**:
- matchOn explizit angeben
- Primärschlüssel aus ignoreColumns entfernen
- Andere Felder für Matching verwenden

### Plattformspezifische Probleme

#### macOS/Linux: "Der Begriff 'powershell' wird nicht erkannt"
**Lösung**: `pwsh` statt `powershell` verwenden

#### Windows: "Ausführung von Skripts ist deaktiviert"
**Lösung**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Docker: Verbindungs-Timeouts
**Lösung**:
- Container-Name als Server verwenden
- Port-Mapping überprüfen
- SQL-Authentifizierung verwenden

## Debug-Modus

Um detailliertere Fehlerinformationen zu erhalten:

1. **-ShowSQL Flag verwenden** um alle SQL-Abfragen und Parameter zu sehen:
   ```powershell
   ./src/sync-export.ps1 -From source -ShowSQL
   ./src/sync-import.ps1 -To target -ShowSQL
   ```

2. **SQL Profiler aktivieren** um tatsächliche Abfragen aus SQL Server-Sicht zu sehen

3. **SQL Server-Fehlerprotokoll prüfen** für detaillierte Meldungen

4. **Ausführliche Ausgabe hinzufügen** zu Skripten:
   ```powershell
   $VerbosePreference = "Continue"
   ./src/sync-export.ps1 -From source -Verbose
   ```

## Hilfe erhalten

Falls Sie auf hier nicht behandelte Probleme stoßen:

1. Fehlermeldung sorgfältig prüfen
2. Ihre Konfiguration überprüfen
3. Zuerst mit einfacher Einzeltabellen-Synchronisierung testen
4. Issue auf GitHub erstellen mit:
   - Fehlermeldung
   - Konfiguration (ohne Passwörter)
   - PowerShell-Version
   - SQL Server-Version