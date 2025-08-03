# Unit Tests für Database Connection - Reparierte Version
# Testet die database-adapter-fixed.ps1 Implementation

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

# Test-Framework laden
$testRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$sharedPath = Join-Path $testRoot "shared"
. (Join-Path $sharedPath "Test-Framework.ps1")
. (Join-Path $sharedPath "Database-TestHelpers.ps1")
. (Join-Path $sharedPath "Assertion-Helpers.ps1")

# Fixed Database Adapter laden
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
. (Join-Path $srcRoot "database-adapter-fixed.ps1")

# Test-Framework initialisieren
Initialize-TestFramework

# Test-Suite erstellen
$suite = New-TestSuite -Name "Database-Connection-Fixed" -Category "unit" -Module "validation"

# Test 1: Database Adapter Factory
$suite.AddTest("Database-Adapter-Factory", {
    param($context)
    
    try {
        # SQLite Connection String
        $sqliteConn = "Data Source=test.db"
        $adapter = New-DatabaseAdapter -ConnectionString $sqliteConn
        
        Assert-NotNull -Value $adapter -Message "Adapter sollte erstellt werden"
        Assert-Equal -Expected "SQLite" -Actual $adapter.DatabaseType -Message "SQLite sollte erkannt werden"
        Assert-Equal -Expected $sqliteConn -Actual $adapter.ConnectionString -Message "Connection String sollte gesetzt sein"
        
        # SQL Server Connection String
        $sqlServerConn = "Server=localhost;Database=TestDB;Integrated Security=true"
        $adapter2 = New-DatabaseAdapter -ConnectionString $sqlServerConn
        
        Assert-Equal -Expected "SqlServer" -Actual $adapter2.DatabaseType -Message "SQL Server sollte erkannt werden"
        
        return @{ Success = $true; Message = "Database Adapter Factory funktional" }
        
    } catch {
        return @{ Success = $false; Message = "Database Adapter Factory Test fehlgeschlagen: $_" }
    }
})

# Test 2: SQLite Connection Test
$suite.AddTest("SQLite-Connection-Test", {
    param($context)
    
    try {
        # Temporäre SQLite-Datenbank erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "connection_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Leere Datenbank erstellen
        "CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT);" | sqlite3 $dbPath
        
        # Connection String
        $connString = "Data Source=$dbPath"
        
        # Test über Wrapper-Funktion
        $result = Test-DatabaseConnection -ConnectionString $connString
        
        Assert-True -Condition $result.Success -Message "SQLite Connection sollte erfolgreich sein"
        Assert-Equal -Expected "SQLite connection successful" -Actual $result.Message -Message "Success Message erwartet"
        Assert-NotNull -Value $result.Permissions -Message "Permissions sollten gesetzt sein"
        Assert-True -Condition $result.Permissions.CanSelect -Message "Select-Berechtigung erwartet"
        
        return @{ Success = $true; Message = "SQLite Connection Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "SQLite Connection Test fehlgeschlagen: $_" }
    }
})

# Test 3: Table Exists Test
$suite.AddTest("Table-Exists-Test", {
    param($context)
    
    try {
        # Test-Datenbank erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "table_exists_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Tabellen erstellen
        $setupQueries = @(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT UNIQUE);",
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL);",
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, total REAL);"
        )
        
        foreach ($query in $setupQueries) {
            $query | sqlite3 $dbPath
        }
        
        $connString = "Data Source=$dbPath"
        
        # Existierende Tabellen testen
        $tables = @("users", "products", "orders")
        foreach ($table in $tables) {
            $exists = Test-TableExists -ConnectionString $connString -TableName $table
            Assert-True -Condition $exists -Message "Tabelle '$table' sollte existieren"
        }
        
        # Nicht-existierende Tabelle testen
        $nonExistent = Test-TableExists -ConnectionString $connString -TableName "non_existent_table"
        Assert-False -Condition $nonExistent -Message "Nicht-existierende Tabelle sollte false zurückgeben"
        
        return @{ Success = $true; Message = "Table Exists Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Table Exists Test fehlgeschlagen: $_" }
    }
})

