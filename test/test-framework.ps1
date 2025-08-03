# SyncRay Test Framework with SQLite
# Comprehensive automated testing for all SyncRay features

param(
    [Parameter(Mandatory=$false)]
    [switch]$SetupOnly,  # Only setup test databases
    
    [Parameter(Mandatory=$false)]
    [switch]$Cleanup,    # Clean up test artifacts
    
    [Parameter(Mandatory=$false)]
    [string[]]$TestNames,  # Run specific tests
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose     # Show detailed output
)

$ErrorActionPreference = "Stop"

# Test configuration
$script:TestConfig = @{
    DatabasePath = Join-Path $PSScriptRoot "test-databases"
    SourceDB = "source_test.db"
    TargetDB = "target_test.db"
    ConfigFile = Join-Path $PSScriptRoot "test-config-sqlite.json"
    DataPath = Join-Path $PSScriptRoot "test-sync-data"
    Results = @{
        Total = 0
        Passed = 0
        Failed = 0
        Skipped = 0
        Details = @()
        StartTime = Get-Date
    }
}

# Load SQLite module based on platform
function Initialize-SQLite {
    $platform = [System.Environment]::OSVersion.Platform
    $sqlitePath = Join-Path $PSScriptRoot "sqlite-drivers"
    
    switch ($platform) {
        "Win32NT" {
            $dllPath = Join-Path $sqlitePath "windows/System.Data.SQLite.dll"
        }
        "Unix" {
            if ($IsMacOS) {
                $dllPath = Join-Path $sqlitePath "macos/System.Data.SQLite.dll"
            } else {
                $dllPath = Join-Path $sqlitePath "linux/System.Data.SQLite.dll"
            }
        }
    }
    
    if (-not (Test-Path $dllPath)) {
        throw "SQLite driver not found at: $dllPath"
    }
    
    try {
        Add-Type -Path $dllPath
        Write-Host "✓ SQLite driver loaded successfully" -ForegroundColor Green
    } catch {
        throw "Failed to load SQLite driver: $_"
    }
}

# Create test databases with schema
function Setup-TestDatabases {
    Write-Host "`n=== SETTING UP TEST DATABASES ===" -ForegroundColor Cyan
    
    # Create database directory
    if (-not (Test-Path $script:TestConfig.DatabasePath)) {
        New-Item -ItemType Directory -Path $script:TestConfig.DatabasePath | Out-Null
    }
    
    # Remove existing databases
    @($script:TestConfig.SourceDB, $script:TestConfig.TargetDB) | ForEach-Object {
        $dbPath = Join-Path $script:TestConfig.DatabasePath $_
        if (Test-Path $dbPath) {
            Remove-Item $dbPath -Force
        }
    }
    
    # Create and populate source database
    $sourceConn = New-Object System.Data.SQLite.SQLiteConnection
    $sourceConn.ConnectionString = "Data Source=$(Join-Path $script:TestConfig.DatabasePath $script:TestConfig.SourceDB);Version=3;"
    $sourceConn.Open()
    
    try {
        # Create test tables
        $tables = @(
            # Basic table
            @"
CREATE TABLE users (
    user_id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL,
    created_date TEXT,
    is_active INTEGER DEFAULT 1,
    last_login TEXT
)
"@,
            # Table with composite key
            @"
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    product_id INTEGER NOT NULL,
    quantity INTEGER NOT NULL,
    price REAL NOT NULL,
    PRIMARY KEY (order_id, product_id)
)
"@,
            # Table for testing ignoreColumns
            @"
CREATE TABLE products (
    product_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    last_modified TEXT,
    modified_by TEXT
)
"@,
            # Table for testing duplicates
            @"
CREATE TABLE duplicate_test (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL,
    value TEXT,
    category TEXT
)
"@,
            # Table for testing replaceMode
            @"
CREATE TABLE reference_data (
    ref_id INTEGER PRIMARY KEY,
    ref_code TEXT NOT NULL,
    ref_value TEXT NOT NULL
)
"@,
            # Table without primary key
            @"
CREATE TABLE no_pk_table (
    col1 TEXT,
    col2 TEXT,
    col3 INTEGER
)
"@,
            # Table for testing exportWhere
            @"
CREATE TABLE orders (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER,
    order_date TEXT,
    status TEXT,
    total REAL
)
"@
        )
        
        foreach ($sql in $tables) {
            $cmd = $sourceConn.CreateCommand()
            $cmd.CommandText = $sql
            $cmd.ExecuteNonQuery() | Out-Null
        }
        
        # Insert test data
        Insert-TestData -Connection $sourceConn
        
        Write-Host "✓ Source database created and populated" -ForegroundColor Green
        
    } finally {
        $sourceConn.Close()
    }
    
    # Create target database with same schema (but different data for some tables)
    $targetConn = New-Object System.Data.SQLite.SQLiteConnection
    $targetConn.ConnectionString = "Data Source=$(Join-Path $script:TestConfig.DatabasePath $script:TestConfig.TargetDB);Version=3;"
    $targetConn.Open()
    
    try {
        foreach ($sql in $tables) {
            $cmd = $targetConn.CreateCommand()
            $cmd.CommandText = $sql
            $cmd.ExecuteNonQuery() | Out-Null
        }
        
        # Insert different data for testing updates/deletes
        Insert-TargetTestData -Connection $targetConn
        
        Write-Host "✓ Target database created and populated" -ForegroundColor Green
        
    } finally {
        $targetConn.Close()
    }
    
    # Create test configuration file
    Create-TestConfig
}

