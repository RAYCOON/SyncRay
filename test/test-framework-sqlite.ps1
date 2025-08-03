# Comprehensive SQLite Test Framework for SyncRay
# Tests all features using local SQLite databases

param(
    [string[]]$Categories = @("Basic", "Advanced", "EdgeCases", "ErrorHandling"),
    [switch]$KeepTestData,
    [switch]$Verbose,
    [switch]$CI,  # Running in CI/CD environment
    [switch]$InMemory  # Use in-memory SQLite for faster tests
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
$testDbPath = Join-Path $testRoot "test-db"
$sourceDbFile = Join-Path $testDbPath "source.db"
$targetDbFile = Join-Path $testDbPath "target.db"
$configFile = Join-Path $testRoot "test-sqlite-config.json"
$exportPath = Join-Path $testRoot "test-sync-data"

# Load database adapter
. (Join-Path $srcRoot "database-adapter.ps1")

# Colors for output
$colors = @{
    Reset = "`e[0m"
    Bold = "`e[1m"
    Red = "`e[31m"
    Green = "`e[32m"
    Yellow = "`e[33m"
    Blue = "`e[34m"
    Cyan = "`e[36m"
    Gray = "`e[90m"
}

# Ensure PSSQLite is installed
function Install-SQLiteModule {
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        Write-Host "Installing PSSQLite module..." -ForegroundColor Yellow
        if ($CI) {
            Install-Module PSSQLite -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
        } else {
            Install-Module PSSQLite -Scope CurrentUser -Force -AllowClobber
        }
    }
    Import-Module PSSQLite -Force
}

# Create test databases
function Initialize-TestDatabases {
    Write-Host "`n$($colors.Cyan)═══ Initializing Test Databases ═══$($colors.Reset)"
    
    # Create directory
    if (-not (Test-Path $testDbPath)) {
        New-Item -ItemType Directory -Path $testDbPath -Force | Out-Null
    }
    
    # Remove existing databases
    @($sourceDbFile, $targetDbFile) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force }
    }
    
    # Create source database
    Write-Host "Creating source database..." -ForegroundColor Gray
    $sourceConn = New-SQLiteConnection -DataSource $sourceDbFile
    
    try {
        # Create tables - SQL Server compatible schema
        $tables = @"
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

-- Products with timestamps for ignore column testing
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

-- ReferenceData for replace mode testing
CREATE TABLE ReferenceData (
    RefID INTEGER PRIMARY KEY,
    RefCode TEXT NOT NULL UNIQUE,
    RefValue TEXT NOT NULL,
    RefCategory TEXT
);

-- DuplicateTest for duplicate detection
CREATE TABLE DuplicateTest (
    ID INTEGER PRIMARY KEY,
    Code TEXT NOT NULL,
    Value TEXT,
    Category TEXT,
    Priority INTEGER
);

-- SpecialChars for edge case testing
CREATE TABLE SpecialChars (
    ID INTEGER PRIMARY KEY,
    Name TEXT NOT NULL,
    Description TEXT,
    JsonData TEXT,
    XmlData TEXT
);

-- LargeTable for performance testing
CREATE TABLE LargeTable (
    ID INTEGER PRIMARY KEY,
    DataField1 TEXT,
    DataField2 TEXT,
    DataField3 INTEGER,
    DataField4 REAL,
    CreatedDate TEXT DEFAULT CURRENT_TIMESTAMP
);

-- NoIdentityTable for non-identity PK testing
CREATE TABLE NoIdentityTable (
    Code TEXT PRIMARY KEY,
    Name TEXT NOT NULL,
    Value INTEGER
);

-- EmptyTable for empty table testing
CREATE TABLE EmptyTable (
    ID INTEGER PRIMARY KEY,
    Data TEXT
);
"@
        
        Invoke-SqliteQuery -SQLiteConnection $sourceConn -Query $tables
        
        # Insert test data
        Insert-SourceTestData -Connection $sourceConn
        
        Write-Host "✓ Source database created with test data" -ForegroundColor Green
        
    } finally {
        $sourceConn.Close()
    }
    
    # Create target database with different data
    Write-Host "Creating target database..." -ForegroundColor Gray
    $targetConn = New-SQLiteConnection -DataSource $targetDbFile
    
    try {
        # Same schema
        Invoke-SqliteQuery -SQLiteConnection $targetConn -Query $tables
        
        # Different data for testing updates/deletes
        Insert-TargetTestData -Connection $targetConn
        
        Write-Host "✓ Target database created with test data" -ForegroundColor Green
        
    } finally {
        $targetConn.Close()
    }
}

