# Comprehensive SyncRay Test Suite using Native SQLite
# Works on all platforms including macOS ARM64

param(
    [string[]]$Categories = @("Basic", "Advanced", "EdgeCases", "Performance"),
    [switch]$KeepTestData,
    [switch]$CI  # Running in CI/CD environment
)

$ErrorActionPreference = "Stop"
$script:TestResults = @{ 
    Passed = 0
    Failed = 0
    Total = 0
    Details = @()
    StartTime = Get-Date
}

# Setup paths
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcRoot = Join-Path (Split-Path -Parent $testRoot) "src"
$testDbPath = Join-Path $testRoot "test-complete-db"
$sourceDb = Join-Path $testDbPath "source.db"
$targetDb = Join-Path $testDbPath "target.db"
$configFile = Join-Path $testRoot "test-complete-config.json"
$exportPath = Join-Path $testRoot "test-complete-data"

# Ensure sqlite3 is available
if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: sqlite3 command not found" -ForegroundColor Red
    Write-Host "Please install SQLite3 for your platform" -ForegroundColor Yellow
    exit 1
}

# Function to execute SQLite commands
function Invoke-SQLite {
    param(
        [string]$Database,
        [string]$Query,
        [switch]$AsJson,
        [switch]$AsCsv
    )
    
    if ($AsJson) {
        $Query = ".mode json`n$Query"
    } elseif ($AsCsv) {
        $Query = ".mode csv`n.headers on`n$Query"
    }
    
    $result = $Query | sqlite3 $Database 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SQLite error: $result"
    }
    
    return $result
}

# Test runner function
function Test-Feature {
    param(
        [string]$Category,
        [string]$Name,
        [string]$Description,
        [scriptblock]$Test
    )
    
    $script:TestResults.Total++
    
    Write-Host "`n━━━ $Category : $Name ━━━" -ForegroundColor Yellow
    Write-Host "$Description" -ForegroundColor Gray
    
    $testStart = Get-Date
    
    try {
        $result = & $Test
        $duration = ((Get-Date) - $testStart).TotalMilliseconds
        
        if ($result.Success) {
            Write-Host "✓ PASSED - $($result.Message) (${duration}ms)" -ForegroundColor Green
            $script:TestResults.Passed++
            $status = "Passed"
        } else {
            Write-Host "✗ FAILED - $($result.Message)" -ForegroundColor Red
            if ($result.Details) {
                Write-Host "  Details: $($result.Details)" -ForegroundColor Gray
            }
            $script:TestResults.Failed++
            $status = "Failed"
        }
    } catch {
        Write-Host "✗ ERROR - $_" -ForegroundColor Red
        $script:TestResults.Failed++
        $status = "Error"
        $result = @{ Message = $_.Exception.Message }
    }
    
    $script:TestResults.Details += @{
        Category = $Category
        Name = $Name
        Status = $status
        Message = $result.Message
        Duration = $duration
        Timestamp = Get-Date
    }
}

# Initialize test environment
function Initialize-TestEnvironment {
    Write-Host "`n═══ Initializing Test Environment ═══" -ForegroundColor Cyan
    
    # Create directories
    @($testDbPath, $exportPath) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
    
    # Clean existing databases
    @($sourceDb, $targetDb) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force }
    }
    
    # Create source database with comprehensive test data
    Write-Host "Creating source database..." -ForegroundColor Gray
    $sourceSchema = @"
-- Users table with various data types
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY,
    Username TEXT NOT NULL,
    Email TEXT NOT NULL UNIQUE,
    IsActive INTEGER DEFAULT 1,
    CreatedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    LastModified TEXT,
    Salary REAL,
    Department TEXT
);

-- Products with timestamps
CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY,
    ProductName TEXT NOT NULL,
    Price REAL NOT NULL,
    Stock INTEGER DEFAULT 0,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system'
);

