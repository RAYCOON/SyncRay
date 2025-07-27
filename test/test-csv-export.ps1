# test-csv-export.ps1 - Test CSV export functionality

Write-Host "`n=== TESTING CSV EXPORT FUNCTIONALITY ===" -ForegroundColor Cyan
Write-Host "This test will create a temporary config with duplicate data to test CSV export" -ForegroundColor Gray

# Create test config
$testConfig = @{
    databases = @{
        test_source = @{
            server = "localhost"
            database = "TestDB"
            auth = "windows"
        }
    }
    syncTables = @(
        @{
            sourceTable = "DuplicateTestTable"
            matchOn = @("GroupKey", "Value")
            allowInserts = $true
            allowUpdates = $true
            allowDeletes = $false
        }
    )
    exportPath = "./test/csv-export-test-data"
}

# Create temporary config file
$configPath = "test/test-csv-export-config.json"
$testConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8

Write-Host "`nTest Scenarios:" -ForegroundColor Yellow
Write-Host "1. Export with -ExportProblems flag - should create CSV files" -ForegroundColor Gray
Write-Host "2. Export without -ExportProblems flag - should not create CSV files" -ForegroundColor Gray

# Test 1: With ExportProblems flag
Write-Host "`n--- Test 1: Export with -ExportProblems ---" -ForegroundColor Yellow
Write-Host "Command: ./src/sync-export.ps1 -From test_source -ExportProblems -NonInteractive -ConfigFile $configPath" -ForegroundColor Gray
Write-Host "Expected output files:" -ForegroundColor Gray
Write-Host "  - duplicates_[timestamp].csv" -ForegroundColor Gray
Write-Host "  - skipped_tables_[timestamp].csv" -ForegroundColor Gray

# Create test output directory
$testOutputDir = "./test/csv-export-output"
if (-not (Test-Path $testOutputDir)) {
    New-Item -Path $testOutputDir -ItemType Directory | Out-Null
}

# Run export with CSV export enabled
Write-Host "`nRunning export with CSV export enabled..." -ForegroundColor Cyan
$currentDir = Get-Location
Set-Location (Split-Path -Parent $PSScriptRoot)
& ./src/sync-export.ps1 -From test_source -ExportProblems -ProblemExportPath $testOutputDir -NonInteractive -ConfigFile $configPath 2>&1 | Out-String
Set-Location $currentDir

# Check for CSV files
$csvFiles = Get-ChildItem -Path $testOutputDir -Filter "*.csv" 2>$null
if ($csvFiles) {
    Write-Host "`n[PASS] CSV files created:" -ForegroundColor Green
    foreach ($file in $csvFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor Gray
        
        # Show sample content
        $content = Import-Csv $file.FullName | Select-Object -First 3
        if ($content) {
            Write-Host "`n  Sample content from $($file.Name):" -ForegroundColor Yellow
            $content | Format-Table -AutoSize | Out-String | Write-Host
        }
    }
} else {
    Write-Host "`n[INFO] No CSV files created (might indicate no duplicates were found)" -ForegroundColor Yellow
}

# Test 2: Without ExportProblems flag
Write-Host "`n--- Test 2: Export without -ExportProblems ---" -ForegroundColor Yellow
Write-Host "Command: ./src/sync-export.ps1 -From test_source -NonInteractive -ConfigFile $configPath" -ForegroundColor Gray
Write-Host "Expected: No new CSV files created" -ForegroundColor Gray

# Clear output directory
Remove-Item -Path "$testOutputDir/*.csv" -Force -ErrorAction SilentlyContinue

# Run export without CSV export
Write-Host "`nRunning export without CSV export..." -ForegroundColor Cyan
$currentDir = Get-Location
Set-Location (Split-Path -Parent $PSScriptRoot)
& ./src/sync-export.ps1 -From test_source -NonInteractive -ConfigFile $configPath 2>&1 | Out-String
Set-Location $currentDir

# Check for CSV files
$csvFiles = Get-ChildItem -Path $testOutputDir -Filter "*.csv" 2>$null
if ($csvFiles) {
    Write-Host "`n[FAIL] CSV files were created when -ExportProblems was not specified" -ForegroundColor Red
} else {
    Write-Host "`n[PASS] No CSV files created as expected" -ForegroundColor Green
}

# Test CSV structure
Write-Host "`n--- Test 3: CSV Structure Validation ---" -ForegroundColor Yellow

# Create sample duplicate problem data
$sampleDuplicates = @(
    @{
        TableName = "TestTable1"
        MatchOnFields = "ID,Name"
        DuplicateGroups = 5
        TotalDuplicates = 12
        Details = @(
            [PSCustomObject]@{ ID = 1; Name = "Test1"; DuplicateGroup = 1 }
            [PSCustomObject]@{ ID = 2; Name = "Test1"; DuplicateGroup = 1 }
        )
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
)

$sampleSkipped = @(
    @{
        TableName = "TestTable2"
        Reason = "Duplicates found"
        DuplicateGroups = 3
        TotalDuplicates = 8
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
)

# Load validation functions
. (Join-Path $PSScriptRoot "../src/sync-validation.ps1")

# Test duplicate export
$duplicateCsv = Join-Path $testOutputDir "test_duplicates.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $sampleDuplicates -OutputPath $duplicateCsv
if ($result.Success) {
    Write-Host "[PASS] Duplicate CSV export successful" -ForegroundColor Green
    Write-Host "  Rows exported: $($result.RowCount)" -ForegroundColor Gray
} else {
    Write-Host "[FAIL] Duplicate CSV export failed: $($result.Message)" -ForegroundColor Red
}

# Test skipped tables export
$skippedCsv = Join-Path $testOutputDir "test_skipped.csv"
$result = Export-SkippedTablesToCSV -SkippedTables $sampleSkipped -OutputPath $skippedCsv
if ($result.Success) {
    Write-Host "[PASS] Skipped tables CSV export successful" -ForegroundColor Green
    Write-Host "  Rows exported: $($result.RowCount)" -ForegroundColor Gray
} else {
    Write-Host "[FAIL] Skipped tables CSV export failed: $($result.Message)" -ForegroundColor Red
}

# Clean up
Write-Host "`nCleaning up test files..." -ForegroundColor Gray
Remove-Item $configPath -ErrorAction SilentlyContinue
Remove-Item -Path $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== CSV EXPORT TEST COMPLETE ===" -ForegroundColor Cyan