# Insert test data into source database
function Insert-TestData {
    param($Connection)
    
    # Users table
    $users = @(
        "INSERT INTO users VALUES (1, 'john_doe', 'john@example.com', '2024-01-01', 1, '2024-12-01')",
        "INSERT INTO users VALUES (2, 'jane_smith', 'jane@example.com', '2024-01-15', 1, '2024-12-15')",
        "INSERT INTO users VALUES (3, 'bob_wilson', 'bob@example.com', '2024-02-01', 0, '2024-11-01')",
        "INSERT INTO users VALUES (4, 'alice_jones', 'alice@example.com', '2024-02-15', 1, '2024-12-20')"
    )
    
    # Products table
    $products = @(
        "INSERT INTO products VALUES (1, 'Laptop', 999.99, '2024-12-01 10:00:00', 'system')",
        "INSERT INTO products VALUES (2, 'Mouse', 29.99, '2024-12-01 10:00:00', 'system')",
        "INSERT INTO products VALUES (3, 'Keyboard', 79.99, '2024-12-01 10:00:00', 'system')"
    )
    
    # Order items (composite key)
    $orderItems = @(
        "INSERT INTO order_items VALUES (1001, 1, 2, 999.99)",
        "INSERT INTO order_items VALUES (1001, 2, 1, 29.99)",
        "INSERT INTO order_items VALUES (1002, 2, 3, 29.99)",
        "INSERT INTO order_items VALUES (1002, 3, 1, 79.99)"
    )
    
    # Duplicate test data (intentional duplicates on 'code' field)
    $duplicates = @(
        "INSERT INTO duplicate_test VALUES (1, 'CODE001', 'Value 1', 'Category A')",
        "INSERT INTO duplicate_test VALUES (2, 'CODE001', 'Value 2', 'Category A')",  # Duplicate code
        "INSERT INTO duplicate_test VALUES (3, 'CODE002', 'Value 3', 'Category B')",
        "INSERT INTO duplicate_test VALUES (4, 'CODE002', 'Value 4', 'Category B')"   # Duplicate code
    )
    
    # Reference data
    $refData = @(
        "INSERT INTO reference_data VALUES (1, 'COUNTRY_US', 'United States')",
        "INSERT INTO reference_data VALUES (2, 'COUNTRY_UK', 'United Kingdom')",
        "INSERT INTO reference_data VALUES (3, 'COUNTRY_DE', 'Germany')"
    )
    
    # No PK table
    $noPK = @(
        "INSERT INTO no_pk_table VALUES ('A', 'B', 1)",
        "INSERT INTO no_pk_table VALUES ('C', 'D', 2)",
        "INSERT INTO no_pk_table VALUES ('E', 'F', 3)"
    )
    
    # Orders (for exportWhere testing)
    $orders = @(
        "INSERT INTO orders VALUES (1, 101, '2024-01-15', 'Completed', 1029.98)",
        "INSERT INTO orders VALUES (2, 102, '2024-02-20', 'Completed', 109.98)",
        "INSERT INTO orders VALUES (3, 103, '2024-11-15', 'Pending', 999.99)",
        "INSERT INTO orders VALUES (4, 104, '2024-12-01', 'Cancelled', 29.99)"
    )
    
    # Execute all inserts
    foreach ($data in @($users, $products, $orderItems, $duplicates, $refData, $noPK, $orders)) {
        foreach ($sql in $data) {
            $cmd = $Connection.CreateCommand()
            $cmd.CommandText = $sql
            $cmd.ExecuteNonQuery() | Out-Null
        }
    }
}

