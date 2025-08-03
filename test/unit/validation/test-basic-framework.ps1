# Basic Framework Test - Demonstriert das Test-Framework ohne SyncRay-Abhängigkeiten

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

# Test-Framework laden
$testRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$sharedPath = Join-Path $testRoot "shared"
. (Join-Path $sharedPath "Test-Framework.ps1")
. (Join-Path $sharedPath "Database-TestHelpers.ps1")
. (Join-Path $sharedPath "Assertion-Helpers.ps1")

# Test-Framework initialisieren
Initialize-TestFramework

# Test-Suite erstellen
$suite = New-TestSuite -Name "Basic-Framework" -Category "unit" -Module "validation"

# Test 1: Framework-Grundfunktionen
$suite.AddTest("Framework-Assertion-Tests", {
    param($context)
    
    try {
        # Basic Assertions testen
        Assert-True -Condition $true -Message "True sollte true sein"
        Assert-False -Condition $false -Message "False sollte false sein"
        Assert-Equal -Expected 42 -Actual 42 -Message "Zahlen sollten gleich sein"
        Assert-NotEqual -Expected 1 -Actual 2 -Message "Verschiedene Zahlen sollten ungleich sein"
        
        # Array Assertions
        $testArray = @(1, 2, 3)
        Assert-IsArray -Object $testArray -ExpectedLength 3 -Message "Array sollte erkannt werden"
        Assert-Contains -Collection $testArray -Item 2 -Message "Array sollte Element enthalten"
        
        # String Assertions
        Assert-StartsWith -String "TestString" -Prefix "Test" -Message "String sollte mit Präfix beginnen"
        Assert-EndsWith -String "TestString" -Suffix "String" -Message "String sollte mit Suffix enden"
        
        return @{ Success = $true; Message = "Alle Basic Assertions erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Framework Assertion Test fehlgeschlagen: $_" }
    }
})

# Test 2: Mock-Funktionalität
$suite.AddTest("Mock-Funktionalitaet", {
    param($context)
    
    try {
        # Test-Funktion definieren
        function Test-MockFunction { return "Original" }
        
        # Originale Funktion testen
        $original = Test-MockFunction
        Assert-Equal -Expected "Original" -Actual $original -Message "Original-Funktion sollte 'Original' zurückgeben"
        
        # Mock erstellen
        Mock-Function -FunctionName "Test-MockFunction" -MockImplementation { return "Mocked" }
        $context.AddCleanup({ Restore-Function -FunctionName "Test-MockFunction" })
        
        # Mock testen
        $mocked = Test-MockFunction
        Assert-Equal -Expected "Mocked" -Actual $mocked -Message "Mock-Funktion sollte 'Mocked' zurückgeben"
        
        # Call Count prüfen
        $callCount = Get-MockCallCount -FunctionName "Test-MockFunction"
        Assert-Equal -Expected 1 -Actual $callCount -Message "Mock sollte einmal aufgerufen worden sein"
        
        return @{ Success = $true; Message = "Mock-Funktionalität erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Mock-Test fehlgeschlagen: $_" }
    }
})