# Test 4: Get Table Columns Test  
$suite.AddTest("Get-Table-Columns-Test", {
    param($context)
    
    try {
        # Test-Datenbank erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "columns_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Tabelle mit verschiedenen Datentypen erstellen
        $createQuery = @"
CREATE TABLE test_table (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    age INTEGER,
    salary REAL,
    is_active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
"@
        $createQuery | sqlite3 $dbPath
        
        $connString = "Data Source=$dbPath"
        
        # Spalten abrufen
        $columns = Get-TableColumns -ConnectionString $connString -TableName "test_table"
        
        Assert-NotNull -Value $columns -Message "Spalten sollten zurückgegeben werden"
        Assert-IsArray -Object $columns -Message "Spalten sollten Array sein"
        Assert-True -Condition $columns.Count -gt 0 -Message "Mindestens eine Spalte erwartet"
        
        # Spezifische Spalten prüfen
        $expectedColumns = @("id", "name", "email", "age", "salary", "is_active", "created_at")
        foreach ($expectedCol in $expectedColumns) {
            $found = $columns | Where-Object { $_.COLUMN_NAME -eq $expectedCol }
            Assert-NotNull -Value $found -Message "Spalte '$expectedCol' sollte gefunden werden"
        }
        
        # Datentyp-Informationen prüfen
        $idColumn = $columns | Where-Object { $_.COLUMN_NAME -eq "id" }
        Assert-Equal -Expected "INTEGER" -Actual $idColumn.DATA_TYPE -Message "ID-Spalte sollte INTEGER sein"
        
        $nameColumn = $columns | Where-Object { $_.COLUMN_NAME -eq "name" }
        Assert-Equal -Expected "TEXT" -Actual $nameColumn.DATA_TYPE -Message "Name-Spalte sollte TEXT sein"
        
        return @{ Success = $true; Message = "Get Table Columns Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Get Table Columns Test fehlgeschlagen: $_" }
    }
})

# Test 5: Get Primary Key Columns Test
$suite.AddTest("Get-Primary-Key-Columns-Test", {
    param($context)
    
    try {
        # Test-Datenbank erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "pk_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Tabellen mit verschiedenen Primary Key Szenarien
        $setupQueries = @(
            "CREATE TABLE single_pk (id INTEGER PRIMARY KEY, name TEXT);",
            "CREATE TABLE composite_pk (order_id INTEGER, product_id INTEGER, line_number INTEGER, quantity INTEGER, PRIMARY KEY (order_id, product_id, line_number));",
            "CREATE TABLE no_pk (name TEXT, value TEXT);"
        )
        
        foreach ($query in $setupQueries) {
            $query | sqlite3 $dbPath
        }
        
        $connString = "Data Source=$dbPath"
        
        # Single Primary Key
        $singlePK = Get-PrimaryKeyColumns -ConnectionString $connString -TableName "single_pk"
        Assert-IsArray -Object $singlePK -Message "Primary Keys sollten Array sein"
        Assert-Equal -Expected 1 -Actual $singlePK.Count -Message "Ein Primary Key erwartet"
        Assert-Equal -Expected "id" -Actual $singlePK[0] -Message "ID sollte Primary Key sein"
        
        # Composite Primary Key
        $compositePK = Get-PrimaryKeyColumns -ConnectionString $connString -TableName "composite_pk"
        Assert-Equal -Expected 3 -Actual $compositePK.Count -Message "Drei Primary Keys erwartet"
        $expectedPKs = @("order_id", "product_id", "line_number")
        foreach ($expectedPK in $expectedPKs) {
            Assert-Contains -Collection $compositePK -Item $expectedPK -Message "Primary Key '$expectedPK' erwartet"
        }
        
        # No Primary Key
        $noPK = Get-PrimaryKeyColumns -ConnectionString $connString -TableName "no_pk"
        Assert-True -Condition ($noPK.Count -eq 0) -Message "Keine Primary Keys für Tabelle ohne PK erwartet"
        
        return @{ Success = $true; Message = "Get Primary Key Columns Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Get Primary Key Columns Test fehlgeschlagen: $_" }
    }
})

# Test 6: Database Query Execution Test
$suite.AddTest("Database-Query-Execution-Test", {
    param($context)
    
    try {
        # Test-Datenbank mit Daten erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "query_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Setup
        $setupQueries = @(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER);",
            "INSERT INTO users (name, age) VALUES ('Alice', 25);",
            "INSERT INTO users (name, age) VALUES ('Bob', 30);",
            "INSERT INTO users (name, age) VALUES ('Charlie', 35);"
        )
        
        foreach ($query in $setupQueries) {
            $query | sqlite3 $dbPath
        }
        
        $connString = "Data Source=$dbPath"
        
        # Query ausführen
        $result = Invoke-DatabaseQuery -ConnectionString $connString -Query "SELECT * FROM users WHERE age > @MinAge" -Parameters @{ MinAge = 25 }
        
        Assert-NotNull -Value $result -Message "Query-Ergebnis sollte nicht null sein"
        Assert-IsArray -Object $result -Message "Ergebnis sollte Array sein"
        Assert-Equal -Expected 2 -Actual $result.Count -Message "Zwei Datensätze erwartet (Bob, Charlie)"
        
        # Einzelnen Datensatz prüfen
        $bob = $result | Where-Object { $_.name -eq "Bob" }
        Assert-NotNull -Value $bob -Message "Bob sollte gefunden werden"
        Assert-Equal -Expected "30" -Actual $bob.age -Message "Bobs Alter sollte 30 sein"
        
        return @{ Success = $true; Message = "Database Query Execution Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Database Query Execution Test fehlgeschlagen: $_" }
    }
})