# Insert comprehensive test data into source
function Insert-SourceTestData {
    param($Connection)
    
    # Users - various scenarios
    $users = @(
        "INSERT INTO Users VALUES (1, 'john_doe', 'john@example.com', 1, '2024-01-01', '2024-12-01', 75000, 'IT')",
        "INSERT INTO Users VALUES (2, 'jane_smith', 'jane@example.com', 1, '2024-01-15', '2024-12-15', 85000, 'Sales')",
        "INSERT INTO Users VALUES (3, 'bob_wilson', 'bob@example.com', 0, '2024-02-01', '2024-11-01', 65000, 'HR')",
        "INSERT INTO Users VALUES (4, 'alice_jones', 'alice@example.com', 1, '2024-02-15', '2024-12-20', 95000, 'IT')",
        "INSERT INTO Users VALUES (5, 'charlie_brown', 'charlie@example.com', 1, '2024-03-01', '2024-12-25', 70000, 'Sales')"
    )
    
    # Products
    $products = @(
        "INSERT INTO Products VALUES (1, 'Laptop Pro', 1299.99, 50, datetime('now'), 'system')",
        "INSERT INTO Products VALUES (2, 'Wireless Mouse', 29.99, 200, datetime('now'), 'system')",
        "INSERT INTO Products VALUES (3, 'Mechanical Keyboard', 149.99, 75, datetime('now'), 'system')",
        "INSERT INTO Products VALUES (4, 'USB-C Hub', 49.99, 150, datetime('now'), 'system')",
        "INSERT INTO Products VALUES (5, '27`" Monitor', 399.99, 30, datetime('now'), 'system')"
    )
    
    # Orders - various statuses for WHERE testing
    $orders = @(
        "INSERT INTO Orders VALUES (1001, 1, '2024-01-15', 'Completed', 1329.98, 'Priority order')",
        "INSERT INTO Orders VALUES (1002, 2, '2024-02-20', 'Completed', 179.98, NULL)",
        "INSERT INTO Orders VALUES (1003, 3, '2024-11-15', 'Pending', 1299.99, 'Awaiting payment')",
        "INSERT INTO Orders VALUES (1004, 4, '2024-12-01', 'Cancelled', 29.99, 'Customer cancelled')",
        "INSERT INTO Orders VALUES (1005, 5, '2024-12-10', 'Completed', 449.98, 'Gift wrapped')",
        "INSERT INTO Orders VALUES (1006, 1, '2024-12-15', 'Processing', 199.98, NULL)"
    )
    
    # OrderItems - composite keys
    $orderItems = @(
        "INSERT INTO OrderItems VALUES (1001, 1, 1, 1299.99, 0)",
        "INSERT INTO OrderItems VALUES (1001, 2, 1, 29.99, 0)",
        "INSERT INTO OrderItems VALUES (1002, 3, 1, 149.99, 10)",
        "INSERT INTO OrderItems VALUES (1002, 2, 1, 29.99, 0)",
        "INSERT INTO OrderItems VALUES (1003, 1, 1, 1299.99, 0)",
        "INSERT INTO OrderItems VALUES (1005, 5, 1, 399.99, 0)",
        "INSERT INTO OrderItems VALUES (1005, 4, 1, 49.99, 0)"
    )
    
    # ReferenceData
    $refData = @(
        "INSERT INTO ReferenceData VALUES (1, 'COUNTRY_US', 'United States', 'Geographic')",
        "INSERT INTO ReferenceData VALUES (2, 'COUNTRY_UK', 'United Kingdom', 'Geographic')",
        "INSERT INTO ReferenceData VALUES (3, 'COUNTRY_DE', 'Germany', 'Geographic')",
        "INSERT INTO ReferenceData VALUES (4, 'STATUS_ACTIVE', 'Active', 'Status')",
        "INSERT INTO ReferenceData VALUES (5, 'STATUS_INACTIVE', 'Inactive', 'Status')"
    )
    
    # DuplicateTest - intentional duplicates
    $duplicates = @(
        "INSERT INTO DuplicateTest VALUES (1, 'CODE001', 'Value 1', 'Category A', 1)",
        "INSERT INTO DuplicateTest VALUES (2, 'CODE001', 'Value 2', 'Category A', 2)",
        "INSERT INTO DuplicateTest VALUES (3, 'CODE002', 'Value 3', 'Category B', 1)",
        "INSERT INTO DuplicateTest VALUES (4, 'CODE002', 'Value 4', 'Category B', 2)",
        "INSERT INTO DuplicateTest VALUES (5, 'CODE003', 'Value 5', 'Category C', 1)"
    )
    
    # SpecialChars - edge cases
    $specialChars = @(
        "INSERT INTO SpecialChars VALUES (1, 'Test''s Name', 'Description with `"quotes`"', '{`"key`": `"value`"}', '<xml>data</xml>')",
        "INSERT INTO SpecialChars VALUES (2, 'Name; with semicolon', 'Line1`nLine2`nLine3', NULL, NULL)",
        "INSERT INTO SpecialChars VALUES (3, 'Ümläüts & Spëcial', 'Test © 2024 ® ™', '{`"emoji`": `"😀`"}', '<test/>')",
        "INSERT INTO SpecialChars VALUES (4, '中文测试', 'Unicode test データ', NULL, NULL)"
    )
    
    # NoIdentityTable
    $noIdentity = @(
        "INSERT INTO NoIdentityTable VALUES ('PROD001', 'Product One', 100)",
        "INSERT INTO NoIdentityTable VALUES ('PROD002', 'Product Two', 200)",
        "INSERT INTO NoIdentityTable VALUES ('PROD003', 'Product Three', 300)"
    )
    
    # Execute all inserts
    @($users, $products, $orders, $orderItems, $refData, $duplicates, $specialChars, $noIdentity) | ForEach-Object {
        foreach ($sql in $_) {
            Invoke-SqliteQuery -SQLiteConnection $Connection -Query $sql
        }
    }
    
    # LargeTable - generate many rows for performance testing
    if (-not $CI) {  # Skip large data in CI to save time
        1..1000 | ForEach-Object {
            $sql = "INSERT INTO LargeTable (DataField1, DataField2, DataField3, DataField4) VALUES ('Data$_', 'Field$_', $_, $(Get-Random -Maximum 1000.0))"
            Invoke-SqliteQuery -SQLiteConnection $Connection -Query $sql
        }
    }
}

