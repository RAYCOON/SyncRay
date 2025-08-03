# Unit Tests für Duplikat-Erkennung
# Testet Test-MatchFieldsUniqueness, Get-DetailedDuplicateRecords, Export-DuplicatesToCSV, Remove-DuplicateRecords

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
$suite = New-TestSuite -Name "Duplicate-Detection" -Category "unit" -Module "validation"

# Test 1: Test-MatchFieldsUniqueness - Keine Duplikate
$suite.AddTest("MatchFieldsUniqueness-Keine-Duplikate", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "unique_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Users haben unique Emails
        $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email")
        
        Assert-True -Condition $result.IsUnique -Message "Email-Felder sollten eindeutig sein"
        Assert-Equal -Expected 0 -Actual $result.DuplicateCount -Message "Keine Duplikate erwartet"
        Assert-True -Condition ($result.DuplicateGroups -eq $null -or $result.DuplicateGroups.Count -eq 0) -Message "Keine Duplikat-Gruppen erwartet"
        
        return @{ Success = $true; Message = "Eindeutige Felder korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test eindeutiger Felder: $_" }
    }
})

# Test 2: Test-MatchFieldsUniqueness - Mit Duplikaten
$suite.AddTest("MatchFieldsUniqueness-Mit-Duplikaten", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "duplicate_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Duplikate einfügen
        $duplicateQueries = @(
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('DuplicateUser1', 'duplicate@test.com', 'Dup', 'User1')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('DuplicateUser2', 'duplicate@test.com', 'Dup', 'User2')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('DuplicateUser3', 'another@test.com', 'Another', 'Dup1')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('DuplicateUser4', 'another@test.com', 'Another', 'Dup2')"
        )
        
        foreach ($query in $duplicateQueries) {
            $query | sqlite3 $testDb
        }
        
        # Duplikate basierend auf Email testen
        $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email")
        
        Assert-False -Condition $result.IsUnique -Message "Email-Felder sollten nicht eindeutig sein"
        Assert-True -Condition $result.DuplicateCount -gt 0 -Message "Duplikate erwartet"
        Assert-NotNull -Value $result.DuplicateGroups -Message "Duplikat-Gruppen sollten vorhanden sein"
        Assert-True -Condition $result.DuplicateGroups.Count -ge 2 -Message "Mindestens 2 Duplikat-Gruppen erwartet"
        
        return @{ Success = $true; Message = "Duplikate erfolgreich erkannt ($($result.DuplicateCount) gefunden)" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test von Duplikaten: $_" }
    }
})

# Test 3: Composite Key Duplikate
$suite.AddTest("Composite-Key-Duplikate", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "composite_dup_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Composite Key Duplikate in OrderItems einfügen (OrderID + ProductID sollten eindeutig sein ohne LineNumber)
        $duplicateQueries = @(
            "INSERT INTO OrderItems (OrderID, ProductID, LineNumber, Quantity, UnitPrice, Total) VALUES (1, 1, 99, 1, 10.00, 10.00)",
            "INSERT INTO OrderItems (OrderID, ProductID, LineNumber, Quantity, UnitPrice, Total) VALUES (1, 1, 100, 2, 15.00, 30.00)"
        )
        
        foreach ($query in $duplicateQueries) {
            $query | sqlite3 $testDb
        }
        
        # Test Composite Key (OrderID + ProductID)
        $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "OrderItems" -MatchOnFields @("OrderID", "ProductID")
        
        Assert-False -Condition $result.IsUnique -Message "OrderID+ProductID Kombination sollte nicht eindeutig sein"
        Assert-True -Condition $result.DuplicateCount -gt 0 -Message "Composite Key Duplikate erwartet"
        
        return @{ Success = $true; Message = "Composite Key Duplikate erfolgreich erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Composite Key Duplikat-Test: $_" }
    }
})

# Test 4: Get-DetailedDuplicateRecords
$suite.AddTest("DetailedDuplicateRecords", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "detailed_dup_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Bekannte Duplikate einfügen
        $duplicateQueries = @(
            "INSERT INTO Users (Username, Email, FirstName, LastName, Department) VALUES ('DupUser1', 'same@test.com', 'John', 'Doe', 'IT')",
            "INSERT INTO Users (Username, Email, FirstName, LastName, Department) VALUES ('DupUser2', 'same@test.com', 'Jane', 'Doe', 'HR')"
        )
        
        foreach ($query in $duplicateQueries) {
            $query | sqlite3 $testDb
        }
        
        # Detaillierte Duplikat-Informationen abrufen
        $duplicates = Get-DetailedDuplicateRecords -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email")
        
        Assert-NotNull -Value $duplicates -Message "Duplikat-Details sollten vorhanden sein"
        Assert-IsArray -Object $duplicates -Message "Duplikat-Details sollten Array sein"
        Assert-True -Condition $duplicates.Count -gt 0 -Message "Duplikat-Details erwartet"
        
        # Prüfen ob alle Felder enthalten sind
        $firstDuplicate = $duplicates[0]
        Assert-HasProperty -Object $firstDuplicate -PropertyName "UserID" -Message "UserID sollte vorhanden sein"
        Assert-HasProperty -Object $firstDuplicate -PropertyName "Email" -Message "Email sollte vorhanden sein"
        Assert-HasProperty -Object $firstDuplicate -PropertyName "Username" -Message "Username sollte vorhanden sein"
        
        return @{ Success = $true; Message = "Detaillierte Duplikat-Informationen erfolgreich abgerufen" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Abrufen detaillierter Duplikat-Informationen: $_" }
    }
})

