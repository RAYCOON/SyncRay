# test-csv-delimiter.ps1 - Test CSV delimiter functionality

Write-Host "`n=== TESTING CSV DELIMITER FUNCTIONALITY ===" -ForegroundColor Cyan
Write-Host "This test checks different CSV delimiter options" -ForegroundColor Gray

# Load validation functions
$scriptPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptPath "src/sync-validation.ps1")

# Create test data
$testDuplicates = @(
    @{
        TableName = "TestTable"
        MatchOnFields = "ID,Name"
        DuplicateGroups = 2
        TotalDuplicates = 4
        Details = @(
            [PSCustomObject]@{ ID = 1; Name = "Test;Name"; Value = "10,5"; DuplicateGroup = 1 }
            [PSCustomObject]@{ ID = 2; Name = "Test;Name"; Value = "10,5"; DuplicateGroup = 1 }
        )
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
)

# Test output directory
$testOutputDir = "./test/delimiter-test-output"
if (-not (Test-Path $testOutputDir)) {
    New-Item -Path $testOutputDir -ItemType Directory | Out-Null
}

Write-Host "`nTest 1: Default delimiter (culture-specific)" -ForegroundColor Yellow
$cultureSeparator = (Get-Culture).TextInfo.ListSeparator
Write-Host "Current culture list separator: '$cultureSeparator'" -ForegroundColor Gray

$defaultCsv = Join-Path $testOutputDir "test_default.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $testDuplicates -OutputPath $defaultCsv

if ($result.Success) {
    Write-Host "[PASS] Default delimiter export successful" -ForegroundColor Green
    $content = Get-Content $defaultCsv | Select-Object -First 3
    Write-Host "Sample content:" -ForegroundColor Gray
    $content | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} else {
    Write-Host "[FAIL] Default delimiter export failed" -ForegroundColor Red
}

Write-Host "`nTest 2: Semicolon delimiter" -ForegroundColor Yellow
$semicolonCsv = Join-Path $testOutputDir "test_semicolon.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $testDuplicates -OutputPath $semicolonCsv -Delimiter ";"

if ($result.Success) {
    Write-Host "[PASS] Semicolon delimiter export successful" -ForegroundColor Green
    $content = Get-Content $semicolonCsv | Select-Object -First 3
    Write-Host "Sample content:" -ForegroundColor Gray
    $content | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    
    # Check if semicolon is used
    if ($content[1] -match ";") {
        Write-Host "[PASS] Semicolon delimiter correctly applied" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Semicolon delimiter not found in output" -ForegroundColor Red
    }
} else {
    Write-Host "[FAIL] Semicolon delimiter export failed" -ForegroundColor Red
}

Write-Host "`nTest 3: Comma delimiter" -ForegroundColor Yellow
$commaCsv = Join-Path $testOutputDir "test_comma.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $testDuplicates -OutputPath $commaCsv -Delimiter ","

if ($result.Success) {
    Write-Host "[PASS] Comma delimiter export successful" -ForegroundColor Green
    $content = Get-Content $commaCsv | Select-Object -First 3
    Write-Host "Sample content:" -ForegroundColor Gray
    $content | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} else {
    Write-Host "[FAIL] Comma delimiter export failed" -ForegroundColor Red
}

Write-Host "`nTest 4: Tab delimiter" -ForegroundColor Yellow
$tabCsv = Join-Path $testOutputDir "test_tab.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $testDuplicates -OutputPath $tabCsv -Delimiter "`t"

if ($result.Success) {
    Write-Host "[PASS] Tab delimiter export successful" -ForegroundColor Green
    $content = Get-Content $tabCsv | Select-Object -First 3
    Write-Host "Sample content:" -ForegroundColor Gray
    $content | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} else {
    Write-Host "[FAIL] Tab delimiter export failed" -ForegroundColor Red
}

Write-Host "`nTest 5: Via sync-export.ps1 with CsvDelimiter parameter" -ForegroundColor Yellow
Write-Host "This would test the full export workflow with delimiter:" -ForegroundColor Gray
Write-Host '  ./src/sync-export.ps1 -From source -ExportProblems -CsvDelimiter ";"' -ForegroundColor DarkGray

# Clean up
Write-Host "`nCleaning up test files..." -ForegroundColor Gray
Remove-Item -Path $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== CSV DELIMITER TEST COMPLETE ===" -ForegroundColor Cyan