# Insert different test data into target
function Insert-TargetTestData {
    param($Connection)
    
    # Users - some different, some same, some missing
    $users = @(
        "INSERT INTO Users VALUES (1, 'john_doe', 'john.old@example.com', 1, '2024-01-01', '2024-11-01', 70000, 'IT')",  # Different email, salary
        "INSERT INTO Users VALUES (2, 'jane_smith', 'jane@example.com', 0, '2024-01-15', '2024-11-15', 85000, 'Sales')",  # Different IsActive
        "INSERT INTO Users VALUES (6, 'target_only', 'target@example.com', 1, '2024-03-01', '2024-12-01', 60000, 'Admin')",  # Only in target
        "INSERT INTO Users VALUES (7, 'another_target', 'another@example.com', 1, '2024-04-01', '2024-12-01', 55000, 'Support')"  # Only in target
        # Missing users 3, 4, 5 from source
    )
    
    # Products - for testing ignoreColumns
    $products = @(
        "INSERT INTO Products VALUES (1, 'Laptop Pro', 999.99, 45, '2024-11-01', 'admin')",  # Different price, stock, timestamps
        "INSERT INTO Products VALUES (2, 'Wireless Mouse', 29.99, 180, '2024-11-01', 'admin')",  # Same price, different stock
        "INSERT INTO Products VALUES (6, 'Webcam HD', 79.99, 60, '2024-11-01', 'admin')"  # Only in target
        # Missing products 3, 4, 5
    )
    
    # ReferenceData - completely different for replaceMode
    $refData = @(
        "INSERT INTO ReferenceData VALUES (10, 'OLD_CODE_1', 'Old Value 1', 'Legacy')",
        "INSERT INTO ReferenceData VALUES (11, 'OLD_CODE_2', 'Old Value 2', 'Legacy')",
        "INSERT INTO ReferenceData VALUES (12, 'OLD_CODE_3', 'Old Value 3', 'Legacy')"
    )
    
    # Execute inserts
    @($users, $products, $refData) | ForEach-Object {
        foreach ($sql in $_) {
            Invoke-SqliteQuery -SQLiteConnection $Connection -Query $sql
        }
    }
}

