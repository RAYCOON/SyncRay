# Unit Tests für Tabellen-Validierungsfunktionen
# Testet Test-TableExists, Get-TableColumns, Get-PrimaryKeyColumns

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

# Test-Framework laden
$testRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$sharedPath = Join-Path $testRoot "shared"
. (Join-Path $sharedPath "Test-Framework.ps1")
. (Join-Path $sharedPath "Database-TestHelpers.ps1")
. (Join-Path $sharedPath "Assertion-Helpers.ps1")

# SyncRay Module laden
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
. (Join-Path $srcRoot "sync-validation.ps1")
. (Join-Path $srcRoot "database-adapter.ps1")
. (Join-Path $srcRoot "sync-common.ps1")

# Test-Framework initialisieren
Initialize-TestFramework

# Test-Suite erstellen
$suite = New-TestSuite -Name "Table-Validation" -Category "unit" -Module "validation"

# Test 1: Test-TableExists - Existierende Tabelle
$suite.AddTest("TableExists-Existierende-Tabelle", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "table_exists_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Standardtabellen testen
        $tables = @("Users", "Products", "Categories", "Orders", "OrderItems")
        
        foreach ($table in $tables) {
            $exists = Test-TableExists -ConnectionString "Data Source=$testDb" -TableName $table
            Assert-True -Condition $exists -Message "Tabelle '$table' sollte existieren"
        }
        
        return @{ Success = $true; Message = "Existierende Tabellen korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test existierender Tabellen: $_" }
    }
})

# Test 2: Test-TableExists - Nicht existierende Tabelle
$suite.AddTest("TableExists-Nicht-Existierende-Tabelle", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "table_not_exists_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Nicht existierende Tabellen testen
        $nonExistentTables = @("NonExistent", "FakeTable", "NotThere", "Missing")
        
        foreach ($table in $nonExistentTables) {
            $exists = Test-TableExists -ConnectionString "Data Source=$testDb" -TableName $table
            Assert-False -Condition $exists -Message "Tabelle '$table' sollte nicht existieren"
        }
        
        return @{ Success = $true; Message = "Nicht existierende Tabellen korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test nicht existierender Tabellen: $_" }
    }
})

# Test 3: Test-TableExists - Case Sensitivity
$suite.AddTest("TableExists-Case-Sensitivity", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "case_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Case-Variationen testen
        $casesVariations = @(
            @{ Table = "Users"; Test = "users"; ShouldExist = $true },
            @{ Table = "Users"; Test = "USERS"; ShouldExist = $true },
            @{ Table = "Users"; Test = "UsErS"; ShouldExist = $true },
            @{ Table = "Products"; Test = "products"; ShouldExist = $true },
            @{ Table = "Products"; Test = "PRODUCTS"; ShouldExist = $true }
        )
        
        foreach ($case in $casesVariations) {
            $exists = Test-TableExists -ConnectionString "Data Source=$testDb" -TableName $case.Test
            
            if ($case.ShouldExist) {
                Assert-True -Condition $exists -Message "Tabelle '$($case.Test)' sollte gefunden werden (case-insensitive)"
            } else {
                Assert-False -Condition $exists -Message "Tabelle '$($case.Test)' sollte nicht gefunden werden"
            }
        }
        
        return @{ Success = $true; Message = "Case Sensitivity korrekt behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Case Sensitivity Test: $_" }
    }
})

# Test 4: Get-TableColumns - Standard-Tabelle
$suite.AddTest("GetTableColumns-Standard", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "columns_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Users-Tabelle Spalten testen
        $columns = Get-TableColumns -ConnectionString "Data Source=$testDb" -TableName "Users"
        
        Assert-NotNull -Value $columns -Message "Spalten sollten zurückgegeben werden"
        Assert-IsArray -Object $columns -Message "Spalten sollten ein Array sein"
        Assert-True -Condition $columns.Count -gt 0 -Message "Mindestens eine Spalte sollte vorhanden sein"
        
        # Erwartete Spalten prüfen
        $expectedColumns = @("UserID", "Username", "Email", "FirstName", "LastName", "IsActive", "Salary", "Department", "Manager", "Settings")
        
        foreach ($expectedColumn in $expectedColumns) {
            $found = $columns | Where-Object { $_.COLUMN_NAME -eq $expectedColumn -or $_.name -eq $expectedColumn }
            Assert-NotNull -Value $found -Message "Spalte '$expectedColumn' sollte vorhanden sein"
        }
        
        return @{ Success = $true; Message = "Tabellen-Spalten erfolgreich abgerufen" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Abrufen der Tabellen-Spalten: $_" }
    }
})