# Insert different data into target database for testing updates/deletes
function Insert-TargetTestData {
    param($Connection)
    
    # Users table - some different, some same, some missing
    $users = @(
        "INSERT INTO users VALUES (1, 'john_doe', 'john.old@example.com', '2024-01-01', 1, '2024-11-01')",  # Different email
        "INSERT INTO users VALUES (2, 'jane_smith', 'jane@example.com', '2024-01-15', 0, '2024-12-15')",   # Different is_active
        "INSERT INTO users VALUES (5, 'target_only', 'target@example.com', '2024-03-01', 1, '2024-12-01')" # Only in target
        # Missing users 3 and 4 from source
    )
    
    # Products - for testing ignoreColumns
    $products = @(
        "INSERT INTO products VALUES (1, 'Laptop', 899.99, '2024-11-01 08:00:00', 'admin')",    # Different price and timestamps
        "INSERT INTO products VALUES (2, 'Mouse', 29.99, '2024-11-01 08:00:00', 'admin')",      # Same price, different timestamps
        "INSERT INTO products VALUES (4, 'Monitor', 299.99, '2024-11-01 08:00:00', 'admin')"    # Only in target
    )
    
    # Reference data - completely different for replaceMode testing
    $refData = @(
        "INSERT INTO reference_data VALUES (10, 'OLD_CODE_1', 'Old Value 1')",
        "INSERT INTO reference_data VALUES (11, 'OLD_CODE_2', 'Old Value 2')"
    )
    
    # Execute inserts
    foreach ($data in @($users, $products, $refData)) {
        foreach ($sql in $data) {
            $cmd = $Connection.CreateCommand()
            $cmd.CommandText = $sql
            $cmd.ExecuteNonQuery() | Out-Null
        }
    }
}

# Create test configuration file
function Create-TestConfig {
    $config = @{
        databases = @{
            source = @{
                server = Join-Path $script:TestConfig.DatabasePath $script:TestConfig.SourceDB
                database = "main"
                auth = "sqlite"
            }
            target = @{
                server = Join-Path $script:TestConfig.DatabasePath $script:TestConfig.TargetDB
                database = "main"
                auth = "sqlite"
            }
        }
        
        syncTables = @(
            @{
                sourceTable = "users"
                matchOn = @("user_id")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $true
            },
            @{
                sourceTable = "products"
                matchOn = @("product_id")
                ignoreColumns = @("last_modified", "modified_by")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "order_items"
                matchOn = @("order_id", "product_id")
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "duplicate_test"
                matchOn = @("code")  # This will cause duplicates
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            },
            @{
                sourceTable = "reference_data"
                replaceMode = $true
                preserveIdentity = $true
            },
            @{
                sourceTable = "orders"
                matchOn = @("order_id")
                exportWhere = "status = 'Completed'"
                allowInserts = $true
                allowUpdates = $true
                allowDeletes = $false
            }
        )
        
        exportPath = "./test-sync-data"
    }
    
    $config | ConvertTo-Json -Depth 10 | Set-Content $script:TestConfig.ConfigFile
    Write-Host "✓ Test configuration created" -ForegroundColor Green
}

# Run a test scenario
function Run-Test {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Test
    )
    
    $script:TestConfig.Results.Total++
    
    Write-Host "`n━━━ Test: $Name ━━━" -ForegroundColor Yellow
    Write-Host "Description: $Description" -ForegroundColor Gray
    
    $testStart = Get-Date
    
    try {
        $result = & $Test
        $duration = (Get-Date) - $testStart
        
        if ($result.Success) {
            Write-Host "✓ PASSED" -ForegroundColor Green -NoNewline
            Write-Host " - $($result.Message) (${duration}ms)" -ForegroundColor Gray
            $script:TestConfig.Results.Passed++
            $status = "Passed"
        } else {
            Write-Host "✗ FAILED" -ForegroundColor Red -NoNewline
            Write-Host " - $($result.Message)" -ForegroundColor Gray
            if ($result.Details) {
                Write-Host "  Details: $($result.Details)" -ForegroundColor DarkGray
            }
            $script:TestConfig.Results.Failed++
            $status = "Failed"
        }
    } catch {
        Write-Host "✗ ERROR" -ForegroundColor Red -NoNewline
        Write-Host " - $($_.Exception.Message)" -ForegroundColor Gray
        Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
        $script:TestConfig.Results.Failed++
        $status = "Error"
        $result = @{ Message = $_.Exception.Message }
    }
    
    $script:TestConfig.Results.Details += @{
        Name = $Name
        Status = $status
        Message = $result.Message
        Duration = $duration
        Timestamp = Get-Date
    }
}

