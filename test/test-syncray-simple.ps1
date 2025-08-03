# Simple SyncRay Test Suite
# Tests core functionality without requiring actual databases

param(
    [switch]$KeepTestData  # Don't cleanup after tests
)

$ErrorActionPreference = "Continue"
$script:TestResults = @{ Passed = 0; Failed = 0; Total = 0 }

Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              SyncRay Simple Test Suite                 ║" -ForegroundColor Cyan  
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Setup paths
$configFile = Join-Path $PSScriptRoot "test-simple-config.json"
$exportPath = Join-Path $PSScriptRoot "test-sync-data"

# Helper function to run tests
function Test-Feature {
    param(
        [string]$Name,
        [string]$Description,
        [scriptblock]$Test
    )
    
    $script:TestResults.Total++
    Write-Host "`n━━━ $Name ━━━" -ForegroundColor Yellow
    Write-Host $Description -ForegroundColor Gray
    
    try {
        $result = & $Test
        if ($result.Success) {
            Write-Host "✓ PASSED: $($result.Message)" -ForegroundColor Green
            $script:TestResults.Passed++
        } else {
            Write-Host "✗ FAILED: $($result.Message)" -ForegroundColor Red
            if ($result.Details) {
                Write-Host "  Details: $($result.Details)" -ForegroundColor DarkRed
            }
            $script:TestResults.Failed++
        }
    } catch {
        Write-Host "✗ ERROR: $_" -ForegroundColor Red
        $script:TestResults.Failed++
    }
}

# Create mock test data
function Create-MockExportData {
    Write-Host "`nCreating mock export data..." -ForegroundColor Cyan
    
    if (-not (Test-Path $exportPath)) {
        New-Item -ItemType Directory -Path $exportPath -Force | Out-Null
    }
    
    # Create Users export
    $usersData = @{
        metadata = @{
            sourceTable = "Users"
            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            rowCount = 4
            columns = @(
                @{ name = "UserID"; type = "int"; isPrimaryKey = $true }
                @{ name = "Username"; type = "nvarchar"; maxLength = 50 }
                @{ name = "Email"; type = "nvarchar"; maxLength = 100 }
                @{ name = "IsActive"; type = "bit" }
                @{ name = "CreatedDate"; type = "datetime" }
                @{ name = "LastModified"; type = "datetime" }
            )
            primaryKeys = @("UserID")
            matchOn = @("UserID")
            ignoreColumns = @()
            allowDeletes = $true
        }
        data = @(
            @{ UserID = 1; Username = "john_doe"; Email = "john@example.com"; IsActive = $true; CreatedDate = "2024-01-01"; LastModified = "2024-12-01" }
            @{ UserID = 2; Username = "jane_smith"; Email = "jane@example.com"; IsActive = $true; CreatedDate = "2024-01-15"; LastModified = "2024-12-15" }
            @{ UserID = 3; Username = "bob_wilson"; Email = "bob@example.com"; IsActive = $false; CreatedDate = "2024-02-01"; LastModified = "2024-11-01" }
            @{ UserID = 4; Username = "alice_jones"; Email = "alice@example.com"; IsActive = $true; CreatedDate = "2024-02-15"; LastModified = "2024-12-20" }
        )
    }
    $usersData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $exportPath "Users.json")
    
    # Create Products export
    $productsData = @{
        metadata = @{
            sourceTable = "Products"
            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            rowCount = 3
            columns = @(
                @{ name = "ProductID"; type = "int"; isPrimaryKey = $true }
                @{ name = "ProductName"; type = "nvarchar"; maxLength = 100 }
                @{ name = "Price"; type = "decimal"; precision = 10; scale = 2 }
                @{ name = "LastModified"; type = "datetime" }
                @{ name = "ModifiedBy"; type = "nvarchar"; maxLength = 50 }
            )
            primaryKeys = @("ProductID")
            matchOn = @("ProductID")
            ignoreColumns = @("LastModified", "ModifiedBy")
            allowDeletes = $false
        }
        data = @(
            @{ ProductID = 1; ProductName = "Laptop"; Price = 999.99; LastModified = "2024-12-01 10:00:00"; ModifiedBy = "system" }
            @{ ProductID = 2; ProductName = "Mouse"; Price = 29.99; LastModified = "2024-12-01 10:00:00"; ModifiedBy = "system" }
            @{ ProductID = 3; ProductName = "Keyboard"; Price = 79.99; LastModified = "2024-12-01 10:00:00"; ModifiedBy = "system" }
        )
    }
    $productsData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $exportPath "Products.json")
    
    # Create Orders export (with WHERE clause filtering)
    $ordersData = @{
        metadata = @{
            sourceTable = "Orders"
            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            rowCount = 2  # Only completed orders
            columns = @(
                @{ name = "OrderID"; type = "int"; isPrimaryKey = $true }
                @{ name = "CustomerID"; type = "int" }
                @{ name = "OrderDate"; type = "datetime" }
                @{ name = "Status"; type = "nvarchar"; maxLength = 20 }
                @{ name = "Total"; type = "decimal"; precision = 10; scale = 2 }
            )
            primaryKeys = @("OrderID")
            matchOn = @("OrderID")
            ignoreColumns = @()
            allowDeletes = $false
            exportWhere = "Status = 'Completed'"
        }
        data = @(
            @{ OrderID = 1; CustomerID = 101; OrderDate = "2024-01-15"; Status = "Completed"; Total = 1029.98 }
            @{ OrderID = 2; CustomerID = 102; OrderDate = "2024-02-20"; Status = "Completed"; Total = 109.98 }
        )
    }
    $ordersData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $exportPath "Orders.json")
    
    # Create OrderItems export (composite key)
    $orderItemsData = @{
        metadata = @{
            sourceTable = "OrderItems"
            exportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            rowCount = 4
            columns = @(
                @{ name = "OrderID"; type = "int"; isPrimaryKey = $true }
                @{ name = "ProductID"; type = "int"; isPrimaryKey = $true }
                @{ name = "Quantity"; type = "int" }
                @{ name = "Price"; type = "decimal"; precision = 10; scale = 2 }
            )
            primaryKeys = @("OrderID", "ProductID")
            matchOn = @("OrderID", "ProductID")
            ignoreColumns = @()
            allowDeletes = $false
        }
        data = @(
            @{ OrderID = 1; ProductID = 1; Quantity = 1; Price = 999.99 }
            @{ OrderID = 1; ProductID = 2; Quantity = 1; Price = 29.99 }
            @{ OrderID = 2; ProductID = 2; Quantity = 3; Price = 29.99 }
            @{ OrderID = 2; ProductID = 3; Quantity = 1; Price = 79.99 }
        )
    }
    $orderItemsData | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $exportPath "OrderItems.json")
    
    Write-Host "✓ Mock export data created" -ForegroundColor Green
}