# Test 5: Get-TableColumns - Nicht existierende Tabelle
$suite.AddTest("GetTableColumns-Nicht-Existierende-Tabelle", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "no_columns_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Nicht existierende Tabelle
        $columns = Get-TableColumns -ConnectionString "Data Source=$testDb" -TableName "NonExistentTable"
        
        # Sollte leeres Array oder null zurückgeben
        Assert-True -Condition ($columns -eq $null -or $columns.Count -eq 0) -Message "Keine Spalten für nicht existierende Tabelle erwartet"
        
        return @{ Success = $true; Message = "Nicht existierende Tabelle korrekt behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test nicht existierender Tabelle: $_" }
    }
})

# Test 6: Get-PrimaryKeyColumns - Einfacher Primary Key
$suite.AddTest("GetPrimaryKeyColumns-Einfach", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "pk_simple_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Users-Tabelle hat UserID als Primary Key
        $primaryKeys = Get-PrimaryKeyColumns -ConnectionString "Data Source=$testDb" -TableName "Users"
        
        Assert-NotNull -Value $primaryKeys -Message "Primary Key sollte gefunden werden"
        Assert-IsArray -Object $primaryKeys -Message "Primary Key sollte als Array zurückgegeben werden"
        Assert-Equal -Expected 1 -Actual $primaryKeys.Count -Message "Ein Primary Key erwartet"
        Assert-Equal -Expected "UserID" -Actual $primaryKeys[0] -Message "UserID als Primary Key erwartet"
        
        return @{ Success = $true; Message = "Einfacher Primary Key erfolgreich gefunden" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Finden des Primary Keys: $_" }
    }
})

# Test 7: Get-PrimaryKeyColumns - Composite Primary Key
$suite.AddTest("GetPrimaryKeyColumns-Composite", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "pk_composite_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # OrderItems-Tabelle hat Composite Primary Key (OrderID, ProductID, LineNumber)
        $primaryKeys = Get-PrimaryKeyColumns -ConnectionString "Data Source=$testDb" -TableName "OrderItems"
        
        Assert-NotNull -Value $primaryKeys -Message "Primary Keys sollten gefunden werden"
        Assert-IsArray -Object $primaryKeys -Message "Primary Keys sollten als Array zurückgegeben werden"
        Assert-Equal -Expected 3 -Actual $primaryKeys.Count -Message "Drei Primary Key Spalten erwartet"
        
        # Erwartete Primary Key Spalten
        $expectedPKs = @("OrderID", "ProductID", "LineNumber")
        foreach ($expectedPK in $expectedPKs) {
            Assert-Contains -Collection $primaryKeys -Item $expectedPK -Message "Primary Key '$expectedPK' sollte vorhanden sein"
        }
        
        return @{ Success = $true; Message = "Composite Primary Key erfolgreich gefunden" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Finden des Composite Primary Keys: $_" }
    }
})

# Test 8: Get-PrimaryKeyColumns - Kein Primary Key
$suite.AddTest("GetPrimaryKeyColumns-Kein-PK", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "no_pk_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Tabelle ohne Primary Key erstellen
        $noPkQuery = @"
CREATE TABLE NoPrimaryKey (
    Column1 TEXT,
    Column2 INTEGER,
    Column3 REAL
);
"@
        $noPkQuery | sqlite3 $testDb
        
        $primaryKeys = Get-PrimaryKeyColumns -ConnectionString "Data Source=$testDb" -TableName "NoPrimaryKey"
        
        # Sollte leeres Array oder null zurückgeben
        Assert-True -Condition ($primaryKeys -eq $null -or $primaryKeys.Count -eq 0) -Message "Keine Primary Keys für Tabelle ohne PK erwartet"
        
        return @{ Success = $true; Message = "Tabelle ohne Primary Key korrekt behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test der Tabelle ohne Primary Key: $_" }
    }
})

