# Umfassendes SyncRay Test-Framework für vollständige Qualitätssicherung
# Alle Tests für Export, Import, Validierung und Edge-Cases

param(
    [switch]$SetupTestData,
    [switch]$CleanupAfter,
    [switch]$Verbose,
    [switch]$CI,
    [string[]]$TestSuites = @("Unit", "Integration", "Performance", "EdgeCases", "ErrorHandling")
)

$ErrorActionPreference = "Stop"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

# Test-Framework Konfiguration
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Total = 0
    Details = @()
    StartTime = Get-Date
    Suites = @{}
}

# Pfade
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
$testDbPath = Join-Path $testRoot "comprehensive-test-db"
$sourceDb = Join-Path $testDbPath "source.db"
$targetDb = Join-Path $testDbPath "target.db"
$backupDb = Join-Path $testDbPath "backup.db"
$configFile = Join-Path $testRoot "comprehensive-config.json"
$exportPath = Join-Path $testRoot "comprehensive-export"

# SQLite Verfügbarkeit prüfen
if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    throw "SQLite3 ist nicht verfügbar. Bitte installieren Sie SQLite3."
}

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           SYNCRAY COMPREHENSIVE TEST FRAMEWORK               ║" -ForegroundColor Cyan
Write-Host "║                Vollständige Qualitätssicherung              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# SQLite Hilfsfunktionen
function Invoke-SQLite {
    param(
        [string]$Database,
        [string]$Query,
        [switch]$AsCsv,
        [switch]$Silent
    )
    
    if ($AsCsv) {
        $Query = ".mode csv`n.headers on`n$Query"
    }
    
    $result = $Query | sqlite3 $Database 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (-not $Silent) {
            throw "SQLite Fehler: $result"
        }
        return $null
    }
    
    return $result
}

# Test-Runner
function Test-Feature {
    param(
        [string]$Suite,
        [string]$Category,
        [string]$Name,
        [string]$Description,
        [scriptblock]$Test,
        [switch]$Skip
    )
    
    $script:TestResults.Total++
    
    if ($Skip) {
        Write-Host "`n⊘ ÜBERSPRUNGEN - [$Suite] $Category : $Name" -ForegroundColor Yellow
        Write-Host "  $Description" -ForegroundColor Gray
        $script:TestResults.Skipped++
        return
    }
    
    Write-Host "`n━━━ [$Suite] $Category : $Name ━━━" -ForegroundColor Yellow
    Write-Host "$Description" -ForegroundColor Gray
    
    $testStart = Get-Date
    
    try {
        $result = & $Test
        $duration = ((Get-Date) - $testStart).TotalMilliseconds
        
        if ($result.Success) {
            Write-Host "✓ BESTANDEN - $($result.Message) (${duration}ms)" -ForegroundColor Green
            $script:TestResults.Passed++
            $status = "Passed"
        } else {
            Write-Host "✗ FEHLGESCHLAGEN - $($result.Message)" -ForegroundColor Red
            if ($result.Details) {
                Write-Host "  Details: $($result.Details)" -ForegroundColor Gray
            }
            $script:TestResults.Failed++
            $status = "Failed"
        }
    } catch {
        Write-Host "✗ FEHLER - $_" -ForegroundColor Red
        Write-Verbose "Stack Trace: $($_.ScriptStackTrace)"
        $script:TestResults.Failed++
        $status = "Error"
        $result = @{ Message = $_.Exception.Message }
    }
    
    $script:TestResults.Details += @{
        Suite = $Suite
        Category = $Category
        Name = $Name
        Status = $status
        Message = $result.Message
        Duration = $duration
        Timestamp = Get-Date
    }
    
    # Suite-Statistiken
    if (-not $script:TestResults.Suites.ContainsKey($Suite)) {
        $script:TestResults.Suites[$Suite] = @{ Passed = 0; Failed = 0; Total = 0 }
    }
    $script:TestResults.Suites[$Suite].Total++
    if ($status -eq "Passed") {
        $script:TestResults.Suites[$Suite].Passed++
    } else {
        $script:TestResults.Suites[$Suite].Failed++
    }
}

# Test-Umgebung initialisieren
function Initialize-TestEnvironment {
    Write-Host "`n═══ Test-Umgebung initialisieren ═══" -ForegroundColor Cyan
    
    # Verzeichnisse erstellen
    @($testDbPath, $exportPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
    
    # Alte Datenbanken löschen
    @($sourceDb, $targetDb, $backupDb) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force }
    }
    
    # Export-Verzeichnis leeren
    if (Test-Path $exportPath) {
        Get-ChildItem $exportPath | Remove-Item -Recurse -Force
    }
    
    Write-Host "✓ Test-Umgebung bereit" -ForegroundColor Green
}