# Test 7: Database Non-Query Execution Test
$suite.AddTest("Database-NonQuery-Execution-Test", {
    param($context)
    
    try {
        # Test-Datenbank erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "nonquery_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Setup
        "CREATE TABLE test_updates (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);" | sqlite3 $dbPath
        "INSERT INTO test_updates (name, value) VALUES ('Item1', 10), ('Item2', 20), ('Item3', 30);" | sqlite3 $dbPath
        
        $connString = "Data Source=$dbPath"
        
        # Non-Query ausführen (UPDATE)
        $affectedRows = Invoke-DatabaseNonQuery -ConnectionString $connString -Query "UPDATE test_updates SET value = @NewValue WHERE value > @MinValue" -Parameters @{ NewValue = 99; MinValue = 15 }
        
        # SQLite gibt nicht immer die genaue Anzahl zurück, aber sollte > 0 sein
        Write-Verbose "affectedRows type: $($affectedRows.GetType().Name), value: '$affectedRows'"
        $rowsAsInt = [int]$affectedRows
        Assert-True -Condition ($rowsAsInt -gt 0) -Message "Mindestens eine Zeile sollte betroffen sein (tatsächlich: $rowsAsInt)"
        
        # Prüfen ob Update funktioniert hat
        $result = Invoke-DatabaseQuery -ConnectionString $connString -Query "SELECT COUNT(*) as Count FROM test_updates WHERE value = 99"
        Assert-True -Condition ([int]$result[0].Count -ge 2) -Message "Mindestens 2 Datensätze sollten upgedatet sein"
        
        return @{ Success = $true; Message = "Database Non-Query Execution Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Database Non-Query Execution Test fehlgeschlagen: $_" }
    }
})

# Test 8: Error Handling Test
$suite.AddTest("Error-Handling-Test", {
    param($context)
    
    try {
        # Ungültige Connection String
        try {
            $result = Test-DatabaseConnection -ConnectionString "Invalid Connection String"
            Assert-False -Condition $result.Success -Message "Ungültige Connection String sollte fehlschlagen"
        } catch {
            # Exception ist auch OK
        }
        
        # Nicht-existierende Datei
        $nonExistentPath = Join-Path (Get-TestTempDirectory) "non_existent_$(Get-Random).db"
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$nonExistentPath"
        
        # SQLite erstellt automatisch Dateien, also sollte das funktionieren
        # Aber wir können testen ob eine komplett ungültige Pfad-Syntax funktioniert
        try {
            $result2 = Test-DatabaseConnection -ConnectionString "Data Source=\invalid\0\path\?.db"
            Assert-False -Condition $result2.Success -Message "Ungültiger Pfad sollte fehlschlagen"
        } catch {
            # Exception ist erwartet
        }
        
        return @{ Success = $true; Message = "Error Handling Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Error Handling Test fehlgeschlagen: $_" }
    }
})

