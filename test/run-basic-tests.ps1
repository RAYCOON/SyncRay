# Grundlegende SyncRay Tests - Schnelle Validierung
# Für tägliche Entwicklung und kontinuierliche Integration

param(
    [switch]$CI
)

$ErrorActionPreference = "Stop"

# Kurze Test-Suite für grundlegende Funktionalität
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"

Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║               SYNCRAY BASIC TESTS                     ║" -ForegroundColor Green
Write-Host "║            Schnelle Qualitätsprüfung                 ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Green

$tests = @{
    Passed = 0
    Failed = 0
    Total = 0
}

function Test-Basic {
    param([string]$Name, [scriptblock]$Test)
    
    $tests.Total++
    Write-Host "`n→ $Name" -ForegroundColor Yellow
    
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  ✓ BESTANDEN" -ForegroundColor Green
            $tests.Passed++
        } else {
            Write-Host "  ✗ FEHLGESCHLAGEN" -ForegroundColor Red
            $tests.Failed++
        }
    } catch {
        Write-Host "  ✗ FEHLER: $_" -ForegroundColor Red
        $tests.Failed++
    }
}

# Grundlegende Tests
Test-Basic "SQLite3 verfügbar" {
    Get-Command sqlite3 -ErrorAction SilentlyContinue
}

Test-Basic "SyncRay Skripte vorhanden" {
    (Test-Path "$srcRoot\sync-export.ps1") -and (Test-Path "$srcRoot\sync-import.ps1")
}

Test-Basic "Temporäre SQLite Datenbank erstellen" {
    $tempPath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    $tempDb = Join-Path $tempPath "syncray-test-$(Get-Random).db"
    try {
        "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);" | sqlite3 $tempDb
        $result = "SELECT name FROM sqlite_master WHERE type='table' AND name='test';" | sqlite3 $tempDb
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
        $result -eq "test"
    } catch {
        Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
        $false
    }
}

Test-Basic "JSON Export/Import Funktionalität" {
    $testData = @{ test = "data"; number = 42 }
    $tempPath = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
    $tempFile = Join-Path $tempPath "syncray-json-test.json"
    try {
        $testData | ConvertTo-Json | Set-Content $tempFile
        $imported = Get-Content $tempFile | ConvertFrom-Json
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        $imported.test -eq "data" -and $imported.number -eq 42
    } catch {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        $false
    }
}

Test-Basic "PowerShell Module Kompatibilität" {
    try {
        # Test grundlegende PowerShell Features
        $hash = @{}
        $hash["test"] = "value"
        $array = @(1, 2, 3)
        $hash["test"] -eq "value" -and $array.Count -eq 3
    } catch {
        $false
    }
}

# Zusammenfassung
Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   BASIC TEST ERGEBNIS                 ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$passRate = if ($tests.Total -gt 0) { [math]::Round(($tests.Passed / $tests.Total) * 100, 1) } else { 0 }

Write-Host "`nErgebnis: $($tests.Passed)/$($tests.Total) Tests bestanden ($passRate%)"

if ($tests.Failed -eq 0) {
    Write-Host "🎉 Alle grundlegenden Tests erfolgreich!" -ForegroundColor Green
    Write-Host "SyncRay ist bereit für erweiterte Tests." -ForegroundColor Green
} else {
    Write-Host "⚠️  $($tests.Failed) Test(s) fehlgeschlagen" -ForegroundColor Yellow
    Write-Host "Bitte Grundkonfiguration prüfen." -ForegroundColor Yellow
}

if ($CI) {
    $results = @{
        TestSuite = "Basic"
        Total = $tests.Total
        Passed = $tests.Passed
        Failed = $tests.Failed
        PassRate = $passRate
        Timestamp = Get-Date
    }
    
    $resultsFile = Join-Path $testRoot "basic-test-results.json"
    $results | ConvertTo-Json | Set-Content $resultsFile
    Write-Host "`nErgebnisse für CI exportiert: $resultsFile" -ForegroundColor Gray
}

exit $(if ($tests.Failed -eq 0) { 0 } else { 1 })