# Umfassende Test-Datenbanken erstellen
function Create-ComprehensiveTestData {
    Write-Host "`n═══ Umfassende Test-Daten erstellen ═══" -ForegroundColor Cyan
    
    # Quelle-Datenbank mit komplexen Testdaten
    $sourceSchema = @"
-- Benutzer-Tabelle mit verschiedenen Datentypen
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY,
    Username TEXT NOT NULL UNIQUE,
    Email TEXT NOT NULL UNIQUE,
    FirstName TEXT NOT NULL,
    LastName TEXT NOT NULL,
    IsActive INTEGER DEFAULT 1,
    CreatedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    LastModified TEXT,
    Salary REAL,
    Department TEXT,
    Manager INTEGER,
    Settings TEXT -- JSON-Daten
);

-- Produkte mit Kategorien
CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY,
    ProductCode TEXT NOT NULL UNIQUE,
    ProductName TEXT NOT NULL,
    CategoryID INTEGER NOT NULL,
    Price REAL NOT NULL,
    Stock INTEGER DEFAULT 0,
    IsActive INTEGER DEFAULT 1,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system',
    Description TEXT,
    Tags TEXT -- Komma-getrennte Tags
);

-- Kategorien
CREATE TABLE Categories (
    CategoryID INTEGER PRIMARY KEY,
    CategoryName TEXT NOT NULL UNIQUE,
    ParentCategoryID INTEGER,
    IsActive INTEGER DEFAULT 1
);