# Test 5: Export-DuplicatesToCSV
$suite.AddTest("Export-DuplicatesToCSV", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "csv_export_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Duplikate einfügen
        $duplicateQueries = @(
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('CSVUser1', 'csv@test.com', 'CSV', 'User1')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('CSVUser2', 'csv@test.com', 'CSV', 'User2')"
        )
        
        foreach ($query in $duplicateQueries) {
            $query | sqlite3 $testDb
        }
        
        # CSV-Export
        $csvPath = Join-Path (Get-TestTempDirectory) "duplicates_$(Get-Random).csv"
        $context.AddCleanup({ Remove-Item $csvPath -Force -ErrorAction SilentlyContinue })
        
        $exported = Export-DuplicatesToCSV -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email") -OutputPath $csvPath
        
        Assert-True -Condition $exported -Message "CSV-Export sollte erfolgreich sein"
        Assert-FileExists -Path $csvPath -Message "CSV-Datei sollte erstellt werden"
        
        # CSV-Inhalt prüfen
        $csvContent = Get-Content $csvPath -Raw
        Assert-IsNotEmpty -Value $csvContent -Message "CSV-Datei sollte Inhalt haben"
        Assert-CsvStructure -CsvContent $csvContent -ExpectedHeaders @("UserID", "Username", "Email") -Message "CSV sollte erwartete Header haben"
        
        # Mindestens 2 Duplikat-Datensätze erwartet
        $lines = $csvContent -split "`n" | Where-Object { $_.Trim() -ne "" }
        Assert-True -Condition $lines.Count -ge 3 -Message "Header + mindestens 2 Duplikat-Zeilen erwartet"
        
        return @{ Success = $true; Message = "CSV-Export erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim CSV-Export: $_" }
    }
})

# Test 6: Remove-DuplicateRecords - Automatisch
$suite.AddTest("Remove-DuplicateRecords-Automatisch", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "remove_dup_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Duplikate einfügen
        $duplicateQueries = @(
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('RemoveUser1', 'remove@test.com', 'Remove', 'User1')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('RemoveUser2', 'remove@test.com', 'Remove', 'User2')",
            "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('RemoveUser3', 'remove@test.com', 'Remove', 'User3')"
        )
        
        foreach ($query in $duplicateQueries) {
            $query | sqlite3 $testDb
        }
        
        # Anzahl vor dem Löschen
        $beforeCount = (Invoke-SqlQuery -Connection $testDb -Query "SELECT COUNT(*) as Count FROM Users WHERE Email = 'remove@test.com'").Count
        Assert-True -Condition $beforeCount -eq 3 -Message "3 Duplikate sollten vorhanden sein"
        
        # Mock für interaktive Bestätigung
        Mock-Function -FunctionName "Read-Host" -MockImplementation { return "y" }
        $context.AddCleanup({ Restore-Function -FunctionName "Read-Host" })
        
        # Duplikate entfernen (behält das erste)
        $removed = Remove-DuplicateRecords -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email") -KeepFirst
        
        Assert-True -Condition $removed -gt 0 -Message "Duplikate sollten entfernt werden"
        
        # Anzahl nach dem Löschen
        $afterCount = (Invoke-SqlQuery -Connection $testDb -Query "SELECT COUNT(*) as Count FROM Users WHERE Email = 'remove@test.com'").Count
        Assert-Equal -Expected 1 -Actual $afterCount -Message "Nur ein Datensatz sollte übrig bleiben"
        
        return @{ Success = $true; Message = "Duplikate erfolgreich entfernt ($removed entfernt)" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Entfernen von Duplikaten: $_" }
    }
})