# Create test configuration
function Create-TestConfig {
    $config = @{
        databases = @{
            source = @{
                server = "localhost"
                database = if ($InMemory) { ":memory:" } else { $sourceDbFile }
                auth = "sqlite"
            }
            target = @{
                server = "localhost"
                database = if ($InMemory) { ":memory:" } else { $targetDbFile }
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
                sourceTable = "DuplicateTest"
                matchOn = @("Code")  # This will cause duplicates
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "ReferenceData"
                replaceMode = $true
                preserveIdentity = $true
            },
            @{
                sourceTable = "Orders"
                matchOn = @("OrderID")
                exportWhere = "Status = 'Completed'"
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "SpecialChars"
                matchOn = @("ID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "LargeTable"
                matchOn = @("ID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "NoIdentityTable"
                matchOn = @("Code")
                preserveIdentity = $false
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "EmptyTable"
                matchOn = @("ID")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            }
        )
        
        exportPath = $exportPath
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $configFile
    Write-Host "✓ Test configuration created" -ForegroundColor Green
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
    
    Write-Host "`n$($colors.Yellow)━━━ $Category : $Name ━━━$($colors.Reset)"
    Write-Host "$($colors.Gray)$Description$($colors.Reset)"
    
    $testStart = Get-Date
    
    try {
        $result = & $Test
        $duration = ((Get-Date) - $testStart).TotalMilliseconds
        
        if ($result.Success) {
            Write-Host "$($colors.Green)✓ PASSED$($colors.Reset) - $($result.Message) (${duration}ms)"
            $script:TestResults.Passed++
            $status = "Passed"
        } else {
            Write-Host "$($colors.Red)✗ FAILED$($colors.Reset) - $($result.Message)"
            if ($result.Details -and $Verbose) {
                Write-Host "  $($colors.Gray)Details: $($result.Details)$($colors.Reset)"
            }
            $script:TestResults.Failed++
            $status = "Failed"
        }
    } catch {
        Write-Host "$($colors.Red)✗ ERROR$($colors.Reset) - $_"
        if ($Verbose) {
            Write-Host "  $($colors.Gray)Stack: $($_.ScriptStackTrace)$($colors.Reset)"
        }
        $script:TestResults.Failed++
        $status = "Error"
        $result = @{ Message = $_.Exception.Message }
    }
    
    $script:TestResults.Details += @{
        Category = $Category
        Name = $Name
        Status = $status
        Message = if ($result) { $result.Message } else { "No result" }
        Duration = $duration
        Timestamp = Get-Date
    }
}

# Basic Tests
function Run-BasicTests {
    Test-Feature -Category "Basic" -Name "Export All Tables" -Description "Export all configured tables" -Test {
        # Clean export directory
        if (Test-Path $exportPath) {
            Remove-Item $exportPath -Recurse -Force
        }
        
        $result = & $srcRoot\sync-export.ps1 -From source -ConfigFile $configFile -SkipOnDuplicates 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $exportedFiles = Get-ChildItem $exportPath -Filter "*.json" -ErrorAction SilentlyContinue
            if ($exportedFiles.Count -ge 8) {
                @{ Success = $true; Message = "Exported $($exportedFiles.Count) tables successfully" }
            } else {
                @{ Success = $false; Message = "Only $($exportedFiles.Count) tables exported" }
            }
        } else {
            @{ Success = $false; Message = "Export failed"; Details = ($result | Out-String) }
        }
    }
    
    Test-Feature -Category "Basic" -Name "Import Preview" -Description "Test dry-run import with change detection" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "Users" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "Insert.*3" -and $result -match "Update.*2" -and $result -match "Delete.*2") {
            @{ Success = $true; Message = "Correctly detected 3 inserts, 2 updates, 2 deletes" }
        } else {
            @{ Success = $false; Message = "Change detection incorrect"; Details = $result }
        }
    }
    
    Test-Feature -Category "Basic" -Name "Execute Import" -Description "Actually execute import and verify changes" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "Users" -ConfigFile $configFile -Execute 2>&1 | Out-String
        
        if ($result -match "Changes committed successfully" -or $result -match "committed") {
            # Verify in database
            $conn = New-SQLiteConnection -DataSource $targetDbFile
            try {
                $count = Invoke-SqliteQuery -SQLiteConnection $conn -Query "SELECT COUNT(*) as Count FROM Users" | Select-Object -ExpandProperty Count
                if ($count -eq 5) {
                    @{ Success = $true; Message = "Import executed successfully, 5 users in target" }
                } else {
                    @{ Success = $false; Message = "Import executed but count wrong: $count" }
                }
            } finally {
                $conn.Close()
            }
        } else {
            @{ Success = $false; Message = "Import execution failed"; Details = $result }
        }
    }
}