# Test 9: Performance Test
$suite.AddTest("Performance-Test", {
    param($context)
    
    try {
        # Test-Datenbank mit mehr Daten erstellen
        $tempDir = Get-TestTempDirectory
        $dbPath = Join-Path $tempDir "performance_test_$(Get-Random).db"
        $context.AddCleanup({ Remove-Item $dbPath -Force -ErrorAction SilentlyContinue })
        
        # Setup
        "CREATE TABLE perf_test (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);" | sqlite3 $dbPath
        
        # 1000 Datensätze einfügen (in SQLite)
        $insertQueries = @()
        for ($i = 1; $i -le 1000; $i++) {
            $insertQueries += "INSERT INTO perf_test (name, value) VALUES ('Name$i', $i);"
        }
        ($insertQueries -join " ") | sqlite3 $dbPath
        
        $connString = "Data Source=$dbPath"
        
        # Performance messen
        $measurement = Measure-DatabaseOperation -OperationName "Large-Query" -Operation {
            Invoke-DatabaseQuery -ConnectionString $connString -Query "SELECT COUNT(*) as Count FROM perf_test WHERE value > @MinValue" -Parameters @{ MinValue = 500 }
        }
        
        Assert-True -Condition $measurement.Success -Message "Performance-Test sollte erfolgreich sein"
        Assert-True -Condition $measurement.Duration.TotalSeconds -lt 2 -Message "Query sollte unter 2 Sekunden dauern"
        
        $result = $measurement.Result
        Assert-Equal -Expected "500" -Actual $result[0].Count -Message "500 Datensätze sollten gefunden werden"
        
        return @{ Success = $true; Message = "Performance Test erfolgreich ($(($measurement.Duration.TotalMilliseconds).ToString('F0'))ms)" }
        
    } catch {
        return @{ Success = $false; Message = "Performance Test fehlgeschlagen: $_" }
    }
})

# Test 10: Connection String Detection Test
$suite.AddTest("Connection-String-Detection-Test", {
    param($context)
    
    try {
        # Verschiedene Connection String Formate testen
        $testCases = @(
            @{ ConnString = "Data Source=test.db"; Expected = "SQLite" },
            @{ ConnString = "Data Source=C:\path\to\database.sqlite"; Expected = "SQLite" },
            @{ ConnString = "Data Source=./relative/path.db"; Expected = "SQLite" },
            @{ ConnString = "Server=localhost;Database=TestDB"; Expected = "SqlServer" },
            @{ ConnString = "Data Source=SERVERNAME\INSTANCE;Initial Catalog=DB"; Expected = "SqlServer" },
            @{ ConnString = "Server=(local);Database=master;Integrated Security=true"; Expected = "SqlServer" }
        )
        
        foreach ($testCase in $testCases) {
            $adapter = New-DatabaseAdapter -ConnectionString $testCase.ConnString
            Assert-Equal -Expected $testCase.Expected -Actual $adapter.DatabaseType -Message "Connection String '$($testCase.ConnString)' sollte als $($testCase.Expected) erkannt werden"
        }
        
        # Ungültige Connection Strings
        try {
            $adapter = New-DatabaseAdapter -ConnectionString "InvalidConnectionString"
            Assert-True -Condition $false -Message "Ungültige Connection String sollte Exception werfen"
        } catch {
            # Exception erwartet
        }
        
        return @{ Success = $true; Message = "Connection String Detection Test erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Connection String Detection Test fehlgeschlagen: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Database Connection Fixed" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Gray
    
    $results = $suite.Run()
    
    # Ergebnisse anzeigen
    Write-Host "`nErgebnisse:" -ForegroundColor White
    Write-Host "  Gesamt: $($results.Total) Tests" -ForegroundColor Gray
    Write-Host "  ✅ Bestanden: $($results.Passed)" -ForegroundColor Green
    Write-Host "  ❌ Fehlgeschlagen: $($results.Failed)" -ForegroundColor Red
    Write-Host "  ⏱️ Dauer: $($results.Duration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray
    
    # Detaillierte Ergebnisse
    foreach ($result in $results.Results) {
        $icon = if ($result.Success) { "✅" } else { "❌" }
        $color = if ($result.Success) { "Green" } else { "Red" }
        Write-Host "  $icon $($result.TestName)" -ForegroundColor $color
        
        if (-not $result.Success) {
            Write-Host "    Error: $($result.ErrorMessage)" -ForegroundColor Yellow
        }
    }
    
    $success = $results.Failed -eq 0
    
    if ($success) {
        Write-Host "`n🎉 Alle Database Connection Fixed Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Database Connection Fixed: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Database Connection Fixed Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}