# Test Scenarios
function Test-BasicExportImport {
    # Clean up any existing export
    if (Test-Path $script:TestConfig.DataPath) {
        Remove-Item $script:TestConfig.DataPath -Recurse -Force
    }
    
    # Test export
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "users" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed"; Details = ($exportResult | Out-String) }
    }
    
    # Check export file
    $exportFile = Join-Path $script:TestConfig.DataPath "users.json"
    if (-not (Test-Path $exportFile)) {
        return @{ Success = $false; Message = "Export file not created" }
    }
    
    # Test import (dry-run)
    $importResult = & ../src/sync-import.ps1 -To target -Tables "users" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Import dry-run failed"; Details = ($importResult | Out-String) }
    }
    
    # Check for expected changes in output
    $output = $importResult | Out-String
    if ($output -match "Insert.*2" -and $output -match "Update.*2" -and $output -match "Delete.*1") {
        return @{ Success = $true; Message = "Detected correct changes: 2 inserts, 2 updates, 1 delete" }
    } else {
        return @{ Success = $false; Message = "Unexpected changes detected"; Details = $output }
    }
}

function Test-CompositeKeySync {
    # Export table with composite key
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "order_items" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed"; Details = ($exportResult | Out-String) }
    }
    
    # Import and check
    $importResult = & ../src/sync-import.ps1 -To target -Tables "order_items" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Import failed"; Details = ($importResult | Out-String) }
    }
    
    $output = $importResult | Out-String
    if ($output -match "Insert.*4") {
        return @{ Success = $true; Message = "Composite key table synced correctly" }
    } else {
        return @{ Success = $false; Message = "Composite key sync failed"; Details = $output }
    }
}

function Test-IgnoreColumns {
    # Export products table
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "products" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed"; Details = ($exportResult | Out-String) }
    }
    
    # Import and check
    $importResult = & ../src/sync-import.ps1 -To target -Tables "products" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Import failed"; Details = ($importResult | Out-String) }
    }
    
    $output = $importResult | Out-String
    # Should detect update for product 1 (price change) but not for product 2 (only timestamp different)
    if ($output -match "Update.*1" -and $output -match "Insert.*1") {
        return @{ Success = $true; Message = "Ignored columns correctly excluded from comparison" }
    } else {
        return @{ Success = $false; Message = "Ignore columns not working correctly"; Details = $output }
    }
}

function Test-DuplicateDetection {
    # Export table with duplicates
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "duplicate_test" -ConfigFile $script:TestConfig.ConfigFile -SkipOnDuplicates 2>&1
    if ($LASTEXITCODE -eq 0) {
        return @{ Success = $false; Message = "Export should have failed due to duplicates" }
    }
    
    $output = $exportResult | Out-String
    if ($output -match "DUPLICATES FOUND" -and $output -match "Skipping table") {
        return @{ Success = $true; Message = "Duplicates correctly detected and table skipped" }
    } else {
        return @{ Success = $false; Message = "Duplicate detection failed"; Details = $output }
    }
}

function Test-ReplaceMode {
    # Export reference data
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "reference_data" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed"; Details = ($exportResult | Out-String) }
    }
    
    # Import with replace mode
    $importResult = & ../src/sync-import.ps1 -To target -Tables "reference_data" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Import failed"; Details = ($importResult | Out-String) }
    }
    
    $output = $importResult | Out-String
    if ($output -match "REPLACE MODE" -and $output -match "Delete all.*Insert.*3") {
        return @{ Success = $true; Message = "Replace mode correctly detected delete all + insert" }
    } else {
        return @{ Success = $false; Message = "Replace mode not working correctly"; Details = $output }
    }
}