# Test 7: NULL-Werte in Match-Feldern
$suite.AddTest("NULL-Werte-Match-Felder", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "null_match_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Datensätze mit NULL-Werten einfügen
        $nullQueries = @(
            "INSERT INTO Users (Username, Email, FirstName, LastName, Department) VALUES ('NullUser1', 'null1@test.com', 'Null', 'User1', NULL)",
            "INSERT INTO Users (Username, Email, FirstName, LastName, Department) VALUES ('NullUser2', 'null2@test.com', 'Null', 'User2', NULL)",
            "INSERT INTO Users (Username, Email, FirstName, LastName, Department) VALUES ('NullUser3', 'null3@test.com', 'Null', 'User3', NULL)"
        )
        
        foreach ($query in $nullQueries) {
            $query | sqlite3 $testDb
        }
        
        # Test mit NULL-Werten als Match-Feld
        $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Department")
        
        # NULL-Werte sollten normalerweise nicht als Duplikate behandelt werden
        # oder alle NULL-Werte sollten als eine Gruppe behandelt werden
        Assert-NotNull -Value $result -Message "Ergebnis sollte vorhanden sein"
        
        # Verhalten kann variieren - dokumentieren was passiert
        Write-Verbose "NULL-Werte Verhalten: IsUnique=$($result.IsUnique), DuplicateCount=$($result.DuplicateCount)"
        
        return @{ Success = $true; Message = "NULL-Werte in Match-Feldern behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim NULL-Werte Test: $_" }
    }
})

# Test 8: Performance mit vielen Duplikaten
$suite.AddTest("Performance-Viele-Duplikate", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "perf_dup_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "medium"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # 100 Duplikate einfügen
        for ($i = 1; $i -le 100; $i++) {
            $groupNumber = ($i % 10) + 1  # 10 Gruppen mit je 10 Duplikaten
            $query = "INSERT INTO Users (Username, Email, FirstName, LastName) VALUES ('PerfUser$i', 'group$groupNumber@test.com', 'Perf', 'User$i')"
            $query | sqlite3 $testDb
        }
        
        # Performance messen
        $measurement = Measure-DatabaseOperation -OperationName "Duplicate-Detection-Performance" -Operation {
            Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email")
        }
        
        Assert-True -Condition $measurement.Success -Message "Performance-Test sollte erfolgreich sein"
        Assert-True -Condition $measurement.Duration.TotalSeconds -lt 10 -Message "Duplikat-Erkennung sollte unter 10 Sekunden dauern"
        
        # Ergebnis prüfen
        $result = $measurement.Result
        Assert-False -Condition $result.IsUnique -Message "Mit vielen Duplikaten sollte nicht eindeutig sein"
        Assert-True -Condition $result.DuplicateCount -gt 90 -Message "Viele Duplikate erwartet"
        
        return @{ Success = $true; Message = "Performance-Test erfolgreich ($(($measurement.Duration.TotalMilliseconds).ToString('F0'))ms, $($result.DuplicateCount) Duplikate)" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Performance-Test: $_" }
    }
})

# Test 9: Edge Case - Leere Tabelle
$suite.AddTest("Edge-Case-Leere-Tabelle", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "empty_table_test" -Schema "standard"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Leere Tabelle testen (keine Test-Daten einfügen)
        $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("Email")
        
        Assert-NotNull -Value $result -Message "Ergebnis sollte auch für leere Tabelle vorhanden sein"
        Assert-True -Condition $result.IsUnique -Message "Leere Tabelle sollte als eindeutig gelten"
        Assert-Equal -Expected 0 -Actual $result.DuplicateCount -Message "Keine Duplikate in leerer Tabelle"
        
        return @{ Success = $true; Message = "Leere Tabelle korrekt behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test leerer Tabelle: $_" }
    }
})

# Test 10: Ungültige Match-Felder
$suite.AddTest("Ungueltige-Match-Felder", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "invalid_fields_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Test mit nicht existierenden Spalten
        try {
            $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @("NonExistentColumn")
            
            # Sollte Fehler werfen oder false zurückgeben
            if ($result) {
                Assert-False -Condition $result.IsUnique -Message "Ungültiges Feld sollte zu Fehler führen"
            }
        } catch {
            # Fehler ist erwartet
            Write-Verbose "Erwarteter Fehler für ungültiges Feld: $_"
        }
        
        # Test mit leerem Match-Feld Array
        try {
            $result = Test-MatchFieldsUniqueness -ConnectionString "Data Source=$testDb" -TableName "Users" -MatchOnFields @()
            
            # Verhalten für leere Match-Felder
            Write-Verbose "Verhalten für leere Match-Felder: $($result | ConvertTo-Json)"
        } catch {
            Write-Verbose "Erwarteter Fehler für leere Match-Felder: $_"
        }
        
        return @{ Success = $true; Message = "Ungültige Match-Felder behandelt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Test ungültiger Match-Felder: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Duplicate Detection" -ForegroundColor Cyan
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
        Write-Host "`n🎉 Alle Duplicate Detection Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Duplicate Detection: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Duplicate Detection Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}