# Advanced Tests
function Run-AdvancedTests {
    Test-Feature -Category "Advanced" -Name "Composite Keys" -Description "Test tables with composite primary keys" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "OrderItems" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "Insert.*7" -and $result -notmatch "ERROR|error") {
            @{ Success = $true; Message = "Composite key table handled correctly" }
        } else {
            @{ Success = $false; Message = "Composite key handling failed"; Details = $result }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "Ignore Columns" -Description "Test that specified columns are ignored" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "Products" -ConfigFile $configFile 2>&1 | Out-String
        
        # Should update product 1 (price change), but not product 2 (only timestamps different)
        if ($result -match "Update.*1" -and $result -match "Insert.*3") {
            @{ Success = $true; Message = "Ignored columns working correctly" }
        } else {
            @{ Success = $false; Message = "Ignore columns not working"; Details = $result }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "Duplicate Detection" -Description "Test duplicate record detection" -Test {
        $result = & $srcRoot\sync-export.ps1 -From source -Tables "DuplicateTest" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "DUPLICATES FOUND" -and ($result -match "Skipping table" -or $result -match "Continue with export")) {
            @{ Success = $true; Message = "Duplicates correctly detected" }
        } else {
            @{ Success = $false; Message = "Duplicate detection failed"; Details = $result }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "Replace Mode" -Description "Test full table replacement" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "ReferenceData" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "REPLACE MODE" -or $result -match "Delete all.*Insert.*5") {
            @{ Success = $true; Message = "Replace mode correctly identified" }
        } else {
            @{ Success = $false; Message = "Replace mode not working"; Details = $result }
        }
    }
    
    Test-Feature -Category "Advanced" -Name "WHERE Clause" -Description "Test export filtering with WHERE clause" -Test {
        $ordersFile = Join-Path $exportPath "Orders.json"
        if (Test-Path $ordersFile) {
            $data = Get-Content $ordersFile | ConvertFrom-Json
            $completedCount = @($data.data | Where-Object { $_.Status -eq 'Completed' }).Count
            
            if ($completedCount -eq $data.data.Count -and $completedCount -eq 3) {
                @{ Success = $true; Message = "WHERE clause correctly filtered to 3 completed orders" }
            } else {
                @{ Success = $false; Message = "Expected 3 completed orders, got $completedCount" }
            }
        } else {
            @{ Success = $false; Message = "Orders export file not found" }
        }
    }
}