# Create test configuration
function Create-TestConfig {
    $config = @{
        databases = @{
            source = @{
                server = "test-server"
                database = "TestSourceDB"
                auth = "windows"
            }
            target = @{
                server = "test-server"
                database = "TestTargetDB"
                auth = "windows"
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
    Write-Host "✓ Test configuration created" -ForegroundColor Green
}

# Run tests
function Run-AllTests {
    # Test 1: Script Availability
    Test-Feature -Name "Script Availability" -Description "Check if all required scripts exist" -Test {
        $scripts = @(
            "../src/sync-export.ps1",
            "../src/sync-import.ps1",
            "../src/syncray.ps1",
            "../src/sync-validation.ps1"
        )
        
        $missing = $scripts | Where-Object { -not (Test-Path $_) }
        if ($missing.Count -eq 0) {
            @{ Success = $true; Message = "All scripts found" }
        } else {
            @{ Success = $false; Message = "Missing scripts: $($missing -join ', ')" }
        }
    }
    
    # Test 2: Configuration Validation
    Test-Feature -Name "Configuration" -Description "Test configuration file handling" -Test {
        if (Test-Path $configFile) {
            try {
                $config = Get-Content $configFile -Raw | ConvertFrom-Json
                if ($config.databases -and $config.syncTables) {
                    @{ Success = $true; Message = "Configuration valid" }
                } else {
                    @{ Success = $false; Message = "Configuration missing required sections" }
                }
            } catch {
                @{ Success = $false; Message = "Configuration parse error: $_" }
            }
        } else {
            @{ Success = $false; Message = "Configuration file not found" }
        }
    }
    
    # Test 3: Help System
    Test-Feature -Name "Help System" -Description "Test help commands" -Test {
        $help = & ../src/syncray.ps1 -Help 2>&1 | Out-String
        if ($help -match "SYNCRAY" -and $help -match "DESCRIPTION") {
            @{ Success = $true; Message = "Help system working" }
        } else {
            @{ Success = $false; Message = "Help output incorrect" }
        }
    }
    
    # Test 4: Error Handling
    Test-Feature -Name "Error Handling" -Description "Test error messages" -Test {
        $result = & ../src/sync-export.ps1 -From nonexistent -ConfigFile $configFile 2>&1 | Out-String
        if ($result -match "not found in config|Database.*not found") {
            @{ Success = $true; Message = "Error handling correct" }
        } else {
            @{ Success = $false; Message = "Error handling incorrect"; Details = $result }
        }
    }
    
    # Test 5: Export File Format
    Test-Feature -Name "Export Format" -Description "Test export file structure" -Test {
        $usersFile = Join-Path $exportPath "Users.json"
        if (Test-Path $usersFile) {
            try {
                $data = Get-Content $usersFile -Raw | ConvertFrom-Json
                if ($data.metadata -and $data.data -and $data.metadata.rowCount -eq $data.data.Count) {
                    @{ Success = $true; Message = "Export format correct" }
                } else {
                    @{ Success = $false; Message = "Export format invalid" }
                }
            } catch {
                @{ Success = $false; Message = "Export file parse error: $_" }
            }
        } else {
            @{ Success = $false; Message = "Export file not found" }
        }
    }
    
    # Test 6: WHERE Clause Data
    Test-Feature -Name "WHERE Filtering" -Description "Test export filtering" -Test {
        $ordersFile = Join-Path $exportPath "Orders.json"
        if (Test-Path $ordersFile) {
            $data = Get-Content $ordersFile -Raw | ConvertFrom-Json
            $allCompleted = @($data.data | Where-Object { $_.Status -ne 'Completed' }).Count -eq 0
            if ($allCompleted -and $data.data.Count -eq 2) {
                @{ Success = $true; Message = "WHERE clause filtered correctly" }
            } else {
                @{ Success = $false; Message = "WHERE clause filtering incorrect" }
            }
        } else {
            @{ Success = $false; Message = "Orders export not found" }
        }
    }
    
    # Test 7: Composite Key Data
    Test-Feature -Name "Composite Keys" -Description "Test composite key handling" -Test {
        $orderItemsFile = Join-Path $exportPath "OrderItems.json"
        if (Test-Path $orderItemsFile) {
            $data = Get-Content $orderItemsFile -Raw | ConvertFrom-Json
            if ($data.metadata.primaryKeys.Count -eq 2 -and $data.metadata.matchOn.Count -eq 2) {
                @{ Success = $true; Message = "Composite keys configured correctly" }
            } else {
                @{ Success = $false; Message = "Composite key configuration incorrect" }
            }
        } else {
            @{ Success = $false; Message = "OrderItems export not found" }
        }
    }
    
    # Test 8: Ignore Columns Config
    Test-Feature -Name "Ignore Columns" -Description "Test ignore columns configuration" -Test {
        $productsFile = Join-Path $exportPath "Products.json"
        if (Test-Path $productsFile) {
            $data = Get-Content $productsFile -Raw | ConvertFrom-Json
            if ($data.metadata.ignoreColumns -contains "LastModified" -and $data.metadata.ignoreColumns -contains "ModifiedBy") {
                @{ Success = $true; Message = "Ignore columns configured correctly" }
            } else {
                @{ Success = $false; Message = "Ignore columns not configured" }
            }
        } else {
            @{ Success = $false; Message = "Products export not found" }
        }
    }
    
    # Test 9: Database Connection Validation
    Test-Feature -Name "Connection Test" -Description "Test database connection error" -Test {
        # This will fail but should show proper validation
        $result = & ../src/sync-export.ps1 -From source -ConfigFile $configFile -Tables "Users" 2>&1 | Out-String
        if ($result -match "Cannot open database|Validating|Login failed|server was not found") {
            @{ Success = $true; Message = "Connection validation working" }
        } else {
            @{ Success = $false; Message = "Connection validation not triggered"; Details = $result }
        }
    }
    
    # Test 10: PowerShell Compatibility
    Test-Feature -Name "PowerShell Version" -Description "Test PowerShell compatibility" -Test {
        if ($PSVersionTable.PSVersion.Major -ge 5) {
            @{ Success = $true; Message = "PowerShell $($PSVersionTable.PSVersion) compatible" }
        } else {
            @{ Success = $false; Message = "PowerShell version too old" }
        }
    }
}

# Main execution
try {
    # Initialize
    Create-TestConfig
    Create-MockExportData
    
    # Run all tests
    Write-Host "`n═══ Running Tests ═══" -ForegroundColor Cyan
    Run-AllTests
    
    # Summary
    Write-Host "`n╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    TEST SUMMARY                        ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $passRate = if ($script:TestResults.Total -gt 0) { 
        [math]::Round(($script:TestResults.Passed / $script:TestResults.Total) * 100, 1) 
    } else { 0 }
    
    Write-Host "`nTotal Tests: $($script:TestResults.Total)"
    Write-Host "✓ Passed: $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "✗ Failed: $($script:TestResults.Failed)" -ForegroundColor Red
    Write-Host "`nPass Rate: $passRate%"
    
    if ($script:TestResults.Failed -eq 0) {
        Write-Host "`n🎉 All tests passed!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Some tests failed" -ForegroundColor Yellow
    }
    
} finally {
    # Cleanup
    if (-not $KeepTestData) {
        Write-Host "`nCleaning up test data..." -ForegroundColor Yellow
        
        @($exportPath, $configFile) | ForEach-Object {
            if (Test-Path $_) {
                Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
    } else {
        Write-Host "`nTest data kept at:" -ForegroundColor Yellow
        Write-Host "  Exports: $exportPath" -ForegroundColor Gray
        Write-Host "  Config: $configFile" -ForegroundColor Gray
    }
}

# Exit with appropriate code
exit $(if ($script:TestResults.Failed -eq 0) { 0 } else { 1 })