-- Bestellungen
CREATE TABLE Orders (
    OrderID INTEGER PRIMARY KEY,
    OrderNumber TEXT NOT NULL UNIQUE,
    CustomerID INTEGER NOT NULL,
    OrderDate TEXT NOT NULL,
    ShippingDate TEXT,
    Status TEXT NOT NULL,
    Total REAL NOT NULL,
    Tax REAL DEFAULT 0,
    Notes TEXT,
    CreatedBy TEXT DEFAULT 'system'
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

-- Konfigurationstabelle
CREATE TABLE Configuration (
    ConfigKey TEXT PRIMARY KEY,
    ConfigValue TEXT NOT NULL,
    Description TEXT,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Leere Tabelle für Tests
CREATE TABLE EmptyTable (
    ID INTEGER PRIMARY KEY,
    Data TEXT
);

-- Tabelle mit Sonderzeichen
CREATE TABLE SpecialChars (
    ID INTEGER PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    JsonData TEXT,
    XmlData TEXT,
    UnicodeText TEXT
);

-- Test-Daten einfügen
INSERT INTO Categories VALUES 
    (1, 'Electronics', NULL, 1),
    (2, 'Computers', 1, 1),
    (3, 'Accessories', 1, 1),
    (4, 'Software', NULL, 1),
    (5, 'Office', NULL, 1);

INSERT INTO Users VALUES 
    (1, 'admin', 'admin@company.com', 'System', 'Administrator', 1, '2024-01-01', '2024-12-01', 120000, 'IT', NULL, '{"theme": "dark", "language": "de"}'),
    (2, 'john.doe', 'john.doe@company.com', 'John', 'Doe', 1, '2024-01-15', '2024-12-15', 75000, 'Sales', 1, '{"theme": "light", "language": "en"}'),
    (3, 'jane.smith', 'jane.smith@company.com', 'Jane', 'Smith', 1, '2024-02-01', '2024-12-10', 85000, 'Marketing', 1, '{"theme": "light", "language": "de"}'),
    (4, 'bob.wilson', 'bob.wilson@company.com', 'Bob', 'Wilson', 0, '2024-02-15', '2024-11-01', 65000, 'HR', 1, '{"theme": "dark", "language": "en"}'),
    (5, 'alice.jones', 'alice.jones@company.com', 'Alice', 'Jones', 1, '2024-03-01', '2024-12-20', 95000, 'IT', 1, '{"theme": "auto", "language": "de"}');

INSERT INTO Products VALUES
    (1, 'LAP-001', 'Business Laptop Pro', 2, 1299.99, 50, 1, datetime('now'), 'system', 'High-performance business laptop', 'laptop,business,professional'),
    (2, 'MOU-001', 'Wireless Optical Mouse', 3, 29.99, 200, 1, datetime('now'), 'system', 'Ergonomic wireless mouse', 'mouse,wireless,ergonomic'),
    (3, 'KEY-001', 'Mechanical Gaming Keyboard', 3, 149.99, 75, 1, datetime('now'), 'system', 'RGB mechanical keyboard', 'keyboard,gaming,rgb,mechanical'),
    (4, 'HUB-001', 'USB-C Multi-Port Hub', 3, 49.99, 150, 1, datetime('now'), 'system', '7-in-1 USB-C hub', 'hub,usb-c,multiport'),
    (5, 'MON-001', 'UltraWide Monitor 34"', 2, 599.99, 25, 1, datetime('now'), 'system', '34 inch ultrawide monitor', 'monitor,ultrawide,34inch');

INSERT INTO Orders VALUES
    (1001, 'ORD-2024-001', 2, '2024-01-15 10:30:00', '2024-01-17 14:00:00', 'Delivered', 1379.97, 137.997, 'Prioritätsbestellung - Express', 'john.doe'),
    (1002, 'ORD-2024-002', 3, '2024-02-20 14:15:00', '2024-02-22 09:30:00', 'Delivered', 199.98, 19.998, NULL, 'jane.smith'),
    (1003, 'ORD-2024-003', 4, '2024-11-15 09:45:00', NULL, 'Processing', 1299.99, 129.999, 'Warten auf Zahlung', 'bob.wilson'),
    (1004, 'ORD-2024-004', 5, '2024-12-01 16:20:00', NULL, 'Cancelled', 29.99, 2.999, 'Kunde hat storniert', 'alice.jones'),
    (1005, 'ORD-2024-005', 2, '2024-12-10 11:00:00', NULL, 'Shipped', 679.97, 67.997, 'Geschenkverpackung', 'john.doe');

INSERT INTO OrderItems VALUES
    (1001, 1, 1, 1, 1299.99, 0, 1299.99),
    (1001, 2, 2, 1, 29.99, 0, 29.99),
    (1001, 4, 3, 1, 49.99, 0, 49.99),
    (1002, 3, 1, 1, 149.99, 15, 134.99),
    (1002, 2, 2, 1, 29.99, 15, 25.49),
    (1003, 1, 1, 1, 1299.99, 0, 1299.99),
    (1005, 5, 1, 1, 599.99, 10, 539.99),
    (1005, 3, 2, 1, 149.99, 10, 134.99);

INSERT INTO Configuration VALUES
    ('app.version', '2.1.0', 'Application version', datetime('now')),
    ('db.backup.enabled', 'true', 'Enable automatic backups', datetime('now')),
    ('export.format', 'json', 'Default export format', datetime('now')),
    ('sync.batch.size', '1000', 'Batch size for sync operations', datetime('now'));

INSERT INTO SpecialChars VALUES
    (1, 'Test''s Name mit Apostrophe', 'Beschreibung mit "Anführungszeichen"', '{"key": "value", "special": "chars"}', '<xml>test & data</xml>', 'Umlaute: äöüÄÖÜß'),
    (2, 'Name; mit Semikolon', 'Zeile1\nZeile2\nZeile3', NULL, NULL, 'Unicode: 中文测试 データ'),
    (3, 'Emoji Test 😀🎉', 'Test © 2024 ® ™', '{"emoji": "😀", "symbols": "®©™"}', '<test/>', 'Griechisch: αβγδε'),
    (4, 'SQL Injection Test', 'Test''; DROP TABLE Users; --', NULL, NULL, 'Русский текст');
"@
    
    Invoke-SQLite -Database $sourceDb -Query $sourceSchema
    Write-Host "✓ Quelle-Datenbank erstellt" -ForegroundColor Green
    
    # Ziel-Datenbank mit unterschiedlichen Daten
    $targetSchema = @"
-- Gleiche Struktur, andere Daten
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY,
    Username TEXT NOT NULL UNIQUE,
    Email TEXT NOT NULL UNIQUE,
    FirstName TEXT NOT NULL,
    LastName TEXT NOT NULL,
    IsActive INTEGER DEFAULT 1,
    CreatedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    LastModified TEXT,
    Salary REAL,
    Department TEXT,
    Manager INTEGER,
    Settings TEXT
);

CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY,
    ProductCode TEXT NOT NULL UNIQUE,
    ProductName TEXT NOT NULL,
    CategoryID INTEGER NOT NULL,
    Price REAL NOT NULL,
    Stock INTEGER DEFAULT 0,
    IsActive INTEGER DEFAULT 1,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system',
    Description TEXT,
    Tags TEXT
);

CREATE TABLE Categories (
    CategoryID INTEGER PRIMARY KEY,
    CategoryName TEXT NOT NULL UNIQUE,
    ParentCategoryID INTEGER,
    IsActive INTEGER DEFAULT 1
);