# Edge Case Tests
function Run-EdgeCaseTests {
    Test-Feature -Category "EdgeCases" -Name "Special Characters" -Description "Test handling of quotes and special chars" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "SpecialChars" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "Insert.*4" -and $result -notmatch "ERROR|error") {
            @{ Success = $true; Message = "Special characters handled correctly" }
        } else {
            @{ Success = $false; Message = "Special character handling failed"; Details = $result }
        }
    }
    
    Test-Feature -Category "EdgeCases" -Name "Empty Table" -Description "Test empty table export/import" -Test {
        $emptyFile = Join-Path $exportPath "EmptyTable.json"
        if (Test-Path $emptyFile) {
            $data = Get-Content $emptyFile | ConvertFrom-Json
            if ($data.metadata.rowCount -eq 0 -and $data.data.Count -eq 0) {
                @{ Success = $true; Message = "Empty table exported correctly" }
            } else {
                @{ Success = $false; Message = "Empty table has unexpected data" }
            }
        } else {
            @{ Success = $false; Message = "Empty table export not found" }
        }
    }
    
    Test-Feature -Category "EdgeCases" -Name "Non-Identity PK" -Description "Test table with non-identity primary key" -Test {
        $result = & $srcRoot\sync-import.ps1 -To target -Tables "NoIdentityTable" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "Insert.*3" -and $result -notmatch "ERROR|error") {
            @{ Success = $true; Message = "Non-identity PK table handled correctly" }
        } else {
            @{ Success = $false; Message = "Non-identity PK handling failed"; Details = $result }
        }
    }
    
    if (-not $CI) {
        Test-Feature -Category "EdgeCases" -Name "Large Table" -Description "Test performance with 1000+ rows" -Test {
            $start = Get-Date
            $result = & $srcRoot\sync-export.ps1 -From source -Tables "LargeTable" -ConfigFile $configFile 2>&1
            $duration = ((Get-Date) - $start).TotalSeconds
            
            if ($LASTEXITCODE -eq 0 -and $duration -lt 30) {
                @{ Success = $true; Message = "Large table exported in $($duration.ToString('0.00'))s" }
            } else {
                @{ Success = $false; Message = "Large table export too slow or failed"; Details = "Duration: ${duration}s" }
            }
        }
    }
}

