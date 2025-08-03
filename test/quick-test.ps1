# Quick Test für Debug
param([switch]$Verbose)

$ErrorActionPreference = "Stop"
if ($Verbose) { $VerbosePreference = "Continue" }

try {
    # Test-Framework laden
    $testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $sharedPath = Join-Path $testRoot "shared"
    
    Write-Host "Loading Test Framework from: $sharedPath" -ForegroundColor Yellow
    . (Join-Path $sharedPath "Test-Framework.ps1")
    
    Write-Host "Loading Database Adapter..." -ForegroundColor Yellow  
    $srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
    . (Join-Path $srcRoot "database-adapter-fixed.ps1")
    
    Write-Host "Testing SQLite connection..." -ForegroundColor Yellow
    # Lokales Test-Data-Verzeichnis verwenden
    $testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $testDataDir = Join-Path $testRoot "test-data" "temp"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir -Force | Out-Null
    }
    $dbPath = Join-Path $testDataDir "quick-test-$(Get-Random).db"
    
    # Einfacher SQLite Test
    $query = "SELECT 1 as TestValue"
    $result = $query | sqlite3 $dbPath
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ SQLite funktioniert: $result" -ForegroundColor Green
    } else {
        Write-Host "❌ SQLite Fehler: Exit Code $LASTEXITCODE" -ForegroundColor Red
    }
    
    # Database Adapter Test
    $connString = "Data Source=$dbPath"
    $adapter = New-DatabaseAdapter -ConnectionString $connString
    $testResult = $adapter.TestConnection()
    
    Write-Host "Database Adapter Test:" -ForegroundColor Yellow
    Write-Host "  Success: $($testResult.Success)" -ForegroundColor $(if($testResult.Success) {"Green"} else {"Red"})
    Write-Host "  Message: $($testResult.Message)" -ForegroundColor Gray
    
    # Cleanup
    Remove-Item $dbPath -Force -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "❌ Fehler: $_" -ForegroundColor Red
    Write-Host "Stack Trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}