# Test 3: Datenbank-Helpers (ohne SyncRay)
$suite.AddTest("SQLite-Grundfunktionen", {
    param($context)
    
    try {
        # Test-Datenbank erstellen
        $testDb = New-TestDatabase -DatabaseName "basic_sqlite_test" -Schema "minimal"
        $context.AddCleanup({ Remove-TestDatabase -DatabasePath $testDb })
        
        Assert-FileExists -Path $testDb -Message "Test-Datenbank sollte erstellt werden"
        
        # Einfache Query ausführen
        $result = Invoke-SqlQuery -Connection $testDb -Query "SELECT name FROM sqlite_master WHERE type='table'"
        
        Assert-NotNull -Value $result -Message "Query-Ergebnis sollte nicht null sein"
        Assert-IsArray -Object $result -Message "Ergebnis sollte Array sein"
        
        # Test-Tabelle sollte vorhanden sein
        $hasTestTable = $result | Where-Object { $_.name -eq "TestTable" }
        Assert-NotNull -Value $hasTestTable -Message "TestTable sollte existieren"
        
        return @{ Success = $true; Message = "SQLite-Grundfunktionen erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "SQLite-Test fehlgeschlagen: $_" }
    }
})

# Test 4: Performance-Messung
$suite.AddTest("Performance-Messung", {
    param($context)
    
    try {
        # Performance einer einfachen Operation messen
        $measurement = Measure-DatabaseOperation -OperationName "Sleep-Test" -Operation {
            Start-Sleep -Milliseconds 100
            return "Test"
        }
        
        Assert-True -Condition $measurement.Success -Message "Performance-Messung sollte erfolgreich sein"
        Assert-Equal -Expected "Test" -Actual $measurement.Result -Message "Ergebnis sollte korrekt sein"
        Assert-True -Condition $measurement.Duration.TotalMilliseconds -ge 90 -Message "Dauer sollte mindestens 90ms sein"
        Assert-True -Condition $measurement.Duration.TotalMilliseconds -lt 200 -Message "Dauer sollte unter 200ms sein"
        
        return @{ Success = $true; Message = "Performance-Messung erfolgreich ($(($measurement.Duration.TotalMilliseconds).ToString('F0'))ms)" }
        
    } catch {
        return @{ Success = $false; Message = "Performance-Test fehlgeschlagen: $_" }
    }
})

# Test 5: JSON-Assertions
$suite.AddTest("JSON-Assertions", {
    param($context)
    
    try {
        # Test-JSON erstellen
        $testObject = @{
            name = "Test User"
            age = 25
            active = $true
            settings = @{
                theme = "dark"
                notifications = $true
            }
        }
        
        $jsonString = $testObject | ConvertTo-Json -Depth 10
        
        # JSON-Property testen
        Assert-JsonProperty -JsonObject $testObject -PropertyPath "name" -ExpectedValue "Test User"
        Assert-JsonProperty -JsonObject $testObject -PropertyPath "settings.theme" -ExpectedValue "dark"
        
        # JSON-Schema testen
        $schema = @{
            name = @{ Required = $true; Type = "String"; MinLength = 1 }
            age = @{ Required = $true; Type = "Int32" }
            active = @{ Required = $true; Type = "Boolean" }
        }
        
        Assert-JsonSchema -JsonObject $testObject -Schema $schema
        
        return @{ Success = $true; Message = "JSON-Assertions erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "JSON-Test fehlgeschlagen: $_" }
    }
})

# Test 6: Test-Daten-Generatoren
$suite.AddTest("Test-Daten-Generatoren", {
    param($context)
    
    try {
        # Test-User generieren
        $user1 = New-TestUser -Id 1 -Prefix "Demo"
        $user2 = New-TestUser -Id 2 -Prefix "Demo"
        
        Assert-Equal -Expected 1 -Actual $user1.UserID -Message "User ID sollte korrekt sein"
        Assert-Equal -Expected "Demo1" -Actual $user1.Username -Message "Username sollte korrekt generiert werden"
        Assert-Equal -Expected "Demo1@test.local" -Actual $user1.Email -Message "Email sollte korrekt generiert werden"
        
        # Test-Product generieren
        $product = New-TestProduct -Id 5 -Prefix "TestProd"
        
        Assert-Equal -Expected 5 -Actual $product.ProductID -Message "Product ID sollte korrekt sein"
        Assert-Equal -Expected "TestProd-0005" -Actual $product.ProductCode -Message "Product Code sollte korrekt formatiert werden"
        Assert-Positive -Value $product.Price -Message "Preis sollte positiv sein"
        
        # Unique-Eigenschaften testen
        Assert-NotEqual -Expected $user1.Email -Actual $user2.Email -Message "Verschiedene Benutzer sollten verschiedene Emails haben"
        
        return @{ Success = $true; Message = "Test-Daten-Generatoren erfolgreich" }
        
    } catch {
        return @{ Success = $false; Message = "Test-Daten-Generator Test fehlgeschlagen: $_" }
    }
})

# Test 7: Error-Handling
$suite.AddTest("Error-Handling", {
    param($context)
    
    try {
        # Assert-Throws testen
        Assert-Throws -ScriptBlock {
            throw "Test Exception"
        } -ExpectedMessage "Test Exception"
        
        # Assert-DoesNotThrow testen
        Assert-DoesNotThrow -ScriptBlock {
            $result = 1 + 1
        }
        
        # Fehlerhafte Assertion sollte Exception werfen
        $threwException = $false
        try {
            Assert-True -Condition $false -Message "This should fail"
        } catch {
            $threwException = $true
        }
        
        Assert-True -Condition $threwException -Message "Fehlerhafte Assertion sollte Exception werfen"
        
        return @{ Success = $true; Message = "Error-Handling erfolgreich getestet" }
        
    } catch {
        return @{ Success = $false; Message = "Error-Handling Test fehlgeschlagen: $_" }
    }
})

# Test-Suite ausführen
try {
    Write-Host "`n🧪 Unit Tests: Basic Framework" -ForegroundColor Cyan
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
        Write-Host "`n🎉 Alle Basic Framework Tests bestanden!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️ $($results.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    }
    
    return @{
        Success = $success
        Message = "Basic Framework: $($results.Passed)/$($results.Total) Tests bestanden"
        Results = $results
    }
    
} catch {
    Write-Host "`n❌ Kritischer Fehler in Basic Framework Tests: $_" -ForegroundColor Red
    return @{
        Success = $false
        Message = "Kritischer Fehler: $_"
    }
} finally {
    # Cleanup
    Clear-AllMocks
    Clear-TestData
}