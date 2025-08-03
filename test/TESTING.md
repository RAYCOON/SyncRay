# SyncRay Test Framework

Umfassendes Test-Framework für SyncRay mit verschiedenen Test-Suiten zur Qualitätssicherung.

## Überblick

Das SyncRay Test-Framework bietet mehrere Test-Skripte für verschiedene Anwendungsfälle:

- **Basic Tests**: Schnelle Validierung der Grundfunktionalität
- **Comprehensive Tests**: Vollständige Test-Suite mit allen Features
- **Native SQLite Tests**: Plattformspezifische SQLite-Tests
- **Demo Tests**: Beispiel-Tests für Entwicklung

## Test-Skripte

### 1. Basic Tests (`run-basic-tests.ps1`)
**Zweck**: Schnelle Validierung für tägliche Entwicklung
**Dauer**: < 10 Sekunden
**Tests**: 5 grundlegende Prüfungen

```powershell
# Schnelle Validierung
./test/run-basic-tests.ps1

# Mit CI-Export
./test/run-basic-tests.ps1 -CI
```

**Getestete Bereiche**:
- SQLite3 Verfügbarkeit
- SyncRay Skript-Existenz
- Temporäre Datenbank-Erstellung
- JSON Funktionalität
- PowerShell Kompatibilität

### 2. Comprehensive Tests (`run-comprehensive-tests.ps1`)
**Zweck**: Vollständige Qualitätssicherung
**Dauer**: 30-60 Sekunden
**Tests**: 14+ umfassende Prüfungen

```powershell
# Vollständige Test-Suite mit Setup
./test/run-comprehensive-tests.ps1 -SetupTestData

# Nur bestimmte Test-Suiten
./test/run-comprehensive-tests.ps1 -SetupTestData -TestSuites Unit,Integration

# CI-Modus (ohne Performance-Tests)
./test/run-comprehensive-tests.ps1 -SetupTestData -CI -CleanupAfter
```

**Test-Suiten**:
- **Unit**: Grundfunktionen (Konfiguration, Datenbank, Struktur)
- **Integration**: Export/Import Pipeline, Änderungserkennung
- **Performance**: Große Datenmengen, Skalierbarkeit
- **EdgeCases**: Sonderzeichen, NULL-Werte, leere Tabellen
- **ErrorHandling**: Fehlerbehandlung, Sicherheit

### 3. Native SQLite Tests (`test-complete-syncray.ps1`)
**Zweck**: Plattformspezifische SQLite-Tests
**Dauer**: 20-40 Sekunden

```powershell
# Standard-Tests
./test/test-complete-syncray.ps1

# Bestimmte Kategorien
./test/test-complete-syncray.ps1 -Categories Basic,Advanced

# Test-Daten behalten
./test/test-complete-syncray.ps1 -KeepTestData
```

### 4. Demo/Simple Tests
**Zweck**: Beispiele und einfache Validierung

```powershell
# Einfacher Funktionstest
./test/test-native-sqlite.ps1

# Mit Cleanup
./test/test-native-sqlite.ps1 -Cleanup
```

## Test-Struktur

### Datenbank-Design
Alle Tests verwenden SQLite-Datenbanken mit realistischen Schemas:

```sql
-- Benutzer mit verschiedenen Datentypen
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY,
    Username TEXT NOT NULL UNIQUE,
    Email TEXT NOT NULL UNIQUE,
    FirstName TEXT NOT NULL,
    LastName TEXT NOT NULL,
    IsActive INTEGER DEFAULT 1,
    Salary REAL,
    Department TEXT,
    Manager INTEGER,
    Settings TEXT  -- JSON-Daten
);

-- Produkte mit Kategorien
CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY,
    ProductCode TEXT NOT NULL UNIQUE,
    ProductName TEXT NOT NULL,
    CategoryID INTEGER NOT NULL,
    Price REAL NOT NULL,
    Stock INTEGER DEFAULT 0,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system'
);

-- Bestellpositionen (Composite Key)
CREATE TABLE OrderItems (
    OrderID INTEGER NOT NULL,
    ProductID INTEGER NOT NULL,
    LineNumber INTEGER NOT NULL,
    Quantity INTEGER NOT NULL,
    UnitPrice REAL NOT NULL,
    Discount REAL DEFAULT 0,
    Total REAL NOT NULL,
    PRIMARY KEY (OrderID, ProductID, LineNumber)
);
```

### Test-Szenarien

#### 1. CRUD-Operationen
- **INSERT**: Neue Datensätze einfügen
- **UPDATE**: Bestehende Datensätze ändern
- **DELETE**: Datensätze löschen (wenn erlaubt)

#### 2. Spezielle Features
- **Composite Keys**: Mehrspaltiger Primärschlüssel
- **WHERE-Klauseln**: Selektiver Export
- **Ignore Columns**: Spalten bei Vergleich ignorieren
- **Replace Mode**: Komplette Tabelle ersetzen
- **NULL-Werte**: Korrekte Behandlung von NULL

#### 3. Edge Cases
- **Sonderzeichen**: Unicode, Apostrophe, Anführungszeichen
- **Große Datenmengen**: Performance-Tests mit 1000+ Datensätzen
- **Leere Tabellen**: Korrekte Behandlung
- **SQL-Injection**: Sicherheitstests

## Test-Ergebnisse

### Erfolgskriterien
- **Basic Tests**: 100% Erfolgsquote erforderlich
- **Comprehensive Tests**: ≥ 85% Erfolgsquote akzeptabel
- **Performance Tests**: Export von 1000 Datensätzen < 5 Sekunden