function Test-ExportWhere {
    # Export orders with WHERE clause
    $exportResult = & ../src/sync-export.ps1 -From source -Tables "orders" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Message = "Export failed"; Details = ($exportResult | Out-String) }
    }
    
    # Check export file
    $exportFile = Join-Path $script:TestConfig.DataPath "orders.json"
    $exportData = Get-Content $exportFile | ConvertFrom-Json
    
    # Should only have 2 completed orders
    if ($exportData.data.Count -eq 2) {
        return @{ Success = $true; Message = "WHERE clause correctly filtered to 2 completed orders" }
    } else {
        return @{ Success = $false; Message = "WHERE clause filtering failed"; Details = "Expected 2 records, got $($exportData.data.Count)" }
    }
}

function Test-ValidationErrors {
    # Test with non-existent table
    $result = & ../src/sync-export.ps1 -From source -Tables "non_existent_table" -ConfigFile $script:TestConfig.ConfigFile 2>&1
    if ($LASTEXITCODE -eq 0) {
        return @{ Success = $false; Message = "Should have failed for non-existent table" }
    }
    
    $output = $result | Out-String
    if ($output -match "Table.*not found") {
        return @{ Success = $true; Message = "Validation correctly detected missing table" }
    } else {
        return @{ Success = $false; Message = "Validation error not properly reported"; Details = $output }
    }
}

# Main execution
function Main {
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     SyncRay Comprehensive Test Suite    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Initialize SQLite
    Initialize-SQLite
    
    if ($Cleanup) {
        Write-Host "`nCleaning up test artifacts..." -ForegroundColor Yellow
        if (Test-Path $script:TestConfig.DatabasePath) {
            Remove-Item $script:TestConfig.DatabasePath -Recurse -Force
        }
        if (Test-Path $script:TestConfig.DataPath) {
            Remove-Item $script:TestConfig.DataPath -Recurse -Force
        }
        if (Test-Path $script:TestConfig.ConfigFile) {
            Remove-Item $script:TestConfig.ConfigFile -Force
        }
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
        return
    }
    
    # Setup test databases
    Setup-TestDatabases
    
    if ($SetupOnly) {
        Write-Host "`n✓ Test setup completed" -ForegroundColor Green
        return
    }
    
    # Define all tests
    $allTests = @(
        @{
            Name = "Basic Export/Import"
            Description = "Test basic table synchronization with inserts, updates, and deletes"
            Test = { Test-BasicExportImport }
        },
        @{
            Name = "Composite Key Sync"
            Description = "Test synchronization of tables with composite primary keys"
            Test = { Test-CompositeKeySync }
        },
        @{
            Name = "Ignore Columns"
            Description = "Test that specified columns are ignored during comparison"
            Test = { Test-IgnoreColumns }
        },
        @{
            Name = "Duplicate Detection"
            Description = "Test detection and handling of duplicate records"
            Test = { Test-DuplicateDetection }
        },
        @{
            Name = "Replace Mode"
            Description = "Test full table replacement mode"
            Test = { Test-ReplaceMode }
        },
        @{
            Name = "Export WHERE Clause"
            Description = "Test filtering during export with WHERE clause"
            Test = { Test-ExportWhere }
        },
        @{
            Name = "Validation Errors"
            Description = "Test proper error handling and validation"
            Test = { Test-ValidationErrors }
        }
    )
    
    # Filter tests if specific ones requested
    if ($TestNames) {
        $allTests = $allTests | Where-Object { $_.Name -in $TestNames }
    }
    
    Write-Host "`n=== RUNNING TESTS ===" -ForegroundColor Cyan
    Write-Host "Total tests to run: $($allTests.Count)" -ForegroundColor Gray
    
    # Run tests
    foreach ($test in $allTests) {
        Run-Test -Name $test.Name -Description $test.Description -Test $test.Test
    }
    
    # Summary
    $duration = (Get-Date) - $script:TestConfig.Results.StartTime
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           TEST SUMMARY                 ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nTotal Tests: $($script:TestConfig.Results.Total)"
    Write-Host "✓ Passed: $($script:TestConfig.Results.Passed)" -ForegroundColor Green
    Write-Host "✗ Failed: $($script:TestConfig.Results.Failed)" -ForegroundColor Red
    Write-Host "⊘ Skipped: $($script:TestConfig.Results.Skipped)" -ForegroundColor Yellow
    Write-Host "`nTotal Duration: $($duration.TotalSeconds.ToString('0.00')) seconds"
    
    # Exit code
    exit $(if ($script:TestConfig.Results.Failed -eq 0) { 0 } else { 1 })
}

# Run main
Main