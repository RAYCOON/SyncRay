# test-per-table-csv.ps1 - Test per-table CSV export functionality

Write-Host "`n=== TESTING PER-TABLE CSV EXPORT ===" -ForegroundColor Cyan
Write-Host "This test verifies that each table gets its own CSV file" -ForegroundColor Gray

# Load validation functions
$scriptPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptPath "src/sync-validation.ps1")

# Create test data with multiple tables
$testDuplicates = @(
    @{
        TableName = "Users"
        MatchOnFields = "UserID,Email"
        DuplicateGroups = 3
        TotalDuplicates = 7
        Details = @(
            [PSCustomObject]@{ UserID = 1; Email = "test@example.com"; Name = "John"; DuplicateGroup = 1 }
            [PSCustomObject]@{ UserID = 2; Email = "test@example.com"; Name = "John Doe"; DuplicateGroup = 1 }
            [PSCustomObject]@{ UserID = 5; Email = "admin@site.com"; Name = "Admin"; DuplicateGroup = 2 }
            [PSCustomObject]@{ UserID = 8; Email = "admin@site.com"; Name = "Administrator"; DuplicateGroup = 2 }
        )
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    },
    @{
        TableName = "Products"
        MatchOnFields = "SKU,Category"
        DuplicateGroups = 2
        TotalDuplicates = 5
        Details = @(
            [PSCustomObject]@{ ProductID = 101; SKU = "ABC123"; Category = "Electronics"; Name = "Widget"; DuplicateGroup = 1 }
            [PSCustomObject]@{ ProductID = 105; SKU = "ABC123"; Category = "Electronics"; Name = "Widget Pro"; DuplicateGroup = 1 }
            [PSCustomObject]@{ ProductID = 110; SKU = "XYZ789"; Category = "Home"; Name = "Gadget"; DuplicateGroup = 2 }
        )
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    },
    @{
        TableName = "Orders"
        MatchOnFields = "OrderNumber"
        DuplicateGroups = 1
        TotalDuplicates = 2
        Details = @(
            [PSCustomObject]@{ OrderID = 1001; OrderNumber = "ORD-2024-001"; CustomerID = 50; Total = 99.99; DuplicateGroup = 1 }
            [PSCustomObject]@{ OrderID = 1002; OrderNumber = "ORD-2024-001"; CustomerID = 51; Total = 99.99; DuplicateGroup = 1 }
        )
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
)

# Test output directory
$testOutputDir = "./test/per-table-test"
if (-not (Test-Path $testOutputDir)) {
    New-Item -Path $testOutputDir -ItemType Directory | Out-Null
}

# Simulate the export logic
Write-Host "`nSimulating per-table CSV export..." -ForegroundColor Yellow
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$duplicatesDir = Join-Path $testOutputDir "duplicates_$timestamp"
if (-not (Test-Path $duplicatesDir)) {
    New-Item -Path $duplicatesDir -ItemType Directory -Force | Out-Null
}

Write-Host "Creating individual CSV files for each table:" -ForegroundColor Gray

# Export each table
foreach ($tableProblem in $testDuplicates) {
    $tableCsvPath = Join-Path $duplicatesDir "$($tableProblem.TableName)_duplicates.csv"
    $result = Export-DuplicatesToCSV -DuplicateProblems @($tableProblem) -OutputPath $tableCsvPath
    
    if ($result.Success) {
        Write-Host "  [PASS] $($tableProblem.TableName): $tableCsvPath" -ForegroundColor Green
        Write-Host "         Rows: $($result.RowCount), Duplicate groups: $($tableProblem.DuplicateGroups)" -ForegroundColor Gray
        
        # Show sample content
        $content = Get-Content $tableCsvPath | Select-Object -First 3
        Write-Host "         Sample:" -ForegroundColor DarkGray
        $content | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        Write-Host ""
    } else {
        Write-Host "  [FAIL] $($tableProblem.TableName): Export failed" -ForegroundColor Red
    }
}

# Create summary file
Write-Host "Creating summary file with all tables:" -ForegroundColor Gray
$summaryCsvPath = Join-Path $duplicatesDir "_summary_all_duplicates.csv"
$result = Export-DuplicatesToCSV -DuplicateProblems $testDuplicates -OutputPath $summaryCsvPath

if ($result.Success) {
    Write-Host "  [PASS] Summary: $summaryCsvPath" -ForegroundColor Green
    Write-Host "         Total rows: $($result.RowCount)" -ForegroundColor Gray
} else {
    Write-Host "  [FAIL] Summary export failed" -ForegroundColor Red
}

# Check directory structure
Write-Host "`nDirectory structure created:" -ForegroundColor Yellow
$files = Get-ChildItem -Path $duplicatesDir -Filter "*.csv"
Write-Host "  $duplicatesDir/" -ForegroundColor Gray
foreach ($file in $files | Sort-Object Name) {
    Write-Host "    - $($file.Name)" -ForegroundColor DarkGray
}

# Test real export command
Write-Host "`nUsage with sync-export.ps1:" -ForegroundColor Yellow
Write-Host '  ./src/sync-export.ps1 -From source -ExportProblems' -ForegroundColor Gray
Write-Host "`nThis will create:" -ForegroundColor Gray
Write-Host "  ./sync-data/duplicates_[timestamp]/" -ForegroundColor DarkGray
Write-Host "    - TableName1_duplicates.csv" -ForegroundColor DarkGray
Write-Host "    - TableName2_duplicates.csv" -ForegroundColor DarkGray
Write-Host "    - _summary_all_duplicates.csv" -ForegroundColor DarkGray

# Clean up
Write-Host "`nCleaning up test files..." -ForegroundColor Gray
Remove-Item -Path $testOutputDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== PER-TABLE CSV EXPORT TEST COMPLETE ===" -ForegroundColor Cyan