-- Orders for WHERE clause testing
CREATE TABLE Orders (
    OrderID INTEGER PRIMARY KEY,
    CustomerID INTEGER NOT NULL,
    OrderDate TEXT NOT NULL,
    Status TEXT NOT NULL,
    Total REAL NOT NULL,
    Notes TEXT
);

-- OrderItems for composite key testing
CREATE TABLE OrderItems (
    OrderID INTEGER NOT NULL,
    ProductID INTEGER NOT NULL,
    Quantity INTEGER NOT NULL,
    Price REAL NOT NULL,
    Discount REAL DEFAULT 0,
    PRIMARY KEY (OrderID, ProductID)
);

-- Test data
INSERT INTO Users VALUES 
    (1, 'john_doe', 'john@example.com', 1, '2024-01-01', '2024-12-01', 75000, 'IT'),
    (2, 'jane_smith', 'jane@example.com', 1, '2024-01-15', '2024-12-15', 85000, 'Sales'),
    (3, 'bob_wilson', 'bob@example.com', 0, '2024-02-01', '2024-11-01', 65000, 'HR'),
    (4, 'alice_jones', 'alice@example.com', 1, '2024-02-15', '2024-12-20', 95000, 'IT');

INSERT INTO Products VALUES
    (1, 'Laptop Pro', 1299.99, 50, datetime('now'), 'system'),
    (2, 'Wireless Mouse', 29.99, 200, datetime('now'), 'system'),
    (3, 'Mechanical Keyboard', 149.99, 75, datetime('now'), 'system'),
    (4, 'USB-C Hub', 49.99, 150, datetime('now'), 'system');

INSERT INTO Orders VALUES
    (1001, 1, '2024-01-15', 'Completed', 1329.98, 'Priority order'),
    (1002, 2, '2024-02-20', 'Completed', 179.98, NULL),
    (1003, 3, '2024-11-15', 'Pending', 1299.99, 'Awaiting payment'),
    (1004, 4, '2024-12-01', 'Cancelled', 29.99, 'Customer cancelled');

INSERT INTO OrderItems VALUES
    (1001, 1, 1, 1299.99, 0),
    (1001, 2, 1, 29.99, 0),
    (1002, 3, 1, 149.99, 10),
    (1002, 2, 1, 29.99, 0),
    (1003, 1, 1, 1299.99, 0);
"@
    
    Invoke-SQLite -Database $sourceDb -Query $sourceSchema
    Write-Host "✓ Source database created" -ForegroundColor Green
    
    # Create target database with different data
    Write-Host "Creating target database..." -ForegroundColor Gray
    $targetSchema = @"
-- Same schema, different data
CREATE TABLE Users (
    UserID INTEGER PRIMARY KEY,
    Username TEXT NOT NULL,
    Email TEXT NOT NULL UNIQUE,
    IsActive INTEGER DEFAULT 1,
    CreatedDate TEXT DEFAULT CURRENT_TIMESTAMP,
    LastModified TEXT,
    Salary REAL,
    Department TEXT
);

CREATE TABLE Products (
    ProductID INTEGER PRIMARY KEY,
    ProductName TEXT NOT NULL,
    Price REAL NOT NULL,
    Stock INTEGER DEFAULT 0,
    LastModified TEXT DEFAULT CURRENT_TIMESTAMP,
    ModifiedBy TEXT DEFAULT 'system'
);

CREATE TABLE Orders (
    OrderID INTEGER PRIMARY KEY,
    CustomerID INTEGER NOT NULL,
    OrderDate TEXT NOT NULL,
    Status TEXT NOT NULL,
    Total REAL NOT NULL,
    Notes TEXT
);

CREATE TABLE OrderItems (
    OrderID INTEGER NOT NULL,
    ProductID INTEGER NOT NULL,
    Quantity INTEGER NOT NULL,
    Price REAL NOT NULL,
    Discount REAL DEFAULT 0,
    PRIMARY KEY (OrderID, ProductID)
);