### Typische Ergebnisse
```
╔══════════════════════════════════════════════════════════════╗
║                      TEST ZUSAMMENFASSUNG                    ║
╚══════════════════════════════════════════════════════════════╝

Gesamtergebnis:
  Gesamt: 14 Tests
  ✓ Bestanden: 12
  ✗ Fehlgeschlagen: 2
  Erfolgsquote: 85.7%
  Dauer: 00:00.73

Ergebnisse nach Test-Suite:
  Unit: 4/4 (100%)
  Integration: 3/3 (100%)
  Performance: 1/1 (100%)
  EdgeCases: 3/3 (100%)
  ErrorHandling: 1/3 (33.3%)
```

## CI/CD Integration

### GitHub Actions
Tests sind in `.github/workflows/test.yml` integriert:

```yaml
jobs:
  test-sqlite:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Run SQLite Tests
      shell: pwsh
      run: |
        ./test/test-complete-syncray.ps1 -CI -Categories Basic,Advanced,EdgeCases
```

### Test-Export
Alle Test-Skripte unterstützen CI-Export:

```powershell
# Ergebnisse werden nach test-results.json exportiert
./test/run-comprehensive-tests.ps1 -CI
```

## Plattform-Kompatibilität

### Unterstützte Plattformen
- ✅ **Windows**: PowerShell 5.1 + PowerShell Core
- ✅ **macOS**: PowerShell Core (ARM64 + Intel)
- ✅ **Linux**: PowerShell Core

### SQLite-Unterstützung
- **Windows**: Kann SQLite3.exe benötigen
- **macOS**: Native SQLite3 (universal binary)
- **Linux**: SQLite3 über Paketmanager

### Installation
```bash
# macOS
brew install sqlite

# Ubuntu/Debian
sudo apt-get install sqlite3

# RHEL/CentOS
sudo yum install sqlite
```

## Entwicklung und Erweiterung

### Neue Tests hinzufügen
1. **Basic Test** hinzufügen:
```powershell
Test-Basic "Neuer Test" {
    # Test-Logik hier
    $result = Test-Something
    $result  # Return true/false
}
```

2. **Comprehensive Test** hinzufügen:
```powershell
Test-Feature -Suite "Unit" -Category "NewCategory" -Name "New Test" -Description "Beschreibung" -Test {
    try {
        # Test-Logik
        @{ Success = $true; Message = "Test erfolgreich" }
    } catch {
        @{ Success = $false; Message = "Test fehlgeschlagen: $_" }
    }
}
```

### Test-Kategorien
- **Unit**: Einzelne Komponenten
- **Integration**: Zusammenspiel von Komponenten
- **Performance**: Geschwindigkeit und Skalierbarkeit
- **EdgeCases**: Grenzfälle und Sondersituationen
- **ErrorHandling**: Fehlerbehandlung und Sicherheit

## Fehlerbehebung

### Häufige Probleme

#### SQLite nicht gefunden
```
ERROR: sqlite3 command not found
```
**Lösung**: SQLite3 installieren (siehe Plattform-Kompatibilität)

#### Berechtigungsfehler
```
ERROR: Permission denied
```
**Lösung**: Skript-Ausführung erlauben:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### Test-Daten nicht gelöscht
```
Test-Daten behalten:
  Datenbanken: /path/to/test-db
```
**Lösung**: Mit `-CleanupAfter` Parameter ausführen

#### ARM64 SQLite-Probleme
```
Unable to load shared library 'SQLite.Interop.dll'
```
**Lösung**: Native SQLite3 verwenden (automatisch in Tests erkannt)

## Best Practices

### Entwicklung
1. **Basic Tests** vor jeder Änderung ausführen
2. **Comprehensive Tests** vor Pull Requests
3. Test-Daten mit `-CleanupAfter` aufräumen
4. CI-Export für automatisierte Auswertung nutzen

### Test-Design
1. Tests sollten idempotent sein (wiederholbar)
2. Keine Abhängigkeiten zwischen Tests
3. Aussagekräftige Fehlermeldungen
4. Cleanup in finally-Blöcken

### Performance
1. Basic Tests: < 10 Sekunden
2. Comprehensive Tests: < 60 Sekunden
3. Große Datenmengen nur bei Performance-Tests
4. CI-Modus für optimierte Ausführung

## Beispiele

### Schnelle Validierung
```powershell
# Vor der Entwicklung - alles OK?
./test/run-basic-tests.ps1

# Output:
# 🎉 Alle grundlegenden Tests erfolgreich!
# SyncRay ist bereit für erweiterte Tests.
```

### Vollständiger Test-Lauf
```powershell
# Umfassende Qualitätssicherung
./test/run-comprehensive-tests.ps1 -SetupTestData -CleanupAfter

# Output:
# 🎉 Alle Tests erfolgreich! Qualitätssicherung bestanden.
```

### CI/CD Pipeline
```powershell
# Für automatisierte Tests
./test/test-complete-syncray.ps1 -CI -Categories Basic,Advanced
```

## Fazit

Das SyncRay Test-Framework bietet umfassende Qualitätssicherung für alle Aspekte der Anwendung. Mit verschiedenen Test-Suiten können sowohl schnelle Validierungen als auch tiefgehende Tests durchgeführt werden. Die plattformübergreifende Kompatibilität und CI/CD-Integration sorgen für zuverlässige und automatisierte Qualitätsprüfung.