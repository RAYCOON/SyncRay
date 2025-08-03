# Unit Tests für Test-DatabaseConnection Funktion
# Testet alle Aspekte der Datenbankverbindung-Validierung

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
$suite = New-TestSuite -Name "Test-DatabaseConnection" -Category "unit" -Module "validation"

# Test 1: Erfolgreiche SQLite-Verbindung
$suite.AddTest("SQLite-Verbindung-Erfolgreich", {
    param($context)
    
    # Test-Datenbank erstellen
    $testDb = New-TestDatabase -DatabaseName "connection_test" -Schema "minimal"
    $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
    
    try {
        # Test-DatabaseConnection aufrufen
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$testDb"
        
        Assert-True -Condition $result.Success -Message "Verbindung sollte erfolgreich sein"
        Assert-Equal -Expected "Connection successful" -Actual $result.Message -Message "Success-Message erwartet"
        Assert-NotNull -Value $result.DatabaseType -Message "DatabaseType sollte gesetzt sein"
        
        return @{ Success = $true; Message = "SQLite-Verbindung erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen der SQLite-Verbindung: $_" }
    }
})

# Test 2: Fehlgeschlagene Verbindung - Datei nicht vorhanden
$suite.AddTest("SQLite-Verbindung-Datei-Nicht-Vorhanden", {
    param($context)
    
    try {
        $nonExistentPath = Join-Path (Get-TestTempDirectory) "non_existent_$(Get-Random).db"
        
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$nonExistentPath"
        
        Assert-False -Condition $result.Success -Message "Verbindung sollte fehlschlagen"
        Assert-Match -String $result.Message -Pattern "no such file|cannot open|file not found" -Message "Fehlermeldung sollte Datei-Problem erwähnen"
        
        return @{ Success = $true; Message = "Fehlgeschlagene Verbindung korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen der fehlgeschlagenen Verbindung: $_" }
    }
})

# Test 3: Ungültige Connection String
$suite.AddTest("Ungueltige-ConnectionString", {
    param($context)
    
    try {
        $invalidConnectionStrings = @(
            "",
            "Invalid Connection String",
            "Data Source=",
            "Server=;Database=;"
        )
        
        foreach ($connStr in $invalidConnectionStrings) {
            $result = Test-DatabaseConnection -ConnectionString $connStr
            
            Assert-False -Condition $result.Success -Message "Ungültige Connection String '$connStr' sollte fehlschlagen"
        }
        
        return @{ Success = $true; Message = "Ungültige Connection Strings korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen ungültiger Connection Strings: $_" }
    }
})

# Test 4: Berechtigungstest - Read/Write
$suite.AddTest("Berechtigungen-Test", {
    param($context)
    
    try {
        # Test-Datenbank mit Daten erstellen
        $testDb = New-TestDatabase -DatabaseName "permissions_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$testDb"
        
        Assert-True -Condition $result.Success -Message "Verbindung sollte erfolgreich sein"
        Assert-HasProperty -Object $result -PropertyName "Permissions" -Message "Permissions-Eigenschaft sollte vorhanden sein"
        
        # Berechtigungen prüfen
        if ($result.Permissions) {
            Assert-True -Condition $result.Permissions.CanRead -Message "Read-Berechtigung sollte vorhanden sein"
            Assert-True -Condition $result.Permissions.CanWrite -Message "Write-Berechtigung sollte vorhanden sein"
        }
        
        return @{ Success = $true; Message = "Berechtigungen erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen der Berechtigungen: $_" }
    }
})