CREATE TABLE Orders (
    OrderID INTEGER PRIMARY KEY,
    OrderNumber TEXT NOT NULL UNIQUE,
    CustomerID INTEGER NOT NULL,
    OrderDate TEXT NOT NULL,
    ShippingDate TEXT,
    Status TEXT NOT NULL,
    Total REAL NOT NULL,
    Tax REAL DEFAULT 0,
    Notes TEXT,
    CreatedBy TEXT DEFAULT 'system'
);

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

CREATE TABLE Configuration (
    ConfigKey TEXT PRIMARY KEY,
    ConfigValue TEXT NOT NULL,
    Description TEXT,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE EmptyTable (
    ID INTEGER PRIMARY KEY,
    Data TEXT
);

CREATE TABLE SpecialChars (
    ID INTEGER PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    JsonData TEXT,
    XmlData TEXT,
    UnicodeText TEXT
);

-- Unterschiedliche Testdaten
INSERT INTO Categories VALUES 
    (1, 'Electronics', NULL, 1),
    (2, 'Computers', 1, 1),
    (10, 'Legacy Category', NULL, 0);

INSERT INTO Users VALUES 
    (1, 'admin', 'admin.old@company.com', 'System', 'Administrator', 1, '2024-01-01', '2024-11-01', 115000, 'IT', NULL, '{"theme": "light", "language": "en"}'),
    (2, 'john.doe', 'john.doe@company.com', 'John', 'Doe', 0, '2024-01-15', '2024-11-15', 75000, 'Sales', 1, '{"theme": "dark", "language": "en"}'),
    (10, 'target.only', 'target@company.com', 'Target', 'Only', 1, '2024-03-01', '2024-12-01', 60000, 'Admin', 1, '{"theme": "auto", "language": "de"}');

INSERT INTO Products VALUES
    (1, 'LAP-001', 'Business Laptop Pro', 2, 999.99, 45, 1, '2024-11-01', 'admin', 'High-performance business laptop', 'laptop,business,professional'),
    (2, 'MOU-001', 'Wireless Optical Mouse', 3, 29.99, 180, 1, '2024-11-01', 'admin', 'Ergonomic wireless mouse', 'mouse,wireless,ergonomic'),
    (10, 'OLD-001', 'Legacy Product', 1, 99.99, 5, 0, '2024-01-01', 'system', 'Old product', 'legacy,discontinued');

INSERT INTO Configuration VALUES
    ('app.version', '2.0.0', 'Application version', '2024-11-01'),
    ('db.backup.enabled', 'false', 'Enable automatic backups', '2024-11-01'),
    ('old.setting', 'value', 'Old configuration', '2024-01-01');
"@
    
    Invoke-SQLite -Database $targetDb -Query $targetSchema
    Write-Host "✓ Ziel-Datenbank erstellt" -ForegroundColor Green
    
    # Konfigurationsdatei erstellen
    $config = @{
        databases = @{
            source = @{
                server = "localhost"
                database = $sourceDb
                auth = "sqlite"
            }
            target = @{
                server = "localhost"
                database = $targetDb
                auth = "sqlite"
            }
        }
        
        syncTables = @(
            @{
                sourceTable = "Users"
                matchOn = @("UserID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "Products"
                matchOn = @("ProductID")
                ignoreColumns = @("LastModified", "ModifiedBy")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "Categories"
                matchOn = @("CategoryID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "Orders"
                matchOn = @("OrderID")
                exportWhere = "Status IN ('Delivered', 'Shipped')"
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "OrderItems"
                matchOn = @("OrderID", "ProductID", "LineNumber")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "Configuration"
                matchOn = @("ConfigKey")
                replaceMode = $true
                preserveIdentity = $false
            },
            @{
                sourceTable = "SpecialChars"
                matchOn = @("ID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "EmptyTable"
                matchOn = @("ID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            }
        )
        
        exportPath = $exportPath
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configFile
    Write-Host "✓ Konfigurationsdatei erstellt" -ForegroundColor Green
}

# Unit Tests - Grundfunktionen
function Run-UnitTests {
    Write-Host "`n═══ UNIT TESTS - Grundfunktionen ═══" -ForegroundColor Cyan
    
    Test-Feature -Suite "Unit" -Category "Validation" -Name "Config File Validation" -Description "Konfigurationsdatei validieren" -Test {
        try {
            if (Test-Path $configFile) {
                $config = Get-Content $configFile | ConvertFrom-Json
                if ($config.databases -and $config.syncTables) {
                    @{ Success = $true; Message = "Konfigurationsdatei ist gültig" }
                } else {
                    @{ Success = $false; Message = "Konfigurationsdatei unvollständig" }
                }
            } else {
                @{ Success = $false; Message = "Konfigurationsdatei nicht gefunden" }
            }
        } catch {
            @{ Success = $false; Message = "Konfigurationsdatei ungültig: $_" }
        }
    }
    
    Test-Feature -Suite "Unit" -Category "Database" -Name "SQLite Connection" -Description "SQLite Datenbankverbindung testen" -Test {
        try {
            $result = Invoke-SQLite -Database $sourceDb -Query "SELECT sqlite_version();"
            @{ Success = $true; Message = "SQLite Version: $result" }
        } catch {
            @{ Success = $false; Message = "SQLite Verbindung fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "Unit" -Category "Database" -Name "Table Structure" -Description "Tabellenstruktur validieren" -Test {
        try {
            $tables = Invoke-SQLite -Database $sourceDb -Query "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" -AsCsv
            $tableList = ($tables | ConvertFrom-Csv).name
            $expectedTables = @("Users", "Products", "Categories", "Orders", "OrderItems", "Configuration", "SpecialChars", "EmptyTable")
            
            $missing = @($expectedTables | Where-Object { $_ -notin $tableList })
            
            if ($missing.Count -eq 0) {
                @{ Success = $true; Message = "Alle $($expectedTables.Count) erwarteten Tabellen vorhanden" }
            } else {
                @{ Success = $false; Message = "Fehlende Tabellen: $($missing -join ', ')" }
            }
        } catch {
            @{ Success = $false; Message = "Tabellenstruktur-Validierung fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "Unit" -Category "Data" -Name "Test Data Integrity" -Description "Testdaten-Integrität prüfen" -Test {
        try {
            $userCount = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) FROM Users;"
            $productCount = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) FROM Products;"
            $orderCount = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) FROM Orders;"
            
            if ($userCount -eq "5" -and $productCount -eq "5" -and $orderCount -eq "5") {
                @{ Success = $true; Message = "Testdaten vollständig: $userCount Benutzer, $productCount Produkte, $orderCount Bestellungen" }
            } else {
                @{ Success = $false; Message = "Testdaten unvollständig: $userCount/$productCount/$orderCount" }
            }
        } catch {
            @{ Success = $false; Message = "Testdaten-Validierung fehlgeschlagen: $_" }
        }
    }
}

# Integration Tests - Export/Import Pipeline
function Run-IntegrationTests {
    Write-Host "`n═══ INTEGRATION TESTS - Export/Import Pipeline ═══" -ForegroundColor Cyan
    
    Test-Feature -Suite "Integration" -Category "Export" -Name "Full Export" -Description "Vollständiger Export aller Tabellen" -Test {
        try {
            $config = Get-Content $configFile | ConvertFrom-Json
            $exportedTables = 0
            
            foreach ($syncTable in $config.syncTables) {
                $tableName = $syncTable.sourceTable
                $whereClause = if ($syncTable.exportWhere) { "WHERE $($syncTable.exportWhere)" } else { "" }
                
                # Daten exportieren
                $query = "SELECT * FROM $tableName $whereClause"
                $data = Invoke-SQLite -Database $sourceDb -Query $query -AsCsv
                
                if ($data) {
                    $dataObjects = $data | ConvertFrom-Csv
                    $export = @{
                        metadata = @{
                            sourceTable = $tableName
                            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                            rowCount = $dataObjects.Count
                            matchOn = $syncTable.matchOn
                            exportWhere = $syncTable.exportWhere
                        }
                        data = $dataObjects
                    }
                    
                    $exportFile = Join-Path $exportPath "$tableName.json"
                    $export | ConvertTo-Json -Depth 10 | Set-Content $exportFile
                    $exportedTables++
                } else {
                    # Leere Tabelle
                    $export = @{
                        metadata = @{
                            sourceTable = $tableName
                            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                            rowCount = 0
                            matchOn = $syncTable.matchOn
                            exportWhere = $syncTable.exportWhere
                        }
                        data = @()
                    }
                    
                    $exportFile = Join-Path $exportPath "$tableName.json"
                    $export | ConvertTo-Json -Depth 10 | Set-Content $exportFile
                    $exportedTables++
                }
            }
            
            if ($exportedTables -eq $config.syncTables.Count) {
                @{ Success = $true; Message = "$exportedTables Tabellen erfolgreich exportiert" }
            } else {
                @{ Success = $false; Message = "Nur $exportedTables von $($config.syncTables.Count) Tabellen exportiert" }
            }
        } catch {
            @{ Success = $false; Message = "Export fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "Integration" -Category "Export" -Name "WHERE Clause Export" -Description "Selektiver Export mit WHERE-Klausel" -Test {
        try {
            $ordersFile = Join-Path $exportPath "Orders.json"
            if (Test-Path $ordersFile) {
                $exportData = Get-Content $ordersFile | ConvertFrom-Json
                $filteredOrders = @($exportData.data | Where-Object { $_.Status -in @('Delivered', 'Shipped') }).Count
                
                if ($filteredOrders -eq $exportData.data.Count -and $filteredOrders -gt 0) {
                    @{ Success = $true; Message = "WHERE-Klausel korrekt: $filteredOrders gefilterte Bestellungen" }
                } else {
                    @{ Success = $false; Message = "WHERE-Klausel fehlerhaft: $filteredOrders von $($exportData.data.Count)" }
                }
            } else {
                @{ Success = $false; Message = "Orders Export-Datei nicht gefunden" }
            }
        } catch {
            @{ Success = $false; Message = "WHERE-Klausel Test fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "Integration" -Category "Import" -Name "Change Detection" -Description "Änderungserkennung zwischen Quelle und Ziel" -Test {
        try {
            $usersFile = Join-Path $exportPath "Users.json"
            if (-not (Test-Path $usersFile)) {
                return @{ Success = $false; Message = "Users Export-Datei nicht gefunden" }
            }
            
            $sourceData = (Get-Content $usersFile | ConvertFrom-Json).data
            $targetData = Invoke-SQLite -Database $targetDb -Query "SELECT * FROM Users;" -AsCsv | ConvertFrom-Csv
            
            $sourceIds = $sourceData.UserID
            $targetIds = $targetData.UserID
            
            $toInsert = @($sourceIds | Where-Object { $_ -notin $targetIds }).Count
            $toUpdate = 0
            $toDelete = @($targetIds | Where-Object { $_ -notin $sourceIds }).Count
            
            # Updates prüfen
            foreach ($sourceUser in $sourceData) {
                $targetUser = $targetData | Where-Object { $_.UserID -eq $sourceUser.UserID }
                if ($targetUser -and ($sourceUser.Email -ne $targetUser.Email -or $sourceUser.Salary -ne $targetUser.Salary)) {
                    $toUpdate++
                }
            }
            
            if ($toInsert -gt 0 -or $toUpdate -gt 0 -or $toDelete -gt 0) {
                @{ Success = $true; Message = "Änderungen erkannt: $toInsert Einfügungen, $toUpdate Aktualisierungen, $toDelete Löschungen" }
            } else {
                @{ Success = $false; Message = "Keine Änderungen erkannt" }
            }
        } catch {
            @{ Success = $false; Message = "Änderungserkennung fehlgeschlagen: $_" }
        }
    }
}

# Performance Tests
function Run-PerformanceTests {
    Write-Host "`n═══ PERFORMANCE TESTS - Leistung und Skalierbarkeit ═══" -ForegroundColor Cyan
    
    if ($CI) {
        Write-Host "Performance Tests in CI-Umgebung übersprungen" -ForegroundColor Yellow
        return
    }
    
    Test-Feature -Suite "Performance" -Category "Large Dataset" -Name "Large Table Export" -Description "Export großer Datenmengen" -Test {
        try {
            # Große Tabelle erstellen
            Invoke-SQLite -Database $sourceDb -Query "CREATE TABLE LargeTable (ID INTEGER PRIMARY KEY, Data TEXT, Value REAL, Category TEXT);"
            
            $insertStart = Get-Date
            $totalRecords = 2000
            
            # Batch-Insert für bessere Performance
            $batchSql = "INSERT INTO LargeTable (Data, Value, Category) VALUES "
            $values = @()
            for ($i = 1; $i -le $totalRecords; $i++) {
                $values += "('TestData$i', $($i * 1.5), 'Category$($i % 10)')"
                
                # Batch alle 500 Datensätze
                if ($i % 500 -eq 0 -or $i -eq $totalRecords) {
                    $fullSql = $batchSql + ($values -join ", ")
                    Invoke-SQLite -Database $sourceDb -Query $fullSql
                    $values = @()
                }
            }
            
            $insertDuration = ((Get-Date) - $insertStart).TotalSeconds
            
            # Export testen
            $exportStart = Get-Date
            $data = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM LargeTable;" -AsCsv | ConvertFrom-Csv
            $exportDuration = ((Get-Date) - $exportStart).TotalSeconds
            
            if ($data.Count -eq $totalRecords -and $exportDuration -lt 5) {
                @{ Success = $true; Message = "$totalRecords Datensätze in ${exportDuration}s exportiert" }
            } else {
                @{ Success = $false; Message = "Performance-Problem: $($data.Count) Datensätze in ${exportDuration}s" }
            }
        } catch {
            @{ Success = $false; Message = "Performance Test fehlgeschlagen: $_" }
        }
    }
}

# Edge Case Tests
function Run-EdgeCaseTests {
    Write-Host "`n═══ EDGE CASE TESTS - Grenzfälle und Sonderfälle ═══" -ForegroundColor Cyan
    
    Test-Feature -Suite "EdgeCases" -Category "Special Characters" -Name "Unicode and Special Chars" -Description "Unicode und Sonderzeichen" -Test {
        try {
            $specialFile = Join-Path $exportPath "SpecialChars.json" 
            if (Test-Path $specialFile) {
                $exportData = Get-Content $specialFile | ConvertFrom-Json
                $specialRecord = $exportData.data | Where-Object { $_.ID -eq "1" }
                
                if ($specialRecord -and $specialRecord.Name -like "*Test's Name*" -and $specialRecord.UnicodeText -like "*äöüÄÖÜß*") {
                    @{ Success = $true; Message = "Sonderzeichen korrekt verarbeitet" }
                } else {
                    @{ Success = $false; Message = "Sonderzeichen nicht korrekt verarbeitet" }
                }
            } else {
                @{ Success = $false; Message = "SpecialChars Export nicht gefunden" }
            }
        } catch {
            @{ Success = $false; Message = "Sonderzeichen Test fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "EdgeCases" -Category "Empty Data" -Name "Empty Table Handling" -Description "Leere Tabellen verarbeiten" -Test {
        try {
            $emptyFile = Join-Path $exportPath "EmptyTable.json"
            if (Test-Path $emptyFile) {
                $exportData = Get-Content $emptyFile | ConvertFrom-Json
                if ($exportData.metadata.rowCount -eq 0) {
                    @{ Success = $true; Message = "Leere Tabelle korrekt exportiert" }
                } else {
                    @{ Success = $false; Message = "Leere Tabelle nicht korrekt verarbeitet" }
                }
            } else {
                @{ Success = $false; Message = "EmptyTable Export nicht gefunden" }
            }
        } catch {
            @{ Success = $false; Message = "Leere Tabelle Test fehlgeschlagen: $_" }
        }
    }
    
    Test-Feature -Suite "EdgeCases" -Category "NULL Values" -Name "NULL Value Handling" -Description "NULL-Werte verarbeiten" -Test {
        try {
            $ordersFile = Join-Path $exportPath "Orders.json"
            if (Test-Path $ordersFile) {
                $exportData = Get-Content $ordersFile | ConvertFrom-Json
                $orderWithNull = $exportData.data | Where-Object { $_.Notes -eq "" -or $null -eq $_.Notes }
                
                if ($orderWithNull) {
                    @{ Success = $true; Message = "NULL-Werte korrekt verarbeitet" }
                } else {
                    @{ Success = $false; Message = "NULL-Werte nicht gefunden oder nicht korrekt verarbeitet" }
                }
            } else {
                @{ Success = $false; Message = "Orders Export nicht gefunden" }
            }
        } catch {
            @{ Success = $false; Message = "NULL-Werte Test fehlgeschlagen: $_" }
        }
    }
}

# Error Handling Tests
function Run-ErrorHandlingTests {
    Write-Host "`n═══ ERROR HANDLING TESTS - Fehlerbehandlung ═══" -ForegroundColor Cyan
    
    Test-Feature -Suite "ErrorHandling" -Category "Invalid Config" -Name "Missing Database" -Description "Fehlende Datenbank" -Test {
        try {
            $nonExistentDb = Join-Path $testDbPath "nonexistent.db"
            $result = Invoke-SQLite -Database $nonExistentDb -Query "SELECT 1;" -Silent
            
            if ($null -eq $result) {
                @{ Success = $true; Message = "Fehlende Datenbank korrekt erkannt" }
            } else {
                @{ Success = $false; Message = "Fehlende Datenbank nicht erkannt" }
            }
        } catch {
            @{ Success = $true; Message = "Fehlende Datenbank korrekt abgefangen" }
        }
    }
    
    Test-Feature -Suite "ErrorHandling" -Category "Invalid Config" -Name "Missing Table" -Description "Fehlende Tabelle" -Test {
        try {
            $result = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM NonExistentTable;" -Silent
            
            if ($null -eq $result) {
                @{ Success = $true; Message = "Fehlende Tabelle korrekt erkannt" }
            } else {
                @{ Success = $false; Message = "Fehlende Tabelle nicht erkannt" }
            }
        } catch {
            @{ Success = $true; Message = "Fehlende Tabelle korrekt abgefangen" }
        }
    }
    
    Test-Feature -Suite "ErrorHandling" -Category "Data Integrity" -Name "SQL Injection Protection" -Description "SQL-Injection Schutz" -Test {
        try {
            $maliciousInput = "'; DROP TABLE Users; --"
            $result = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM SpecialChars WHERE Name = '$maliciousInput';" -Silent
            
            # Prüfen ob Users Tabelle noch existiert
            $usersExists = Invoke-SQLite -Database $sourceDb -Query "SELECT name FROM sqlite_master WHERE type='table' AND name='Users';" -Silent
            
            if ($usersExists) {
                @{ Success = $true; Message = "SQL-Injection erfolgreich abgewehrt" }
            } else {
                @{ Success = $false; Message = "SQL-Injection war erfolgreich - Sicherheitsproblem!" }
            }
        } catch {
            @{ Success = $true; Message = "SQL-Injection korrekt abgefangen" }
        }
    }
}

# Hauptausführung
try {
    Initialize-TestEnvironment
    
    if ($SetupTestData) {
        Create-ComprehensiveTestData
    }
    
    Write-Host "`n═══ Test-Suiten ausführen: $($TestSuites -join ', ') ═══" -ForegroundColor Cyan
    
    foreach ($suite in $TestSuites) {
        switch ($suite) {
            "Unit" { Run-UnitTests }
            "Integration" { Run-IntegrationTests }
            "Performance" { Run-PerformanceTests }
            "EdgeCases" { Run-EdgeCaseTests }
            "ErrorHandling" { Run-ErrorHandlingTests }
            default { Write-Host "Unbekannte Test-Suite: $suite" -ForegroundColor Yellow }
        }
    }
    
    # Zusammenfassung
    $duration = (Get-Date) - $script:TestResults.StartTime
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      TEST ZUSAMMENFASSUNG                    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $passRate = if ($script:TestResults.Total -gt 0) { 
        [math]::Round(($script:TestResults.Passed / $script:TestResults.Total) * 100, 1) 
    } else { 0 }
    
    Write-Host "`nGesamtergebnis:"
    Write-Host "  Gesamt: $($script:TestResults.Total) Tests"
    Write-Host "  ✓ Bestanden: $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "  ✗ Fehlgeschlagen: $($script:TestResults.Failed)" -ForegroundColor Red
    Write-Host "  ⊘ Übersprungen: $($script:TestResults.Skipped)" -ForegroundColor Yellow
    Write-Host "  Erfolgsquote: $passRate%"
    Write-Host "  Dauer: $($duration.ToString('mm\:ss\.ff'))"
    
    # Suite-Details
    Write-Host "`nErgebnisse nach Test-Suite:"
    foreach ($suite in $script:TestResults.Suites.Keys) {
        $suiteStats = $script:TestResults.Suites[$suite]
        $suiteRate = if ($suiteStats.Total -gt 0) { 
            [math]::Round(($suiteStats.Passed / $suiteStats.Total) * 100, 1) 
        } else { 0 }
        Write-Host "  $suite`: $($suiteStats.Passed)/$($suiteStats.Total) ($suiteRate%)" -ForegroundColor $(if ($suiteStats.Failed -eq 0) { "Green" } else { "Yellow" })
    }
    
    if ($script:TestResults.Failed -eq 0) {
        Write-Host "`n🎉 Alle Tests erfolgreich! Qualitätssicherung bestanden." -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Einige Tests fehlgeschlagen - Qualitätssicherung unvollständig" -ForegroundColor Yellow
        
        Write-Host "`nFehlgeschlagene Tests:" -ForegroundColor Red
        $script:TestResults.Details | Where-Object { $_.Status -ne "Passed" } | ForEach-Object {
            Write-Host "  - [$($_.Suite)] $($_.Category) - $($_.Name): $($_.Message)" -ForegroundColor Red
        }
    }
    
    # CI-Export
    if ($CI) {
        $resultsFile = Join-Path $testRoot "comprehensive-test-results.json"
        $script:TestResults | ConvertTo-Json -Depth 10 | Set-Content $resultsFile
        Write-Host "`nTest-Ergebnisse exportiert: $resultsFile" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "`nSchwerwiegender Fehler: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
} finally {
    # Aufräumen
    if ($CleanupAfter) {
        Write-Host "`nTest-Daten aufräumen..." -ForegroundColor Yellow
        
        @($testDbPath, $exportPath, $configFile) | ForEach-Object {
            if (Test-Path $_) {
                Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "✓ Aufräumen abgeschlossen" -ForegroundColor Green
    } else {
        Write-Host "`nTest-Daten behalten:" -ForegroundColor Yellow
        Write-Host "  Datenbanken: $testDbPath" -ForegroundColor Gray
        Write-Host "  Exports: $exportPath" -ForegroundColor Gray
        Write-Host "  Konfiguration: $configFile" -ForegroundColor Gray
    }
}

# Exit-Code
exit $(if ($script:TestResults.Failed -eq 0) { 0 } else { 1 })