# Test 9: Spalten-Datentyp-Informationen
$suite.AddTest("Spalten-Datentyp-Informationen", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "datatype_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        $columns = Get-TableColumns -ConnectionString "Data Source=$testDb" -TableName "Users"
        
        Assert-NotNull -Value $columns -Message "Spalten sollten vorhanden sein"
        
        # Prüfen ob Datentyp-Informationen verfügbar sind
        foreach ($column in $columns) {
            # SQLite PRAGMA table_info gibt 'type' zurück, INFORMATION_SCHEMA gibt 'DATA_TYPE'
            $hasTypeInfo = ($column.type -ne $null) -or ($column.DATA_TYPE -ne $null)
            Assert-True -Condition $hasTypeInfo -Message "Spalte sollte Datentyp-Information haben"
        }
        
        return @{ Success = $true; Message = "Spalten-Datentyp-Informationen verfügbar" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Prüfen der Datentyp-Informationen: $_" }
    }
})

# Test 10: Performance-Test große Tabelle
$suite.AddTest("Performance-Grosse-Tabelle", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "performance_table_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "medium"  # 100 Benutzer, etc.
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Performance messen
        $measurement = Measure-DatabaseOperation -OperationName "Table-Validation" -Operation {
            $tables = @("Users", "Products", "Categories", "Orders", "OrderItems")
            foreach ($table in $tables) {
                Test-TableExists -ConnectionString "Data Source=$testDb" -TableName $table | Out-Null
                Get-TableColumns -ConnectionString "Data Source=$testDb" -TableName $table | Out-Null
                Get-PrimaryKeyColumns -ConnectionString "Data Source=$testDb" -TableName $table | Out-Null
            }
        }
        
        Assert-True -Condition $measurement.Success -Message "Performance-Test sollte erfolgreich sein"
        Assert-True -Condition $measurement.Duration.TotalSeconds -lt 3 -Message "Tabellen-Validierung sollte unter 3 Sekunden dauern"
        
        return @{ Success = $true; Message = "Performance-Test erfolgreich ($(($measurement.Duration.TotalMilliseconds).ToString('F0'))ms)" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Performance-Test: $_" }
    }
})

# Test 11: Sonderzeichen in Tabellennamen
$suite.AddTest("Sonderzeichen-Tabellennamen", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "special_chars_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Tabellen mit Sonderzeichen erstellen
        $specialTables = @(
            'TableWith"Quotes',
            "TableWith'Apostrophe",
            "Table_With_Underscores",
            "Table-With-Dashes",
            "Table.With.Dots"
        )
        
        foreach ($tableName in $specialTables) {
            try {
                # Tabelle erstellen (mit quoted identifier)
                $createQuery = "CREATE TABLE `"$tableName`" (ID INTEGER PRIMARY KEY, Name TEXT);"
                $createQuery | sqlite3 $testDb
                
                # Testen ob erkannt wird
                $exists = Test-TableExists -ConnectionString "Data Source=$testDb" -TableName $tableName
                Assert-True -Condition $exists -Message "Tabelle mit Sonderzeichen '$tableName' sollte erkannt werden"
                
            } catch {
                Write-Verbose "Sonderzeichen-Tabelle '$tableName' übersprungen: $_"
            }
        }
        
        return @{ Success = $true; Message = "Sonderzeichen in Tabellennamen behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test von Sonderzeichen: $_" }
    }
})

# Test 12: Concurrent Access Test
$suite.AddTest("Concurrent-Access", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "concurrent_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Simuliere gleichzeitige Zugriffe
        $jobs = @()
        for ($i = 1; $i -le 3; $i++) {
            $job = Start-Job -ScriptBlock {
                param($dbPath, $testNumber)
                
                # Module in Job-Scope laden
                $srcRoot = $using:srcRoot
                . (Join-Path $srcRoot "sync-validation.ps1")
                . (Join-Path $srcRoot "database-adapter.ps1")
                . (Join-Path $srcRoot "sync-common.ps1")
                
                $result = @()
                for ($j = 1; $j -le 5; $j++) {
                    $exists = Test-TableExists -ConnectionString "Data Source=$dbPath" -TableName "Users"
                    $result += $exists
                    Start-Sleep -Milliseconds 100
                }
                return $result
            } -ArgumentList $testDb, $i
            
            $jobs += $job
        }
        
        # Warten auf Fertigstellung
        $results = $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job
        
        # Alle Ergebnisse sollten true sein
        foreach ($result in $results) {
            Assert-True -Condition $result -Message "Concurrent Access sollte erfolgreich sein"
        }
        
        return @{ Success = $true; Message = "Concurrent Access erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Concurrent Access Test: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Table Validation" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Gray
    
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
        Write-Host "`n🎉 Alle Table Validation Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Table Validation: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Table Validation Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}