# Error Handling Tests
function Run-ErrorHandlingTests {
    Test-Feature -Category "ErrorHandling" -Name "Missing Database" -Description "Test error for non-existent database" -Test {
        $result = & $srcRoot\sync-export.ps1 -From nonexistent -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "not found in config|Database.*not found") {
            @{ Success = $true; Message = "Missing database error handled correctly" }
        } else {
            @{ Success = $false; Message = "Error handling incorrect"; Details = $result }
        }
    }
    
    Test-Feature -Category "ErrorHandling" -Name "Missing Table" -Description "Test error for non-existent table" -Test {
        $result = & $srcRoot\sync-export.ps1 -From source -Tables "NonExistentTable" -ConfigFile $configFile 2>&1 | Out-String
        
        if ($result -match "not found|does not exist|Table.*not found") {
            @{ Success = $true; Message = "Missing table error handled correctly" }
        } else {
            @{ Success = $false; Message = "Missing table not detected"; Details = $result }
        }
    }
    
    Test-Feature -Category "ErrorHandling" -Name "Invalid matchOn" -Description "Test validation of non-existent matchOn fields" -Test {
        # Modify config temporarily
        $config = Get-Content $configFile | ConvertFrom-Json
        $config.syncTables[0].matchOn = @("NonExistentField")
        $tempConfig = Join-Path $testRoot "temp-invalid-config.json"
        $config | ConvertTo-Json -Depth 10 | Set-Content $tempConfig
        
        try {
            $result = & $srcRoot\sync-export.ps1 -From source -Tables "Users" -ConfigFile $tempConfig 2>&1 | Out-String
            
            if ($result -match "not found|missing|does not exist") {
                @{ Success = $true; Message = "Invalid matchOn field detected" }
            } else {
                @{ Success = $false; Message = "Invalid matchOn not detected"; Details = $result }
            }
        } finally {
            Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main execution
try {
    Write-Host "`n$($colors.Cyan)╔═══════════════════════════════════════════════════════╗$($colors.Reset)"
    Write-Host "$($colors.Cyan)║$($colors.Reset)     $($colors.Bold)SyncRay SQLite Test Framework$($colors.Reset)                    $($colors.Cyan)║$($colors.Reset)"
    Write-Host "$($colors.Cyan)╚═══════════════════════════════════════════════════════╝$($colors.Reset)"
    
    # Install SQLite module
    Install-SQLiteModule
    
    # Initialize test environment
    Initialize-TestDatabases
    Create-TestConfig
    
    # Run selected test categories
    Write-Host "`n$($colors.Cyan)═══ Running Test Categories: $($Categories -join ', ') ═══$($colors.Reset)"
    
    foreach ($category in $Categories) {
        switch ($category) {
            "Basic" { Run-BasicTests }
            "Advanced" { Run-AdvancedTests }
            "EdgeCases" { Run-EdgeCaseTests }
            "ErrorHandling" { Run-ErrorHandlingTests }
            default { Write-Host "Unknown category: $category" -ForegroundColor Yellow }
        }
    }
    
    # Summary
    $duration = (Get-Date) - $script:TestResults.StartTime
    Write-Host "`n$($colors.Cyan)╔═══════════════════════════════════════════════════════╗$($colors.Reset)"
    Write-Host "$($colors.Cyan)║$($colors.Reset)                  $($colors.Bold)TEST SUMMARY$($colors.Reset)                        $($colors.Cyan)║$($colors.Reset)"
    Write-Host "$($colors.Cyan)╚═══════════════════════════════════════════════════════╝$($colors.Reset)"
    
    $passRate = if ($script:TestResults.Total -gt 0) { 
        [math]::Round(($script:TestResults.Passed / $script:TestResults.Total) * 100, 1) 
    } else { 0 }
    
    Write-Host "`nTotal Tests: $($script:TestResults.Total)"
    Write-Host "$($colors.Green)✓ Passed: $($script:TestResults.Passed)$($colors.Reset)"
    Write-Host "$($colors.Red)✗ Failed: $($script:TestResults.Failed)$($colors.Reset)"
    Write-Host "`nPass Rate: $passRate%"
    Write-Host "Duration: $($duration.ToString('mm\:ss\.ff'))"
    
    if ($script:TestResults.Failed -eq 0) {
        Write-Host "`n$($colors.Green)🎉 All tests passed!$($colors.Reset)"
    } else {
        Write-Host "`n$($colors.Yellow)⚠️  Some tests failed$($colors.Reset)"
        
        if ($Verbose) {
            Write-Host "`nFailed Tests:" -ForegroundColor Red
            $script:TestResults.Details | Where-Object { $_.Status -ne "Passed" } | ForEach-Object {
                Write-Host "  - [$($_.Category)] $($_.Name): $($_.Message)" -ForegroundColor Red
            }
        }
    }
    
    # Export results for CI
    if ($CI) {
        $resultsFile = Join-Path $testRoot "test-results.json"
        $script:TestResults | ConvertTo-Json -Depth 10 | Set-Content $resultsFile
        Write-Host "`nTest results exported to: $resultsFile" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "`n$($colors.Red)Fatal error: $_$($colors.Reset)" -ForegroundColor Red
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