-- Different test data
INSERT INTO Users VALUES 
    (1, 'john_doe', 'john.old@example.com', 1, '2024-01-01', '2024-11-01', 70000, 'IT'),
    (2, 'jane_smith', 'jane@example.com', 0, '2024-01-15', '2024-11-15', 85000, 'Sales'),
    (5, 'target_only', 'target@example.com', 1, '2024-03-01', '2024-12-01', 60000, 'Admin');

INSERT INTO Products VALUES
    (1, 'Laptop Pro', 999.99, 45, '2024-11-01', 'admin'),
    (2, 'Wireless Mouse', 29.99, 180, '2024-11-01', 'admin'),
    (5, 'Webcam HD', 79.99, 60, '2024-11-01', 'admin');
"@
    
    Invoke-SQLite -Database $targetDb -Query $targetSchema
    Write-Host "✓ Target database created" -ForegroundColor Green
    
    # Create configuration
    Write-Host "Creating configuration..." -ForegroundColor Gray
    $config = @{
        databases = @{
            source = @{
                server = "localhost"
                database = $sourceDb
                auth = "sqlite"
            }
            target = @{
                server = "localhost"
                database = $targetDb
                auth = "sqlite"
            }
        }
        
        syncTables = @(
            @{
                sourceTable = "Users"
                matchOn = @("UserID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "Products"
                matchOn = @("ProductID")
                ignoreColumns = @("LastModified", "ModifiedBy")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "OrderItems"
                matchOn = @("OrderID", "ProductID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "Orders"
                matchOn = @("OrderID")
                exportWhere = "Status = 'Completed'"
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            }
        )
        
        exportPath = $exportPath
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configFile
    Write-Host "✓ Configuration created" -ForegroundColor Green
}

# Basic Tests
function Run-BasicTests {
    Test-Feature -Category "Basic" -Name "SQLite Availability" -Description "Verify SQLite is available and working" -Test {
        try {
            $version = sqlite3 --version
            @{ Success = $true; Message = "SQLite available: $($version.Split(' ')[0])" }
        } catch {
            @{ Success = $false; Message = "SQLite not available" }
        }
    }
    
    Test-Feature -Category "Basic" -Name "Database Creation" -Description "Test database creation and basic queries" -Test {
        try {
            $userCount = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) FROM Users;"
            $productCount = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) FROM Products;"
            
            if ($userCount -eq "4" -and $productCount -eq "4") {
                @{ Success = $true; Message = "Databases created with correct data" }
            } else {
                @{ Success = $false; Message = "Incorrect data count" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    Test-Feature -Category "Basic" -Name "Export to JSON" -Description "Test exporting data to JSON format" -Test {
        try {
            # Export Users table
            $usersCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM Users;" -AsCsv
            $usersData = $usersCsv | ConvertFrom-Csv
            
            $export = @{
                metadata = @{
                    sourceTable = "Users"
                    exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    rowCount = $usersData.Count
                    matchOn = @("UserID")
                }
                data = $usersData
            }
            
            $exportFile = Join-Path $exportPath "Users.json"
            $export | ConvertTo-Json -Depth 10 | Set-Content $exportFile
            
            if ((Test-Path $exportFile) -and (Get-Content $exportFile | ConvertFrom-Json).data.Count -eq 4) {
                @{ Success = $true; Message = "Export successful with 4 users" }
            } else {
                @{ Success = $false; Message = "Export failed or incorrect data" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    Test-Feature -Category "Basic" -Name "Change Detection" -Description "Test detecting changes between databases" -Test {
        try {
            # Get source users
            $sourceCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT UserID FROM Users;" -AsCsv
            $sourceIds = ($sourceCsv | ConvertFrom-Csv).UserID
            
            # Get target users
            $targetCsv = Invoke-SQLite -Database $targetDb -Query "SELECT UserID FROM Users;" -AsCsv
            $targetIds = ($targetCsv | ConvertFrom-Csv).UserID
            
            $toInsert = @($sourceIds | Where-Object { $_ -notin $targetIds }).Count
            $toDelete = @($targetIds | Where-Object { $_ -notin $sourceIds }).Count
            
            if ($toInsert -eq 2 -and $toDelete -eq 1) {
                @{ Success = $true; Message = "Correctly detected 2 inserts, 1 delete" }
            } else {
                @{ Success = $false; Message = "Insert: $toInsert, Delete: $toDelete" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}

# Advanced Tests
function Run-AdvancedTests {
    Test-Feature -Category "Advanced" -Name "Composite Keys" -Description "Test tables with composite primary keys" -Test {
        try {
            $itemsCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT COUNT(*) as count FROM OrderItems;" -AsCsv
            $count = ($itemsCsv | ConvertFrom-Csv).count
            
            if ($count -eq "5") {
                @{ Success = $true; Message = "Composite key table has correct data" }
            } else {
                @{ Success = $false; Message = "Expected 5 items, got $count" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "WHERE Clause Export" -Description "Test selective export with WHERE clause" -Test {
        try {
            # Export only completed orders
            $ordersCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM Orders WHERE Status = 'Completed';" -AsCsv
            $ordersData = $ordersCsv | ConvertFrom-Csv
            
            $export = @{
                metadata = @{
                    sourceTable = "Orders"
                    exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    rowCount = $ordersData.Count
                    matchOn = @("OrderID")
                    exportWhere = "Status = 'Completed'"
                }
                data = $ordersData
            }
            
            $exportFile = Join-Path $exportPath "Orders.json"
            $export | ConvertTo-Json -Depth 10 | Set-Content $exportFile
            
            if ($ordersData.Count -eq 2) {
                @{ Success = $true; Message = "WHERE clause correctly filtered to 2 completed orders" }
            } else {
                @{ Success = $false; Message = "Expected 2 completed orders, got $($ordersData.Count)" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "Data Type Handling" -Description "Test various data types" -Test {
        try {
            $userCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM Users WHERE UserID = 1;" -AsCsv
            $user = $userCsv | ConvertFrom-Csv
            
            $checks = @(
                $user.UserID -eq "1"
                $user.Username -eq "john_doe"
                $user.IsActive -eq "1"
                $user.Salary -eq "75000"
                $user.Department -eq "IT"
            )
            
            if ($checks -notcontains $false) {
                @{ Success = $true; Message = "All data types handled correctly" }
            } else {
                @{ Success = $false; Message = "Data type mismatch" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}

# Edge Case Tests
function Run-EdgeCaseTests {
    Test-Feature -Category "EdgeCases" -Name "Empty Table" -Description "Test handling empty tables" -Test {
        try {
            # Create empty table
            Invoke-SQLite -Database $sourceDb -Query "CREATE TABLE EmptyTable (ID INTEGER PRIMARY KEY, Data TEXT);"
            
            $csv = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM EmptyTable;" -AsCsv
            $data = $csv | ConvertFrom-Csv
            
            if ($null -eq $data -or $data.Count -eq 0) {
                @{ Success = $true; Message = "Empty table handled correctly" }
            } else {
                @{ Success = $false; Message = "Empty table returned data" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
    
    Test-Feature -Category "EdgeCases" -Name "NULL Values" -Description "Test NULL value handling" -Test {
        try {
            $orderCsv = Invoke-SQLite -Database $sourceDb -Query "SELECT Notes FROM Orders WHERE OrderID = 1002;" -AsCsv
            $order = $orderCsv | ConvertFrom-Csv
            
            if ([string]::IsNullOrEmpty($order.Notes)) {
                @{ Success = $true; Message = "NULL values handled correctly" }
            } else {
                @{ Success = $false; Message = "NULL value not empty: '$($order.Notes)'" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}

# Performance Tests
function Run-PerformanceTests {
    if ($CI) {
        Write-Host "`nSkipping performance tests in CI environment" -ForegroundColor Yellow
        return
    }
    
    Test-Feature -Category "Performance" -Name "Large Table Export" -Description "Test performance with larger dataset" -Test {
        try {
            # Create large table
            Invoke-SQLite -Database $sourceDb -Query "CREATE TABLE LargeTable (ID INTEGER PRIMARY KEY, Data TEXT, Value REAL);"
            
            # Insert many rows
            $insertStart = Get-Date
            1..1000 | ForEach-Object {
                Invoke-SQLite -Database $sourceDb -Query "INSERT INTO LargeTable VALUES ($_, 'Data$_', $($_ * 1.5));"
            }
            $insertDuration = ((Get-Date) - $insertStart).TotalSeconds
            
            # Export
            $exportStart = Get-Date
            $csv = Invoke-SQLite -Database $sourceDb -Query "SELECT * FROM LargeTable;" -AsCsv
            $data = $csv | ConvertFrom-Csv
            $exportDuration = ((Get-Date) - $exportStart).TotalSeconds
            
            if ($data.Count -eq 1000 -and $exportDuration -lt 5) {
                @{ Success = $true; Message = "1000 rows exported in ${exportDuration}s" }
            } else {
                @{ Success = $false; Message = "Performance issue or incorrect count" }
            }
        } catch {
            @{ Success = $false; Message = $_.Exception.Message }
        }
    }
}

# Main execution
try {
    Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     Comprehensive SyncRay SQLite Test Suite           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Initialize
    Initialize-TestEnvironment
    
    # Run test categories
    Write-Host "`n═══ Running Test Categories: $($Categories -join ', ') ═══" -ForegroundColor Cyan
    
    foreach ($category in $Categories) {
        switch ($category) {
            "Basic" { Run-BasicTests }
            "Advanced" { Run-AdvancedTests }
            "EdgeCases" { Run-EdgeCaseTests }
            "Performance" { Run-PerformanceTests }
            default { Write-Host "Unknown category: $category" -ForegroundColor Yellow }
        }
    }
    
    # Summary
    $duration = (Get-Date) - $script:TestResults.StartTime
    Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                  TEST SUMMARY                         ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $passRate = if ($script:TestResults.Total -gt 0) { 
        [math]::Round(($script:TestResults.Passed / $script:TestResults.Total) * 100, 1) 
    } else { 0 }
    
    Write-Host "`nTotal Tests: $($script:TestResults.Total)"
    Write-Host "✓ Passed: $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "✗ Failed: $($script:TestResults.Failed)" -ForegroundColor Red
    Write-Host "`nPass Rate: $passRate%"
    Write-Host "Duration: $($duration.ToString('mm\:ss\.ff'))"
    
    if ($script:TestResults.Failed -eq 0) {
        Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Some tests failed" -ForegroundColor Yellow
        
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        $script:TestResults.Details | Where-Object { $_.Status -ne "Passed" } | ForEach-Object {
            Write-Host "  - [$($_.Category)] $($_.Name): $($_.Message)" -ForegroundColor Red
        }
    }
    
    # Export results for CI
    if ($CI) {
        $resultsFile = Join-Path $testRoot "test-results.json"
        $script:TestResults | ConvertTo-Json -Depth 10 | Set-Content $resultsFile
        Write-Host "`nTest results exported to: $resultsFile" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "`nFatal error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
} finally {
    # Cleanup
    if (-not $KeepTestData) {
        Write-Host "`nCleaning up test data..." -ForegroundColor Yellow
        
        @($testDbPath, $exportPath, $configFile) | ForEach-Object {
            if (Test-Path $_) {
                Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
    } else {
        Write-Host "`nTest data kept at:" -ForegroundColor Yellow
        Write-Host "  Databases: $testDbPath" -ForegroundColor Gray
        Write-Host "  Exports: $exportPath" -ForegroundColor Gray
        Write-Host "  Config: $configFile" -ForegroundColor Gray
    }
}

# Exit with appropriate code
exit $(if ($script:TestResults.Failed -eq 0) { 0 } else { 1 })