# Test 5: Datenbank-Informationen abrufen
$suite.AddTest("Datenbank-Informationen", {
    param($context)
    
    try {
        # Test-Datenbank mit Standardschema erstellen
        $testDb = New-TestDatabase -DatabaseName "info_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "small"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$testDb"
        
        Assert-True -Condition $result.Success -Message "Verbindung sollte erfolgreich sein"
        Assert-HasProperty -Object $result -PropertyName "DatabaseInfo" -Message "DatabaseInfo sollte vorhanden sein"
        
        # Datenbank-Informationen prüfen
        if ($result.DatabaseInfo) {
            Assert-HasProperty -Object $result.DatabaseInfo -PropertyName "Version" -Message "Version-Information sollte vorhanden sein"
            Assert-HasProperty -Object $result.DatabaseInfo -PropertyName "TableCount" -Message "TableCount sollte vorhanden sein"
            
            # Standard-Schema hat 5 Tabellen
            Assert-InRange -Value $result.DatabaseInfo.TableCount -MinValue 5 -MaxValue 10 -Message "TableCount sollte im erwarteten Bereich sein"
        }
        
        return @{ Success = $true; Message = "Datenbank-Informationen erfolgreich abgerufen" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Abrufen der Datenbank-Informationen: $_" }
    }
})

# Test 6: Connection-Timeout Test
$suite.AddTest("Connection-Timeout", {
    param($context)
    
    try {
        # Mock für zeitaufwändige Verbindung
        Mock-Function -FunctionName "sqlite3" -MockImplementation {
            Start-Sleep -Seconds 2
            return "Error: timeout"
        }
        $context.AddCleanup({ Restore-Function -FunctionName "sqlite3" })
        
        $testDb = Join-Path (Get-TestTempDirectory) "timeout_test.db"
        
        # Mit sehr kurzem Timeout testen
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$testDb" -TimeoutSeconds 1
        
        Assert-False -Condition $result.Success -Message "Verbindung sollte wegen Timeout fehlschlagen"
        Assert-Match -String $result.Message -Pattern "timeout|time.*out" -Message "Timeout-Fehlermeldung erwartet"
        
        return @{ Success = $true; Message = "Connection-Timeout erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen des Connection-Timeouts: $_" }
    }
})

# Test 7: Verschiedene SQLite-Formate
$suite.AddTest("SQLite-Formate", {
    param($context)
    
    try {
        $formats = @(
            @{ Name = "Standard"; Extension = ".db" },
            @{ Name = "SQLite3"; Extension = ".sqlite3" },
            @{ Name = "SQLite"; Extension = ".sqlite" }
        )
        
        foreach ($format in $formats) {
            $testDb = New-TestDatabase -DatabaseName "format_test_$($format.Name)" -Schema "minimal"
            $newPath = $testDb -replace '\.db$', $format.Extension
            Move-Item $testDb $newPath
            $context.AddCleanup({ Remove-TestDatabase -DatabasePath $newPath })
            
            $result = Test-DatabaseConnection -ConnectionString "Data Source=$newPath"
            
            Assert-True -Condition $result.Success -Message "$($format.Name)-Format sollte funktionieren"
        }
        
        return @{ Success = $true; Message = "Verschiedene SQLite-Formate erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen verschiedener SQLite-Formate: $_" }
    }
})

# Test 8: Error-Handling bei korrupter Datenbank
$suite.AddTest("Korrupte-Datenbank", {
    param($context)
    
    try {
        # "Korrupte" Datei erstellen (einfach eine Textdatei mit .db Extension)
        $corruptDb = Join-Path (Get-TestTempDirectory) "corrupt_$(Get-Random).db"
        "This is not a valid SQLite database file" | Set-Content $corruptDb
        $context.AddCleanup({ Remove-Item $corruptDb -Force -ErrorAction SilentlyContinue })
        
        $result = Test-DatabaseConnection -ConnectionString "Data Source=$corruptDb"
        
        Assert-False -Condition $result.Success -Message "Korrupte Datenbank sollte fehlschlagen"
        Assert-Match -String $result.Message -Pattern "not a database|file is encrypted|corrupted" -Message "Korruptions-Fehlermeldung erwartet"
        
        return @{ Success = $true; Message = "Korrupte Datenbank korrekt erkannt" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Testen korrupter Datenbank: $_" }
    }
})

# Test 9: Connection-String Parsing
$suite.AddTest("ConnectionString-Parsing", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "parsing_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Verschiedene Connection String Formate testen
        $connectionStrings = @(
            "Data Source=$testDb",
            "DataSource=$testDb",
            "Data Source=$testDb;Version=3",
            "Data Source=$testDb;Journal Mode=WAL"
        )
        
        foreach ($connStr in $connectionStrings) {
            $result = Test-DatabaseConnection -ConnectionString $connStr
            
            Assert-True -Condition $result.Success -Message "Connection String '$connStr' sollte funktionieren"
        }
        
        return @{ Success = $true; Message = "Connection String Parsing erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Connection String Parsing: $_" }
    }
})

# Test 10: Performance-Test
$suite.AddTest("Performance-Test", {
    param($context)
    
    try {
        $testDb = New-TestDatabase -DatabaseName "performance_test" -Schema "standard"
        Initialize-TestData -Connection $testDb -DataSet "medium"  # 100 Datensätze
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        # Performance messen
        $measurement = Measure-DatabaseOperation -OperationName "Test-DatabaseConnection" -Operation {
            Test-DatabaseConnection -ConnectionString "Data Source=$testDb"
        }
        
        Assert-True -Condition $measurement.Success -Message "Performance-Test sollte erfolgreich sein"
        Assert-True -Condition $measurement.Duration.TotalSeconds -lt 5 -Message "Verbindungstest sollte unter 5 Sekunden dauern"
        
        return @{ Success = $true; Message = "Performance-Test erfolgreich ($(($measurement.Duration.TotalMilliseconds).ToString('F0'))ms)" }
        
    } catch {
        return @{ Success = $false; Message = "Fehler beim Performance-Test: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Test-DatabaseConnection" -ForegroundColor Cyan
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
        Write-Host "`n🎉 Alle Test-DatabaseConnection Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Test-DatabaseConnection: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Test-DatabaseConnection Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}